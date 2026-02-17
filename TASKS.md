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

### ONNX Engine Input Features Fix (2026-02-17)

**問題**: ONNX 引擎的 policy 輸出過度均勻，無法區分好壞手，所有候選手勝率相同（約 60%）。

**根本原因**:
1. Move history 編碼錯誤：應使用 channels 6-10，卻用了 9-13
2. Global features 幾乎全空：只有 komi 和 board size，缺少 pass indicators 等 19 個特徵
3. Territory estimation 過度簡化

**修正** (`mobile/lib/services/inference/onnx_engine.dart`):
1. 修正 binary features (22 channels) 按照 KataGo v7 規格：
   - Channels 0-2: on-board, current player, opponent
   - Channels 3-5: ko-ban, encore ko features
   - Channels 6-10: move history (last 5 moves)
   - Channels 14-17: ladder features (atari detection)
   - Channels 18-19: territory estimation (flood-fill based)
2. 補齊 global features (19 values)：
   - 0-4: pass indicators for last 5 turns
   - 5: komi / 20.0 (v7 normalization)
   - 6-7: ko rule encoding
   - 8: multi-stone suicide legality
   - 9: territory scoring flag
   - 10-14: tax rules, encore phase, komi parity
3. 改進 policy 評估：
   - 增加 uniformity ratio 檢測（max_prob / avg_prob * 10）
   - ratio > 2.0 時使用模型輸出，否則 fallback 到 tactical heuristic
   - 候選手勝率基於相對 policy probability 調整

**測試結果** (Android ONNX):
- 修正前：uniformity ratio < 2.0，所有手勝率 ~60%
- 修正後：uniformity ratio 2.5-6.5，勝率範圍 38%-99%
- Top moves 現在有明確差異，分析結果合理

**參考資料**:
- [KataGo paper - Accelerating Self-Play Learning in Go](https://arxiv.org/pdf/1902.10565)
- [KataGo GitHub](https://github.com/lightvector/KataGo) - `cpp/neuralnet/nninputs.cpp` (fillRowV7)

### iOS Simulator: ONNX Fallback (2026-02-15)

iOS Simulator 上 native KataGo 會崩潰。修復方式：
1. `AppDelegate.swift` 加入 `#if targetEnvironment(simulator)` 阻止 native 引擎啟動
2. `game_provider.dart` 在 native 失敗時自動 fallback 到 ONNX Runtime
3. iOS 真機仍使用 native KataGo（完整 MCTS），Simulator 使用 ONNX（單次推理）

### 棋盤建議顯示修正: Top 3 一致 (2026-02-15)

棋盤上只畫 Rank 1 建議，但分析清單顯示 Top 3。修正 `go_board_widget.dart`，移除勝率過濾並限制顯示前 3 個 rank，與清單一致。

### Repo 清理: 刪除 22 個過時 MD 檔案 (2026-02-15)

刪除開發過程中的中間文件（APPROACHES_TRIED.md、CRASH_ROOT_CAUSE.md 等），保留 CLAUDE.md、TASKS.md 和 docs/spec/ 下的規範文件。

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
