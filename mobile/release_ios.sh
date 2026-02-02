#!/bin/bash
# Go Strategy App - iOS Release & Upload Script
#
# This script:
# 1. Gets the version from version.sh
# 2. Zips the Runner.app
# 3. Uploads the zip to GitHub Releases (joining the Android release)
#
# Usage:
#   ./release_ios.sh

set -e

cd "$(dirname "$0")"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Go Strategy App - iOS Releaser${NC}"
echo -e "${BLUE}========================================${NC}"

# Check for gh CLI
if ! command -v gh &> /dev/null; then
    echo -e "${RED}Error: GitHub CLI (gh) is not installed.${NC}"
    exit 1
fi

# Get version info
VERSION=$(./version.sh | grep "版本號:" | awk '{print $NF}' | sed 's/\x1b\[[0-9;]*m//g')
BUILD=$(./version.sh | grep "Build Number:" | awk '{print $NF}' | sed 's/\x1b\[[0-9;]*m//g')
TAG="v${VERSION}+${BUILD}"

echo -e "Target Version: ${GREEN}${VERSION}${NC}"
echo -e "Build Number:   ${GREEN}${BUILD}${NC}"
echo -e "Git Tag:        ${GREEN}${TAG}${NC}"

APP_PATH="build/ios/iphoneos/Runner.app"
ZIP_NAME="ios-runner-app.zip"

if [ ! -d "$APP_PATH" ]; then
    echo -e "${RED}Error: iOS build not found at $APP_PATH${NC}"
    echo "Please run 'flutter build ios --no-codesign --release' first."
    exit 1
fi

echo -e "\n${YELLOW}Zipping Runner.app...${NC}"
rm -f "$ZIP_NAME"
cd build/ios/iphoneos/
zip -r "../../../$ZIP_NAME" Runner.app
cd ../../../

echo -e "\n${YELLOW}Uploading to GitHub Release ${TAG}...${NC}"

# Check if release exists
if gh release view "$TAG" &> /dev/null; then
    echo -e "${YELLOW}Release $TAG found, uploading iOS artifact...${NC}"
    gh release upload "$TAG" "$ZIP_NAME" --clobber
else
    echo -e "${YELLOW}Release $TAG not found, creating new release...${NC}"
    RELEASE_NOTES="### Go Strategy App - iOS & Android Release
    
**Version:** $VERSION  
**Build:** $BUILD  
**Status:** iOS (No-Codesign) & Android Supported

#### Changes:
- Integrated local KataGo engine for iOS and Android.
- Resolved build and linker issues on iOS."

    gh release create "$TAG" "$ZIP_NAME" --title "Release $TAG" --notes "$RELEASE_NOTES"
fi

echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}iOS Release Uploaded!${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "File uploaded to: ${BLUE}https://github.com/justmaker/go-strategy-app/releases/tag/${TAG}${NC}"
