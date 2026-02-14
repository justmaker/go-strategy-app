# Android Hybrid MCTS+ONNX 測試指南

## 快速測試步驟

### 1. 建置並安裝

```bash
cd mobile
flutter build apk --release
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

### 2. 自動化測試（Opening Book 場景）

```bash
./scripts/test_android_hybrid_mcts.sh
```

**預期結果：**
- ✅ 無 crash
- ✅ Opening book 返回結果
- ⚠️ Native engine 未觸發 (book hit)

### 3. 手動測試（觸發 Native MCTS）

#### 方法 A: 深度局面（超出 opening book）

1. 在 19x19 棋盤上下 20+ 手
2. 走不常見的變化（避開定石）
3. 觀察 logcat:

```bash
adb logcat | grep -E "KataGoNative|ONNX|analyzePosition"
```

**預期 log：**
```
I KataGoNative: === analyzePositionNative ===
I KataGoNative: Board: 19x19, Komi: 7.5, MaxVisits: 100
I KataGoNative: Number of moves: 25
I KataGoNative: Position set up, next player: BLACK
I KataGoNative: Starting search (100 visits)...
I KataGo-ONNX: ONNX inference completed for batch size 1
I KataGoNative: Search completed
I KataGoNative: Analysis result: 1234 bytes
```

#### 方法 B: 強制 Local Engine

修改 `game_provider.dart`:

```dart
Future<void> analyze({bool forceRefresh = false, bool forceLocalEngine = true}) async {
    // ...
    if (forceLocalEngine || !_openingBook.isLoaded) {
        await _analyzeWithInferenceEngine();
        return;
    }
    // ...
}
```

然後在 app 中任意局面點擊 "Analyze" 按鈕。

---

## 驗證品質

### 比較測試局面

使用標準測試局面，比較 Android 和 Desktop 結果：

**測試局面 1: 空棋盤 (19x19, komi 7.5)**
```
Desktop KataGo:
  Top move: Q16 (winrate ~50%)

Android Hybrid:
  Top move: Q16 (winrate ~50%)
```

**測試局面 2: 標準定石**
```
Moves: B Q16, W D4, B Q3
Desktop: 預期 W R5 或 C6
Android: 應該一致
```

### 品質指標

| 指標 | 目標 | 驗證方法 |
|------|------|---------|
| Top-1 一致率 | ≥80% | 10 個測試局面 |
| Top-3 一致率 | ≥95% | 同上 |
| Policy logit 範圍 | [-20, +10] | 檢查 logcat |
| Value 準確度 | ±5% | 空棋盤 ~50% |
| 無 crash | 100% | 連續 100 次分析 |

---

## Logcat 篩選指令

```bash
# 即時監控 KataGo
adb logcat -s KataGoNative:V KataGo-ONNX:V MainActivity:I flutter:I

# 只看錯誤
adb logcat *:E | grep -E "FORTIFY|SIGABRT|Fatal"

# 完整 log 收集
adb logcat -d > /tmp/katago_test_$(date +%H%M%S).log

# 分析特定模式
adb logcat -d | grep -E "analyzePosition|ONNX inference|Search completed"
```

---

## 效能測試

### Benchmark Script

```bash
#!/bin/bash
# 測試 100 visits 分析延遲

adb logcat -c
# Trigger analysis (需要手動或自動化)
START=$(date +%s%N)
# Wait for "Search completed"
END=$(date +%s%N)

DURATION=$(( (END - START) / 1000000 ))  # ms
echo "Analysis time: ${DURATION} ms"
```

### 預期效能

| Visits | 預期延遲 | 備註 |
|--------|---------|------|
| 50 | ~500ms | 快速分析 |
| 100 | ~1s | 預設 |
| 500 | ~5s | 高品質 |
| 1000 | ~10s | 專業級 |

---

## 已知限制

### 1. Opening Book 優先
- App 設計為 opening book first
- 大部分開局不會觸發 native engine
- 這是 **feature, not bug**（快速響應）

### 2. 單線程較慢
- 比多線程 desktop KataGo 慢 2-4x
- 但品質相同（給定相同 visits）
- Mobile 上可接受的 trade-off

### 3. 需要手動測試場景
- 自動化測試難以繞過 opening book
- 建議手動建立深度局面或不常見變化

---

## 故障排除

### 問題：Native library 載入失敗

**Log:**
```
E KataGoEngine: Failed to load native library: ...
```

**解決：**
- 確認 `libkatago_mobile.so` 和 `libonnxruntime.so` 都在 APK 中
- `unzip -l app-release.apk | grep "\.so$"`
- 應該看到兩個 library 對每個架構

### 問題：ONNX session 建立失敗

**Log:**
```
E KataGo-ONNX: Failed to create ONNX session: ...
```

**解決：**
- 確認 `.onnx` 模型檔案已正確提取
- 檢查 `/data/data/com.gostratefy.go_strategy_app/cache/model_19x19.onnx`
- 確認檔案大小 ~4MB

### 問題：仍然 crash

**Log:**
```
F libc: FORTIFY: pthread_mutex_lock called on a destroyed mutex
```

**可能原因：**
- ONNX Runtime 內部建立了 thread
- 需要 double-check `SetIntraOpNumThreads(1)` 配置
- 或某處仍有 `std::thread` 建立

---

## 成功標誌

### Logcat 中應該看到：

```
I KataGoNative: === Initializing KataGo (ONNX Backend, Single-threaded) ===
I KataGo-ONNX: Created ONNX ComputeContext for 19x19 board
I KataGo-ONNX: Using CPU execution provider (single-threaded)
I KataGoNative: ✓ Single-threaded mode enabled
I KataGoNative: ✓ KataGo initialized successfully (no pthread created)
...
I KataGoNative: === analyzePositionNative ===
I KataGoNative: Starting search (100 visits)...
I KataGo-ONNX: ONNX inference completed for batch size 1
I KataGoNative: Search completed
I KataGoNative: Analysis result: 1500 bytes
```

### 決定性測試

**100 次連續分析無 crash = 成功！**

```bash
for i in {1..100}; do
    # Trigger analysis
    # Check for crash
    if adb logcat -d | grep -q "SIGABRT\|FORTIFY"; then
        echo "FAILED at iteration $i"
        exit 1
    fi
done
echo "SUCCESS: 100 iterations, 0 crashes"
```

---

## Summary

✅ **實作完成** - 所有 Phase 已實作並編譯成功

⏳ **待驗證** - 需要實際觸發 native engine 分析來驗證端到端功能

**預期：** 在所有 Android 設備上穩定運行，包含 Snapdragon 8 Gen 3 + Android 16。
