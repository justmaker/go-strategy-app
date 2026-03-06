# Tasks

## 待處理

### Opening Book: 13x13 / 19x19 擴充

**狀態**: 🟡 可繼續擴充

目前 Opening Book 資料量：

| Board Size | Opening Book | analysis_cache | Depth | Visits | 說明 |
|------------|-------------|----------------|-------|--------|------|
| 9x9 | 3,201,154 | 3,201,154 | 0-50 | 10K+ | KataGo 官方 book，已完成 |
| 13x13 | 256,867 | 1,673,962 | 0-14 | 250-1000 | b18c384 模型，dead move filter 後 |
| 19x19 | 1,071,874 | 1,071,874 | 0-15 | 500 | b18c384 模型 |

**13x13 現況**:
- analysis_cache 有 1,673,962 筆，但 depth 8-12 的廣度擴展缺少子節點（depth 13-14 只有 277,645 筆）
- Dead move filter 後 opening book 僅保留 256,867 筆（有完整後續路徑的局面）
- 要增加 opening book 覆蓋率，需在 GPU server 補齊 depth 13-15 的子節點

可繼續擴充 depth 16+，需在 GPU server 上執行：
```bash
python3 -m src.scripts.build_opening_book_parallel \
    --board-size 13 --depth 15 --visits 500 --batch-size 64 --branching 7
```

---

## 已完成

### 13x13 Opening Book 重新匯出 (2026-03-06)

從 analysis_cache (1,673,962 筆) 重新匯出 13x13 opening book。Dead move filter 後保留 256,867 筆（有完整後續的局面）。檔案大小從 107 KB 增長至 16 MB。

### 9x9 Opening Book 座標修正 (2026-03-01)

`import_katago_book.py` 的 link index 使用 y-major 拆解，但 KataGo book 實際用 x-major。修正後重新匯入 3,201,154 筆。

### Opening Book 職責分離重構 (2026-02-27)

PR #23。`opening_book_service.dart` (706→555 行) 拆分為 `board_symmetry.dart`、`standard_openings.dart`、`move_ranking.dart`，建立排名單一真相來源。新增 30 個單元測試。

### 全棋盤 Opening Book 啟用 (2026-02-27)

移除 9x9-only 限制，13x13/19x19 都使用 opening book。過濾 0% 勝率的垃圾手。

### 9x9 Opening Book 資料全面修正 (2026-02-27)

修正 wl 視角（統一用 Black winrate）、Y 軸座標反轉、偶數/奇數 depth 不對稱問題。三階段 DB migration 修正 3,201,154 筆。

### 抽出 katago-onnx-mobile 到獨立 repo (2026-02-27)

PR #22。將 KataGo ONNX 引擎（Dart + Android JNI + iOS Bridge + C++ core + 模型）抽出為 Flutter plugin `katago-onnx-mobile`。App 改用 git dependency。驗證：macOS / Android / iOS / iPad 全通過。

Plugin repo: `https://github.com/justmaker/katago-onnx-mobile`

### macOS Google Sign-In 修復 (2026-02-19)

OAuth Client ID 從 Desktop 類型改為 iOS 類型，修正回調不返回的問題。

### Web Deploy: dart:ffi 編譯修復 (2026-02-19)

新增 `onnx_engine_stub.dart` 解決 Wasm 編譯時 `dart:ffi` 不可用的問題。

### 19x19 Opening Book 淺層覆蓋改善 (2026-02-19)

注入星位為標準開局，build script 新增 `--branching` 參數，depth 0 展開所有候選。

### ONNX 模型統一 (2026-02-18)

3 個 size-specific 模型合併為單一 `model.onnx` (b20c256)。

### 9x9 Opening Book 勝率修正 (2026-02-17)

修正 `wl` 轉換（不再反轉）和 `score_lead` 取反。後續在 2026-02-27 全面修正。

### iOS KataGo ONNX 整合 (2026-02-17)

Native KataGo C++ + ONNX Runtime 整合，即時進度回報，ONNX Engine input features 修正。

### iOS Simulator ONNX Fallback (2026-02-15)

Simulator 上 native KataGo 崩潰，自動 fallback 到 ONNX Runtime。

### UI 改善 (2026-02-14)

Pass 按鈕、Clear 確認對話框、19 路棋盤加大。

### CI/CD 多平台發布 (2026-02-10)

GitHub Actions workflow，5 平台並行建置（Android / iOS / macOS / Windows / Linux）。

### Android pthread Crash Fix (2026-02-14)

改用 ONNX Runtime 1.23.2 + NNAPI 解決 Android 16 + Snapdragon 8 Gen 3 的 pthread crash。
