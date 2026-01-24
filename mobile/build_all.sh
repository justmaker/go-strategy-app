#!/bin/bash
# Flutter 批次建置腳本
# 用法: ./build_all.sh [平台...]
# 範例: 
#   ./build_all.sh          # 建置目前系統可建置的所有平台
#   ./build_all.sh web ios  # 只建置 web 和 ios

set -e

# 顏色定義
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 切換到 mobile 目錄
cd "$(dirname "$0")"

echo -e "${BLUE}======================================${NC}"
echo -e "${BLUE}   Flutter 批次建置腳本${NC}"
echo -e "${BLUE}======================================${NC}"
echo ""

# 顯示版本資訊
VERSION=$(grep "^version:" pubspec.yaml | sed 's/version: //')
GIT_SHA=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
GIT_SHA_FULL=$(git rev-parse HEAD 2>/dev/null || echo "unknown")

echo -e "版本: ${GREEN}${VERSION}${NC}"
echo -e "Git Commit: ${YELLOW}${GIT_SHA}${NC}"
echo -e "Git SHA Full: ${YELLOW}${GIT_SHA_FULL}${NC}"
echo ""

# 偵測作業系統
OS="$(uname -s)"
case "$OS" in
    Darwin*)  HOST_OS="macos" ;;
    Linux*)   HOST_OS="linux" ;;
    MINGW*|MSYS*|CYGWIN*)  HOST_OS="windows" ;;
    *)        HOST_OS="unknown" ;;
esac

echo -e "偵測到作業系統: ${GREEN}$HOST_OS${NC}"
echo ""

# 定義各平台可建置的目標
case "$HOST_OS" in
    macos)
        AVAILABLE_PLATFORMS="web android ios macos"
        ;;
    windows)
        AVAILABLE_PLATFORMS="web android windows"
        ;;
    linux)
        AVAILABLE_PLATFORMS="web android linux"
        ;;
    *)
        AVAILABLE_PLATFORMS="web android"
        ;;
esac

echo -e "此系統可建置的平台: ${GREEN}$AVAILABLE_PLATFORMS${NC}"
echo ""

# 如果有指定平台參數，使用指定的；否則使用全部可用平台
if [ $# -gt 0 ]; then
    PLATFORMS="$@"
else
    PLATFORMS="$AVAILABLE_PLATFORMS"
fi

# 驗證請求的平台是否可在此系統建置
for platform in $PLATFORMS; do
    if [[ ! " $AVAILABLE_PLATFORMS " =~ " $platform " ]]; then
        echo -e "${RED}錯誤: '$platform' 無法在 $HOST_OS 上建置${NC}"
        echo -e "可用平台: $AVAILABLE_PLATFORMS"
        exit 1
    fi
done

echo -e "將建置以下平台: ${YELLOW}$PLATFORMS${NC}"
echo ""

# 確保依賴已安裝
echo -e "${BLUE}[準備] 取得依賴套件...${NC}"
flutter pub get
echo ""

# 記錄建置結果
declare -A RESULTS
declare -A SIZES
declare -A OUTPUTS

# 建置函數
build_platform() {
    local platform=$1
    echo -e "${BLUE}======================================${NC}"
    echo -e "${BLUE}[建置] $platform${NC}"
    echo -e "${BLUE}======================================${NC}"
    
    case "$platform" in
        web)
            if flutter build web --release; then
                RESULTS[$platform]="✅ 成功"
                SIZES[$platform]=$(du -sh build/web 2>/dev/null | cut -f1)
                OUTPUTS[$platform]="build/web/"
            else
                RESULTS[$platform]="❌ 失敗"
            fi
            ;;
        android)
            if flutter build apk --release; then
                RESULTS[$platform]="✅ 成功"
                SIZES[$platform]=$(du -sh build/app/outputs/flutter-apk/app-release.apk 2>/dev/null | cut -f1)
                OUTPUTS[$platform]="build/app/outputs/flutter-apk/app-release.apk"
            else
                RESULTS[$platform]="❌ 失敗"
            fi
            ;;
        ios)
            if flutter build ios --release --no-codesign; then
                RESULTS[$platform]="✅ 成功"
                SIZES[$platform]=$(du -sh build/ios/iphoneos/Runner.app 2>/dev/null | cut -f1)
                OUTPUTS[$platform]="build/ios/iphoneos/Runner.app"
            else
                RESULTS[$platform]="❌ 失敗"
            fi
            ;;
        macos)
            if flutter build macos --release; then
                RESULTS[$platform]="✅ 成功"
                SIZES[$platform]=$(du -sh build/macos/Build/Products/Release/go_strategy_app.app 2>/dev/null | cut -f1)
                OUTPUTS[$platform]="build/macos/Build/Products/Release/go_strategy_app.app"
            else
                RESULTS[$platform]="❌ 失敗"
            fi
            ;;
        windows)
            if flutter build windows --release; then
                RESULTS[$platform]="✅ 成功"
                SIZES[$platform]=$(du -sh build/windows/x64/runner/Release 2>/dev/null | cut -f1)
                OUTPUTS[$platform]="build/windows/x64/runner/Release/"
            else
                RESULTS[$platform]="❌ 失敗"
            fi
            ;;
        linux)
            if flutter build linux --release; then
                RESULTS[$platform]="✅ 成功"
                SIZES[$platform]=$(du -sh build/linux/x64/release/bundle 2>/dev/null | cut -f1)
                OUTPUTS[$platform]="build/linux/x64/release/bundle/"
            else
                RESULTS[$platform]="❌ 失敗"
            fi
            ;;
    esac
    echo ""
}

# 執行建置
for platform in $PLATFORMS; do
    build_platform "$platform"
done

# 顯示結果摘要
echo -e "${BLUE}======================================${NC}"
echo -e "${BLUE}   建置結果摘要${NC}"
echo -e "${BLUE}======================================${NC}"
echo ""
printf "%-10s %-10s %-10s %s\n" "平台" "狀態" "大小" "輸出路徑"
printf "%-10s %-10s %-10s %s\n" "------" "------" "------" "----------"

for platform in $PLATFORMS; do
    printf "%-10s %-10s %-10s %s\n" \
        "$platform" \
        "${RESULTS[$platform]:-❓ 未知}" \
        "${SIZES[$platform]:-N/A}" \
        "${OUTPUTS[$platform]:-N/A}"
done

echo ""
echo -e "${GREEN}建置完成！${NC}"
