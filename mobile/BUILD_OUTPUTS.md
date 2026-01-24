# Flutter 建置指南

**專案目錄:** `mobile/`

---

## 快速開始：改完程式碼後如何發布新版

### 步驟一：完成開發並 commit

```bash
cd mobile
git add -A
git commit -m "feat: 描述你的改動"
```

### 步驟二：升版號

```bash
# 查看目前版本
./version.sh

# 升版（選一個）
./version.sh bump patch   # 小修正: 1.0.0 → 1.0.1
./version.sh bump minor   # 新功能: 1.0.0 → 1.1.0
./version.sh bump major   # 大改版: 1.0.0 → 2.0.0
```

### 步驟三：Commit 版號變更

```bash
git add pubspec.yaml
git commit -m "release: v1.0.1"
git push
```

### 步驟四：一鍵建置所有平台

```bash
./build_all.sh
```

建置完成後會顯示：
```
平台       狀態       大小       輸出路徑
------    ------    ------    ----------
web       ✅ 成功    36M       build/web/
android   ✅ 成功    25M       build/app/outputs/flutter-apk/app-release.apk
ios       ✅ 成功    22M       build/ios/iphoneos/Runner.app
macos     ✅ 成功    47M       build/macos/Build/Products/Release/go_strategy_app.app
```

### 步驟五：取得建置檔案

建置完成後，各平台的檔案位置請參考下方「快速對照表」。

---

## 跨平台建置限制

| 建置機器 | Web | Android | iOS | macOS | Windows | Linux |
|---------|:---:|:-------:|:---:|:-----:|:-------:|:-----:|
| **macOS** | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ |
| **Windows** | ✅ | ✅ | ❌ | ❌ | ✅ | ❌ |
| **Linux** | ✅ | ✅ | ❌ | ❌ | ❌ | ✅ |

**限制說明：**
- **iOS/macOS** - 只能在 macOS 上建置（需要 Xcode）
- **Windows** - 只能在 Windows 上建置（需要 Visual Studio）
- **Linux** - 只能在 Linux 上建置
- **Web/Android** - 可以在任何平台建置

---

## 各平台建置指令與輸出位置

### Web (網頁版)

```bash
flutter build web --release
```

**輸出位置:** `build/web/`

**主要檔案:**
- `build/web/index.html` - 入口頁面
- `build/web/main.dart.js` - 編譯後的 Dart 程式碼
- `build/web/flutter.js` - Flutter 引擎
- `build/web/assets/` - 資源檔案（圖片、字型、opening_book 等）

**部署方式:** 將整個 `build/web/` 目錄上傳至任何靜態網頁伺服器

---

### Android (APK)

```bash
flutter build apk --release
```

**輸出位置:** `build/app/outputs/flutter-apk/app-release.apk`

**檔案大小:** 約 15-25 MB

**安裝方式:** 
- 傳到手機後直接安裝
- 或上傳至 Google Play Store

---

### Android (App Bundle - 上架用)

```bash
flutter build appbundle --release
```

**輸出位置:** `build/app/outputs/bundle/release/app-release.aab`

**說明:** Google Play Store 推薦使用 AAB 格式，可減少用戶下載大小

---

### iOS

```bash
# 不簽名建置（開發測試用）
flutter build ios --release --no-codesign

# 正式簽名建置（上架用）
flutter build ios --release
```

**輸出位置:** `build/ios/iphoneos/Runner.app`

**檔案大小:** 約 21.8 MB

**注意事項:**
- 需要 macOS 系統
- `--no-codesign` 可跳過簽名，用於測試
- 正式上架需要 Apple Developer 帳號並在 Xcode 中設定簽名憑證

---

### macOS (桌面版)

```bash
flutter build macos --release
```

**輸出位置:** `build/macos/Build/Products/Release/go_strategy_app.app`

**檔案大小:** 約 46.7 MB

**安裝方式:** 
- 直接雙擊執行，或
- 將 `.app` 拖入「應用程式」資料夾

---

### Windows

```bash
flutter build windows --release
```

**輸出位置:** `build/windows/x64/runner/Release/`

