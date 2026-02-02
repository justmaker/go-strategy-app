# Branching Move History Specification

本文件定義 Go Strategy App 對於「分支棋譜」(Game Variations/Branching) 的實作規範。

## 1. 資料結構 (Data Structure)

目前的 `GameRecord` 採用平坦的 `List<GameMove>`。為了支援分支，我們將改為 **樹狀結構 (Tree Structure)**。

### 1.1 MoveNode
每個棋步節點應包含：
- `id`: 唯一識別碼。
- `player`: 'B' or 'W'。
- `coordinate`: GTP 座標。
- `comment`: 使用者註解。
- `parentId`: 指向父節點的 ID (如果是開局第一手則為 null)。
- `children`: 子節點列表 (支援多個分支)。
- `analysis`: 該手棋的 AI 分析結果快取。

### 1.2 導航狀態 (Navigation State)
App 在導航棋譜時，除了記錄「當前手數」，還需記錄「當前路徑 (Path)」。

## 2. UI 互動規範 (UI Interaction)

### 2.1 觸發分支
- 當使用者在棋譜的中間手數 (例如第 10 手) 強行落子，且該位置與歷史紀錄 (第 11 手) 不同時，系統應自動建立分支。
- **提示**: 系統應彈出微型提示「已建立分支」。

### 2.2 分支切換 (Variation Picker)
- 在「歷史紀錄」列表或棋盤上，若當前節點有多個子節點，應顯示分支切換按鈕。
- 顯示樣式：`A`, `B`, `C` 或標註 `(Main)`, `(Var 1)`。

## 3. SGF 支援
- **匯出**: 遞迴遍歷樹狀結構，產出包含 `(...)` 分支語法的 SGF 檔案。
- **匯入**: 支援傳統 SGF 的分支讀取。

## 4. 實作路徑 (Implementation Roadmap)

1.  **Phase 1**: 修改 `GameRecord` 模型，支援 `parentId` 與 `children`。
2.  **Phase 2**: 更新 `BoardState` 邏輯，使其能從任意節點重建盤面。
3.  **Phase 3**: UI 實作分支切換器 (Variation Selector)。
