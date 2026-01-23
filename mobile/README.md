# Go Strategy Mobile App

A Flutter-based mobile app for Go (Weiqi/Baduk) strategy analysis, powered by KataGo AI.

## Features

- Interactive Go board with tap-to-play
- Real-time AI analysis with move suggestions
- Color-coded recommendations (Blue=Best, Green=Good, Yellow=OK)
- Offline support with local SQLite cache
- Support for 9x9, 13x13, and 19x19 boards
- Configurable analysis visits and komi

## Prerequisites

1. **Flutter SDK** (3.5.0+): [Installation Guide](https://flutter.dev/docs/get-started/install)
2. **Android SDK** (for Android builds)
3. **Java 11+** (for Android builds)

## Configuration

Before building, edit `lib/config.dart` to set your API server URL:

```dart
class AppConfig {
  // Change this to your server's address
  static const String apiBaseUrl = 'http://YOUR_SERVER_IP:8000';
  
  // ... other settings
}
```

## Building the APK

### Option 1: Using the build script

```bash
cd mobile

# Build with default API URL (from config.dart)
./build_apk.sh

# Or override the API URL during build
./build_apk.sh http://192.168.1.100:8000
```

### Option 2: Manual build

```bash
cd mobile

# Get dependencies
flutter pub get

# Build release APK
flutter build apk --release
```

The APK will be at: `build/app/outputs/flutter-apk/app-release.apk`

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
├── config.dart          # App configuration (API URL, defaults)
├── main.dart            # App entry point
├── models/              # Data models
│   ├── board_state.dart # Board state management
│   └── analysis_result.dart
├── providers/           # State management
│   └── game_provider.dart
├── screens/             # UI screens
│   └── analysis_screen.dart
├── services/            # Backend services
│   ├── api_service.dart # REST API client
│   └── cache_service.dart
└── widgets/             # UI components
    └── go_board_widget.dart
```

## Coordinate System

The app uses GTP (Go Text Protocol) standard coordinates:
- **X-axis**: A-T (left to right, skipping 'I')
- **Y-axis**: 1-19 (bottom to top)

Example: Q16 = column Q (16th), row 16

## API Requirements

The mobile app requires a running Go Strategy API server. See the main project README for server setup instructions.

Endpoints used:
- `GET /health` - Connection check
- `POST /analyze` - Get AI analysis for a position
- `POST /query` - Check cache for existing analysis
- `GET /stats` - Cache statistics

## Troubleshooting

### "Connection refused" error
- Ensure the API server is running
- Check the API URL in `lib/config.dart`
- If using local network, ensure your device is on the same network
- Android emulator: Use `10.0.2.2` instead of `localhost`

### "Cleartext traffic not permitted" error
- The app is configured to allow HTTP traffic (for local development)
- For production, use HTTPS

### Build errors
```bash
flutter clean
flutter pub get
flutter build apk --release
```

## License

MIT License
