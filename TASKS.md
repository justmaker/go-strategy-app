# Tasks

## 🚨 Android Crash Fix: TensorFlow Lite Migration (Priority 1)

### 狀態: 📋 Planning

### 問題描述

ASUS Zenfone 12 Ultra (Snapdragon 8 Gen 3 / Adreno 750 / Android 16) 上無法執行 KataGo native pthread，任何從 native code 建立的 thread 都會觸發系統層級的 `pthread_mutex_lock called on a destroyed mutex` crash。

已嘗試的方法（全部失敗）：
- ✅ 延遲載入 native library
- ✅ std::thread → pthread 轉換
- ✅ shared C++ runtime (c++_shared)
- ✅ 4MB stack size
- ✅ JNI_OnLoad 提早初始化
- ✅ 30 秒啟動延遲
- ❌ 所有方法都在 pthread_create 後 50ms 內 crash

### 解決方案: 改用 TensorFlow Lite Mobile + NNAPI

採用 BadukAI 的做法，使用 Google 官方 mobile AI framework。

### 工作項目

#### Phase 1: 模型轉換 (估計 1-2 天)
1. 研究 KataGo 模型格式與 TFLite 轉換流程
2. 將 KataGo `.bin.gz` 模型轉換為 `.tflite`
3. 驗證轉換後模型的準確性（與原 KataGo 比對）

#### Phase 2: TFLite 整合 (估計 2-3 天)
1. 加入 TensorFlow Lite dependencies 到 `pubspec.yaml`
2. 建立 `TFLiteKataGoService` 替換現有 `KataGoService`
3. 實作 NNAPI delegate 啟用硬體加速
4. 實作 pre/post-processing（board state → tensor → move probabilities）

#### Phase 3: 測試與優化 (估計 1 天)
1. 在 ASUS Zenfone 12 Ultra 上測試
2. 效能 benchmark (latency, memory)
3. 與原 KataGo 結果比對（確保準確性）

### 參考資源

