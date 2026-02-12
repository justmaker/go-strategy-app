# Security & Authentication Spec

**Version**: 1.0
**Last Updated**: 2026-02-12

---

## 概覽

Go Strategy App 採用 **offline-first** 設計，使用者無需登入即可使用核心功能（棋盤分析、Opening Book 查詢）。認證機制僅用於雲端同步功能（棋譜備份到 Google Drive / iCloud / OneDrive）。

### 安全原則

1. **最小權限 (Least Privilege)** -- 僅在需要時請求認證，僅請求必要的 OAuth scope
2. **Offline-First** -- 所有核心功能離線可用，不依賴認證狀態
3. **使用者資料所有權** -- 棋譜存在使用者自己的雲端硬碟，App 不託管任何使用者資料
4. **平台原生安全機制** -- 憑證儲存依賴各平台原生安全儲存（Keychain、Keystore 等）

---

## 認證架構

### 支援的登入方式

| Provider | 套件 | 狀態 | 雲端儲存 |
|----------|------|------|---------|
| **Google Sign-In** | `google_sign_in: ^6.2.2` | 部分完成 | Google Drive |
| **Apple Sign-In** | `sign_in_with_apple: ^6.1.4` | 已實作 | iCloud (placeholder) |
| **Microsoft Sign-In** | `aad_oauth: ^1.0.1` | 未實作 (placeholder) | OneDrive (placeholder) |
| **Anonymous** | -- | 已完成 | 無 |

### 認證狀態機

```
initializing --> signedOut --> signingIn --> signedIn
                    ^             |              |
                    |             v              |
                    +---------- error            |
                    +----------------------------+  (signOut)
```

定義於 `mobile/lib/services/auth_service.dart`:

```dart
enum AuthState {
  initializing,  // App 啟動中，嘗試恢復 session
  signedOut,     // 未登入（匿名模式）
  signedIn,      // 已登入
  signingIn,     // 登入中
  error,         // 登入失敗
}
```

### Google Sign-In OAuth Flow

**目前狀態**: 部分完成 -- OAuth 流程可啟動並在瀏覽器完成認證，但 macOS 平台的 callback 尚未正確處理（UI 未更新）。

#### OAuth 配置

- **OAuth Type**: Desktop (macOS) / Mobile (iOS, Android)
- **Client ID** (macOS): `1046387...apps.googleusercontent.com`（完整值見 `mobile/macos/Runner/Info.plist`）
- **iOS Client ID**: 尚未在 Info.plist 配置（仍為 placeholder `YOUR_CLIENT_ID`）

#### 請求的 Scopes

```dart
GoogleSignIn(scopes: [
  'email',
  'https://www.googleapis.com/auth/drive.file',    // 存取 App 建立的檔案
  'https://www.googleapis.com/auth/drive.appdata',  // App-specific 資料夾
]);
```

`drive.file` 和 `drive.appdata` 均為 restricted scope，僅允許 App 存取自己建立的檔案，無法讀取使用者其他 Drive 檔案。

#### Token Lifecycle

| 階段 | 說明 |
|------|------|
| **取得** | 使用者點擊登入 -> 系統瀏覽器 OAuth -> 取得 access token + refresh token |
| **靜默恢復** | App 啟動時呼叫 `_googleSignIn.signInSilently()` 嘗試恢復 session |
| **刷新** | `refreshAuth()` 呼叫 `signInSilently(reAuthenticate: true)` 取得新 token |
| **過期處理** | Google Sign-In SDK 自動管理 token 過期與刷新 |
| **登出** | 呼叫 `_googleSignIn.signOut()` 清除本地 session |

#### 已知問題

- macOS 平台 OAuth callback 後 `signIn()` 未正確回傳 `GoogleSignInAccount`（TASKS.md 記錄）
- iOS 平台 `Info.plist` 中 `GIDClientID` 和 `CFBundleURLSchemes` 仍為 placeholder 值

### Apple Sign-In Flow

**狀態**: 已實作基本流程。

- 使用 `sign_in_with_apple` 套件
- 請求 `email` 和 `fullName` scope
- Apple 不支援 silent sign-in，重啟 App 時從 SharedPreferences 恢復使用者資訊
- iCloud 雲端儲存為 placeholder（需要 CloudKit 設定）

### Microsoft Sign-In

