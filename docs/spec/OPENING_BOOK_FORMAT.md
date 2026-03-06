# Opening Book 格式規格

本文件描述 Opening Book 的檔案格式、資料庫 Schema、載入流程，以及各棋盤大小的資料差異。

## 1. 檔案位置與打包

### 1.1 App 打包資產

```
mobile/assets/data/
├── opening_book_9x9.db.gz      # 9x9 棋盤，KataGo 官方 book
├── opening_book_13x13.db.gz    # 13x13 棋盤，b18c384 模型自建
└── opening_book_19x19.db.gz    # 19x19 棋盤，b18c384 模型自建
```

- 格式：SQLite 資料庫，經 gzip 壓縮
- 管理：Git LFS（`.gitattributes` 中配置）
- 每個檔案包含單一棋盤大小的資料

### 1.2 來源資料

```
data/analysis.db                # 完整分析快取（所有棋盤大小）
```

Opening Book 由 `analysis.db` 中的 `analysis_cache` 表匯出產生。

## 2. SQLite Schema

三種棋盤大小使用**完全相同的 Schema**。

### 2.1 `opening_book` 表

```sql
CREATE TABLE opening_book (
    id              INTEGER PRIMARY KEY,
    board_size      INTEGER NOT NULL,    -- 9, 13, 或 19
    komi            REAL    NOT NULL,    -- 貼目值，目前皆為 7.5
    moves_sequence  TEXT    NOT NULL DEFAULT '',  -- 著手序列
    top_moves       TEXT    NOT NULL,    -- 候選著手（compact JSON）
    visits          INTEGER NOT NULL     -- 該局面的分析 visits 數
);
```

**注意**：打包的 `.db.gz` 不含索引。App 首次載入時建立：

```sql
CREATE INDEX idx_lookup ON opening_book(board_size, komi, moves_sequence);
```

省略索引可減少壓縮後約 30 MB。

### 2.2 `opening_book_meta` 表

```sql
CREATE TABLE opening_book_meta (
    key   TEXT PRIMARY KEY,
    value TEXT
);
```

| Key | Value 範例 | 說明 |
|-----|-----------|------|
| `total_entries` | `"1071874"` | 總記錄數（字串） |
| `by_board_size` | `{"19": 1071874}` | 各棋盤大小記錄數（JSON） |
| `min_visits` | `"50"` | 匯出時的最低 visits 門檻 |
| `version` | `"1"` | 格式版本 |
| `generated_at` | `"2026-02-23T..."` | 匯出時間（ISO 8601） |

## 3. 資料格式

### 3.1 `moves_sequence` — 著手序列

以分號 `;` 分隔的括號式記譜法：

```
B[Q16];W[D4];B[P3]
```

| 元素 | 說明 |
|------|------|
| `B` / `W` | 黑方 / 白方 |
| `[Q16]` | GTP 座標（跳過 'I' 字元） |
| `;` | 分隔符 |
| 空字串 `""` | 表示空盤（depth 0） |

深度（depth）= 序列中的著手數 = `;` 數量 + 1（空字串為 depth 0）。

### 3.2 `top_moves` — 候選著手 JSON

Compact JSON 陣列，鍵名縮寫以節省空間：

```json
[{"m":"Q16","w":0.5027,"s":0.23,"v":1286},{"m":"D4","w":0.501,"s":0.15,"v":733}]
```

| Key | 全名 | 類型 | 說明 |
|-----|------|------|------|
| `m` | move | string | GTP 座標（如 `Q16`） |
| `w` | winrate | float | 黑方勝率 [0.0 - 1.0] |
| `s` | score_lead | float | 黑方目數領先（正 = 黑優） |
| `v` | visits | int | 該著手的分析 visits 數 |

**精度**：`w` 保留 6 位小數，`s` 保留 2 位小數。

### 3.3 資料儲存方式

Opening Book 僅儲存 **canonical（正規化）** 局面，不展開對稱變換。每個棋盤局面只有一筆記錄。App 端查詢時嘗試 8 種對稱變換來匹配。

## 4. 各棋盤大小的資料差異

