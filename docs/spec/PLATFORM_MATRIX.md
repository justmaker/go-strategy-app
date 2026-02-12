# Platform Support Matrix

> **Version**: 1.0
> **Updated**: 2026-02-12
> **Framework**: Flutter 3.38.9 / Dart SDK ^3.5.0

本文件定義 Go Strategy App 在各平台上的功能支援、技術差異與已知限制。

---

## 1. Platform Support Overview (平台支援總覽)

| Platform | Status | Target | Min Version | Rendering |
|----------|--------|--------|-------------|-----------|
| **Android** | Production | ARM64, x86_64 | API 24 (Android 7.0) | Skia |
| **iOS** | Production | ARM64 | iOS 12+ | Metal |
| **macOS** | Production | ARM64, x86_64 | macOS 10.14+ | Metal |
| **Windows** | Production | x86_64, ARM64 | Windows 10+ | DirectX |
| **Linux** | CI Only | x86_64 | GTK 3.0+ | OpenGL |
| **Web** | Supported | Browser | Modern browsers | CanvasKit / HTML |

---

## 2. Feature Support Matrix (功能支援矩陣)

每個功能在各平台上的支援狀態，以及實作方式的差異。

### 2.1 Core Features (核心功能)

| Feature | Web | Android | iOS | macOS | Windows | Linux |
|---------|:---:|:-------:|:---:|:-----:|:-------:|:-----:|
| Board Display (棋盤顯示) | OK | OK | OK | OK | OK | OK |
| Stone Placement (落子) | OK | OK | OK | OK | OK | OK |
| Move Undo (悔棋) | OK | OK | OK | OK | OK | OK |
| Move Numbers Toggle | OK | OK | OK | OK | OK | OK |
| Move Confirmation Mode | OK | OK | OK | OK | OK | OK |
| Board Size Switch (9/13/19) | OK | OK | OK | OK | OK | OK |
| Coordinate Display | OK | OK | OK | OK | OK | OK |

### 2.2 Analysis Features (分析功能)

| Feature | Web | Android | iOS | macOS | Windows | Linux |
|---------|:---:|:-------:|:---:|:-----:|:-------:|:-----:|
| Opening Book Lookup | OK | OK | OK | OK | OK | OK |
| Local SQLite Cache | -- | OK | OK | OK | OK | OK |
| API Analysis (Remote) | OK | OK | OK | OK | OK | OK |
| Local KataGo (Native) | -- | JNI | FFI* | Process | Process | Process |
| Real-time Progress | -- | OK | OK* | OK | OK | OK |
| Symmetry Expansion | OK | OK | OK | OK | OK | OK |

> **--** = Not supported on this platform
> **OK*** = Requires native library build; iOS KataGo via CocoaPods framework

### 2.3 Authentication (認證登入)

| Provider | Web | Android | iOS | macOS | Windows | Linux |
|----------|:---:|:-------:|:---:|:-----:|:-------:|:-----:|
| Anonymous (Local only) | OK | OK | OK | OK | OK | OK |
| Google Sign-In | OK | OK | OK | OK | OK | OK |
| Apple Sign-In | OK | -- | OK | OK | -- | -- |
| Microsoft Sign-In | WIP | WIP | WIP | WIP | WIP | WIP |

> Apple Sign-In: 僅在 Apple 平台 (iOS/macOS) 及 Web 上可用。`auth_service.dart` 中以 `Platform.isIOS || Platform.isMacOS` 判斷。
> Microsoft Sign-In: 使用 `aad_oauth` 套件，目前為 placeholder，尚未實作。

### 2.4 Cloud Storage (雲端同步)

| Provider | Web | Android | iOS | macOS | Windows | Linux |
|----------|:---:|:-------:|:---:|:-----:|:-------:|:-----:|
| Google Drive | OK | OK | OK | OK | OK | OK |
| iCloud | -- | -- | OK | OK | -- | -- |
| OneDrive | WIP | WIP | WIP | WIP | WIP | WIP |

### 2.5 File Operations (檔案操作)

