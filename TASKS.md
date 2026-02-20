# Tasks

## 待處理

### 抽出 katago-onnx-mobile 到獨立 repo

**狀態**: 🟡 進行中（iOS/Android ONNX 測試通過，待合併到 main）

**目的**: Go Strategy App 要做第二個獨立的圍棋解題 App，兩個 app 共用 KataGo ONNX 引擎。需要將 ONNX 相關的共用元件抽出到 `https://github.com/justmaker/katago-onnx-mobile` 作為 Flutter plugin。

**新 App 規格**:
- 輸入方式: 手動擺棋 + 拍照辨識 + 匯入圖片/SGF + GTP
- 引擎: 手機平板用 KataGo ONNX，桌機用 KataGo Eigen
- 目標: 提供局部或整盤棋局，算出 top N 次一手

**要抽出的元件**:

| 類別 | 檔案 | 來源路徑 |
|------|------|---------|
| Dart | `inference_engine.dart` | `mobile/lib/services/inference/` |
| Dart | `onnx_engine.dart` | 同上 |
| Dart | `onnx_engine_stub.dart` | 同上 |
| Dart | `katago_engine.dart` | 同上 |
| Dart | `liberty_calculator.dart` | 同上 |
| Dart | `tactical_evaluator.dart` | 同上 |
| iOS | `KataGoOnnxBridge.h/mm` | `mobile/ios/KataGoMobile/Sources/` |
| iOS | `KataGoWrapper.h/mm` | 同上 |
| iOS | `stubs.cpp` | 同上 |
| iOS | KataGo C++ core | `mobile/ios/KataGoMobile/Sources/katago/cpp/` |
| Android | `native-lib.cpp` | `mobile/android/app/src/main/cpp/` |
| Android | `stubs.cpp` | 同上 |
| Android | `CMakeLists.txt` | 同上 |
| Android | `KataGoEngine.kt` | `mobile/android/.../go_strategy_app/` |
| Android | KataGo C++ core | `mobile/android/app/src/main/cpp/katago/` |
| Android | Eigen headers | `mobile/android/app/src/main/cpp/eigen/` |
| Android | ONNX Runtime libs | `mobile/android/app/src/main/cpp/onnxruntime/` |
| Model | `model.onnx`, `model.bin.gz`, `model.bin` | `mobile/assets/` |

**Plugin 目標結構**:

```
katago-onnx-mobile/
├── pubspec.yaml
├── lib/
│   ├── katago_onnx_mobile.dart     # Public API
│   └── src/                        # Dart inference 檔案
├── android/
│   ├── build.gradle
│   └── src/main/
│       ├── kotlin/.../KataGoEngine.kt
│       └── cpp/                    # native-lib, katago, eigen, onnxruntime
├── ios/
│   ├── Classes/                    # OnnxBridge, Wrapper, stubs
│   ├── katago/cpp/                 # KataGo core
│   └── katago_onnx_mobile.podspec
├── assets/                         # model.onnx, model.bin, model.bin.gz
└── example/
```

**實作步驟**:

1. ✅ 計劃已寫入 TASKS.md
2. ✅ 建立新 repo 基本結構 (`flutter create --template=plugin`)
3. ✅ 遷移 Dart 程式碼（修改 import paths，移除 app-specific 依賴）
4. ✅ 遷移 Android Native（JNI package 名稱、build.gradle plugin 格式）
5. ✅ 遷移 iOS Native（podspec、header search paths、single-threaded mode）
6. ✅ 遷移 Model 檔案（改為 regular git，不用 LFS — Flutter pub get 不支援 LFS）
7. ✅ 修改原 Go Strategy App（改用 git dependency，移除 KataGoMobile pod）
8. 🟡 驗證:
   - ✅ macOS build (808.5MB)
   - ✅ Android ONNX inference (96 次推論，0 error)
   - ✅ iOS ONNX inference (8+ 次推論，19x19 + 13x13 切換正常)
   - ⬠iOS 記憶體問題：Signal 9 (SIGKILL)，opening_book.db 過大
   - ⬜ Plugin example app 獨立 build 測試

**Plugin repo**: `https://github.com/justmaker/katago-onnx-mobile`
**App branch**: `feature/katago-onnx-mobile-plugin`

