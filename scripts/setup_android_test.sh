#!/bin/bash
set -e

echo "=== Android Setup & Test Script ==="

# 1. Ensure System Image is Installed
echo "[1/5] Ensuring System Image is fully installed..."
# Accepting licenses automatically
echo "y" | sdkmanager "emulator" "system-images;android-34;google_apis;arm64-v8a"

# 2. Create AVD
echo "[2/5] Creating AVD 'test_avd'..."
# "no" to custom hardware profile prompt
echo "no" | avdmanager create avd -n test_avd -k "system-images;android-34;google_apis;arm64-v8a" --device "pixel" --force

# 3. Start Emulator
echo "[3/5] Starting Emulator (Background)..."
# We assume 'emulator' is in PATH. If not, user might need to adjust PATH.
# Using -gpu swift for M1/M2 host usually works better, or auto.
emulator -avd test_avd &
EMULATOR_PID=$!

echo "Emulator PID: $EMULATOR_PID"

# 4. Wait for Boot
echo "[4/5] Waiting for device to be online..."
adb wait-for-device

echo "Waiting for boot completion..."
until adb shell getprop sys.boot_completed | grep -m 1 "1"; do
  sleep 2
done

# 5. Install & Run
echo "[5/5] Installing APK..."
APK_PATH="mobile/build/app/outputs/flutter-apk/app-release.apk"
if [ -f "$APK_PATH" ]; then
    adb install "$APK_PATH"
    echo "Launching App..."
    adb shell monkey -p com.gostratefy.go_strategy_app -c android.intent.category.LAUNCHER 1
    echo "SUCCESS: App launched on Emulator."
else
    echo "ERROR: APK not found at $APK_PATH"
fi

echo "Note: Emulator is still running. Close it manually when done."
