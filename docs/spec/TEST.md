# Testing & QA Specification

本文件定義 Go Strategy App 的測試標準與驗收流程，確保在不同平台上的一致性與穩定性。

## 1. 自動化測試 (Automated Testing)

### 1.1 Python Backend 測試
- **範圍**: `board.py` (座標轉換、Hash)、`cache.py` (資料庫 CRUD)。
- **指令**: `pytest tests/ -v`
- **通過標準**: 100% Pass。

### 1.2 Flutter 單元測試
- **範圍**: `GameProvider` 狀態管理、`Coordinate` 映射邏輯。
- **指令**: `flutter test`
- **通過標準**: 核心計算 logic 必須全數通過。

## 2. 平台驗收矩陣 (Platform Verification)

每次發布 Release 前，需在以下平台完成手動驗收：

| 平台 | 環境 | 測試項 | 檢查點 |
| :--- | :--- | :--- | :--- |
| **Android** | 實機 (ARM64) | 離線 AI 分析 | 是否正確載入 NDK Lib，CPU 有無異常發熱 |
| **iOS** | iPad/iPhone | UI 適配 | 側邊欄是否遮擋棋盤，觸控座標是否精準 |
| **macOS** | Desktop | 視窗縮放 | 棋盤是否保持正方形且自動重新繪製 |
| **Windows** | Windows 11 VM | 建置部署 | `sync_windows.ps1` 是否能正確打包 |

## 3. 功能驗收清單 (Feature Checklist)

- [ ] **棋規校驗**: 能否正確處理「提子」、「打劫暫禁」與「禁止自殺」。
- [ ] **分析同步**: 點擊建議棋步後，棋盤是否即時更新並開始分析下一手。
- [ ] **斷網測試**: 關閉 Wi-Fi/行動數據，App 是否仍能提供基本分析結果（從 Book 或本地計算）。
- [ ] **雙滑桿效果**: 調整 Lookup Visits 後，是否能觸發原本略過的快取點。

## 4. 效能基準 (Benchmarks)
- **啟動時間**: 從點擊 Icon 到看見棋盤應在 3 秒內（不含引擎冷啟動）。
- **分析延遲**: 在訪問數為 50 的情況下，單步分析回傳不應超過 10 秒（手機 CPU）。
