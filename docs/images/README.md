# 📸 Go Strategy App 圖片資源

本目錄包含 Go Strategy App 使用者手冊所需的所有截圖和圖示。

---

## 📂 目前可用的截圖

### ✅ 已有的截圖

| 檔案名稱 | 內容 | 大小 | 使用位置 |
|---------|------|------|---------|
| `app_main_screen.png` | 主畫面整體佈局 | 416 KB | USER_GUIDE.md, USER_MANUAL_完整版.md |
| `ui_board_ranks.png` | 棋盤座標與排名顯示 | 85 KB | - |
| `ui_sidebar_stats.png` | 側邊欄統計資訊 | 153 KB | USER_MANUAL_完整版.md (設定章節) |

---

## 📋 建議新增的截圖

詳細的截圖需求列表請參考：[SCREENSHOT_GUIDE.md](../SCREENSHOT_GUIDE.md)

### 優先順序

#### 🔴 高優先級（建議優先製作）

1. **AI 推薦標記** (`ai_recommendations.png`)
   - 顯示棋盤上的藍/綠/橘色標記
   - 用於解釋 AI 建議系統

2. **分析面板詳細資訊** (`ai_analysis_panel.png`)
   - Top Moves 的完整數據顯示
   - 用於解釋勝率、領先目數等數據

3. **設定選單總覽** (`settings_menu.png`)
   - 顯示所有設定選項
   - 用於設定章節

4. **Lookup Visits 滑桿** (`settings_lookup_visits.png`)
   - 顯示滑桿與數值說明
   - 用於進階設定說明

5. **Compute Visits 滑桿** (`settings_compute_visits.png`)
   - 顯示滑桿與數值說明
   - 用於進階設定說明

#### 🟡 中優先級（視需求製作）

6. **落子操作** (`operation_place_stone.png`)
7. **悔棋操作** (`operation_undo.png`)
8. **清空棋盤** (`operation_clear.png`)
9. **分析中狀態** (`ai_analyzing.png`)
10. **棋盤座標系統** (`board_coordinates.png`)

#### 🟢 低優先級（可選）

11. **平台特定截圖** (iOS Widget, Android 浮動視窗等)
12. **棋局記錄** (歷史列表、匯出 SGF)
13. **雲端同步設定**

---

## 🎨 截圖規範

### 檔案格式
- **PNG** (推薦) - 清晰、支援透明背景
- **JPG** (次選) - 檔案較小
- **GIF** (動畫) - 用於演示操作流程

### 解析度建議
- **全螢幕截圖**: 保持原始解析度
- **局部截圖**: 800x600 或更小
- **細節特寫**: 400x400 或更小

### 檔案大小
- 單張截圖應 < 500 KB
- GIF 動畫應 < 5 MB

詳細規範請參考：[SCREENSHOT_GUIDE.md](../SCREENSHOT_GUIDE.md)

---

## 📝 使用截圖

### Markdown 引用語法

```markdown
![替代文字](./images/檔案名稱.png)

範例：
![App 主畫面](./images/app_main_screen.png)
```

### 帶說明文字

```markdown
![App 主畫面](./images/app_main_screen.png)

*圖：Go Strategy App 的主要介面，包含棋盤、分析面板和控制按鈕*
```

---

## 🤝 貢獻截圖

歡迎貢獻高品質的截圖！請參考：

1. [SCREENSHOT_GUIDE.md](../SCREENSHOT_GUIDE.md) - 詳細的截圖指引
2. 確認檔案符合命名規範
3. 提交 Pull Request

---

## 📞 聯絡

如有任何關於截圖的問題：

- 📧 Email: docs@go-strategy.app
- 💬 Discord: discord.gg/go-strategy
- 🐛 GitHub: https://github.com/justmaker/go-strategy-app/issues

---

**感謝您的貢獻！📸**

*最後更新：2026-02-04*
