# Development Progress & Handover Note
**Date:** 2026-01-27
**Status:** Windows Setup & Android Release Automation Complete

## 📌 Accomplished Today
1.  **Windows Setup Automation (UTM/VM)**
    *   Refined `scripts/windows_setup.ps1` to include automatic **KataGo (Eigen)** and **Model** downloads.
    *   Fixed zip extraction logic to handle nested subdirectories within the KataGo release bundle.
    *   Verified the script ensures `katago.exe` is at `C:\Program Files\KataGo` for easy detection by the Flutter app.

2.  **Android Release Workflow & Native Integration**
    *   Resolved major C++ build issues for Android (clashing headers, missing symbols, zlib).
    *   Successfully integrated KataGo C++ engine via JNI (Native NDK).
    *   Created `release_android.sh` to handle automated build, git tagging, and uploading to GitHub Releases.
    *   Integrated `version.sh` to automatically sync the app's build number with the git commit count.

3.  **Project Status Tracking**
    *   Updated `STATUS_REPORT.md` with the latest milestones and reorganized task priorities.

## ⚠️ Known Issues / Pending Tasks
1.  **Windows VM Performance**: Local KataGo analysis on the VM will be CPU-bound and slower than native macOS.
2.  **API Coordinate Mapping**: Still need to verify if the frontend coordinate mapping perfectly matches the backend for all board sizes.

## 🚀 Next Steps (For tomorrow)
1.  **Run Windows Setup**: Execute the new `windows_setup.ps1` inside the VM and verify the full app build/run flow.
2.  **Physical Device Testing**: Test the Android APK on a real device to profile KataGo NDK performance.
3.  **Coordinate Verification**: Run integration tests between the Flutter GUI and Python API to confirm coordinate consistency.

## 🛠 Command Reference
*   **Run Windows Setup**: `powershell -ExecutionPolicy Bypass -File .\scripts\windows_setup.ps1` (Inside VM)
*   **Release Android**: `./release_android.sh`
*   **Start Backend**: `export PYTHONPATH=$PYTHONPATH:. && source venv/bin/activate && export PORT=8001 && uvicorn src.api:app --host 0.0.0.0 --port 8001`
