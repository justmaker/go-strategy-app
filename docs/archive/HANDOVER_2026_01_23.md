# 交接報告 (Handover Instructions) - 2026-01-23

## 1. 🔍 最近完成的工作

這段時間主要致力於修復 GUI 體驗與核心邏輯的一致性，並啟動了數據生成。

### ✅ UI 修復與優化
*   **側欄不遮擋**：解決了側欄展開時覆蓋棋盤的問題（透過 CSS 增加 `padding-left: 10rem`，且設定側欄預設展開）。
*   **右側欄重組**：調整順序為 `Next Player` -> `Move History` -> `Analysis` -> `Game Info`。
*   **手數顯示**：棋子上現在會正確顯示手數編號。
*   **持久化邏輯優化**：移除了磁碟持久化（`current_session.json`），改為僅在瀏覽器 Session 內持久，重開 Streamlit 會自動重置為空盤，避免混淆。

### ✅ 核心邏輯修復
*   **座標地獄修正**：
    *   統一了 `board.py` (邏輯層) 與 `gui.py` (顯示層) 的 Y 軸座標定義（GTP 標準：Row 1 在底部）。
    *   修復了 `coords_to_gtp` 轉換錯誤，解決了「點擊位置與歷史紀錄不符」的嚴重 Bug。
    *   現在歷史紀錄 (`Move History`) 與棋盤顯示完全一致。
*   **推薦點顏色邏輯**：修復了所有推薦點都顯示藍色的問題，現在依據勝率跌幅區分為：
    *   🔵 **藍色**：最佳 (跌幅 ≤ 0.5%)
    *   🟢 **綠色**：好棋 (跌幅 ≤ 3%)
    *   🟡 **黃色**：可接受 (跌幅 ≤ 10%)

### ✅ 數據生成 (Data Generation)
*   創建了自動化腳本 `run_data_generation.sh`。
*   已運行了約 4 小時的 **9路開局庫** 生成，產生了約 **5500 個高質量節點** (Depth 12, Visits 500)。
*   目前的 App 已經能夠利用這些緩存，9 路開局會顯示「Source: Cache」並秒回。

---

## 2. 🚀 如何繼續開發

### 啟動應用
```bash
source venv/bin/activate
streamlit run src/gui.py --server.port 8501
```

### 繼續跑數據 (建議在有 GPU 的機器上跑)
目前的生成腳本還剩下 **13路** 和 **19路** 未跑完。如果您更換到有 GPU 的機器，請執行：

1. **確保 Setup 完成**：KataGo 需可用。
2. **執行生成腳本**：
   ```bash
   ./run_data_generation.sh
   # 或者後台執行：
   nohup ./run_data_generation.sh > generation.log 2>&1 &
   ```
   *注意：如果不想重跑 9 路，可以編輯 `run_data_generation.sh` 註解掉第一段。*

### 觀察數據庫
目前的數據儲存在 `data/analysis.db` (SQLite)。
```bash
sqlite3 data/analysis.db "SELECT count(*) FROM analysis_cache;"
```

---

## 3. 📝 待辦事項 (Next Steps)

1.  **移動端 (Mobile) 整合**：目前的 API 端點 (`src/api.py`) 還未跟上最新的 `board.py` 座標修復，建議檢查 API 是否需要同步修正座標邏輯。
2.  **GPU 加速**：目前的數據生成是基於 CPU，效率較低。遷移到 GPU 環境可以加速 10-50 倍。
3.  **UI 微調**：目前的左邊距 (`padding-left`) 是寫死的，如果在超寬或超窄螢幕上可能還不夠完美，未來可以考慮用 JavaScript 動態計算側欄寬度。
4.  **歷史紀錄互動**：目前點擊歷史紀錄是「跳轉 (Jump)」，未來可以考慮加入「分支 (Branch)」功能，讓使用者嘗試不同變化圖。

---

## 4. 📂 關鍵檔案位置

*   `src/gui.py`: 主介面邏輯 (包含 CSS hack)。
*   `src/board.py`: 棋盤核心邏輯 (座標轉換在這裡)。
*   `run_data_generation.sh`: 數據生成腳本。
*   `data/analysis.db`: 緩存數據庫。

---
**Happy Coding!** 🚀
