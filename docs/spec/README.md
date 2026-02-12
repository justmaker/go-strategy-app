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

7.  **[Architecture Specification (ARCHITECTURE.md)](./ARCHITECTURE.md)**
    *   系統架構總覽、元件關係圖、三層查詢流程。
    *   線上/離線模式資料流與部署拓撲。

8.  **[Database Specification (DATABASE.md)](./DATABASE.md)**
    *   完整資料庫 Schema（analysis_cache、opening_book_meta、game_records）。
    *   索引策略、Zobrist Hash、Schema 遷移紀錄。

9.  **[Security Specification (SECURITY.md)](./SECURITY.md)**
    *   認證架構（Google/Apple/Microsoft Sign-In）。
    *   各平台憑證儲存、API 安全、未來安全路線圖。

10. **[Error Handling Specification (ERROR_HANDLING.md)](./ERROR_HANDLING.md)**
    *   錯誤分類（網路、引擎、資料、UI）與 Fallback 鏈。
    *   重試策略、使用者錯誤訊息規範。

11. **[Platform Matrix (PLATFORM_MATRIX.md)](./PLATFORM_MATRIX.md)**
    *   各平台功能支援矩陣（Web、Android、iOS、macOS、Windows、Linux）。
    *   平台特定限制與原生 API 使用情況。

12. **[Performance Specification (PERFORMANCE.md)](./PERFORMANCE.md)**
    *   效能目標與基準、SQLite 優化策略。
    *   快取命中率、Flutter 渲染效能、記憶體管理。

## 🛠 文件維護標準
*   每次重大功能更新後，應同步更新對應的 Spec 文件。
*   Spec 文件的變更應與代碼變更一同 Commit。

## 📝 變更紀錄

### 2026-02-12 — v1.0 初版建立
*   新增 #7~#12 共 6 份規格文件（ARCHITECTURE、DATABASE、SECURITY、ERROR_HANDLING、PLATFORM_MATRIX、PERFORMANCE）。

### 2026-02-12 — v1.0.1 品質修正
| 文件 | 修正內容 |
|------|---------|
| ARCHITECTURE.md | OpenAPI 版本號修正為 3.1.0 |
| SECURITY.md | 截斷 OAuth Client ID，避免完整值暴露於文件中 |
| PLATFORM_MATRIX.md | Google Sign-In iOS/macOS 狀態修正為 WIP，新增與 SECURITY.md 交叉引用 |
| ERROR_HANDLING.md | 新增 Python `logging` 模組建議；新增第 11 節「錯誤監控與告警」 |
| PERFORMANCE.md | 新增 App bundle 大小考量；新增 Dart AOT vs JIT 啟動時間說明 |
