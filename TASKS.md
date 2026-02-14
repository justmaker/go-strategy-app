# Tasks

## 待處理

### macOS Google Sign-In: OAuth 回調未返回

**狀態**: 🔴 未解決
**PR**: [#1](https://github.com/justmaker/go-strategy-app/pull/1) (已 merged)

Google Sign-In 基本配置已完成（不再崩潰、瀏覽器正確開啟登入頁），但 OAuth 回調後 `_googleSignIn.signIn()` 沒有正確返回，UI 仍顯示未登入。

**Debug 線索**:
- `auth_service.dart` 已有 `[AuthService]` debug print
- 需觀察 console 是否出現 `signIn returned:` 訊息
- 可能是 AppDelegate 或 URL scheme 回調處理問題

### Opening Book: 13x13 / 19x19 擴充

**狀態**: 🟡 暫停

目前 Opening Book 資料量：

| Board Size | Entries | Visits | 說明 |
|------------|---------|--------|------|
| 9x9 | 1,519,000 | 205M avg | KataGo 官方 book，已完成 |
| 13x13 | ~8,500 | 500 | 待擴充 depth 12 |
| 19x19 | ~17,000 | 500 | 待擴充 depth 12 |

擴充需在 GPU server 上執行 `python3 -m src.scripts.build_opening_book`。

---

## 已完成

### UI 改善: Pass 按鈕 / Clear 確認 / 棋盤加大 (2026-02-14)

- Pass 按鈕：支援圍棋虛手，手數編號不跳號
- Clear 按鈕：加入確認對話框防誤觸
- 19 路棋盤：減少 padding、調整 flex 比例，棋盤更大

### CI/CD 修復 (2026-02-14)

- Android build：CI 自動從 Maven Central 下載 ONNX Runtime `.so`
- Web deploy：移除未使用的 `onnx_engine` import（避免 `dart:ffi` 錯誤）

### CI/CD: GitHub Actions 多平台發布 (2026-02-10)

`.github/workflows/release.yml` — workflow_dispatch 觸發，5 平台並行建置：

| Job | Runner | 產出 |
|-----|--------|------|
| build-android | ubuntu-latest | APK |
| build-ios | macos-latest | Runner.app.zip (unsigned) |
| build-macos | macos-latest | go_strategy_app.app.zip |
| build-windows | windows-latest | go-strategy-windows.zip |
| build-linux | ubuntu-latest | linux-app.tar.gz |

### Android pthread Crash Fix: ONNX Runtime Migration (2026-02-14)

Android 16 + Snapdragon 8 Gen 3 的 pthread crash 問題，改用 ONNX Runtime 1.23.2 + NNAPI 解決。
詳見 `docs/spec/ARCHITECTURE.md` §9.4。