**狀態**: 未實作。`aad_oauth` 套件已加入 dependency，但 `signInWithMicrosoft()` 僅回傳錯誤訊息。需要 Azure AD App Registration。

---

## 憑證儲存

### 各平台儲存機制

| 平台 | 機制 | 說明 |
|------|------|------|
| **iOS** | Keychain (由 `google_sign_in` SDK 管理) | OAuth token 由 SDK 內部管理，App 不直接存取 |
| **Android** | AccountManager / Keystore (由 `google_sign_in` SDK 管理) | 同上 |
| **macOS** | Keychain (由 `google_sign_in` SDK 管理) | 已配置 `com.apple.security.network.client` entitlement |
| **Web** | Browser session / cookies | 由 Google Sign-In JS SDK 管理 |

### 使用者資訊持久化

使用者基本資訊（id, email, displayName, provider）透過 `SharedPreferences` 儲存：

```dart
static const String _userPrefKey = 'auth_user';
static const String _syncPrefKey = 'cloud_sync_prefs';
```

**注意**: `SharedPreferences` 在各平台的安全性：

| 平台 | 儲存位置 | 加密 |
|------|---------|------|
| iOS | NSUserDefaults (App sandbox) | 否（sandbox 保護） |
| Android | XML file (App internal storage) | 否（App sandbox 保護） |
| macOS | plist file (App container) | 否（sandbox 保護） |
| Web | localStorage | 否 |

目前未儲存 OAuth token 到 SharedPreferences -- token 由 SDK 自行管理。SharedPreferences 僅儲存非敏感的使用者資訊（display name、email）用於 UI 顯示和 session 恢復判斷。

---

## API 安全

### 目前狀態: 無認證

Backend API (`src/api.py`) **目前沒有任何認證機制**。所有端點皆為公開存取：

```python
# CORS - 目前允許所有來源
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],          # 所有來源
    allow_credentials=True,
    allow_methods=["*"],          # 所有方法
    allow_headers=["*"],          # 所有 header
)
```

API 提供的是 **唯讀** 分析功能（查詢 KataGo 分析結果），不處理使用者資料，因此目前的安全風險較低。但 CORS 應在 production 環境限制。

### API 端點風險評估

| 端點 | 方法 | 風險 | 說明 |
|------|------|------|------|
| `/health` | GET | 低 | 系統狀態，無敏感資訊 |
| `/analyze` | POST | 中 | 可能觸發 KataGo 運算（資源消耗） |
| `/query` | POST | 低 | 僅查詢快取 |
| `/stats` | GET | 低 | 快取統計，含 DB 路徑（可移除） |

### 建議的未來安全措施

1. **Rate Limiting** -- 限制 `/analyze` 的請求頻率，防止資源濫用
2. **CORS 白名單** -- 限制 `allow_origins` 到已知的 App domain
3. **API Key** -- 為 App client 分配 API key（若 API 公開部署）
4. **Input Validation** -- 目前已有 Pydantic model 驗證，但可加強 moves 格式檢查

---

## 資料保護

### 本地資料庫

- **分析快取** (`analysis_cache.db`): 使用 SQLite，**未加密**。包含棋盤分析結果，非敏感資料
- **棋譜記錄**: 透過 `GameRecordService` 儲存，使用 SQLite，**未加密**
- 資料庫檔案存放在 App 的 Application Support 目錄（有 OS sandbox 保護）

### 網路安全

| 項目 | 狀態 | 說明 |
|------|------|------|
| **HTTPS** | 部分 | Google/Apple OAuth 強制 HTTPS；API 連線取決於部署方式 |
| **ATS (iOS)** | 已停用 | `NSAllowsArbitraryLoads = true`（允許 HTTP，用於本地開發） |
| **cleartext (Android)** | 已啟用 | `android:usesCleartextTraffic="true"`（允許 HTTP） |

**重要**: Production 部署時應：
- iOS: 移除 `NSAllowsArbitraryLoads` 或配置 exception domain
- Android: 設定 `android:usesCleartextTraffic="false"` 並使用 Network Security Config
- API Server: 使用 HTTPS（TLS 1.2+）

### Debug / Log 中的敏感資訊

`auth_service.dart` 中使用 `debugPrint` 輸出登入資訊：

```dart
debugPrint('Signed in with Google: ${_user?.email}');
debugPrint('Google sign in error: $e');
```

這些只在 debug build 中輸出。Flutter 的 `debugPrint` 在 release build 中會被 tree-shaken 移除，不會出現在 production binary。

