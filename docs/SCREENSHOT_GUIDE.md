# 📸 截圖指引 - Go Strategy App 使用者手冊配圖

本文件說明如何為使用者手冊截取清晰、易懂的操作截圖。

---

## 📋 需要的截圖清單

### ✅ 已完成的截圖

1. ✅ `app_main_screen.png` - 主畫面整體佈局
2. ✅ `ui_board_ranks.png` - 棋盤座標與排名顯示
3. ✅ `ui_sidebar_stats.png` - 側邊欄統計資訊

### 📸 建議新增的截圖

#### 基本操作系列

| 檔案名稱 | 內容 | 說明 |
|---------|------|------|
| `operation_place_stone.png` | 落子操作 | 顯示手指或滑鼠點擊棋盤的示意 |
| `operation_undo.png` | 悔棋操作 | 標示 Undo 按鈕並顯示悔棋前後對比 |
| `operation_clear.png` | 清空棋盤 | 顯示 Clear 按鈕與確認對話框 |
| `operation_reanalyze.png` | 重新分析 | 標示 Re-analyze 按鈕與分析進度 |

#### AI 分析系列

| 檔案名稱 | 內容 | 說明 |
|---------|------|------|
| `ai_recommendations.png` | AI 推薦標記 | 清楚顯示棋盤上的藍/綠/橘色標記 |
| `ai_analysis_panel.png` | 分析面板詳細資訊 | Top Moves 的完整數據顯示 |
| `ai_source_book.png` | 開局庫來源 | 顯示「Source: Book」的截圖 |
| `ai_source_cache.png` | 快取來源 | 顯示「Source: Cache」的截圖 |
| `ai_source_local.png` | 本地運算來源 | 顯示「Source: Local」與進度條 |
| `ai_analyzing.png` | 分析中狀態 | 顯示「分析中...」與進度動畫 |

#### 設定選單系列

| 檔案名稱 | 內容 | 說明 |
|---------|------|------|
| `settings_menu.png` | 設定選單總覽 | 顯示所有設定選項 |
| `settings_board_size.png` | 棋盤大小選擇 | 標示 [9] [13] [19] 按鈕 |
| `settings_lookup_visits.png` | Lookup Visits 滑桿 | 顯示滑桿與數值說明 |
| `settings_compute_visits.png` | Compute Visits 滑桿 | 顯示滑桿與數值說明 |
| `settings_komi.png` | 貼目設定 | 顯示貼目輸入欄位 |
| `settings_show_moves.png` | 顯示手數開關 | 顯示開關與棋盤上的手數標示 |
| `settings_cloud_sync.png` | 雲端同步設定 | 顯示 Google Drive/iCloud/OneDrive 選項 |

#### 棋盤細節系列

| 檔案名稱 | 內容 | 說明 |
|---------|------|------|
| `board_coordinates.png` | 座標系統 | 清楚標示 A-T 與 1-19 座標 |
| `board_star_points.png` | 星位標示 | 特寫星位的黑色圓點 |
| `board_stones.png` | 黑白棋子 | 顯示棋子的漸層與陰影效果 |
| `board_move_numbers.png` | 手數標示 | 顯示棋子上的數字標記 |

#### 棋局記錄系列

| 檔案名稱 | 內容 | 說明 |
|---------|------|------|
| `game_history.png` | 棋局歷史列表 | 顯示過去的對局記錄 |
| `game_export_sgf.png` | 匯出 SGF | 顯示匯出選單與 SGF 選項 |
| `game_cloud_backup.png` | 雲端備份 | 顯示雲端同步狀態 |

#### 平台特定系列

| 檔案名稱 | 內容 | 說明 |
|---------|------|------|
| `ios_3d_touch.png` | iOS 3D Touch | 長按棋盤的操作示意 |
| `ios_widget.png` | iOS Widget | 主畫面小工具 |
| `android_floating.png` | Android 浮動視窗 | 小視窗模式 |
| `macos_menu_bar.png` | macOS 選單列 | Menu Bar 圖示與選單 |
| `web_browser.png` | 網頁版介面 | 瀏覽器中的畫面 |

---

## 🎨 截圖規範

### 尺寸與解析度

| 類型 | 建議尺寸 | 說明 |
|------|---------|------|
| **全螢幕截圖** | 1920x1080 (桌面) 或 1284x2778 (手機) | 保持原始解析度 |
| **局部截圖** | 800x600 或更小 | 只截取重要區域 |
| **細節特寫** | 400x400 或更小 | 標示按鈕或 UI 元件 |

