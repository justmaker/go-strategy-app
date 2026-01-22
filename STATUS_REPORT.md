# Go Strategy App - 開發狀況報告
**日期**: 2026-01-22 08:44
**狀態**: 進行中，有待修復問題

---

## ✅ 已完成的功能

### 1. SGF Import/Export
- **完成度**: 100%
- `src/sgf_handler.py` 已實作 `parse_sgf()` 和 `create_sgf()`
- GUI 側邊欄有 File Uploader 和 Download Button

### 2. Board Size 按鈕化
- **完成度**: 100%
- 原本的下拉選單已改為 3 個按鈕 (9, 13, 19)

### 3. 對稱擴充 (Symmetry Expansion)
- **完成度**: 100%
- `_expand_symmetries()` 正常運作，會顯示所有對稱等價的點

### 4. 開局庫生成 (Symmetry Pruning)
- **完成度**: 100%
- 9x9 (500v), 13x13 (300v), 19x19 (100v) 都已生成
- 資料庫大小: 3.3 MB

---

## ⚠️ 需要修復/測試的問題

### 1. 空盤第一手推薦顯示問題

**用戶需求**:
- 空盤時應該強制顯示 Top 3 (對稱等價視為同一個 Top)
- 過濾條件應該只看勝率，不看目數
- 勝率下降超過 10% 才不列入

**問題描述**:
- 9x9 空盤應該顯示天元 (E5) 為 Top 1，但實際顯示的可能是其他點
- 13x13 和 19x19 只顯示星位，沒有顯示其他類型的開局點

**根本原因**:
- 開局庫 Cache 裡的數據是用 `top_moves_count=3` 生成的 (已改為 10，但舊數據未重建)
- KataGo 在空盤時只返回少數候選（因為對稱性，visits 集中在最佳手）

**最新狀態** (commit 3022df0):
- GUI 過濾邏輯已簡化為 winrate-only
- 顏色規則:
  - 藍色: winrate drop ≤ 0.5%
  - 綠色: winrate drop ≤ 3%  
  - 黃色: winrate drop ≤ 10%
  - 不顯示: winrate drop > 10%

### 2. 已移除但保留的代碼
- `src/analyzer.py` 中有 `_add_empty_board_candidates` 方法
- 目前沒有被調用（已移除調用點）
- 可以刪除，或留著備用

---

## 🔧 接手後的待辦事項

### 優先級 1: 測試新邏輯
1. 重啟 Streamlit:
   ```bash
   pkill -f "streamlit run"
   source venv/bin/activate
   streamlit run src/gui.py --server.port 8501
   ```

2. 測試 9x9, 13x13, 19x19 空盤:
   - 檢查顯示的候選數量
   - 確認顏色是否符合 winrate 規則
   - 確認對稱等價點是否都有顯示

### 優先級 2: 如果顯示仍不正確
選項 A: 重新生成開局庫
```bash
# 刪除舊數據
sqlite3 data/analysis.db "DELETE FROM analysis_cache WHERE move_count = 0"

# 重新生成 (使用新的 top_moves_count=10)
python src/scripts/build_opening_book.py --board-size 9 --visits 500 --max-depth 10
python src/scripts/build_opening_book.py --board-size 13 --visits 300 --max-depth 10
python src/scripts/build_opening_book.py --board-size 19 --visits 100 --max-depth 10
```

選項 B: 接受現有數據，讓用戶點擊棋盤後再看完整分析

### 優先級 3: 清理代碼
- 決定是否刪除 `_add_empty_board_candidates` 方法
- 確認 `analysisWideRootNoise = 0.25` 在 `katago/gtp_analysis.cfg` 是否需要保留

---

## 📁 關鍵文件狀態

| 文件 | 狀態 | 說明 |
|------|------|------|
| `src/gui.py` | ✅ 剛修改 | 過濾邏輯已簡化為 winrate-only |
| `src/analyzer.py` | ✅ 剛修改 | 移除了 `_add_empty_board_candidates` 調用 |
| `src/config.py` | ✅ OK | `top_moves_count` 改為 10 |
| `katago/gtp_analysis.cfg` | ✅ OK | 添加了 `analysisWideRootNoise = 0.25` |
| `data/analysis.db` | ⚠️ 舊數據 | 開局庫是用 `top_n=3` 生成的 |
| `src/sgf_handler.py` | ✅ 新文件 | SGF 導入導出功能 |

---

## 🚀 快速啟動指令

```bash
# 進入專案目錄
cd /path/to/go-strategy-app

# 啟動虛擬環境
source venv/bin/activate

# 啟動 Streamlit
streamlit run src/gui.py --server.port 8501

# 開啟瀏覽器
open http://localhost:8501
```

---

## 📝 Git 狀態

最新 commit: `3022df0` - "refactor: simplify move filtering to winrate-only (10% threshold)"

所有變更已推送到 GitHub main 分支。
