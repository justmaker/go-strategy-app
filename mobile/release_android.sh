#!/bin/bash
# Go Strategy App - Android Release & Upload Script
#
# This script:
# 1. Updates/gets the version from pubspec.yaml
# 2. Builds the release APK
# 3. Creates a Git tag
# 4. Uploads the APK to GitHub Releases
#
# Usage:
#   ./release_android.sh [version]
#
# Example:
#   ./release_android.sh        # Use current version in pubspec.yaml
#   ./release_android.sh 1.1.0  # Set version to 1.1.0 then release

set -e

cd "$(dirname "$0")"

# Set JAVA_HOME for Apple Silicon Macs if not set
if [[ "$OSTYPE" == "darwin"* ]] && [ -z "$JAVA_HOME" ]; then
    if [ -d "/opt/homebrew/opt/openjdk@17" ]; then
        export JAVA_HOME="/opt/homebrew/opt/openjdk@17"
        export PATH="$JAVA_HOME/bin:$PATH"
    fi
fi

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Go Strategy App - Android Releaser${NC}"
echo -e "${BLUE}========================================${NC}"

# Check for gh CLI
if ! command -v gh &> /dev/null; then
    echo -e "${RED}Error: GitHub CLI (gh) is not installed.${NC}"
    echo "Please install it: brew install gh"
    exit 1
fi

# Check gh auth status
if ! gh auth status &> /dev/null; then
    echo -e "${RED}Error: Not logged in to GitHub CLI.${NC}"
    echo "Please run: gh auth login"
    exit 1
fi

# Optionally set version
if [ -n "$1" ]; then
    echo -e "${YELLOW}Setting version to $1...${NC}"
    ./version.sh set "$1"
fi

# Get version info
VERSION=$(./version.sh | grep "版本號:" | awk '{print $NF}' | sed 's/\x1b\[[0-9;]*m//g')
BUILD=$(./version.sh | grep "Build Number:" | awk '{print $NF}' | sed 's/\x1b\[[0-9;]*m//g')
TAG="v${VERSION}+${BUILD}"

echo -e "Target Version: ${GREEN}${VERSION}${NC}"
echo -e "Build Number:   ${GREEN}${BUILD}${NC}"
echo -e "Git Tag:        ${GREEN}${TAG}${NC}"

# Ensure we have the latest dependencies
echo -e "\n${YELLOW}Getting dependencies...${NC}"
flutter pub get

# Build the APK
echo -e "\n${YELLOW}Building release APK...${NC}"
# Use the existing build_apk.sh which handles config and cleaning
./build_apk.sh

APK_PATH="build/app/outputs/flutter-apk/app-release.apk"

if [ ! -f "$APK_PATH" ]; then
    echo -e "${RED}Error: Build failed, APK not found at $APK_PATH${NC}"
    exit 1
fi

# Create and push tag
echo -e "\n${YELLOW}Creating and pushing git tag ${TAG}...${NC}"
if git rev-parse "$TAG" >/dev/null 2>&1; then
    echo -e "${YELLOW}Tag ${TAG} already exists. Deleting local and remote tag to overwrite...${NC}"
    git tag -d "$TAG" || true
    git push origin :refs/tags/"$TAG" || true
fi

git tag "$TAG"
git push origin "$TAG"

# Upload to GitHub Release
echo -e "\n${YELLOW}Uploading to GitHub Releases...${NC}"

# Check if release already exists
if gh release view "$TAG" &> /dev/null; then
    echo -e "${YELLOW}Release $TAG already exists, updating assets...${NC}"
    gh release upload "$TAG" "$APK_PATH" --clobber
else
    echo -e "${YELLOW}Creating new release $TAG...${NC}"
    # Use version.sh output for release notes or a standard message
    RELEASE_NOTES="### Go Strategy App - Android Release
    
**Version:** $VERSION  
**Build:** $BUILD  
**Platform:** Android  
**Offline Mode:** Supported (KataGo Native)

#### Changes:
- Enabled offline KataGo analysis on device.
- Integrated opening book for instant lookup.
- Enhanced UI for move suggestions."

    gh release create "$TAG" "$APK_PATH" --title "Android Release $TAG" --notes "$RELEASE_NOTES"
fi

echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}Release Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "APK uploaded to: ${BLUE}https://github.com/justmaker/go-strategy-app/releases/tag/${TAG}${NC}"
