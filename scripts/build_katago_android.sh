#!/bin/bash
# Build KataGo for Android (ARM64)
#
# This script cross-compiles KataGo for Android devices using the NDK.
# The resulting binary can be embedded in the Flutter app.
#
# Prerequisites:
#   1. Android NDK (r25+) installed
#   2. CMake 3.18+
#   3. KataGo source code in katago_source/
#
# Usage:
#   ./scripts/build_katago_android.sh
#
# Output:
#   mobile/android/app/src/main/jniLibs/arm64-v8a/libkatago.so

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}KataGo Android Build Script${NC}"
echo -e "${GREEN}========================================${NC}"

# Configuration
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
KATAGO_SRC="$PROJECT_ROOT/katago_source"
BUILD_DIR="$PROJECT_ROOT/build/katago_android"
OUTPUT_DIR="$PROJECT_ROOT/mobile/android/app/src/main/jniLibs/arm64-v8a"

# Android NDK settings
ANDROID_ABI="arm64-v8a"
ANDROID_PLATFORM="android-24"  # Android 7.0+
MIN_SDK_VERSION=24

# Try to find NDK
find_ndk() {
    # Check environment variable first
    if [ -n "$ANDROID_NDK_HOME" ] && [ -d "$ANDROID_NDK_HOME" ]; then
        echo "$ANDROID_NDK_HOME"
        return 0
    fi
    
    # Check common locations
    local NDK_PATHS=(
        "$HOME/Library/Android/sdk/ndk"
        "$HOME/Android/Sdk/ndk"
        "/usr/local/share/android-ndk"
        "/opt/android-ndk"
    )
    
    for base in "${NDK_PATHS[@]}"; do
        if [ -d "$base" ]; then
            # Find the latest version
            local latest=$(ls -1 "$base" 2>/dev/null | sort -V | tail -1)
            if [ -n "$latest" ]; then
                echo "$base/$latest"
                return 0
            fi
        fi
    done
    
    return 1
}

# Check prerequisites
check_prerequisites() {
    echo -e "\n${YELLOW}Checking prerequisites...${NC}"
    
    # Check KataGo source
    if [ ! -d "$KATAGO_SRC/cpp" ]; then
        echo -e "${RED}Error: KataGo source not found at $KATAGO_SRC${NC}"
        echo "Please clone KataGo: git clone https://github.com/lightvector/KataGo.git katago_source"
        exit 1
    fi
    echo -e "  ${GREEN}✓${NC} KataGo source found"
    
    # Check CMake
    if ! command -v cmake &> /dev/null; then
        echo -e "${RED}Error: CMake not found${NC}"
        echo "Install with: brew install cmake"
        exit 1
    fi
    local CMAKE_VERSION=$(cmake --version | head -1 | grep -oE '[0-9]+\.[0-9]+')
    echo -e "  ${GREEN}✓${NC} CMake found (version $CMAKE_VERSION)"
    
    # Check NDK
    NDK_PATH=$(find_ndk)
    if [ -z "$NDK_PATH" ]; then
        echo -e "${RED}Error: Android NDK not found${NC}"
        echo ""
        echo "Please install Android NDK:"
        echo "  Option 1: Via Android Studio -> SDK Manager -> SDK Tools -> NDK"
        echo "  Option 2: brew install --cask android-ndk"
        echo "  Option 3: Download from https://developer.android.com/ndk/downloads"
        echo ""
        echo "Then set: export ANDROID_NDK_HOME=/path/to/ndk"
        exit 1
    fi
    echo -e "  ${GREEN}✓${NC} Android NDK found at $NDK_PATH"
    
    # Verify NDK toolchain
    TOOLCHAIN_FILE="$NDK_PATH/build/cmake/android.toolchain.cmake"
    if [ ! -f "$TOOLCHAIN_FILE" ]; then
        echo -e "${RED}Error: NDK toolchain file not found${NC}"
        echo "Expected: $TOOLCHAIN_FILE"
        exit 1
    fi
    echo -e "  ${GREEN}✓${NC} NDK toolchain file found"
}