---

## Secret 管理

### 目前的 Secret 清單

| Secret | 存放位置 | Git 追蹤 |
|--------|---------|---------|
| Google OAuth Client ID (macOS) | `mobile/macos/Runner/Info.plist` | 是 (非機密) |
| Google OAuth Client ID (iOS) | `mobile/ios/Runner/Info.plist` | 是 (placeholder) |
| `.env` 檔案 | 專案根目錄 | 否 (.gitignore) |
| `google-services.json` | 不存在 | -- |
| `GoogleService-Info.plist` | 不存在 | -- |

**注意**: OAuth Client ID 本身不是 secret（它是公開的 identifier），真正的 secret 是 Client Secret，目前未使用（mobile app 使用 PKCE flow，不需要 client secret）。

### .gitignore 中的安全規則

```gitignore
# Environment variables (secrets)
.env
.env.local
.env.production

# Database (可能包含分析資料)
*.db
```

### 建議新增的 .gitignore 規則

```gitignore
# Firebase config (if added in future)
google-services.json
GoogleService-Info.plist

# Keystore (Android signing)
*.jks
*.keystore
key.properties
```

---

## 新功能安全檢查清單

開發新功能時，檢查以下安全項目：

### 認證相關

- [ ] 是否需要認證？如果是，使用 `AuthService` 而非自行實作
- [ ] 是否正確處理未登入狀態（anonymous mode）？
- [ ] 是否在 token 過期時正確重試？

### 資料儲存

- [ ] 是否儲存敏感資料？使用平台原生安全儲存（非 SharedPreferences）
- [ ] 本地資料庫查詢是否使用參數化查詢（防 SQL injection）？
- [ ] 是否在 log 中輸出敏感資訊？確認僅在 debug build 中輸出

### 網路通訊

- [ ] API 呼叫是否使用 HTTPS？
- [ ] 是否驗證 server 憑證？（不要停用 SSL verification）
- [ ] 是否正確處理 CORS？
- [ ] 輸入資料是否經過驗證？（Pydantic model / Dart type check）

### 第三方套件

- [ ] 新增的套件是否來自可信來源？
- [ ] 是否檢查套件的已知漏洞？

---

## 未來安全規劃

### 短期 (P0 -- 修復已知問題)

1. **修復 macOS Google Sign-In callback** -- OAuth 完成後 UI 未更新
2. **配置 iOS OAuth Client ID** -- 替換 Info.plist 中的 placeholder
3. **限制 ATS / cleartext** -- Production build 應強制 HTTPS

### 中期 (P1 -- 強化安全)

4. **API Rate Limiting** -- 防止 `/analyze` 端點資源濫用
5. **CORS 白名單** -- 限制 API 的 allowed origins
6. **Certificate Pinning** -- 可選，針對 API server 的 TLS 憑證固定
7. **實作 iCloud CloudKit 整合** -- 完成 Apple Sign-In 雲端同步

### 長期 (P2 -- 完整安全架構)

8. **實作 Microsoft Sign-In** -- Azure AD OAuth + OneDrive 整合
9. **端對端加密** -- 雲端棋譜加密儲存
10. **安全審計** -- 定期檢查第三方套件漏洞
11. **Biometric 保護** -- 可選的 Face ID / Touch ID 解鎖

---

## 相關檔案

| 檔案 | 說明 |
|------|------|
| `mobile/lib/services/auth_service.dart` | 認證服務（Google、Apple、Microsoft） |
| `mobile/lib/services/cloud_storage_service.dart` | 雲端儲存服務（Drive、iCloud、OneDrive） |
| `mobile/lib/services/api_service.dart` | API 通訊服務 |
| `mobile/lib/models/game_record.dart` | 棋譜模型（含雲端同步狀態） |
| `mobile/ios/Runner/Info.plist` | iOS OAuth / ATS 配置 |
| `mobile/macos/Runner/Info.plist` | macOS OAuth 配置 |
| `mobile/macos/Runner/DebugProfile.entitlements` | macOS Debug entitlements |
| `mobile/macos/Runner/Release.entitlements` | macOS Release entitlements |
| `mobile/android/app/src/main/AndroidManifest.xml` | Android 網路權限配置 |
| `src/api.py` | Backend API（CORS、端點定義） |
| `.gitignore` | Secret 排除規則 |
