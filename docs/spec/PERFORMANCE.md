# Performance Specification

**Version**: 1.0
**Last Updated**: 2026-02-12

本文件定義 Go Strategy App 的效能目標、優化策略與監控方式，涵蓋後端 SQLite、Flutter 前端渲染、KataGo 分析引擎與網路層。

---

## 1. Performance Targets（效能目標）

所有目標以 Release build 為準，測量環境為中階 Android 裝置或 macOS Desktop。

| Metric | Target | Measurement Method |
| :--- | :--- | :--- |
| App 冷啟動（含 Opening Book 載入） | < 3s | 從 Icon 點擊到棋盤可見 |
| Opening Book 查詢（單次） | < 5ms | `lookupByMoves()` 回傳時間 |
| SQLite cache 查詢（單次） | < 10ms | `CacheService.get()` 回傳時間 |
| KataGo 本地分析（50 visits） | < 10s | 手機 CPU，不含引擎冷啟動 |
| KataGo 本地分析（500 visits） | < 60s | Desktop GPU |
| 棋盤渲染（每次 frame） | < 16ms | CustomPainter.paint() 執行時間 |
| 落子到建議顯示（Book hit） | < 100ms | 使用者感知延遲 |
| 落子到建議顯示（Cache hit） | < 200ms | 使用者感知延遲 |
| Memory footprint（idle） | < 150MB | App 閒置時常駐記憶體 |

---

## 2. SQLite Optimization（資料庫優化）

### 2.1 Index Strategy（索引策略）

`analysis_cache` 表的查詢以 Zobrist hash 為主鍵，索引設計如下：

```sql
-- 主要查詢索引：依 board_hash 快速定位
CREATE INDEX IF NOT EXISTS idx_board_hash
  ON analysis_cache(board_hash);

-- 唯一約束索引：確保同一 hash + visits + komi 只有一筆
CREATE UNIQUE INDEX IF NOT EXISTS idx_board_hash_visits_komi
  ON analysis_cache(board_hash, engine_visits, komi);
```

**設計考量**：
- `board_hash` 為 16 字元 hex string (64-bit Zobrist)，B-tree 索引效率高
- 複合唯一索引 `(board_hash, engine_visits, komi)` 支援 `INSERT OR REPLACE` 語意
- 未對 `board_size` 單獨建索引，因為所有查詢都以 `board_hash` 開始（hash 已包含 board_size 資訊）

### 2.2 Query Patterns（查詢模式）

| Query | 使用場景 | 預期效能 |
| :--- | :--- | :--- |
| `WHERE board_hash = ? AND komi = ? AND engine_visits = ?` | 精確 visits 查詢 | O(1) via unique index |
| `WHERE board_hash = ? AND komi = ? ORDER BY engine_visits DESC LIMIT 1` | 最高 visits 查詢 | O(log n) via index scan |
| `SELECT COUNT(*) ... GROUP BY board_size` | 統計查詢 | Full scan, 非頻繁操作 |

### 2.3 WAL Mode（Write-Ahead Logging）

```python
conn.execute("PRAGMA journal_mode=WAL")
conn.execute("PRAGMA synchronous=NORMAL")
```

**WAL 模式的優勢**：
- 讀寫並行：分析結果寫入時不阻塞查詢
- 減少 fsync 次數：`synchronous=NORMAL` 在 WAL 模式下依然安全
- 更好的 crash recovery：WAL 提供原子性寫入保護

**注意**：每次 `_get_connection()` 都重設 PRAGMA，因為 Python `sqlite3` 不維持持久連線。Flutter 端使用 `sqflite`，由框架管理連線池。

### 2.4 Connection Management（連線管理）

**Python 資料工具**（`src/cache.py`，非運行時）：
- 使用 `with self._get_connection() as conn:` 確保連線及時釋放
- 設定 `timeout=60` 避免長時間等待鎖
- 每次操作獨立連線，適合批次資料生成場景

**Flutter (sqflite)**：
- `openDatabase()` 內部維護連線池
- Desktop 平台使用 FFI (`sqflite_common_ffi`)，需手動 `initFfiDatabase()`
- Web 平台停用 SQFlite，僅依賴 Opening Book

---

## 3. Cache Performance（快取效能）

### 3.1 三層快取架構

分析結果的查詢遵循離線優先策略，優先使用最快的資料來源：

```
Layer 1: Opening Book (In-Memory HashMap)
   ↓ miss
Layer 2: Local SQLite Cache (Disk)
   ↓ miss
Layer 3: Local KataGo Engine (即時運算)
```

| Layer | Storage | Lookup Time | 容量 |
| :--- | :--- | :--- | :--- |
| Opening Book | Memory (HashMap) | O(1), < 5ms | ~31,000 entries (gzip 壓縮資產) |
| Local SQLite | Disk (WAL mode) | O(log n), < 10ms | 無上限，隨使用累積 |
| KataGo Engine | Compute | 秒級 | 即時運算 |

