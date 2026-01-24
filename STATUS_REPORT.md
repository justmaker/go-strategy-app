# Go Strategy App - Project Status Report

**最後更新:** 2026-01-25  
**Status:** Active Development  
**Repository:** https://github.com/justmaker/go-strategy-app

---

## Table of Contents
1. [Project Overview](#project-overview)
2. [Architecture](#architecture)
3. [Component Status](#component-status)
4. [Build Outputs](#build-outputs)
5. [Database Status](#database-status)
6. [Pending Tasks](#pending-tasks)
7. [Known Issues](#known-issues)
8. [Development Guide](#development-guide)

---

## Project Overview

A Go (Weiqi/Baduk) strategy analysis tool powered by KataGo AI. The project consists of:

- **Web GUI** (Streamlit) - Interactive board with AI analysis
- **REST API** (FastAPI) - Backend service for analysis
- **Flutter App** - Cross-platform mobile/desktop client
- **Opening Book** - Pre-computed analysis database

### Target Architecture (Planned)

```
┌─────────────────────────────────────────────────────────────┐
│                      Flutter App                             │
├─────────────────────────────────────────────────────────────┤
│  1. Query Opening Book (bundled SQLite)                      │
│     - If found: Display cached result (instant)              │
│     - If not found: ↓                                        │
│                                                              │
│  2. Local KataGo Analysis (on-device)                        │
│     - Compute with user-specified visits                     │
│     - Display real-time progress                             │
└─────────────────────────────────────────────────────────────┘

UI Controls:
  - Lookup Visits Slider: Min visits for DB lookup (100-5000)
  - Compute Visits Slider: Visits for live analysis (10-200)
```

**Key Principle:** No server required. Everything runs locally on the user's device.

---

## Architecture

### Directory Structure

```
go-strategy-app/
├── src/                    # Python backend
│   ├── api.py              # FastAPI REST API
│   ├── board.py            # Go board logic + Zobrist hashing
│   ├── cache.py            # SQLite analysis cache
│   ├── gui.py              # Streamlit web GUI
│   ├── katago_*.py         # KataGo integration (GTP/Analysis)
│   ├── katago_*.py         # KataGo integration (GTP/Analysis)
│   └── scripts/            # Data generation scripts (Python)
│
├── scripts/                # Shell scripts & Utilities
│   ├── run_data_generation.sh
│   ├── setup_katago.sh
│   └── deploy.sh
│
├── mobile/                 # Flutter cross-platform app
│   ├── lib/
│   │   ├── config.dart     # API URLs, defaults
│   │   ├── models/         # Data models
│   │   ├── providers/      # State management
│   │   ├── screens/        # UI screens
│   │   ├── services/       # API, Cache, KataGo services
│   │   └── widgets/        # Go board widget
│   ├── assets/
│   │   ├── opening_book.json.gz  # Bundled opening book (380KB)
│   │   └── katago/model.bin.gz   # KataGo neural network (3.8MB)
│   └── build/              # Build outputs
│
├── katago/                 # KataGo configs
├── data/                   # Analysis database
│   └── analysis.db         # SQLite cache (~31MB)
├── tests/                  # Python unit tests
└── docker/                 # Docker deployment configs
```

### Coordinate System

All components use **GTP (Go Text Protocol)** standard:
- **X-axis:** A-T (left to right, skipping 'I')
- **Y-axis:** 1-19 (bottom to top, row 1 = bottom)
- **Example:** `Q16` = column Q (16th), row 16

---

## Component Status

### Python Backend

| Component | Status | Notes |
|-----------|--------|-------|
| `board.py` | ✅ Complete | Zobrist hashing, GTP coordinate conversion |
| `cache.py` | ✅ Complete | SQLite with merge support |
| `api.py` | ✅ Complete | CORS enabled, all endpoints working |
| `gui.py` | ✅ Complete | Streamlit GUI with analysis display |
| `katago_gtp.py` | ✅ Complete | GTP protocol integration |
| Unit Tests | ✅ 53 tests passing | `pytest tests/ -v` |

### Flutter App

| Component | Status | Notes |
|-----------|--------|-------|
| Go Board Widget | ✅ Complete | Touch input, stone rendering, suggestions |
| Opening Book Service | ✅ Complete | Loads bundled .json.gz |
| Cache Service | ✅ Complete | Local SQLite persistence |
| API Service | ✅ Complete | REST client with retry logic |
| KataGo Service (Mobile) | ⚠️ Scaffold only | Platform channel defined, native code needed |
| KataGo Desktop Service | ✅ Complete | Subprocess-based for macOS/Windows/Linux |
| Game Provider | ✅ Complete | State management, dual slider, offline-first |
| Flutter Analyze | ✅ Clean | 0 issues |
| Flutter Tests | ✅ 18 tests passing | BoardPoint, MoveCandidate, BoardState, GameProvider |
| Python Tests | ✅ 53 tests passing | board.py, cache.py |

### Platform Support

| Platform | Build Status | Local KataGo | Notes |
|----------|--------------|--------------|-------|
| **Android** | ⚠️ 需要 Java | ❌ Needs NDK | 系統缺少 Java Runtime |
| **iOS** | ✅ Built (21.8MB) | ❌ Needs XCFramework | Use `--no-codesign` for testing |
| **macOS** | ✅ Built (46.7MB) | ✅ Can spawn process | adhoc signed, runs directly |
| **Windows** | ❌ Needs Windows | ✅ Can spawn process | Cross-compile not possible |
| **Web** | ✅ Built (36MB) | ❌ Not possible | PWA ready |

---

## Build Outputs

### Current Outputs

| Platform | Location | Size | Status |
|----------|----------|------|--------|
| Web | `mobile/build/web/` | 36MB | ✅ Ready |
| macOS | `mobile/build/macos/Build/Products/Release/go_strategy_app.app` | 46.7MB | ✅ Ready |
| iOS | `mobile/build/ios/iphoneos/Runner.app` | 21.8MB | ✅ Ready (no codesign) |
| Android APK | `mobile/build/app/outputs/flutter-apk/app-release.apk` | - | ⚠️ Not built |

### Build Commands

```bash
cd mobile

# Web (PWA)
flutter build web --release
# Output: build/web/

# Android APK
flutter build apk --release
# Output: build/app/outputs/flutter-apk/app-release.apk

# macOS (currently blocked)
flutter build macos --release
# Output: build/macos/Build/Products/Release/go_strategy_app.app

# iOS (requires Apple Developer account)
flutter build ios --release
# Output: build/ios/iphoneos/Runner.app
```

---

## Database Status

### Analysis Cache (`data/analysis.db`)

| Board Size | Records | Visits | Notes |
|------------|---------|--------|-------|
| 9x9 | 58,734 | 100 | Most complete |
| 13x13 | 1,630 | 100 | Needs expansion |
| 19x19 | 46 | 100 | Needs GPU generation |

**Total Size:** ~31MB

### Bundled Opening Book (`mobile/assets/opening_book.json.gz`)

| Board Size | Positions | Min Visits |
|------------|-----------|------------|
| 9x9 | 2,945 | 100 |
| 13x13 | 3,004 | 100 |
| 19x19 | 1,820 | 100 |
| **Total** | **7,769** | - |

**File Size:** 380KB (compressed)

### Regenerating Opening Book

```bash
cd /Users/rexhsu/Documents/go-strategy-app
source venv/bin/activate

# Export from database with minimum visits threshold
python -m src.scripts.export_opening_book --min-visits 100 --compress

# Output: mobile/assets/opening_book.json.gz
```

---

## Completed Tasks (2026-01-25)

- [x] **Local KataGo Integration (Desktop)** - `katago_desktop_service.dart`
  - Subprocess-based KataGo for macOS/Windows/Linux
  - Auto-detection of KataGo binary path
  - Real-time progress streaming

- [x] **Dual Slider UI** - Complete implementation
  - Lookup Visits slider (100-5000) for book/cache threshold
  - Compute Visits slider (10-200) for live local analysis
  - Updated `config.dart` with dual slider configuration
  - Updated `game_provider.dart` with `setLookupVisits()` and `setComputeVisits()`
  - Updated `analysis_screen.dart` Settings sheet with two chip selectors
  - Progress display handles both mobile and desktop engine progress

- [x] **Code Quality**
  - Fixed all lint warnings (dangling doc comments, deprecated APIs)
  - Added unit tests for GameProvider dual slider logic
  - Fixed GTP coordinate system tests
  - Flutter analyze: 0 issues
  - Flutter tests: 18 passing

- [x] **macOS/iOS Build Issues Resolved**
  - macOS: 成功建置 (46.7MB)，adhoc 簽名可直接執行
  - iOS: 成功建置 (21.8MB)，使用 `--no-codesign` 跳過簽名
  - 之前的 codesign 問題已不存在

- [x] **批次建置與版本管理**
  - `build_all.sh` - 一鍵建置所有可建置平台
  - `version.sh` - 版本管理（自動使用 git commit 數量作為 build number）
  - 所有平台使用相同版號，方便追蹤

- [x] **Python 測試** - 53 tests passing

- [x] **README.md 更新** - 加入 Flutter 建置說明（中文）

## Pending Tasks

### High Priority

### Medium Priority

- [ ] **GPU Data Generation**
  - 19x19: Expand from 46 to 10,000+ positions
  - 13x13: Expand from 1,630 to 5,000+ positions
  - Run on GPU machine for speed

- [ ] **Android KataGo**
  - Compile KataGo with Android NDK
  - Create JNI bridge
  - Test on real device

### Low Priority

- [ ] **iOS Native Build** - Requires Apple Developer account
- [ ] **Re-export Opening Book** - Current: 7,769 positions, DB has 60,410

---

## Known Issues

### Minor

1. **CPU KataGo is Slow**
   - Deep search (depth > 8) takes minutes
   - Solution: Use GPU or pre-computed opening book

2. **Sidebar Padding Hardcoded**
   - Web GUI uses fixed `10rem` padding
   - May need adjustment for extreme screen sizes

---

## Development Guide

### Prerequisites

```bash
# Python (3.9+)
brew install python@3.9

# Flutter (3.5+)
brew install --cask flutter

# KataGo
brew install katago

# CocoaPods (for iOS/macOS)
brew install cocoapods
```

### Setup

```bash
# Clone repository
git clone https://github.com/justmaker/go-strategy-app.git
cd go-strategy-app

# Python environment
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt

# Flutter dependencies
cd mobile
flutter pub get
```

### Running Locally

```bash
# Web GUI (Streamlit)
source venv/bin/activate
streamlit run src/gui.py
# Open: http://localhost:8501

# REST API
uvicorn src.api:app --host 0.0.0.0 --port 8000
# API docs: http://localhost:8000/docs

# Flutter Web
cd mobile
flutter run -d chrome

# Flutter (specific device)
flutter devices  # List available devices
flutter run -d <device_id>
```

### Running Tests

```bash
# Python tests
source venv/bin/activate
pytest tests/ -v

# Flutter analyze
cd mobile
flutter analyze
```

### Git Workflow

```bash
# Current branch: main
# Remote: origin (GitHub)

git status
git add <files>
git commit -m "type: description"
git push origin main
```

---

## 下次繼續的待辦事項

### 需要 GPU 才能做的任務

```bash
# 1. 重新匯出 Opening Book（目前 7,769 位置，DB 有 60,410 位置）
cd /Users/rexhsu/Documents/go-strategy-app
source venv/bin/activate
python -m src.scripts.export_opening_book --min-visits 100 --compress

# 2. GPU 資料生成（擴充 19x19 和 13x13 位置）
python -m src.scripts.build_opening_book --board-size 19 --visits 100
python -m src.scripts.build_opening_book --board-size 13 --visits 100
```

### 不需要 GPU 的任務

```bash
# 1. 安裝 Java（Android 建置需要）
brew install openjdk@17

# 2. 建置 Android APK
cd mobile
flutter build apk --release
```

### 快速驗證環境

```bash
cd /Users/rexhsu/Documents/go-strategy-app

# Python 測試
source venv/bin/activate
pytest tests/ -v  # 應該 53 passed

# Flutter 測試
cd mobile
flutter analyze   # 應該 0 issues
flutter test      # 應該 18 passed

# 一鍵建置
./build_all.sh
```

---

## Contact

For questions or handoff, refer to this document and the codebase comments.

**Key Files to Review:**
- `src/board.py` - Core Go logic
- `src/cache.py` - Database schema
- `mobile/lib/providers/game_provider.dart` - App state management
- `mobile/lib/services/opening_book_service.dart` - Offline lookup logic
- `mobile/BUILD_OUTPUTS.md` - 建置指南（中文）
- `scripts/run_data_generation.sh` - 數據生成腳本
