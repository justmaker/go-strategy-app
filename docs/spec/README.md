# Go Strategy App - Specification Index

本目錄包含 Go Strategy App 的完整技術規範與設計文件。這些文件作為「單一事實來源」(Source of Truth)，確保跨平台開發的一致性。

## 📋 規範列表

1.  **[API Specification (API.md)](./API.md)**
    *   定義 REST API 端點、請求/回應格式。
    *   規範 GTP 座標與棋盤狀態的傳輸標準。

2.  **[Core Logic Specification (LOGIC.md)](./LOGIC.md)**
    *   詳細說明離線優先 (Offline-First) 的分析邏輯。
    *   雙滑桿 (Lookup vs. Compute) 的判定演算法。
    *   SQLite 快取結構與 Symmetry-Aware Hashing 說明。

3.  **[Data Generation Specification (DATA.md)](./DATA.md)**
    *   Opening Book 生成標準（深度、Visit、棋盤大小）。
    *   資料導出與壓縮格式規範。

4.  **[UI/UX Specification (UI_SPEC.md)](../UI_SPEC.md)**
    *   視覺系統、顏色、棋子渲染規範（位於 docs 根目錄）。

5.  **[Testing & QA Specification (TEST.md)](./TEST.md)**
    *   自動化測試標準與手動驗收 Checklists。

6. **[Branching Specification (BRANCHING.md)](./BRANCHING.md)**
    *   定義分支棋譜 (Variations) 的資料結構與 UI 互動規範。

## 🛠 文件維護標準
*   每次重大功能更新後，應同步更新對應的 Spec 文件。
*   Spec 文件的變更應與代碼變更一同 Commit。