### 檔案格式

- **PNG** - 優先使用（支援透明背景、無損壓縮）
- **JPG** - 次選（檔案較小，但有失真）
- **GIF** - 用於動畫示意（如分析進度）

### 品質要求

✅ **良好的截圖：**
- 清晰銳利，無模糊
- 內容聚焦，無多餘元素
- 顏色準確，亮度適中
- 重要元素用箭頭或框線標示

❌ **避免：**
- 模糊或像素化
- 包含敏感個人資訊（帳號、郵箱）
- 過度曝光或過暗
- 無關的背景內容

---

## 📱 各平台截圖方法

### iOS / iPadOS

**方法 1：實體按鍵**
- iPhone X 以後：同時按「側邊按鈕 + 音量增加鍵」
- iPhone 8 以前：同時按「Home 鍵 + 電源鍵」

**方法 2：AssistiveTouch**
1. 設定 → 輔助使用 → 觸控 → AssistiveTouch
2. 開啟 AssistiveTouch
3. 點擊浮動按鈕 → 裝置 → 更多 → 截圖

**截圖位置：** 照片 App → 相簿 → 截圖

---

### Android

**方法 1：實體按鍵**
- 大多數裝置：同時按「電源鍵 + 音量減小鍵」
- 三星裝置：同時按「電源鍵 + Home 鍵」（舊機型）

**方法 2：快速設定**
- 下拉通知欄 → 點擊「截圖」圖示

**方法 3：Google Assistant**
- 說「OK Google, 截圖」

**截圖位置：** 相簿 App → Screenshots 資料夾

---

### macOS

**方法 1：截取整個畫面**
- 按 `Cmd + Shift + 3`

**方法 2：截取選取區域（推薦）**
- 按 `Cmd + Shift + 4`
- 拖曳選取要截圖的區域

**方法 3：截取視窗**
- 按 `Cmd + Shift + 4`
- 按 `Space`（游標變成相機圖示）
- 點擊要截圖的視窗

**方法 4：使用截圖工具**
- 按 `Cmd + Shift + 5`
- 選擇截圖類型（整個畫面、選取區域、視窗、錄影）

**截圖位置：** 桌面（預設）或自訂資料夾

---

### Windows

**方法 1：截取整個畫面**
- 按 `PrtScn` 或 `Win + PrtScn`

**方法 2：截取選取區域（推薦）**
- 按 `Win + Shift + S`
- 拖曳選取要截圖的區域

**方法 3：使用截圖工具**
- 開啟「剪取工具」或「Snipping Tool」
- 選擇截圖模式

**截圖位置：** 圖片 → 螢幕擷取畫面 資料夾

---

### 網頁版（Chrome/Edge）

**方法 1：瀏覽器開發者工具**
1. 按 `F12` 開啟開發者工具
2. 按 `Ctrl + Shift + P` (Mac: `Cmd + Shift + P`)
3. 輸入「screenshot」
4. 選擇「Capture full size screenshot」

**方法 2：擴充功能**
- 安裝「Awesome Screenshot」或「Nimbus Screenshot」

---

## 🖼 後製處理建議

### 推薦工具

| 工具 | 平台 | 用途 |
|------|------|------|
| **Preview** (內建) | macOS | 基本裁切、標註 |
| **Markup** (內建) | iOS | 快速標註 |
| **Snagit** | Windows/Mac | 專業截圖與標註 |
| **GIMP** | 跨平台 | 免費的進階編輯 |
| **Figma** | 網頁 | 設計專業的示意圖 |

### 標註技巧

#### 1. 箭頭標示

```
用途：指向重要的按鈕或區域
顏色：紅色或黃色（醒目）
粗細：3-5px
```

**範例：**
```
┌─────────────────┐
│  Go Strategy    │ ← 用箭頭指向 App 名稱
└─────────────────┘
```

#### 2. 方框框選

```
用途：框出重要區域
顏色：紅色或藍色
粗細：2-3px
樣式：虛線或實線
```

**範例：**
```
┌─────────────────┐
│ ┌─────────────┐ │
│ │ [9][13][19] │ │ ← 用方框框選按鈕群組
│ └─────────────┘ │
└─────────────────┘
```

#### 3. 文字註解

```
用途：補充說明
字體：Sans-serif (如 Arial, Helvetica)
大小：14-18pt
顏色：與背景對比明顯
```