| Feature | Web | Android | iOS | macOS | Windows | Linux |
|---------|:---:|:-------:|:---:|:-----:|:-------:|:-----:|
| SGF Export (Share) | Share | Share | Share | FilePicker | FilePicker | FilePicker |
| SGF Import | -- | OK | OK | OK | OK | OK |
| File Save Dialog | -- | -- | -- | OK | OK | OK |

> Web 使用 `share_plus`，Mobile 使用 `share_plus`，Desktop 使用 `file_picker` 的 `saveFile()` dialog。
> 平台判斷邏輯在 `analysis_screen.dart` 中：`Platform.isMacOS || Platform.isWindows || Platform.isLinux` 走 FilePicker 路徑。

### 2.6 Offline Capability (離線功能)

| Feature | Web | Android | iOS | macOS | Windows | Linux |
|---------|:---:|:-------:|:---:|:-----:|:-------:|:-----:|
| Opening Book (Bundled) | OK | OK | OK | OK | OK | OK |
| Local Cache (SQLite) | -- | OK | OK | OK | OK | OK |
| Local KataGo Engine | -- | OK | OK* | OK | OK | OK |
| Full Offline Mode | Partial | OK | OK* | OK | OK | OK |

> Web 無法使用 SQFlite（`kIsWeb` 時 disabled），也無法跑本地 KataGo，離線模式僅限 Opening Book。

---

## 3. KataGo Engine Availability (KataGo 引擎可用性)

KataGo 本地引擎在各平台的實作方式不同：

| Platform | Implementation | Service Class | Communication | Native Code |
|----------|---------------|---------------|---------------|-------------|
| **Android** | JNI (NDK) | `KataGoService` | Platform Channel (MethodChannel/EventChannel) | `KataGoEngine.kt` + C++ via CMake |
| **iOS** | FFI (CocoaPods) | `KataGoService` | Platform Channel (MethodChannel/EventChannel) | `KataGoWrapper.mm` + C++ (KataGoMobile pod) |
| **macOS** | Subprocess | `KataGoDesktopService` | stdin/stdout JSON (Analysis API) | System `katago` binary |
| **Windows** | Subprocess | `KataGoDesktopService` | stdin/stdout JSON (Analysis API) | System `katago.exe` binary |
| **Linux** | Subprocess | `KataGoDesktopService` | stdin/stdout JSON (Analysis API) | System `katago` binary |
| **Web** | N/A | -- | -- | -- |

### 3.1 Desktop Engine Discovery (桌面版引擎偵測)

`KataGoDesktopService.findKataGoPath()` 會依序搜尋：

```
/opt/homebrew/bin/katago      (macOS Apple Silicon)
/usr/local/bin/katago          (macOS Intel / Linux)
/usr/bin/katago                (Linux)
C:\Program Files\KataGo\katago.exe  (Windows)
which katago / where katago    (PATH fallback)
```

### 3.2 Mobile Engine (行動版引擎)

- **Android**: 透過 JNI 載入 `libkatago_mobile.so`，使用 NDK CMake 建置。需要 minSdk 24。
- **iOS**: 透過 CocoaPods framework `KataGoMobile`，包含 Eigen 數學庫及 KataGo 原始碼。

### 3.3 Analysis Fallback Chain (分析回退鏈)

所有平台共用相同的分析優先順序（定義在 `GameProvider.analyze()`）：

```
1. Opening Book (bundled JSON)     → Instant, all platforms
2. Local Cache (SQLite)            → Instant, non-web platforms
3. Local KataGo Engine             → Seconds, depends on platform
4. Remote API (server)             → Network dependent
5. No analysis available           → Error message
```

---

## 4. Platform Detection Logic (平台偵測邏輯)

程式碼中的關鍵平台判斷：

