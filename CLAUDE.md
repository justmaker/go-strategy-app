# Claude Code 專案指引

本文件提供 AI 助手在協助本專案時的重要上下文資訊。

## 專案概述

Go Strategy App 是一個基於 KataGo AI 的圍棋策略分析工具，支援跨平台（Web、iOS、Android、macOS）。

## 測試優先順序

### macOS 開發環境測試原則

**在 macOS 上進行 Flutter 測試時，優先使用 macOS 原生版本，而非 Web 版。**

```bash
# 優先使用
cd mobile && flutter run -d macos

# 避免使用 (效能差，重繪問題)
cd mobile && flutter run -d chrome
```

#### 原因

1. **效能問題**：Flutter Web 的 Canvas 每步重繪，體驗差
2. **程式碼共用**：macOS 與其他平台共用 95%+ Dart 程式碼
3. **測試等價性**：在 macOS 測試的結果適用於 iOS/Android，只需重新 build

#### 測試覆蓋等價性

| 在 macOS 原生測試 | 等價於測試 |
|------------------|-----------|
| UI 元件和佈局 | 所有平台 |
| GameProvider 狀態管理 | 所有平台 |
| Opening Book 查詢 | 所有平台 |
| Cache Service | 所有平台 |
| 棋盤互動邏輯 | 所有平台 |
| 座標轉換 | 所有平台 |

#### 例外情況

以下情況需要在特定平台測試：

- **KataGo 本地引擎 (JNI/FFI)**：需在 Android/iOS 實機測試
- **平台特定 UI**：如 iOS 的 Cupertino 風格元件

## 快取配置

19x19 棋盤的 visits 設定必須與資料庫一致：

```yaml
# config.yaml
analysis:
  visits_19x19: 500  # 必須與 DB 中的資料一致
  visits_small: 500
```

資料庫狀態：
- 9x9: 10,230 筆 (500v)
- 13x13: 8,543 筆 (500v)
- 19x19: 12,817 筆 (500v)

## 常用指令

```bash
# 啟動 macOS 原生 app (推薦測試方式)
cd mobile && flutter run -d macos

# 啟動 Web GUI (Python/Streamlit)
streamlit run src/gui.py --server.port 8501

# 執行 Python 測試
pytest tests/ -v

# 執行 Flutter 測試
cd mobile && flutter test

# 建置所有平台
cd mobile && ./build_all.sh
```

## 相關文件

- [docs/spec/TEST.md](docs/spec/TEST.md) - 測試規範
- [docs/spec/LOGIC.md](docs/spec/LOGIC.md) - 核心邏輯
- [docs/UI_SPEC.md](docs/UI_SPEC.md) - UI 設計規範
- [mobile/BUILD_OUTPUTS.md](mobile/BUILD_OUTPUTS.md) - 建置輸出說明
