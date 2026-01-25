# Development Progress & Handover Note
**Date:** 2026-01-25
**Status:** iOS Simulator & Web (Layout Fixed, Core Functionality Working)

## 📌 Accomplished Today
1.  **AI Analysis Integration (Localhost Fix)**
    *   Enabled iOS Simulator to connect to local Python backend (`127.0.0.1:8001`) for KataGo analysis.
    *   Updated `Info.plist` to allow arbitrary loads (HTTP) for local testing.
    *   **Result**: When opening book misses, the app successfully requests live analysis from the Mac host.

2.  **UI/UX Improvements (Go Board)**
    *   **Coordinate Alignment**: Completely rewrote `_drawCoordinates` in `go_board_widget.dart`. Coordinates are now absolutely centered in their padding areas, ensuring perfect symmetry.
    *   **Background**: Extended the wood texture background to cover the entire widget area, solving the "floating coordinates" and "cut-off" issues.
    *   **Visibility**: Optimized font sizes (dynamic scaling + minimum 10pt) and boldness for 19x19 boards.
    *   **Padding**: Standardized padding to **10%** across all platforms to prevent Web clipping while maintaining a tight look on mobile.

3.  **Platform Compatibility Fixes**
    *   **Database (sqflite)**: Solved `databaseFactory not initialized` error on Desktop/Web.
        *   Added `sqflite_common_ffi` for MacOS support.
        *   Added **Conditional Import** in `cache_service.dart` to prevent Web builds from crashing when trying to load FFI.

## ⚠️ Known Issues / Pending Tasks
1.  **Web Analysis Backend**: Currently, the Web version points to `localhost:3001` (client) but needs to correctly route API requests to the Python backend (`localhost:8001`). Cross-Origin Resource Sharing (CORS) on the Python server is enabled, but might need verification if moving to a real device.
2.  **Performance**: On 19x19 analysis, the UI response is good, but the Python backend (on CPU) might be slow. GPU acceleration for KataGo on the Mac host is configured but should be double-checked if analysis times exceed 5-10s.

## 🚀 Next Steps (For tomorrow)
1.  **Verify Web Functionality**: Since we just killed the Web process to fix the "frozen" state, the next session should start by cleanly running `flutter run -d chrome --web-port=3000` to confirm the database fix works in practice.
2.  **Cloud Sync**: The settings menu has a placeholder for "Account & Cloud". The next major feature is integrating Google Drive/Cloud sync for SGFs and analysis history.
3.  **Release Build**: iOS release build (`flutter build ios`) compilation was successful earlier, but final signing/deployment to a real device hasn't been tested yet.

## 🛠 Command Reference
*   **Run iOS Simulator**: `flutter run -d <UUID> --no-pub`
*   **Run Web**: `flutter run -d chrome --web-port=3000`
*   **Start Backend**: `export PYTHONPATH=$PYTHONPATH:. && source venv/bin/activate && export PORT=8001 && uvicorn src.api:app --host 0.0.0.0 --port 8001`
