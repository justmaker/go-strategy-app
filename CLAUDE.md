# Claude Code 專案指引

本文件提供 AI 助手在協助本專案時的重要上下文資訊。

## 專案概述

Go Strategy App 是一個基於 KataGo AI 的圍棋策略分析工具，支援跨平台（Web、iOS、Android、macOS）。

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
| **SQLite 資料庫** | `data/analysis.db` | 伺服器 API、完整資料 |
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

# 啟動 API server
uvicorn src.api:app --host 0.0.0.0 --port 8000 --reload

# 啟動 Web GUI (Python/Streamlit)
streamlit run src/gui.py --server.port 8501

# 執行 Python 測試
pytest tests/ -v

# 執行 Flutter 測試
cd mobile && flutter test

# 驗證 OpenAPI 規範與實作一致性
python scripts/validate_openapi.py

# 建置所有平台
cd mobile && ./build_all.sh
```

## API 開發規範

### OpenAPI 規範優先（Spec-First Workflow）

本專案採用 **OpenAPI 規範文件** 作為 API 的正式定義。修改 API 時必須同步更新規範。

```
docs/spec/openapi.yaml  ← 正式規範（必須手動維護）
src/api.py              ← FastAPI 實作（必須與規範一致）
```

### API 修改流程

1. **先修改 `docs/spec/openapi.yaml`**
   - 新增/修改端點定義
   - 更新 request/response schema
   - 維護範例值（example）

2. **再修改 `src/api.py`**
   - 更新 Pydantic 模型，與 openapi.yaml 一致
   - 實作端點邏輯

3. **驗證一致性**
   ```bash
   # 啟動 API server
   uvicorn src.api:app --port 8000

   # 驗證規範與實作一致
   python scripts/validate_openapi.py
   ```

### 重要注意事項

| 項目 | 說明 |
|-----|------|
| **座標格式** | 統一使用 GTP 格式（`Q16`, `D4`），'I' 字元跳過 |
| **棋盤大小** | 僅支援 9, 13, 19，使用 enum 限制 |
| **Pydantic Field** | 必須有 `description`，與 openapi.yaml 描述一致 |
| **範例值** | `json_schema_extra` 的 example 必須與 openapi.yaml 同步 |
| **錯誤回應** | 統一使用 `ErrorResponse` schema，包含 `detail` 欄位 |

### 新增 API 端點檢查清單

- [ ] 在 `openapi.yaml` 新增路徑定義
- [ ] 定義 request/response schema（若需要新 schema）
- [ ] 在 `src/api.py` 新增 Pydantic 模型
- [ ] 實作端點函數，包含適當的 docstring
- [ ] 執行 `python scripts/validate_openapi.py` 驗證
- [ ] 更新 `docs/spec/API.md`（若為重大變更）

## 相關文件

- [docs/spec/openapi.yaml](docs/spec/openapi.yaml) - **OpenAPI 規範（正式 API 定義）**
- [docs/spec/API.md](docs/spec/API.md) - API 快速參考
- [docs/spec/TEST.md](docs/spec/TEST.md) - 測試規範
- [docs/spec/LOGIC.md](docs/spec/LOGIC.md) - 核心邏輯
- [docs/UI_SPEC.md](docs/UI_SPEC.md) - UI 設計規範
- [mobile/BUILD_OUTPUTS.md](mobile/BUILD_OUTPUTS.md) - 建置輸出說明