# Build KataGo
build_katago() {
    echo -e "\n${YELLOW}Building KataGo for Android ($ANDROID_ABI)...${NC}"
    
    # Clean and create build directory
    rm -rf "$BUILD_DIR"
    mkdir -p "$BUILD_DIR"
    cd "$BUILD_DIR"
    
    # Configure with CMake
    echo -e "\n${YELLOW}Configuring CMake...${NC}"
    cmake "$KATAGO_SRC/cpp" \
        -DCMAKE_TOOLCHAIN_FILE="$TOOLCHAIN_FILE" \
        -DANDROID_ABI="$ANDROID_ABI" \
        -DANDROID_PLATFORM="$ANDROID_PLATFORM" \
        -DANDROID_STL=c++_shared \
        -DCMAKE_BUILD_TYPE=Release \
        -DUSE_BACKEND=EIGEN \
        -DNO_GIT_REVISION=1 \
        -DBUILD_DISTRIBUTED=0 \
        -DNO_LIBZIP=1 \
        -DUSE_TCMALLOC=0
    
    # Build
    echo -e "\n${YELLOW}Compiling (this may take a few minutes)...${NC}"
    make -j$(sysctl -n hw.ncpu)
    
    echo -e "${GREEN}Build complete!${NC}"
}

# Package output
package_output() {
    echo -e "\n${YELLOW}Packaging output...${NC}"
    
    # Create output directory
    mkdir -p "$OUTPUT_DIR"
    
    # Copy the katago executable
    if [ -f "$BUILD_DIR/katago" ]; then
        cp "$BUILD_DIR/katago" "$OUTPUT_DIR/libkatago.so"
        echo -e "  ${GREEN}✓${NC} Copied katago to $OUTPUT_DIR/libkatago.so"
    else
        echo -e "${RED}Error: katago binary not found${NC}"
        exit 1
    fi
    
    # Copy libc++_shared.so from NDK
    local LIBCXX="$NDK_PATH/toolchains/llvm/prebuilt/darwin-x86_64/sysroot/usr/lib/aarch64-linux-android/libc++_shared.so"
    if [ -f "$LIBCXX" ]; then
        cp "$LIBCXX" "$OUTPUT_DIR/"
        echo -e "  ${GREEN}✓${NC} Copied libc++_shared.so"
    else
        echo -e "${YELLOW}Warning: libc++_shared.so not found, may need to bundle separately${NC}"
    fi
    
    # Show file sizes
    echo -e "\n${YELLOW}Output files:${NC}"
    ls -lh "$OUTPUT_DIR"/*.so 2>/dev/null || true
}

# Download a small model
download_model() {
    echo -e "\n${YELLOW}Downloading small KataGo model...${NC}"
    
    MODEL_DIR="$PROJECT_ROOT/mobile/assets/katago"
    mkdir -p "$MODEL_DIR"
    
    # b6 model (smallest, ~15MB)
    MODEL_URL="https://github.com/lightvector/KataGo/releases/download/v1.4.5/g170e-b6c96-s175395328-d26788732.bin.gz"
    MODEL_FILE="$MODEL_DIR/model.bin.gz"
    
    if [ ! -f "$MODEL_FILE" ]; then
        echo "Downloading b6 model..."
        curl -L -o "$MODEL_FILE" "$MODEL_URL"
        echo -e "  ${GREEN}✓${NC} Model downloaded to $MODEL_FILE"
    else
        echo -e "  ${GREEN}✓${NC} Model already exists"
    fi
    
    # Show size
    ls -lh "$MODEL_FILE"
}

# Main
main() {
    check_prerequisites
    build_katago
    package_output
    download_model
    
    echo -e "\n${GREEN}========================================${NC}"
    echo -e "${GREEN}Build completed successfully!${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    echo "Next steps:"
    echo "  1. Create Flutter platform channel to invoke KataGo"
    echo "  2. Add JNI wrapper if needed"
    echo "  3. Bundle model file in assets"
    echo ""
}

main "$@"
