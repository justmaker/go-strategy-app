# Flutter 各平台建置輸出路徑

**專案目錄:** `/Users/rexhsu/Documents/go-strategy-app/mobile`

---

## 建置指令與輸出位置

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
flutter build ios --release
```

**輸出位置:** `build/ios/iphoneos/Runner.app`

**注意事項:**
- 需要 macOS 系統
- 需要 Apple Developer 帳號
- 需要在 Xcode 中設定簽名憑證
- 目前受 macOS Sonoma codesign 問題影響

---

### macOS (桌面版)

```bash
flutter build macos --release
```

**輸出位置:** `build/macos/Build/Products/Release/go_strategy_app.app`

**安裝方式:** 將 `.app` 拖入「應用程式」資料夾

**注意事項:** 目前受 `com.apple.provenance` codesign 問題影響

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

## 清除建置檔案

```bash
# 清除所有建置輸出
flutter clean

# 重新取得相依套件
flutter pub get
```

---

## 目前建置狀態

| 平台 | 狀態 | 備註 |
|------|------|------|
| Web | ✅ 可建置 | 已測試，36MB |
| Android APK | ⚠️ 未測試 | 需要執行建置 |
| iOS | ❌ 受阻 | macOS Sonoma codesign 問題 |
| macOS | ❌ 受阻 | macOS Sonoma codesign 問題 |
| Windows | ❌ 需 Windows | 無法在 macOS 上交叉編譯 |
| Linux | ⚠️ 未測試 | 需要執行建置 |
