#!/bin/bash
# 版本管理腳本
# 用法:
#   ./version.sh          # 顯示目前版本
#   ./version.sh set 1.2.0  # 設定新版本號
#   ./version.sh bump patch # 自動升版 (major/minor/patch)

set -e

cd "$(dirname "$0")"

# 顏色定義
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 取得目前版本
get_current_version() {
    grep "^version:" pubspec.yaml | sed 's/version: //' | cut -d'+' -f1
}

# 取得目前 build number
get_current_build() {
    grep "^version:" pubspec.yaml | sed 's/version: //' | cut -d'+' -f2
}

# 取得 git commit SHA (短)
get_git_sha() {
    git rev-parse --short HEAD 2>/dev/null || echo "unknown"
}

# 取得 git commit SHA (完整)
get_git_sha_full() {
    git rev-parse HEAD 2>/dev/null || echo "unknown"
}

# 取得 git commit 數量 (作為 build number)
get_git_commit_count() {
    git rev-list --count HEAD 2>/dev/null || echo "1"
}

# 設定版本
set_version() {
    local new_version=$1
    local build_number=$(get_git_commit_count)
    
    # 更新 pubspec.yaml
    sed -i '' "s/^version: .*/version: ${new_version}+${build_number}/" pubspec.yaml
    
    echo -e "${GREEN}版本已更新為: ${new_version}+${build_number}${NC}"
}

# 自動升版
bump_version() {
    local bump_type=$1
    local current=$(get_current_version)
    
    IFS='.' read -r major minor patch <<< "$current"
    
    case "$bump_type" in
        major)
            major=$((major + 1))
            minor=0
            patch=0
            ;;
        minor)
            minor=$((minor + 1))
            patch=0
            ;;
        patch)
            patch=$((patch + 1))
            ;;
        *)
            echo "用法: ./version.sh bump [major|minor|patch]"
            exit 1
            ;;
    esac
    
    set_version "${major}.${minor}.${patch}"
}

# 顯示版本資訊
show_version() {
    local version=$(get_current_version)
    local build=$(get_current_build)
    local sha=$(get_git_sha)
    local sha_full=$(get_git_sha_full)
    local commit_count=$(get_git_commit_count)
    
    echo -e "${BLUE}======================================${NC}"
    echo -e "${BLUE}   版本資訊${NC}"
    echo -e "${BLUE}======================================${NC}"
    echo ""
    echo -e "版本號:        ${GREEN}${version}${NC}"
    echo -e "Build Number:  ${GREEN}${build}${NC}"
    echo -e "完整版本:      ${GREEN}${version}+${build}${NC}"
    echo ""
    echo -e "Git Commit:    ${YELLOW}${sha}${NC}"
    echo -e "Git SHA Full:  ${YELLOW}${sha_full}${NC}"
    echo -e "Commit Count:  ${YELLOW}${commit_count}${NC}"
    echo ""
    echo -e "${BLUE}--------------------------------------${NC}"
    echo -e "建議的版本字串 (含 git SHA):"
    echo -e "  ${GREEN}${version}+${commit_count} (${sha})${NC}"
    echo ""
}

# 主程式
case "${1:-}" in
    set)
        if [ -z "$2" ]; then
            echo "用法: ./version.sh set <版本號>"
            echo "範例: ./version.sh set 1.2.0"
            exit 1
        fi
        set_version "$2"
        ;;
    bump)
        bump_version "${2:-patch}"
        ;;
    sha)
        get_git_sha
        ;;
    *)
        show_version
        ;;
esac