- [TensorFlow Lite Android Quickstart](https://www.tensorflow.org/lite/android/quickstart)
- [LiteRT (TFLite successor)](https://github.com/google-ai-edge/LiteRT)
- [NNAPI Migration Guide](https://developer.android.com/ndk/guides/neuralnetworks/migration-guide)
- BadukAI 使用 `libtensorflowlite.so` + Qualcomm QNN/SNPE

### 備註

- 此修復也會讓其他 Android 裝置受益（TFLite 效能通常優於自編譯 KataGo）
- Opening book (2.5M entries) 不受影響，持續可用

---

# Tasks

## CI/CD: GitHub Actions Multi-Platform Release

### 狀態: ✅ 已完成 (2026-02-10)

建立了 GitHub Actions 工作流，支援一鍵建置 Android / iOS / macOS 並發布到 GitHub Releases。

### 工作流檔案

- `.github/workflows/release.yml` - 多平台建置與發布

### 觸發方式

在 GitHub Actions 頁面手動觸發 (workflow_dispatch)：
- **version**: 可選，指定版本號（如 `1.1.0`），留空使用目前版本
- **build_notes**: 可選，額外的發布備註

### 建置矩陣

| Job | Runner | 產出 | 說明 |
|-----|--------|------|------|
| build-android | ubuntu-latest | APK | Java 17 + CMake (KataGo native) |
| build-ios | macos-latest | Runner.app.zip | --no-codesign (sideload) |
| build-macos | macos-latest | go_strategy_app.app.zip | 拖入 Applications 即可 |
| release | ubuntu-latest | GitHub Release | 收集所有產物並發布 |

### 版本策略

- Tag 格式: `v{VERSION}+{BUILD_NUMBER}`
- Build Number = git commit count
- 三個平台並行建置，最後統一發布

---

## macOS Google Sign-In (branch: `fix/macos-google-signin`)

### 狀態: 部分完成，需要繼續 debug

### ✅ 已完成

1. **修復 macOS Google Sign-In 崩潰問題**
   - 加入 `GIDClientID` 到 `macos/Runner/Info.plist`
   - 加入 `CFBundleURLTypes` URL scheme
   - 加入 `com.apple.security.network.client` entitlement

2. **設定 Google Cloud OAuth**
   - 建立 Desktop 類型 OAuth Client ID
   - Client ID: `1046387...`（完整值見 `mobile/macos/Runner/Info.plist`）
   - 加入測試使用者

3. **OAuth 流程測試結果**
   - App 不再崩潰 ✓
   - 瀏覽器正確開啟 Google 登入頁面 ✓
   - 使用者可完成 Google 認證 ✓

### ❌ 待解決

**問題**: OAuth 回調後 UI 沒有更新（仍顯示未登入）

- `_googleSignIn.signIn()` 在瀏覽器完成認證後沒有正確返回
- 需要檢查 OAuth callback 處理機制

### Debug 線索

- 已在 `auth_service.dart` 加入 `[AuthService]` debug print
- 需要觀察 console 是否有 `signIn returned:` 訊息
- 可能需要檢查 AppDelegate 或 URL scheme 配置

### 相關 PR

- PR #1: https://github.com/justmaker/go-strategy-app/pull/1

---

# Opening Book Enhancement Tasks

## Status Overview (GPU Server - Updated 2026-02-05 12:38)

> **注意**：以下為 GPU Server 上的資料量。本地 `data/analysis.db` 的數字可能不同（目前：9x9=10,230 / 13x13=8,543 / 19x19=12,822）。

| Board Size | Database Entries (GPU) | Avg Visits | Status | Export Ready |
|------------|------------------------|------------|--------|--------------|
| **9x9** | 1,519,000 | 205M | ✅ **COMPLETE** | ✅ 64MB .gz |
| **13x13** | 8,552 | 500 | ⏳ Waiting for 19x19 | ✅ Ready |
| **19x19** | 16,898 | 500 | 🔄 **RUNNING** depth 12 | ⏳ In progress |

### Quality Metrics
- **9x9**: 1,519,000 positions, min=90K, max=54.9T, avg=205M visits (KataGo official book)
- **13x13**: 8,552 positions, 500 visits (ready for export)
- **19x19**: 16,898 positions, 500 visits (generation in progress)

### 19x19 Generation Progress
- **Runtime**: ~7 min (restarted 2026-02-05 12:31)
- **Process**: KataGo GTP (PID 256491)
- **GPU**: RTX 5060 @ 63% utilization
- **Note**: Previous run (12h+) was interrupted; restarted fresh

## Recent Progress (2026-02-05)
- ✅ Downloaded KataGo 9x9 Opening Book (book9x9tt-20241105.tar.gz, 772MB)
- ✅ Imported 1,519,000 positions to GPU server database
- ✅ Exported to mobile/assets/opening_book.json.gz (64MB, 240,252 entries)
- 🔄 19x19 depth 12 generation restarted (PID 256491, started 12:31)
- ⚠️ Killed conflicting 13x13 process (was causing GPU contention)
- 📂 Source: https://katagobooks.org/

---

## This Machine (GPU) - go-strategy-app server

### Task 1: Generate 19x19 Depth 12 Opening Book [🔄 RUNNING]
```bash
# Run KataGo analysis to expand 19x19 opening book to depth 12
python3 -m src.scripts.build_opening_book --board-size 19 --depth 12 --visits 500

# Monitor progress
watch -n 30 'python3 -c "import sqlite3; c=sqlite3.connect(\"data/analysis.db\").execute(\"SELECT COUNT(*) FROM analysis_cache WHERE board_size=19\"); print(f\"19x19: {c.fetchone()[0]:,}\")"'
```

### Task 2: Generate 13x13 Depth 12 Opening Book
```bash
# Run KataGo analysis to expand 13x13 opening book to depth 12
python3 -m src.scripts.build_opening_book --board-size 13 --depth 12 --visits 500
```

---

## Other Server (No GPU)

### Task 1: Clean Low-Visit Data
```bash
# Delete entries with visits < 500 from 13x13 & 19x19
python3 -c "
import sqlite3
conn = sqlite3.connect('data/analysis.db')
cur = conn.cursor()
cur.execute('DELETE FROM analysis_cache WHERE board_size IN (13, 19) AND engine_visits < 500')
print(f'Deleted {cur.rowcount} rows')
conn.commit()
conn.close()
"
```

### Task 2: Re-export Opening Book
```bash
# Export opening book with min-visits 500 filter
python3 -m src.scripts.export_opening_book --min-visits 500
```

---

## Execution Order

1. **[GPU Machine]** Run 19x19 depth 12 generation
2. **[GPU Machine]** Run 13x13 depth 12 generation
3. **[Other Server]** Clean visits < 500 data
4. **[Other Server]** Re-export Opening Book

**Note**: Steps 3-4 should be done AFTER steps 1-2 complete and database is synced.