### 3.2 Cache Hit Rate Targets（快取命中率目標）

| Board Size | Opening Book entries | Target Hit Rate (前 10 手) |
| :--- | :--- | :--- |
| 9x9 | 10,230 (500v) | > 90% |
| 13x13 | 8,543 (500v) | > 80% |
| 19x19 | 12,817 (500v) | > 70% |

前 10 手最常見，Opening Book 覆蓋率最高。隨著棋局深入，命中率自然下降，此時由本地引擎接手。

### 3.3 Opening Book Lookup（開局書查詢）

Opening Book 使用兩個 in-memory HashMap：

```dart
// Hash-based lookup: O(1)
final Map<String, OpeningBookEntry> _index = {};

// Move-sequence-based lookup: O(1)
final Map<String, OpeningBookEntry> _moveIndex = {};
```

**Symmetry-aware 查詢**：
- 對 8 個 D4 對稱變換逐一嘗試，最多 8 次 HashMap lookup
- 最壞情況 O(8) = O(1)
- 命中後反向變換座標，確保結果與使用者視角一致

**記憶體估算**：
- 約 31,000 entries，每筆 ~200 bytes
- 總計 ~6 MB in-memory，可接受

### 3.4 Cache Warming Strategy（快取預熱策略）

| 策略 | 實作方式 |
| :--- | :--- |
| Bundled DB | `assets/data/analysis.db` 隨 App 發佈，首次啟動自動複製 |
| Opening Book | `assets/opening_book.json.gz` 解壓後載入記憶體 |
| Auto-save | 本地引擎分析結果自動存入 SQLite，累積個人快取 |

### 3.5 Symmetry-Aware Canonical Hashing（對稱正規化雜湊）

Zobrist Hash 搭配 D4 對稱群（8 種變換），將對稱等價的局面映射到同一 hash：

```python
# 計算規範 hash：取 8 個對稱變換中的最小值
for transform in ALL_TRANSFORMS:
    transformed_stones = transform_stones(stones, board_size, transform)
    h = self._compute_hash_int(transformed_stones, next_player, komi, board_size)
    if min_hash is None or h < min_hash:
        min_hash = h
        min_transform = transform
```

**效能影響**：
- 每次 hash 計算需 8 次 Zobrist XOR（每次 O(stones)）
- 理論上可提高 cache hit rate 最多 8 倍
- 實際提升取決於局面對稱程度（空棋盤 8x，一般中盤 ~1x）

---

## 4. KataGo Analysis Optimization（KataGo 分析優化）

### 4.1 Visit Count Tuning（訪問次數調校）

```yaml
# config.yaml
analysis:
  visits_19x19: 500   # 預存資料庫的標準品質
  visits_small: 500    # 9x9 / 13x13 同等品質
```

**雙滑桿系統**：

| 參數 | 範圍 | 用途 |
| :--- | :--- | :--- |
| Lookup Visits | 100 - 5000 | 快取查詢門檻：`engine_visits >= lookup_visits` |
| Compute Visits | 10 - 200 | 本地引擎即時分析的目標次數 |

Compute Visits 刻意限制在 200 以下，原因：
- 手機 CPU 散熱限制，200v 約需 5-10 秒
- 使用者體驗要求即時回饋
- 更高品質分析由預存的 Opening Book (500v) 提供

### 4.2 Analysis Timeout（分析超時處理）

```dart
// 120 秒全域超時
await completer.future.timeout(
  const Duration(seconds: 120),
  onTimeout: () {
    _kataGoDesktop.cancelAnalysis();
    _error = 'Analysis timed out';
  },
);
```

| 場景 | 超時設定 | 處理方式 |
| :--- | :--- | :--- |
| 本地引擎分析 | 120s | 取消分析，顯示錯誤 |
| KataGo Desktop 啟動 | 30s | 標記引擎啟動失敗 |
| API 請求 | 由 HTTP client 控制 | 回退到離線模式 |

### 4.3 Progress Reporting（進度回報）

Desktop KataGo 使用 `reportDuringSearchEvery: 0.5` 每 0.5 秒回報一次中間結果，包含：
- 當前 visits / 目標 visits
- 即時 winrate 和 scoreLead
- 目前最佳候選手

這讓 UI 能在長時間分析中顯示進度條和即時預覽。

### 4.4 Engine Lifecycle（引擎生命週期）

```
App 啟動 → _initLocalEngine() → Process.start(katago, args)
         → 等待 stderr: "ready to begin handling requests"
         → 標記 running → 接受分析請求

分析請求 → stdin: JSON query → stdout: JSON response (streaming)

App 結束 → terminate command → kill process → 釋放資源
```