三種棋盤大小的 **Schema 完全一致**，差異只在資料內容：

| | 9x9 | 13x13 | 19x19 |
|--|-----|-------|-------|
| **來源** | KataGo 官方 book | b18c384 模型自建 | b18c384 模型自建 |
| **記錄數** | 1,519,000 | 345,055 | 1,071,874 |
| **深度範圍** | depth 0-18 | depth 0-14 | depth 0-14 |
| **visits** | 90K+ (每筆不同) | ~500 (固定) | ~500 (固定) |
| **top_moves `v` 值** | 百萬級 | 百~千級 | 百~千級 |
| **壓縮大小** | 55 MB | 19 MB | 57 MB |
| **匯入腳本** | `import_katago_book.py` | `build_opening_book_parallel.py` | `build_opening_book_parallel.py` |

### 4.1 9x9 特殊說明

9x9 資料來自 KataGo 官方 9x9 opening book（高 visits 完整搜尋樹），匯入時需進行 winrate 轉換：

```python
# KataGo 的 wl 是 [-1, 1] 範圍（對手視角）
# 轉換為黑方勝率 [0, 1]：
if next_player == 'B':
    winrate = (1.0 + wl) / 2.0
else:
    winrate = (1.0 - wl) / 2.0
```

### 4.2 13x13 / 19x19

使用 KataGo b18c384 模型以 BFS 方式生成，每個局面固定 500 visits。

## 5. 匯出流程

從 `analysis.db` 匯出到 `.db.gz`：

```bash
# 匯出單一棋盤大小
python3 -m src.scripts.export_opening_book \
    --format sqlite \
    --board-size 19 \
    --output mobile/assets/data/opening_book_19x19.db \
    --min-visits 50

# 壓縮
gzip mobile/assets/data/opening_book_19x19.db

# 對三種大小分別執行上述步驟
```

### 5.1 Dead Move Filter

匯出時可選擇過濾「死路著手」——沒有後續分析資料的推薦著手：

- 預設啟用，可用 `--no-filter-dead-moves` 關閉
- 深度 0-3 的著手不受過濾（保留所有開局候選）
- 若一個局面的所有候選著手都被過濾，該局面整筆跳過
- **注意**：終端深度的局面會因子節點不存在而被全部過濾，適用於樹結構完整的情況

## 6. App 載入流程

定義於 `mobile/lib/services/opening_book_service.dart`：

### 6.1 版本管理

- 目前版本：**v4**（`_bundledVersion = 4`）
- 執行時 DB 檔名：`opening_book_v4.db`
- 版本變更時自動重新解壓

### 6.2 解壓與合併

1. 載入第一個 `.db.gz`（9x9），gzip 解壓為 base SQLite DB
2. 後續 `.db.gz`（13x13、19x19）逐一解壓到暫存檔
3. 透過 `ATTACH DATABASE` + `INSERT SELECT` 合併到 base DB
4. 合併 metadata：`total_entries` 加總，`by_board_size` JSON 合併
5. 建立索引 `idx_lookup(board_size, komi, moves_sequence)`

### 6.3 查詢

1. 收到查詢（boardSize, komi, moves）
2. 嘗試 8 種對稱變換，逐一查詢 `WHERE board_size = ? AND komi = ? AND moves_sequence = ?`
3. 命中後，對結果的 top_moves 做逆對稱變換還原座標
4. 回傳 `AnalysisResult`（與 KataGo 引擎分析結果相同的結構）

## 7. 相關檔案

| 檔案 | 用途 |
|------|------|
| `src/scripts/export_opening_book.py` | 匯出腳本（SQLite / JSON 格式） |
| `src/scripts/build_opening_book_parallel.py` | BFS 資料生成（GPU） |
| `src/scripts/import_katago_book.py` | 匯入 KataGo 官方 9x9 book |
| `mobile/lib/services/opening_book_service.dart` | App 端載入與查詢 |
| `data/analysis.db` | 來源資料庫（`analysis_cache` 表） |
| `CLAUDE.md` | 資料狀態與開發指引 |
| `docs/spec/DATABASE.md` | 資料庫整體規格 |
