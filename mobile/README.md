# Go Strategy Mobile App

A Flutter-based mobile app for Go (Weiqi/Baduk) strategy analysis, powered by KataGo AI.

## Features

- Interactive Go board with tap-to-play
- Real-time AI analysis with move suggestions
- Color-coded recommendations (Blue=Best, Green=Good, Yellow=OK)
- **Offline-first architecture** with bundled opening book
- Local SQLite cache for additional positions
- Support for 9x9, 13x13, and 19x19 boards
- Configurable analysis visits and komi

## Offline Support

The app includes a bundled opening book with ~7,700 pre-analyzed positions:
- **9x9**: ~2,900 positions (500 visits each)
- **13x13**: ~3,000 positions (300 visits each)
- **19x19**: ~1,800 positions (100-150 visits each)

Analysis lookup priority:
1. **Bundled Opening Book** - Instant, always available (~380KB compressed)
2. **Local Cache** - Fast, persisted between sessions
3. **Local KataGo Engine** - On-device AI analysis (Desktop/Mobile)

The UI shows the source of each analysis:
- 📖 **Book** (green) - From bundled opening book
- 💾 **Cache** (blue) - From local SQLite cache
- 🔧 **Engine** (orange) - From local KataGo engine

## Prerequisites

1. **Flutter SDK** (3.38+): [Installation Guide](https://flutter.dev/docs/get-started/install)
2. **Xcode** (for iOS/macOS builds)
3. **Android SDK** (for Android builds) - see setup below
4. **Java 17** (for Android builds with Gradle 8.9+)

### Android SDK Setup (macOS with Homebrew)

Flutter 3.38 requires Android SDK 36, Build Tools 36.0.0, NDK 28.2, and Java 17:

```bash
# 1. Install Java 17
brew install openjdk@17

# 2. Install Android command line tools
brew install --cask android-commandlinetools

# 3. Configure Flutter to use the SDK
flutter config --android-sdk /opt/homebrew/share/android-commandlinetools

# 4. Set environment and install SDK components
export JAVA_HOME=/opt/homebrew/opt/openjdk@17
export PATH="$JAVA_HOME/bin:$PATH"
export ANDROID_SDK_ROOT=/opt/homebrew/share/android-commandlinetools

# Accept licenses
yes | sdkmanager --licenses

# Install required components
sdkmanager "platforms;android-36" "build-tools;36.0.0" "ndk;28.2.13676358"

# 5. Verify setup
flutter doctor -v
```

**Important**: Always set `JAVA_HOME` before running Android builds:
```bash
export JAVA_HOME=/opt/homebrew/opt/openjdk@17
export PATH="$JAVA_HOME/bin:$PATH"
```

## Building

### Android APK

#### Option 1: Using the build script

```bash
cd mobile

# Build with default API URL (from config.dart)
./build_apk.sh

# Or override the API URL during build
./build_apk.sh http://192.168.1.100:8000
```

#### Option 2: Manual build

```bash
cd mobile

# Get dependencies
flutter pub get

# Build release APK
flutter build apk --release
```

The APK will be at: `build/app/outputs/flutter-apk/app-release.apk`

### Web (PWA)

Build the web version for deployment as a Progressive Web App:

```bash
cd mobile

# Get dependencies
flutter pub get

# Build web release
flutter build web --release
```

The web files will be at: `build/web/`

#### Web Deployment Options

1. **Static hosting** (GitHub Pages, Netlify, Vercel):
   ```bash
   # Copy build/web/ contents to your hosting service
   ```

2. **Local testing**:
   ```bash
   cd build/web
   python3 -m http.server 8080
   # Open http://localhost:8080
   ```

### iOS

The iOS version is now supported and includes integrated KataGo engine.

```bash
cd mobile

# Build release iOS app (skipping codesign for distribution via other means)
flutter build ios --release --no-codesign
```

The app will be at: `build/ios/iphoneos/Runner.app`

### macOS

The macOS version is fully supported and can be built directly on Apple Silicon or Intel Macs.

```bash
cd mobile

# Build release macOS app
flutter build macos --release
```

The app will be at: `build/macos/Build/Products/Release/go_strategy_app.app`

### Release Scripts (Automation)

We provide several scripts to automate the build and upload process to GitHub Releases:

- `./release_android.sh`: Builds APK and uploads to GitHub.
- `./release_ios.sh`: Zips `Runner.app` and uploads to GitHub.
- `./release_macos.sh`: Zips `go_strategy_app.app` and uploads to GitHub.
- `./build_all.sh`: Builds all supported platforms at once.

## Updating the Opening Book

To update the bundled opening book with new analysis data:

```bash
# From project root
source venv/bin/activate

# Export with compression (recommended)
python -m src.scripts.export_opening_book --min-visits 100 --compress

# This creates: mobile/assets/opening_book.json.gz
```

Then rebuild the APK to include the updated data.

## Installing the APK

### Via ADB (USB debugging)
```bash
adb install build/app/outputs/flutter-apk/app-release.apk
```

### Manual installation
1. Copy the APK to your Android device
2. Enable "Install from unknown sources" in Settings
3. Open the APK file to install

## Development

### Run in debug mode
```bash
flutter run
```

### Run on specific device
```bash
# List available devices
flutter devices

# Run on specific device
flutter run -d <device_id>
```

### Run tests
```bash
flutter test
```

## Architecture

```
lib/
├── config.dart              # App configuration (API URL, defaults)
├── main.dart                # App entry point
├── models/                  # Data models
│   ├── board_state.dart     # Board state management
│   └── analysis_result.dart
├── providers/               # State management
│   └── game_provider.dart   # Offline-first analysis logic
├── screens/                 # UI screens
│   └── analysis_screen.dart
├── services/                # App services
│   ├── cache_service.dart   # Local SQLite cache
│   ├── opening_book_service.dart  # Bundled opening book
│   ├── katago_service.dart        # Mobile KataGo engine (JNI/FFI)
│   └── katago_desktop_service.dart # Desktop KataGo engine (subprocess)
└── widgets/                 # UI components
    └── go_board_widget.dart

assets/
└── opening_book.json.gz     # Bundled opening book (~380KB)
```

## Coordinate System

The app uses GTP (Go Text Protocol) standard coordinates:
- **X-axis**: A-T (left to right, skipping 'I')
- **Y-axis**: 1-19 (bottom to top)

Example: Q16 = column Q (16th), row 16

## Offline Architecture

App 採用純離線架構，**不依賴任何遠端 API Server**。所有分析在本地完成：
1. Opening Book（隨 App 打包）
2. Local SQLite Cache（累積歷史分析）
3. Local KataGo Engine（Desktop/Mobile 即時運算）

## Troubleshooting

### "Cleartext traffic not permitted" error
- The app is configured to allow HTTP traffic (for local development)
- For production, use HTTPS

### Build errors
```bash
flutter clean
flutter pub get
flutter build apk --release
```

### Android: "JAVA_HOME not set" or wrong Java version
```bash
# Set Java 17 (required for Gradle 8.9)
export JAVA_HOME=/opt/homebrew/opt/openjdk@17
export PATH="$JAVA_HOME/bin:$PATH"

# Verify
java -version  # Should show 17.x
```

### Android: "SDK not found" or wrong SDK path
```bash
# Reconfigure Flutter SDK path
flutter config --android-sdk /opt/homebrew/share/android-commandlinetools

# Verify
flutter doctor -v | grep "Android SDK"
```

### Android: "NDK not found" or license issues
```bash
export JAVA_HOME=/opt/homebrew/opt/openjdk@17
export PATH="$JAVA_HOME/bin:$PATH"
export ANDROID_SDK_ROOT=/opt/homebrew/share/android-commandlinetools

# Accept all licenses
yes | sdkmanager --licenses

# Install NDK
sdkmanager "ndk;28.2.13676358"
```

### Opening book not loading
- Ensure `assets/opening_book.json` or `assets/opening_book.json.gz` exists
- Check that `pubspec.yaml` includes the assets folder
- Run `flutter pub get` after adding assets

## License

MIT License