**範例：**
```
[⬅️ Undo]  ← 點擊此按鈕悔棋
```

#### 4. 高亮區域

```
用途：強調特定區域
方法：半透明的彩色遮罩
顏色：黃色或藍色
透明度：30-50%
```

---

## 🎬 動畫截圖 (GIF)

### 適用情境

- 演示落子流程
- 顯示 AI 分析進度
- 展示設定調整效果

### 製作工具

| 工具 | 平台 | 說明 |
|------|------|------|
| **LICEcap** | Windows/Mac | 免費、輕量 |
| **ScreenToGif** | Windows | 功能豐富 |
| **Kap** | macOS | 開源、現代化 |
| **GIPHY Capture** | macOS | 簡單易用 |

### GIF 規範

- **幀率：** 10-15 FPS（流暢但檔案不會太大）
- **時長：** 3-5 秒（簡短精煉）
- **循環：** 無限循環
- **檔案大小：** < 5 MB

---

## 📂 檔案管理

### 目錄結構

```
docs/
└── images/
    ├── README.md              (本檔案的複本)
    │
    ├── main/                  (主畫面系列)
    │   ├── app_main_screen.png
    │   └── ...
    │
    ├── operations/            (基本操作系列)
    │   ├── operation_place_stone.png
    │   ├── operation_undo.png
    │   └── ...
    │
    ├── ai/                    (AI 分析系列)
    │   ├── ai_recommendations.png
    │   ├── ai_analysis_panel.png
    │   └── ...
    │
    ├── settings/              (設定選單系列)
    │   ├── settings_menu.png
    │   ├── settings_lookup_visits.png
    │   └── ...
    │
    ├── board/                 (棋盤細節系列)
    │   ├── board_coordinates.png
    │   └── ...
    │
    ├── games/                 (棋局記錄系列)
    │   └── ...
    │
    └── platforms/             (平台特定系列)
        ├── ios/
        ├── android/
        ├── macos/
        └── web/
```

### 命名規則

```
{類別}_{描述}_{選項}.{副檔名}

範例：
- settings_lookup_visits_slider.png
- ai_analysis_panel_detailed.png
- operation_undo_before_after.png
```

---

## ✅ 截圖檢查清單

在提交截圖前，請確認：

- [ ] 解析度足夠（至少 800px 寬）
- [ ] 內容清晰無模糊
- [ ] 已移除個人敏感資訊
- [ ] 檔案大小合理（< 1 MB）
- [ ] 檔案命名符合規範
- [ ] 放置在正確的資料夾
- [ ] 已在使用者手冊中引用

---

## 📝 使用者手冊引用方式

### Markdown 語法

```markdown
![替代文字](./images/檔案名稱.png)

範例：
![AI 推薦標記示意](./images/ai/ai_recommendations.png)
```

### 帶說明的圖片

```markdown
![AI 推薦標記示意](./images/ai/ai_recommendations.png)

*圖：AI 會用藍、綠、橘三種顏色標示推薦棋步*
```

### 並排圖片（使用 HTML）

```html
<div style="display: flex; gap: 10px;">
  <img src="./images/operation_undo_before.png" alt="悔棋前" width="300">
  <img src="./images/operation_undo_after.png" alt="悔棋後" width="300">
</div>
```

---

## 🤝 貢獻截圖

### 如何提交

1. **Fork 專案**
   ```bash
   git clone https://github.com/justmaker/go-strategy-app.git
   cd go-strategy-app
   ```

2. **建立分支**
   ```bash
   git checkout -b add-screenshots
   ```

3. **新增截圖**
   - 將截圖放到 `docs/images/` 對應資料夾
   - 確認檔案命名符合規範

4. **更新使用者手冊**
   - 在 `docs/USER_MANUAL_完整版.md` 中引用新截圖

5. **提交 Pull Request**
   ```bash
   git add docs/images/
   git commit -m "docs: 新增 AI 分析系列截圖"
   git push origin add-screenshots
   ```

6. **發起 PR**
   - 前往 GitHub
   - 點擊「New Pull Request」
   - 描述您新增的截圖

---

## 📞 聯絡我們

如有任何關於截圖的問題，歡迎聯繫：

- 📧 Email: docs@go-strategy.app
- 💬 Discord: discord.gg/go-strategy
- 🐛 GitHub Issues: https://github.com/justmaker/go-strategy-app/issues

---

**感謝您為 Go Strategy App 文件貢獻！📸**

*最後更新：2026-02-04*
