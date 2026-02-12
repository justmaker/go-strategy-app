# Claude Code 專案指引

本文件提供 AI 助手在協助本專案時的重要上下文資訊。

## 專案概述

Go Strategy App 是一個基於 KataGo AI 的圍棋策略分析工具，採用純離線架構，支援跨平台（Web、iOS、Android、macOS、Windows、Linux）。App 不依賴遠端 API Server，所有分析在本地完成。

## 測試優先順序

### macOS 開發環境測試原則

**在 macOS 上進行 Flutter 測試時，優先使用 macOS 原生版本，而非 Web 版。**

```bash
# 優先使用
cd mobile && flutter run -d macos

# 避免使用 (效能差，重繪問題)
cd mobile && flutter run -d chrome
```

#### 原因

1. **效能問題**：Flutter Web 的 Canvas 每步重繪，體驗差
2. **程式碼共用**：macOS 與其他平台共用 95%+ Dart 程式碼
3. **測試等價性**：在 macOS 測試的結果適用於 iOS/Android，只需重新 build

#### 測試覆蓋等價性

| 在 macOS 原生測試 | 等價於測試 |
|------------------|-----------|
| UI 元件和佈局 | 所有平台 |
| GameProvider 狀態管理 | 所有平台 |
| Opening Book 查詢 | 所有平台 |
| Cache Service | 所有平台 |
| 棋盤互動邏輯 | 所有平台 |
| 座標轉換 | 所有平台 |

#### 例外情況

以下情況需要在特定平台測試：

- **KataGo 本地引擎 (JNI/FFI)**：需在 Android/iOS 實機測試
- **平台特定 UI**：如 iOS 的 Cupertino 風格元件

## 快取配置

19x19 棋盤的 visits 設定必須與資料庫一致：

```yaml
# config.yaml
analysis:
  visits_19x19: 500  # 必須與 DB 中的資料一致
  visits_small: 500
```

資料庫狀態：
- 9x9: 10,230 筆 (500v)
- 13x13: 8,543 筆 (500v)
- 19x19: 12,817 筆 (500v)

## 資料匯入注意事項

**匯入新的 KataGo book 或分析資料時，必須同時更新兩個來源：**

| 資料來源 | 位置 | 用途 |
|---------|------|------|
| **SQLite 資料庫** | `data/analysis.db` | 資料生成工具源資料 |
| **Opening Book JSON** | `mobile/assets/opening_book.json.gz` | App 打包資產、離線使用 |

### 匯入流程

```bash
# 1. 匯入到 SQLite
python -m src.scripts.import_katago_book --book-path katago/books/xxx.tar.gz

# 2. 導出到 Opening Book JSON（需要有導出腳本）
python -m src.scripts.export_opening_book

# 3. 驗證兩邊資料一致
```

### KataGo Book winrate 轉換

KataGo book 的 `wl` (winLoss) 欄位是**對手勝率**（即己方輸棋率），匯入時需轉換：

```python
winrate = 1.0 - wl  # 轉換為己方勝率
```

## 常用指令

```bash
# 啟動 macOS 原生 app (推薦測試方式)
cd mobile && flutter run -d macos

# 執行 Python 測試（資料工具）
pytest tests/ -v

# 執行 Flutter 測試
cd mobile && flutter test

# 建置所有平台
cd mobile && ./build_all.sh

# 資料生成工具（非 App 運行時）
python -m src.scripts.build_opening_book --visits 500 --depth 10
python -m src.scripts.export_opening_book --compress
```

## 開發規範

### 座標與資料格式

| 項目 | 說明 |
|-----|------|
| **座標格式** | 統一使用 GTP 格式（`Q16`, `D4`），'I' 字元跳過 |
| **棋盤大小** | 僅支援 9, 13, 19 |

## 協作開發規則

### 工作記錄必須寫入 Repo

這是多人協作專案，所有工作進度和待辦事項必須記錄在 repo 中，而非 Claude 的本地 memory 目錄。

| 記錄類型 | 檔案位置 |
|---------|---------|
| 待辦事項、進行中任務 | `TASKS.md` |
| 已知問題、Debug 線索 | `TASKS.md` 或相關 PR |
| 專案規則、開發指引 | `CLAUDE.md` |

這樣其他開發者或其他電腦上的 Claude 都能看到目前的進度狀態。

---

## 相關文件

- [docs/spec/TEST.md](docs/spec/TEST.md) - 測試規範
- [docs/spec/LOGIC.md](docs/spec/LOGIC.md) - 核心邏輯
- [docs/UI_SPEC.md](docs/UI_SPEC.md) - UI 設計規範
- [mobile/BUILD_OUTPUTS.md](mobile/BUILD_OUTPUTS.md) - 建置輸出說明