**iOS 修復記錄** (2026-02-19):
1. 移除舊 `KataGoMobile` pod 避免 duplicate symbols
2. 修正 moves 格式轉換（`["B Q16"]` → `[["B", "Q16"]]`）
3. 從 Android 移植 `setSingleThreadedMode` 到 iOS KataGo C++（nneval.h/cpp）
4. 新增 board size 追蹤，切換棋盤大小時重新初始化引擎

**注意事項**:
- Flutter pub get 不支援 Git LFS — plugin 的大檔案必須用 regular git
- iOS 使用 plugin 的 MethodChannel (`com.justmaker.katago_onnx_mobile/engine`)
- Android 目前仍用 app 內建的 channel (`com.gostratefy.go_strategy_app/katago`)，之後需遷移
- macOS 使用 Eigen backend，不受 ONNX plugin 影響

---

### Opening Book: 13x13 / 19x19 擴充

**狀態**: 🟡 可繼續擴充

目前 Opening Book 資料量：

| Board Size | Entries | Depth | Visits | 說明 |
|------------|---------|-------|--------|------|
| 9x9 | 1,519,000 | 0-18 | 90K+ avg | KataGo 官方 book，已完成 |
| 13x13 | 139,235 | 0-14 | 500 | b18c384 模型 |
| 19x19 | 404,473 | 0-14 | 500 | b18c384 模型，淺層已補強 |

可繼續擴充 depth 15+，需在 GPU server 上執行：
```bash
python3 -m src.scripts.build_opening_book_parallel \
    --board-size 19 --depth 15 --visits 500 --batch-size 64 --branching 7
```

本機也可補充淺層資料（需 `/opt/homebrew/bin/katago`）：
```bash
python3 -m src.scripts.build_opening_book_parallel \
    --board-size 19 --depth 3 --visits 500 --batch-size 4 --branching 7 \
    --min-cache-visits 500 \
    --katago-path /opt/homebrew/bin/katago \
    --model-path /opt/homebrew/share/katago/kata1-b18c384nbt-s9996604416-d4316597426.bin.gz \
    --config-path katago/analysis.cfg
```

---

## 已完成

### macOS Google Sign-In 修復 (2026-02-19)

**問題**: OAuth 回調後 `_googleSignIn.signIn()` 不返回，UI 仍顯示未登入。

**根本原因**: OAuth Client ID 類型為 **Desktop**，但 GoogleSignIn SDK（google_sign_in_ios）預期 **iOS** 類型。Desktop 類型的 redirect URI 是 loopback (`http://localhost:PORT`)，與 SDK 構建的 custom URL scheme redirect 不匹配。

**修正**:
1. 在 Google Cloud Console 建立 **iOS 類型** OAuth Client ID（Bundle ID: `com.gostratefy.goStrategyApp`）
2. 更新 `Info.plist` 的 `GIDClientID` 和 `CFBundleURLTypes` 使用新 Client ID
3. `AppDelegate.swift` 加入 `application(_:open:)` override 和 debug logging
4. 啟用 Google Drive API 支援 Cloud Sync

### Web Deploy: dart:ffi 編譯修復 (2026-02-19)

**問題**: `Deploy Flutter Web to GitHub Pages` workflow 持續失敗，因為 `onnx_engine.dart` 無條件 import `package:onnxruntime`（依賴 `dart:ffi`），Wasm 編譯時不可用。

**修正**:
- 新增 `onnx_engine_stub.dart`：Web 平台用的空實作（`isAvailable = false`）
- `game_provider.dart`：改用 conditional import `if (dart.library.ffi)` 選擇真實 vs stub
- 本地 `flutter build web` 驗證通過，CI 已綠 ✅

### 19x19 Opening Book 淺層覆蓋改善 (2026-02-19)

**問題**: 19x19 開局只顯示 2 個 rank（小目 + 三三），缺少星位（4-4 hoshi）；opening book tree 在 depth 0 只有 3 個候選且全為小目等價點，BFS 展開因 branching factor=3 導致樹極窄。

**修正**:
1. **`opening_book_service.dart`**:
   - 注入 4-4 星位（hoshi）為 13x13/19x19 的標準開局
   - 星位、小目、三三使用不同 winrate ratio 確保 3 個獨立 rank 顯示
   - Opening book 版本 2→3，強制 app 重新解壓

2. **`build_opening_book_parallel.py`**:
   - 新增 `--branching`（default 7）、`--shallow-branching` CLI 參數
   - Depth 0：展開所有候選（無 branching/winrate 限制）
   - Depth 1-2：寬展開（shallow branching）、放寬 winrate 門檻至 0.20
   - 儲存 top 20 候選（原 10），避免對稱等價點佔滿名額
   - 新增 `--katago-path`、`--model-path`、`--config-path` 支援本機執行
   - 新增 `--min-cache-visits` 過濾低品質 cache 條目