**Desktop vs Mobile 差異**：
- Desktop：使用 `dart:io Process` 直接啟動子程序
- Mobile：使用 Platform Channel (JNI/FFI) 呼叫原生 KataGo library

---

## 5. Flutter Rendering Performance（Flutter 渲染效能）

### 5.1 Board Rendering Architecture（棋盤渲染架構）

棋盤使用 `CustomPainter` 繪製，單一 `paint()` 方法依序繪製：

```
1. drawRect     → 棋盤底色
2. _drawGrid    → 格線 (board.size * 2 條線)
3. _drawStarPoints → 星位 (最多 9 點)
4. _drawCoordinates → 座標標籤
5. _drawSuggestions → AI 建議棋步
6. _drawStones   → 棋子 + 手數
7. _drawPendingMove → 待確認棋步預覽
```

### 5.2 Repaint Strategy（重繪策略）

`shouldRepaint()` 比較所有輸入參數變化：

```dart
bool shouldRepaint(covariant _BoardPainter oldDelegate) {
  return oldDelegate.board != board ||
      oldDelegate.suggestions != suggestions ||
      oldDelegate.theme != theme ||
      oldDelegate.showCoordinates != showCoordinates ||
      oldDelegate.showMoveNumbers != showMoveNumbers ||
      oldDelegate.pendingMove != pendingMove;
}
```

**最佳化要點**：
- 只有輸入變化才觸發重繪，避免無謂的 frame 消耗
- `BoardState` 和 `List<MoveCandidate>` 的 equality check 使用 reference equality
- 當 `notifyListeners()` 導致 `Consumer` rebuild 時，才會觸發新的 `paint()`

### 5.3 Frame Budget（幀預算）

目標 60fps = 每幀 16.67ms：

| 繪製階段 | 估計耗時 (19x19) | 備註 |
| :--- | :--- | :--- |
| 格線 | ~0.5ms | 38 條直線 |
| 星位 | ~0.1ms | 9 個圓點 |
| 座標 | ~1.0ms | TextPainter layout + paint |
| 建議 | ~1.5ms | 最多 ~40 個半透明圓 + 文字 |
| 棋子 | ~3.0ms | 最多 361 顆 (RadialGradient) |
| 總計 | ~6ms | 遠低於 16ms 預算 |

### 5.4 Widget Rebuild Minimization（Widget 重建最小化）

- `GoBoardWidget` 是 `StatelessWidget`，由 `Consumer<GameProvider>` 驅動
- `GameProvider` 使用 `ChangeNotifier`，只在狀態真正改變時呼叫 `notifyListeners()`
- 分析進度更新 (`AnalysisProgress`) 每 0.5 秒觸發一次，不影響棋盤重繪
- 棋盤大小使用 `AspectRatio(1.0)` + `LayoutBuilder` 確保正方形，避免 layout 抖動

### 5.5 Platform-Specific Rendering（平台特定渲染）

| 平台 | Rendering Backend | 效能特性 |
| :--- | :--- | :--- |
| macOS | Metal (Impeller) | 原生 GPU 加速，流暢 |
| iOS | Metal (Impeller) | 同 macOS |
| Android | OpenGL / Vulkan (Impeller) | 依裝置 GPU 能力 |
| Web | CanvasKit / HTML | Canvas 每步全部重繪，效能較差 |

**Web 效能警告**：Flutter Web 使用 Canvas 渲染，每次 `paint()` 完整重繪整個棋盤。不建議在 Web 進行開發測試，應以 macOS native 為主（見 CLAUDE.md）。

---

## 6. Network Optimization（網路優化）

### 6.1 Offline-First Architecture（離線優先架構）

App 在完全離線的情況下仍能提供分析功能：

```
Opening Book (bundled)  →  永遠可用
Local SQLite Cache      →  累積歷史分析
Local KataGo Engine     →  即時運算（Desktop/高階手機）
```

**好處**：
- 無任何網路依賴，所有分析完全在本地完成
- 零延遲的離線體驗
- 無伺服器成本

### 6.2 Data Compression（資料壓縮）

| 資產 | 壓縮方式 | 原始大小 | 壓縮後 |
| :--- | :--- | :--- | :--- |
| Opening Book JSON | gzip | ~8 MB | ~2 MB |
| Bundled analysis.db | 無（SQLite 自帶壓縮） | ~15 MB | ~15 MB |

Opening Book 使用 gzip 壓縮後隨 App bundle 發佈，啟動時解壓到記憶體。

---

## 7. Memory Management（記憶體管理）

### 7.1 Game Tree Memory（遊戲樹記憶體）

| 元件 | 記憶體估算 | 說明 |
| :--- | :--- | :--- |
| `BoardState` (19x19) | ~3 KB | stones dict + moves list |
| `AnalysisResult` | ~1 KB | top 5 moves + metadata |
| Opening Book index | ~6 MB | 31,000 entries in HashMap |
| SQLite connection | ~1 MB | sqflite 內部緩衝 |
| KataGo process | 50-200 MB | 依模型大小，Desktop 獨立程序 |