```dart
// Desktop detection (game_provider.dart:116)
bool get _isDesktop =>
    !kIsWeb && (Platform.isMacOS || Platform.isWindows || Platform.isLinux);

// FFI vs SQFlite plugin (cache_service.dart:42)
if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    initFfiDatabase();  // sqflite_common_ffi
} else {
    getDatabasesPath(); // sqflite (mobile plugin)
}

// Web disabled (cache_service.dart:36)
if (kIsWeb) {
    return; // SQFlite not available on web
}

// Apple Sign-In availability (auth_service.dart:143)
case AuthProvider.apple:
    if (kIsWeb) return true;
    return !kIsWeb && (Platform.isIOS || Platform.isMacOS);

// Android emulator API URL (config.dart:50)
if (Platform.isAndroid) return 'http://10.0.2.2:$apiPort';
```

### 4.1 Conditional Imports (條件式匯入)

SQLite FFI 使用 conditional import 處理 Web 相容性：

```dart
// cache_service.dart:15-16
import 'cache_service_ffi_stub.dart'
    if (dart.library.io) 'cache_service_ffi.dart';
```

- `cache_service_ffi.dart`: Desktop 實作，初始化 `sqflite_common_ffi`
- `cache_service_ffi_stub.dart`: Web stub，`initFfiDatabase()` 為 no-op

---

## 5. UI Framework Decisions (UI 框架決策)

### 5.1 Design System

- **Primary**: Material Design (`uses-material-design: true` in `pubspec.yaml`)
- **iOS/macOS additions**: `cupertino_icons` 套件提供 Cupertino 風格圖示
- **Custom rendering**: 棋盤使用 Flutter `CustomPainter` 直接 Canvas 繪製，不依賴任何平台 widget

### 5.2 Layout Strategy (佈局策略)

根據 `docs/UI_SPEC.md` 定義：

| Layout | Screen Width | Board | Panel |
|--------|-------------|-------|-------|
| Portrait (Mobile) | < 600dp | Top, full width | Bottom, scrollable |
| Landscape (Tablet) | 600-1200dp | Left, square | Right, sidebar |
| Desktop | > 1200dp | Left, fixed size | Right, expanded |

### 5.3 Platform-Specific UI Behaviors

| Behavior | Mobile | Desktop | Web |
|----------|--------|---------|-----|
| File Export | Share sheet | Save file dialog | Share/Download |
| Touch input | Tap to place | Click to place | Click to place |
| Move confirmation | Optional overlay | Optional overlay | Optional overlay |
| Settings | Bottom sheet | Bottom sheet | Bottom sheet |
| Rendering engine | Skia/Metal | Metal/DirectX | CanvasKit (slow) |

---

## 6. Build Requirements (建置需求)

### 6.1 SDK & Tools

| Platform | Runner OS | Required Tools | SDK |
|----------|-----------|---------------|-----|
| **Android** | Any | Java 17, Android SDK, NDK | compileSdk 36, minSdk 24 |
| **iOS** | macOS | Xcode, CocoaPods | iOS 12+ |
| **macOS** | macOS | Xcode, CocoaPods | macOS 10.14+ |
| **Windows** | Windows | Visual Studio Build Tools | Windows 10+ |
| **Linux** | Linux | GCC/Clang, ninja-build, libgtk-3-dev, libsecret-1-dev, libjsoncpp-dev | GTK 3+ |
| **Web** | Any | Chrome (for testing) | Modern browsers |

### 6.2 Cross-Build Limitation Matrix (跨平台建置限制)

| Build Machine | Web | Android | iOS | macOS | Windows | Linux |
|--------------|:---:|:-------:|:---:|:-----:|:-------:|:-----:|
| **macOS** | OK | OK | OK | OK | -- | -- |
| **Windows** | OK | OK | -- | -- | OK | -- |
| **Linux** | OK | OK | -- | -- | -- | OK |

> iOS/macOS 只能在 macOS 上建置（需 Xcode）。Windows 只能在 Windows 上建置。Linux 只能在 Linux 上建置。

### 6.3 Flutter Version

CI/CD 統一使用 `flutter-version: '3.38.9'`（stable channel），定義在 `.github/workflows/release.yml`。

---

## 7. CI/CD Platform Coverage (CI/CD 平台覆蓋)

