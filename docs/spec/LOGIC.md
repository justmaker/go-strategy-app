# Core Logic Specification

本文件詳細說明 Go Strategy App 的核心運算邏輯，包含離線優先策略、快取機制與 AI 分析流程。

## 1. 離線優先運算流程 (Offline-First Flow)

App 在處理局面分析時，遵循以下優先順序：

1.  **Opening Book (Bundled)**: 
    - 檢查隨 App 附帶的壓縮資產 (`opening_book.json.gz`)。
    - 這些數據通常是高 visits (1000+) 的預算結果，涵蓋常見定式。
2.  **Local Cache (SQLite)**: 
    - 若 Opening Book 找不到，查詢本地資料庫 `analysis.db`。
    - 判斷條件：`engine_visits >= User_Lookup_Visits`。
3.  **Local KataGo Execution**: 
    - 若前兩者皆無符合條件之結果，啟動本地 KataGo 引擎進行即時運算。
    - 運算強度由 `User_Compute_Visits` 決定。

## 2. 雙滑桿邏輯 (Dual-Slider Logic)

UI 提供兩個滑桿來控制分析行為：

- **Lookup Visits (100 - 5000)**:
    - 定義「合格快取」的最低門檻。
    - 如果快取中的 Visits 低於此值，系統會視為「資訊不足」，並觸發重新運算。
- **Compute Visits (10 - 200)**:
    - 定義本地引擎運算時的目標次數。
    - 限制此值是為了平衡手持設備的耗電量與發熱。

## 3. 快取機制 (Caching Mechanisms)

### 3.1 Symmetry-Aware Hashing (對稱感知雜湊)
為了提高 8 倍的快取效率，系統在儲存與查詢前會進行對稱化處理：
1.  將當前盤面進行 8 種對稱變換（旋轉與翻轉）。
2.  選取所有對稱變換中「字典序最小」的一種作為 **Canonical State** (規範狀態)。
3.  計算 Canonical State 的 **Zobrist Hash** 並以此作為資料庫唯一鍵值。
4.  查詢時，若發生對稱變換，會將結果座標進行「反向變換」後才顯示於 UI。

### 3.2 資料庫 Schema
`analysis_cache` 表結構：
- `board_hash` (TEXT, Index): 規範化後的雜湊值。
- `engine_visits` (INTEGER): 運算次數。
- `analysis_result` (TEXT): 儲存 Top Moves 的 JSON 陣列。
- `komi` (REAL): 貼目（不同貼目的分析結果不通用）。

## 4. 防呆與規則
- **打劫 (KO)**: 必須包含在 Hash 計算中，防止在打劫點循環分析。
- **Pass 處理**: 連續兩次 Pass 應停止分析。