### 7.2 Memory Lifecycle（記憶體生命週期）

```dart
@override
void dispose() {
  _kataGo.dispose();           // 停止 KataGo Platform Channel
  _kataGoDesktop.dispose();    // 終止 KataGo 子程序
  _api.dispose();              // 關閉 HTTP client
  _cache.close();              // 關閉 SQLite 連線
  _openingBook.clear();        // 釋放 Opening Book HashMap
  super.dispose();
}
```

**重點**：
- `OpeningBookService.clear()` 主動釋放 `_index` 和 `_moveIndex` 兩個 HashMap
- KataGo Desktop 子程序通過 `Process.kill()` 確保釋放
- SQLite WAL checkpoint 在 `close()` 時自動執行

### 7.3 Large Board State（大棋盤狀態處理）

19x19 棋盤最多 361 個交叉點：
- `stones` 使用 `Dict[Tuple[int, int], str]`（Python）或 `List<List<StoneColor>>`（Dart）
- 提子操作使用 BFS flood-fill (`_get_group()`)，最壞 O(361)
- Zobrist hash 增量更新為 O(1)（XOR 操作），但 canonical hash 需要 O(8 * stones)

---

## 8. Monitoring & Profiling（監控與效能分析）

### 8.1 Built-in Diagnostics（內建診斷）

| 工具 | 用途 | 觸發方式 |
| :--- | :--- | :--- |
| `CacheService.getStats()` | 快取統計（by board size） | Settings 頁面 |
| `OpeningBookService.getStats()` | Opening Book 統計 | Settings 頁面 |
| `GameProvider.getCacheStats()` | 綜合統計 | Debug 面板 |
| `debugPrint` 日誌 | Opening Book 命中/未命中 | Debug build console |

### 8.2 Flutter DevTools（Flutter 開發工具）

```bash
# 啟動帶 DevTools 的 profile build
cd mobile && flutter run --profile -d macos
```

- **Performance Overlay**：監控 frame rendering time
- **Widget Inspector**：檢查不必要的 rebuild
- **Memory Tab**：追蹤 Dart heap 使用量
- **Timeline**：分析 `paint()` 耗時

### 8.3 SQLite Diagnostics（SQLite 診斷）

```python
# 查看快取統計
cache.get_stats()
# => {'total_entries': 31590, 'by_board_size': {9: 10230, 13: 8543, 19: 12817}, ...}

# 查看 visit count 分佈
cache.get_visit_counts(board_size=19, komi=7.5)
# => {500: 12817}
```

---

## 9. Performance Regression Prevention（效能回歸預防）

### 9.1 Automated Checks（自動化檢查）

| 檢查項目 | 方法 | CI 整合 |
| :--- | :--- | :--- |
| `flutter test` 通過 | 單元測試 | 每次 PR |
| `pytest tests/ -v` 通過 | 後端測試 | 每次 PR |
| Opening Book 載入 | 驗證 entry count | 手動 |
| SQLite index 存在 | `_init_db()` 自動建立 | App 啟動時 |

### 9.2 Manual Benchmarks（手動基準測試）

每次 Release 前應驗證：

- [ ] App 冷啟動 < 3s（macOS native）
- [ ] 空棋盤首次分析 < 100ms（Opening Book hit）
- [ ] 50v 本地分析 < 10s（手機 CPU）
- [ ] 連續落子 10 手，每手 UI 回應 < 200ms（Book hit）
- [ ] Memory 穩定（連續操作 5 分鐘無持續成長）

### 9.3 Known Performance Considerations（已知效能注意事項）

1. **Opening Book gzip 解壓**：啟動時需解壓 ~2MB gzip，耗時約 200-500ms。若 Book 持續增長，考慮分片載入。
2. **Canonical Hash 計算**：每次分析需 8 次 Zobrist XOR，目前忽略不計。若棋子數量極多（>200），可考慮快取 hash。
3. **SQLite 無連線池（Python 工具）**：資料生成工具每次操作新建連線，批次匯入時效能可接受。
4. **Flutter Web Canvas 重繪**：Web 版每次 `paint()` 完整重繪，不適合作為主要平台。應優先使用 Native build。
5. **App Bundle 大小**：Android APK ~25-54MB（含 KataGo native library），macOS ~47MB。KataGo neural network model (`kata1-b18c384`) 佔大部分體積。若需縮小，可考慮按需下載模型而非隨 App 打包。
6. **Dart AOT vs JIT 對啟動時間的影響**：Release build 使用 AOT 編譯，啟動時間顯著優於 Debug build（JIT）。效能基準測試應一律使用 `flutter run --release` 或 `flutter build` 產出的 Release build。