Release workflow (`release.yml`) 使用 `workflow_dispatch` 觸發，建置所有 6 個平台：

| Job | Runner | Output |
|-----|--------|--------|
| `build-android` | `ubuntu-latest` | `app-release.apk` |
| `build-ios` | `macos-latest` | `runner-app.zip` (unsigned) |
| `build-macos` | `macos-latest` | `go-strategy-macos.zip` |
| `build-windows` | `windows-latest` | `go-strategy-windows.zip` |
| `build-linux` | `ubuntu-latest` | `linux-app.tar.gz` |
| `release` | `ubuntu-latest` | GitHub Release with all assets |

### 7.1 Platform-Specific CI Steps

- **Android**: 需額外設定 Java 17 (`actions/setup-java`)，快取 Gradle
- **iOS/macOS**: 快取 CocoaPods，iOS 使用 `--no-codesign`
- **Windows**: PowerShell 處理版號更新，`Compress-Archive` 打包
- **Linux**: 需安裝系統套件 (`ninja-build`, `libgtk-3-dev`, `libsecret-1-dev`, `libjsoncpp-dev`)，且使用 `flutter create --platforms=linux .` 啟用 Linux 支援

---

## 8. Native APIs by Platform (平台原生 API)

### 8.1 File System Access (檔案系統)

| Platform | DB Storage Path | Method |
|----------|----------------|--------|
| Android | App internal storage | `getDatabasesPath()` (sqflite) |
| iOS | App sandbox | `getDatabasesPath()` (sqflite) |
| macOS | `~/Library/Application Support/` | `getApplicationSupportDirectory()` + FFI |
| Windows | `%APPDATA%/` | `getApplicationSupportDirectory()` + FFI |
| Linux | `~/.local/share/` | `getApplicationSupportDirectory()` + FFI |
| Web | N/A | SQFlite disabled |

### 8.2 Bundled Data (打包資料)

所有非 Web 平台在首次啟動時，會從 Flutter assets 複製 bundled database：

```
assets/data/analysis.db        → Local SQLite cache (initial data)
assets/opening_book.json.gz    → In-memory opening book index
assets/katago/model.bin.gz     → KataGo neural network model
assets/katago/analysis.cfg     → KataGo configuration
```

### 8.3 Keychain / Secure Storage

| Platform | Auth Persistence | Implementation |
|----------|-----------------|----------------|
| All platforms | `SharedPreferences` | `shared_preferences` package |

> 目前認證資訊使用 `SharedPreferences` 儲存（非加密），Google Sign-In token 由 SDK 自行管理。

### 8.4 App Lifecycle

| Platform | Behavior |
|----------|----------|
| Android | KataGo engine lifecycle tied to Flutter Engine |
| iOS | Same as Android; background suspension may kill engine |
| macOS | KataGo subprocess managed by `Process.start()` / `Process.kill()` |
| Windows | Same as macOS |
| Linux | Same as macOS |
| Web | No engine lifecycle; depends on browser tab |

---

## 9. Known Limitations & Workarounds (已知限制)

### 9.1 Web Platform

| Issue | Detail | Workaround |
|-------|--------|------------|
| No SQFlite | `sqflite` 不支援 Web | 離線僅依賴 Opening Book JSON |
| No local KataGo | 無法在瀏覽器執行 native binary | 必須連線 API server |
| Canvas redraw | 每步棋完整重繪，效能差 | 避免在 Web 上進行開發測試 |
| `dart:io` unavailable | Web 不能使用 `Platform.*` | 使用 `kIsWeb` 先判斷 |

### 9.2 Windows Platform

| Issue | Detail | Workaround |
|-------|--------|------------|
| VM build required | macOS 無法交叉編譯 Windows | 使用 UTM/VM 建立 Windows 11 ARM64 環境 |
| Shared folder limitation | UTM 共用資料夾 (Z:) 上建置會失敗 | 使用 `sync_windows.ps1` 同步到 C: 本地磁碟 |
| KataGo binary | 需要自行安裝 `katago.exe` | `windows_setup.ps1` 自動安裝 |