**主要檔案:**
- `go_strategy_app.exe` - 主程式
- `flutter_windows.dll` - Flutter 引擎
- `data/` - 資源檔案

**注意事項:** 需要在 Windows 系統上建置

---

### Linux

```bash
flutter build linux --release
```

**輸出位置:** `build/linux/x64/release/bundle/`

**主要檔案:**
- `go_strategy_app` - 主程式（可執行檔）
- `lib/` - 相依函式庫
- `data/` - 資源檔案

---

## 快速對照表

| 平台 | 建置指令 | 輸出路徑 |
|------|---------|---------|
| Web | `flutter build web --release` | `build/web/` |
| Android APK | `flutter build apk --release` | `build/app/outputs/flutter-apk/app-release.apk` |
| Android AAB | `flutter build appbundle --release` | `build/app/outputs/bundle/release/app-release.aab` |
| iOS | `flutter build ios --release` | `build/ios/iphoneos/Runner.app` |
| macOS | `flutter build macos --release` | `build/macos/Build/Products/Release/go_strategy_app.app` |
| Windows | `flutter build windows --release` | `build/windows/x64/runner/Release/` |
| Linux | `flutter build linux --release` | `build/linux/x64/release/bundle/` |

---

## 版本管理

### 版本格式說明

Flutter 版本格式：`主版本.次版本.修訂版+建置號`

例如：`1.2.3+75`
- `1` = 主版本（大改版時升級）
- `2` = 次版本（新功能時升級）
- `3` = 修訂版（修 bug 時升級）
- `75` = 建置號（自動使用 git commit 數量）

### 版本指令

```bash
# 查看目前版本與 git commit 對應
./version.sh

# 升版
./version.sh bump patch   # 修 bug: 1.0.0 → 1.0.1
./version.sh bump minor   # 新功能: 1.0.0 → 1.1.0
./version.sh bump major   # 大改版: 1.0.0 → 2.0.0

# 直接設定版本
./version.sh set 2.0.0
```

### 版本與 Git Commit 的關係

執行 `./version.sh` 會顯示：
```
版本號:        1.0.0
Build Number:  75
完整版本:      1.0.0+75

Git Commit:    7fa221e
Commit Count:  75

建議的版本字串:
  1.0.0+75 (7fa221e)
```

**重點：**
- Build Number 自動等於 git commit 數量
- 所有平台使用相同版號
- 可透過版號追溯到對應的 git commit

---

## 清除建置檔案

```bash
# 清除所有建置輸出
flutter clean

# 重新取得相依套件
flutter pub get
```

---

## 目前建置狀態

| 平台 | 狀態 | 大小 | 備註 |
|------|------|------|------|
| Web | ✅ 已建置 | 36 MB | PWA 可部署到任何網頁伺服器 |
| Android APK | ⚠️ 未測試 | - | 需要執行建置 |
| iOS | ✅ 已建置 | 21.8 MB | 使用 `--no-codesign`，上架需簽名 |
| macOS | ✅ 已建置 | 46.7 MB | 可直接雙擊執行 |
| Windows | ❌ 需 Windows | - | 無法在 macOS 上建置 |
| Linux | ⚠️ 未測試 | - | 無法在 macOS 上建置 |

---

## 常見問題

### Q: 為什麼 Windows/Linux 不能在 Mac 上建置？

Flutter 的桌面版需要對應平台的原生編譯器：
- Windows 需要 Visual Studio (只有 Windows 有)
- Linux 需要 GCC/Clang (需要 Linux 環境)
- macOS/iOS 需要 Xcode (只有 Mac 有)

### Q: 如何確認建置的版本？

1. 執行 `./version.sh` 查看版本和 git commit
2. 在 App 的「設定」頁面底部會顯示版本號
3. 建置時會在終端機顯示版本資訊

### Q: 如何讓 iOS app 可以安裝到手機？

需要以下其中一種方式：
1. **Apple Developer 帳號** - 正式簽名後可安裝
2. **TestFlight** - 透過 Apple 的測試平台分發
3. **Ad-hoc 分發** - 需要先註冊裝置 UDID

---

**最後更新:** 2026-01-25
