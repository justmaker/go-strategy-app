# Android 混合架構實作狀態

## 目標
在 Android 上保留 KataGo C++ MCTS，替換 Eigen backend 為 ONNX Runtime C++，消除所有 native pthread 以避免 Snapdragon 8 Gen 3 + Android 16 的 GPU driver crash。

## 實作進度

### ✅ Phase 1: ONNX Runtime C++ Backend (已完成)

**檔案：** `mobile/android/app/src/main/cpp/katago/cpp/neuralnet/onnxbackend.cpp` (新建, ~700行)

**實作內容：**
- `LoadedModel`: 載入 `.bin.gz` (metadata) + `.onnx` (inference)
- `ComputeContext`: 持有 `Ort::Env` 全域環境
- `ComputeHandle`: 持有 `Ort::Session`，配置單線程 (`SetIntraOpNumThreads(1)`)
- `InputBuffers`: 同 Eigen backend
- `convertNHWCtoNCHW()`: KataGo NHWC → ONNX NCHW 格式轉換
- `NeuralNet::getOutput()`: 完整的 inference pipeline
  - 複製輸入 + symmetry 變換
  - NHWC → NCHW 轉換
  - ONNX inference (synchronous)
  - 解析 policy/value/ownership/scoreValue 輸出
  - NCHW → NHWC + symmetry 逆轉

**關鍵特性：**
- 支援 NNAPI 硬體加速 (optional)
- 單線程模式：無 thread pool
- 支援所有 model version (3-16)

**Build 配置：**
- `CMakeLists.txt`: 切換到 `-DUSE_ONNX_BACKEND`，link `libonnxruntime.so`
- `build.gradle`: 配置 `jniLibs.srcDirs` 打包 ONNX Runtime

**ONNX Runtime：**
- 版本：1.23.2
- 大小：18MB (arm64-v8a)
- 位置：`mobile/android/app/src/main/cpp/onnxruntime/`

---

### ✅ Phase 2: 單線程 NNEvaluator (已完成)

**檔案：** `nneval.h`, `nneval.cpp`

**實作內容：**

1. **新增成員變數** (nneval.h):
```cpp
std::atomic<bool> singleThreadedMode;
ComputeHandle* syncComputeHandle;  // Lazy-init
NNServerBuf* syncServerBuf;
```

2. **修改 evaluate()** (nneval.cpp):
```cpp
if(singleThreadedMode.load()) {
    // Lazy-init syncComputeHandle
    // Direct synchronous call to NeuralNet::getOutput()
    // 跳過 queryQueue 和 server threads
} else {
    // Original queue-based multi-threaded path
}
```

3. **新方法**:
- `setSingleThreadedMode(bool)`: 啟用/停用單線程模式
- `getSingleThreadedMode()`: 查詢當前模式

4. **Destructor**: 清理 `syncComputeHandle` 和 `syncServerBuf`

**效果：**
- 當 `singleThreadedMode = true` 時，完全不使用 server threads
- 所有 NN evaluation 在 caller thread 同步執行
- 保留 NNCache 和其他功能

---

### ⏳ Phase 3: 同步 JNI API (待實作)

**目標：** 重寫 `native-lib.cpp`，移除 pthread + pipe 架構

**當前架構問題：**
- `pthread_create()` 建立 detached thread 運行 `MainCmds::analysis()`
- Pipe-based IPC (stdin/stdout)
- 所有這些都會觸發 Android crash

**新架構設計：**
```cpp
// 初始化 (一次性，不建立 thread)
JNIEXPORT jboolean JNICALL initializeNative(
    JNIEnv*, jobject, jstring config, jstring modelBin, jstring modelOnnx);

// 同步分析 (blocking, 在 Kotlin coroutine 的 IO thread 上執行)
JNIEXPORT jstring JNICALL analyzePositionNative(
    JNIEnv*, jobject,
    jint boardX, jint boardY, jdouble komi, jint maxVisits,
    jobjectArray moves);

// 清理
JNIEXPORT void JNICALL destroyNative(JNIEnv*, jobject);
```

