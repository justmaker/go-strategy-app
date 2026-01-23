#!/bin/bash
# Go Strategy App - Android APK Build Script
#
# Prerequisites:
# 1. Flutter SDK installed (https://flutter.dev/docs/get-started/install)
# 2. Android SDK installed
# 3. Java 11+ installed
#
# Usage:
#   ./build_apk.sh [api_url]
#
# Examples:
#   ./build_apk.sh                              # Use default API URL from config.dart
#   ./build_apk.sh http://192.168.1.100:8000    # Override API URL

set -e

cd "$(dirname "$0")"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Go Strategy App - APK Builder${NC}"
echo -e "${GREEN}========================================${NC}"

# Check if Flutter is installed
if ! command -v flutter &> /dev/null; then
    echo -e "${RED}Error: Flutter is not installed or not in PATH${NC}"
    echo "Please install Flutter: https://flutter.dev/docs/get-started/install"
    exit 1
fi

# Optional: Update API URL if provided
if [ -n "$1" ]; then
    API_URL="$1"
    echo -e "${YELLOW}Updating API URL to: $API_URL${NC}"
    
    # Backup original config
    cp lib/config.dart lib/config.dart.bak
    
    # Update API URL in config
    sed -i.tmp "s|static const String apiBaseUrl = '.*';|static const String apiBaseUrl = '$API_URL';|" lib/config.dart
    rm -f lib/config.dart.tmp
    
    echo -e "${GREEN}API URL updated in config.dart${NC}"
fi

# Get dependencies
echo -e "\n${YELLOW}Getting dependencies...${NC}"
flutter pub get

# Clean previous builds
echo -e "\n${YELLOW}Cleaning previous builds...${NC}"
flutter clean
flutter pub get

# Build APK
echo -e "\n${YELLOW}Building release APK...${NC}"
flutter build apk --release

# Show result
APK_PATH="build/app/outputs/flutter-apk/app-release.apk"
if [ -f "$APK_PATH" ]; then
    APK_SIZE=$(du -h "$APK_PATH" | cut -f1)
    echo -e "\n${GREEN}========================================${NC}"
    echo -e "${GREEN}Build successful!${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo -e "APK location: ${YELLOW}$APK_PATH${NC}"
    echo -e "APK size: ${YELLOW}$APK_SIZE${NC}"
    echo -e "\nTo install on device:"
    echo -e "  ${YELLOW}adb install $APK_PATH${NC}"
    echo -e "\nOr copy the APK to your device and install manually."
else
    echo -e "${RED}Build failed - APK not found${NC}"
    exit 1
fi

# Restore original config if we modified it
if [ -f lib/config.dart.bak ]; then
    mv lib/config.dart.bak lib/config.dart
    echo -e "\n${GREEN}Restored original config.dart${NC}"
fi

echo -e "\n${GREEN}Done!${NC}"
