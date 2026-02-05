# 雲端服務設定指南

本文件說明如何設定 Google、Apple、Microsoft 登入及雲端儲存功能。

## 1. Google Sign-In + Google Drive

### 步驟 1: 建立 Google Cloud 專案

1. 前往 [Google Cloud Console](https://console.cloud.google.com/)
2. 建立新專案或選擇現有專案
3. 啟用以下 API:
   - Google Drive API
   - Google Sign-In

### 步驟 2: 設定 OAuth 同意畫面

1. 前往 APIs & Services > OAuth consent screen
2. 選擇 "External" 使用者類型
3. 填寫應用程式資訊:
   - 應用程式名稱: Go Strategy
   - 使用者支援電子郵件: 您的電子郵件
   - 開發人員聯絡資訊: 您的電子郵件
4. 新增範圍 (Scopes):
   - `email`
   - `profile`
   - `https://www.googleapis.com/auth/drive.file`
   - `https://www.googleapis.com/auth/drive.appdata`

### 步驟 3: 建立 OAuth 2.0 憑證

#### iOS 憑證:
1. 前往 APIs & Services > Credentials
2. 建立 OAuth client ID
3. 應用程式類型: iOS
4. Bundle ID: `com.example.goStrategyApp` (或您的 Bundle ID)
5. 下載 `GoogleService-Info.plist`
6. 將檔案放入 `ios/Runner/` 目錄

#### Android 憑證:
1. 建立 OAuth client ID
2. 應用程式類型: Android
3. Package name: `com.example.go_strategy_app`
4. SHA-1 憑證指紋: 
   ```bash
   keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey -storepass android -keypass android
   ```
5. 下載 `google-services.json`
6. 將檔案放入 `android/app/` 目錄

### 步驟 4: 更新設定檔

#### iOS (`ios/Runner/Info.plist`):
將 `YOUR_CLIENT_ID` 替換為實際的 Client ID:
```xml
<key>CFBundleURLSchemes</key>
<array>
    <string>com.googleusercontent.apps.ACTUAL_CLIENT_ID</string>
</array>
<key>GIDClientID</key>
<string>ACTUAL_CLIENT_ID.apps.googleusercontent.com</string>
```

#### macOS (`macos/Runner/Info.plist`):
與 iOS 相同，將 `YOUR_CLIENT_ID` 替換為實際的 Client ID:
```xml
<key>CFBundleURLSchemes</key>
<array>
    <string>com.googleusercontent.apps.ACTUAL_CLIENT_ID</string>
</array>
<key>GIDClientID</key>
<string>ACTUAL_CLIENT_ID.apps.googleusercontent.com</string>
```

**注意**: macOS 需要在 Google Cloud Console 建立獨立的 OAuth client ID (Desktop 類型)。

#### Android (`android/app/build.gradle`):
確認已新增:
```gradle
apply plugin: 'com.google.gms.google-services'
```

---

## 2. Apple Sign-In + iCloud

### 步驟 1: Apple Developer 設定

1. 前往 [Apple Developer](https://developer.apple.com/)
2. 在 Certificates, Identifiers & Profiles 中:
   - 編輯您的 App ID
   - 啟用 "Sign In with Apple"
   - 啟用 "iCloud" (選擇 CloudKit)

### 步驟 2: Xcode 設定

1. 在 Xcode 開啟專案
2. 選擇 Runner target
3. 前往 Signing & Capabilities
4. 新增 "Sign In with Apple" capability
5. 新增 "iCloud" capability (選擇 CloudKit)

### 步驟 3: 設定 CloudKit Container

1. 在 iCloud 設定中，建立新的 CloudKit container
2. Container ID: `iCloud.com.example.goStrategyApp`

---

## 3. Microsoft Sign-In + OneDrive (即將推出)

### 步驟 1: Azure AD 設定

1. 前往 [Azure Portal](https://portal.azure.com/)
2. 建立 App Registration
3. 設定 Redirect URI
4. 新增 API 權限:
   - Microsoft Graph > Files.ReadWrite
   - Microsoft Graph > User.Read

### 步驟 2: 更新程式碼

在 `lib/services/auth_service.dart` 中設定 Azure AD 配置:
```dart
// TODO: 實作中
```

---

## 資料儲存位置

| 登入方式 | 雲端儲存位置 |
|---------|-------------|
| Google | Google Drive > Go Strategy 資料夾 |
| Apple | iCloud > Go Strategy 資料夾 |
| Microsoft | OneDrive > Apps > Go Strategy 資料夾 |

所有棋譜都儲存在使用者自己的雲端空間中，用戶可以：
- 在雲端硬碟中直接查看檔案
- 手動刪除或管理檔案
- 使用其他應用程式開啟 SGF 檔案

---

## 測試

### 本機測試 (不需要實際憑證):
```bash
cd mobile
flutter run
```

登入功能會顯示錯誤訊息，但其他功能可正常使用（匿名模式）。

### 完整測試:
1. 完成上述設定
2. 執行 `flutter run`
3. 點擊「使用 Google 登入」
4. 完成登入流程
5. 啟用雲端同步
6. 儲存一個棋譜
7. 確認檔案出現在 Google Drive 的 "Go Strategy" 資料夾中