### 9.3 Linux Platform

| Issue | Detail | Workaround |
|-------|--------|------------|
| No local directory | 專案中無 `mobile/linux/` 目錄 | CI 使用 `flutter create --platforms=linux .` 動態產生 |
| System dependencies | 需要多個系統套件 | CI 中 `apt-get install` 處理 |

### 9.4 iOS Platform

| Issue | Detail | Workaround |
|-------|--------|------------|
| Code signing | 開發測試版無簽名 | 使用 `--no-codesign` |
| KataGo build | 需要編譯 KataGoMobile pod (含 Eigen) | CocoaPods 自動處理 |
| Background suspension | iOS 背景暫停可能終止引擎 | 回前台時自動重啟 |

### 9.5 Android Platform

| Issue | Detail | Workaround |
|-------|--------|------------|
| Native library loading | `libkatago_mobile.so` 可能載入失敗 | `KataGoEngine.loadNativeLibrary()` 有 try-catch 防護 |
| CPU heat | 長時間分析可能造成手機發熱 | 降低 `maxVisits` 或使用 `numSearchThreads = 2` |
| Emulator API URL | localhost 需映射 | 自動使用 `10.0.2.2` |

---

## 10. Testing Priority (測試優先順序)

根據 `CLAUDE.md` 與 `TEST.md` 定義的測試策略：

### 10.1 Development Testing Order

```
1. macOS Native (推薦)  → Metal 渲染、效能佳、95%+ 程式碼共用
2. Unit Tests           → flutter test (pure Dart logic)
3. Android Device       → JNI/NDK 引擎驗證
4. iOS Device           → FFI 引擎驗證、Apple Sign-In
5. Windows VM           → 建置驗證
6. Web                  → 最後 (Canvas 效能差，僅驗證 API 連線)
```

### 10.2 Test Coverage Equivalence (測試等價性)

在 macOS 原生版測試通過的功能，等價於在所有平台測試：

| Tested on macOS | Equivalent for |
|-----------------|---------------|
| UI Components & Layout | All platforms |
| GameProvider State Management | All platforms |
| Opening Book Lookup | All platforms |
| CacheService CRUD | All platforms |
| Board Interaction Logic | All platforms |
| Coordinate Conversion | All platforms |

### 10.3 Platform-Specific Tests Required

| Test | Platform | Reason |
|------|----------|--------|
| KataGo JNI Engine | Android device | NDK native library |
| KataGo FFI Engine | iOS device | CocoaPods framework |
| Apple Sign-In | iOS/macOS | Platform-specific API |
| Windows build | Windows VM | Build toolchain |
| Canvas performance | Web | CanvasKit rendering |

---

## 11. Build Output Reference (建置輸出參考)

| Platform | Command | Output Path | Typical Size |
|----------|---------|-------------|-------------|
| Web | `flutter build web --release` | `build/web/` | ~36 MB |
| Android APK | `flutter build apk --release` | `build/app/outputs/flutter-apk/app-release.apk` | ~25-54 MB |
| Android AAB | `flutter build appbundle --release` | `build/app/outputs/bundle/release/app-release.aab` | Smaller |
| iOS | `flutter build ios --release` | `build/ios/iphoneos/Runner.app` | ~22 MB |
| macOS | `flutter build macos --release` | `build/macos/Build/Products/Release/go_strategy_app.app` | ~47 MB |
| Windows | `flutter build windows --release` | `build/windows/x64/runner/Release/` | -- |
| Linux | `flutter build linux --release` | `build/linux/x64/release/bundle/` | -- |

---

**Related Documents**:
- [CLAUDE.md](../../CLAUDE.md) - 開發指引與測試優先順序
- [BUILD_OUTPUTS.md](../../mobile/BUILD_OUTPUTS.md) - 詳細建置指南
- [WINDOWS_BUILD.md](../../mobile/WINDOWS_BUILD.md) - Windows VM 建置指南
- [TEST.md](TEST.md) - 測試規範
- [UI_SPEC.md](../UI_SPEC.md) - UI 設計規範