3. **`export_opening_book.py`**:
   - Dead move filter 跳過 depth 0-3，保留淺層所有候選

4. **`analysis.cfg`**:
   - 加入 `numAnalysisThreads`（analysis mode 必要參數）
   - 修正 `reportAnalysisWinratesAs = BLACK`（與 GPU config 一致）

5. **Opening Book 數據補強**:
   - 本機用 KataGo Metal (500 visits) 重新分析 depth 0-2
   - 初始位置從 3 候選 → 20 候選（星位、小目、高目全覆蓋）
   - 合併 25 筆新數據到 opening_book.db.gz

### ONNX 模型統一與最佳化 (2026-02-18)

**任務**: 統一 ONNX 模型為單一 b20c256 變體，取代 3 個 size-specific 模型。

**完成項目**:
1. **模型合併**:
   - 刪除 `model_9x9.onnx`、`model_13x13.onnx`、`model_19x19.onnx`
   - 統一使用 `model.onnx` (b20c256)
   - b20c256 對所有棋盤大小具有更好的泛化能力

2. **模型加載優先順序調整**:
   - Android (`KataGoEngine.kt`): 優先 `model.onnx`，備用 size-specific 模型
   - iOS (`AppDelegate.swift`): 優先 `model.onnx` (b20c256) 用於 native MCTS，備用 b6c96 variants

3. **Opening Book 排序邏輯改善**:
   - 考慮當前玩家的輪次（黑白交替）
   - 根據當前玩家的實際勝率評估：黑手為直接勝率，白手則反轉
   - 優先按 visits 排序（MCTS 偏好），將低於 30% 當前玩家勝率的手段推至末尾
   - 結果：更準確的手段排名，符合 KataGo MCTS 搜尋的自然偏好

4. **Git LFS 配置擴充**:
   - 新增 `model.onnx` (4.5 MB)、`model.bin` (4.1 MB)、`model.bin.gz` (3.8 MB) 到 LFS 追蹤

5. **構建腳本格式規範**:
   - `build_opening_book_parallel.py` 更新為括號式記譜 (e.g., `B[Q16];W[D4]`)
   - 與 `import_katago_book.py` 保持一致

**影響**:
- App 資產包體積優化（3 個模型 → 1 個）
- 推論品質提升（b20c256 對小棋盤更好）
- 更準確的手段排名

### 9x9 Opening Book 勝率修正 (2026-02-17)

**問題**: 9x9 opening book 的勝率顯示反轉 — 邊角 99.8%、中央 3.5%。

**根本原因**: `import_katago_book.py` 誤將 `wl` 當作對手勝率做 `1.0 - wl` 轉換，但 KataGo book 的 `wl` 本身就是當前玩家勝率。同時 `ssM` 是對手的 score lead，需要取反。

**修正**:
1. `import_katago_book.py`: `winrate = wl`（不再反轉）、`score_lead = -ssM`
2. `opening_book.db.gz`: 修正 1,519,000 筆 9x9 資料
3. `opening_book_service.dart`: 版本號 1→2，強制 app 重新解壓

### iOS KataGo ONNX 即時進度更新 (2026-02-17)

使用大型模型（20b+）時 ONNX 推論耗時較長，新增即時進度回報和取消功能：
- `KataGoOnnxBridge.mm`: 透過 atomic `getRootVisits()` 讀取搜尋進度，支援 `requestStop()` 取消
- `AppDelegate.swift`: GCD timer 每 0.3 秒輪詢進度，透過 EventChannel 串流到 Dart
- `katago_engine.dart`: 監聽 EventChannel 的 `onnx_progress` 事件
- `game_provider.dart`: 傳遞 `onProgress` callback 更新 UI

**待驗證**: 需要大型模型實機測試（目前小模型推論太快，看不到進度變化）

### iOS Native KataGo-ONNX 整合 (2026-02-17)

在 iOS 上整合 native KataGo C++ 引擎搭配 ONNX Runtime，支援完整 MCTS 搜尋。
- 編譯 KataGo search/core/game 模組為 Objective-C++ bridge
- 透過 MethodChannel 呼叫 `analyzeOnnx`、EventChannel 回傳結果
- 支援可配置的 visits 數和模型路徑

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