**實作要點：**
- 不使用 `MainCmds::analysis()`（它會建立多個 threads）
- 直接使用 `Search` 類：
  - 建立 `SearchParams` (numThreads=1)
  - `search->setPosition()`
  - `search->runWholeSearch()` (同步執行)
  - 從 search tree 提取結果
- 啟用 `nnEval->setSingleThreadedMode(true)`

---

### ⏳ Phase 4: Kotlin/Dart 整合 (待實作)

**Kotlin** (`KataGoEngine.kt`):
- 移除 pipe-based coroutine reader
- 改用直接 JNI 呼叫：`analyzePositionNative()` (blocking)
- 在 `Dispatchers.IO` 上執行

**Dart** (`inference_factory.dart`, `katago_service.dart`):
- Android: 優先使用 native KataGo (如果可用)
- 不再需要 device detection fallback

---

### ⏳ Phase 5: 測試與驗證 (待實作)

**編譯測試：**
```bash
cd mobile && flutter build apk --release
```

**自動化測試腳本：**
```bash
adb install -r app-release.apk
adb shell am start -n com.gostratefy.go_strategy_app/.MainActivity
# 自動下10步，觸發 MCTS 分析
for i in 1 2 3 4 5 6 7 8 9 10; do
    adb shell "input tap $((380 + i%4*90)) $((790 + i/4*85))"
    sleep 3
done
# 收集 log
adb logcat -d | grep -E "ONNX|KataGo|Search"
```

**品質驗證指標：**
- ✅ 無 crash (0 SIGABRT/FORTIFY)
- ✅ ONNX inference 成功
- ✅ Policy logit 範圍合理 ([-20, +10])
- ✅ Top move 在合理位置
- ✅ Top-1 move 一致率 ≥80% (vs desktop KataGo)

---

## 當前狀態

**編譯狀態：** 🔄 正在測試編譯...

**已完成：**
- ✅ ONNX Runtime 整合
- ✅ `onnxbackend.cpp` 完整實作
- ✅ 單線程 NNEvaluator

**待完成：**
- ⏳ `native-lib.cpp` 重寫 (大工程)
- ⏳ `KataGoEngine.kt` 更新
- ⏳ Dart 端整合
- ⏳ 實機測試

**預估剩餘工時：** 2-3 天
- Phase 3: 1-1.5 天
- Phase 4: 0.5 天
- Phase 5: 0.5-1 天

---

## 關鍵技術細節

### NHWC ↔ NCHW 轉換

**KataGo (Eigen NHWC):**
```
memory[n][h][w][c] = data[n*C*H*W + c + w*C + h*C*W]
```

**ONNX (NCHW):**
```
memory[n][c][h][w] = data[n*C*H*W + c*H*W + h*W + w]
```

### Thread 消除策略

| 原有 Thread | 消除方法 |
|------------|---------|
| Main pthread | 移除，改用 JNI caller thread |
| NNEvaluator server threads | `singleThreadedMode=true` |
| Search worker threads | `numSearchThreads=1` |
| Analysis threads | 不使用 `MainCmds::analysis()` |

### 模型檔案

**需要兩個檔案：**
1. `model.bin.gz`: KataGo 格式，提供 `ModelDesc` metadata
2. `model_19x19.onnx`: ONNX 格式，用於 inference

**載入邏輯：**
```cpp
LoadedModel(const string& binGz, const string& onnx) {
    ModelDesc::loadFromFileMaybeGZipped(binGz, modelDesc, "");
    onnxModelPath = onnx;
}
```

---

## 風險評估

| 風險 | 影響 | 緩解 |
|------|------|------|
| 編譯錯誤 (missing symbols) | 高 | 需補充 stubs 或調整 exclude 規則 |
| ONNX model I/O 格式不匹配 | 中 | 已參考 eigenbackend 實作，應該正確 |
| Search 單線程太慢 | 低 | b6c96 小模型，ONNX ARM64 ~10ms |
| std::mutex 也觸發 crash | 低 | mutex lock 非 pthread_create，應該安全 |

---

## 下一步行動

1. **等待編譯完成**，檢查是否有錯誤
2. **如果編譯成功**：Phase 3 可簡化為最小改動
3. **如果編譯失敗**：修正錯誤後重新編譯
4. **編譯通過後**：完成 Phase 3-5
