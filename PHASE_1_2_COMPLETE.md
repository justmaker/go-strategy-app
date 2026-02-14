# ✅ Phase 1-2 完成報告

## 🎉 編譯成功

**APK 位置:** `mobile/build/app/outputs/flutter-apk/app-debug.apk`
**Git Commit:** `68c7649` - feat(android): implement ONNX Runtime C++ backend (Phase 1-2)

---

## 已完成工作

### ✅ Phase 1: ONNX Runtime C++ Backend

**新建檔案:**
1. **`onnxbackend.cpp`** (~700行)
   - 完整實作 NeuralNet 介面
   - LoadedModel, ComputeContext, ComputeHandle, InputBuffers
   - NHWC ↔ NCHW 格式轉換
   - 完整的 getOutput() inference pipeline
   - 支援 policy/value/ownership/scoreValue 所有輸出
   - 支援 model version 3-16

2. **ONNX Runtime 1.23.2 Libraries**
   - `onnxruntime/include/` (11個 header files)
   - `onnxruntime/lib/arm64-v8a/libonnxruntime.so` (18MB)
   - `onnxruntime/lib/armeabi-v7a/libonnxruntime.so` (13MB)
   - `onnxruntime/lib/x86_64/libonnxruntime.so` (22MB)
   - `onnxruntime/lib/x86/libonnxruntime.so` (22MB)

**修改檔案:**
- `CMakeLists.txt`: 切換到 `-DUSE_ONNX_BACKEND`，排除 eigen/dummy backends
- `build.gradle`: 配置 jniLibs 打包 ONNX Runtime

### ✅ Phase 2: 單線程 NNEvaluator

**修改檔案:**
1. **`nneval.h`**:
   - 加入 `std::atomic<bool> singleThreadedMode`
   - 加入 `ComputeHandle* syncComputeHandle`
   - 加入 `NNServerBuf* syncServerBuf`
   - 加入 `setSingleThreadedMode()` / `getSingleThreadedMode()`

2. **`nneval.cpp`**:
   - Constructor: 初始化新成員
   - Destructor: 清理 sync resources
   - `evaluate()`: 加入單線程路徑
     ```cpp
     if(singleThreadedMode.load()) {
         // Direct synchronous getOutput() call
     } else {
         // Original queue-based path
     }
     ```
   - 實作 getter/setter 方法

---

## 關鍵技術實作

### 1. NHWC ↔ NCHW 轉換

```cpp
// KataGo NHWC (Eigen column-major): memory[c + w*C + h*C*W + n*C*W*H]
// ONNX NCHW: memory[n*C*H*W + c*H*W + h*W + w]

for (int n = 0; n < N; n++)
  for (int c = 0; c < C; c++)
    for (int h = 0; h < H; h++)
      for (int w = 0; w < W; w++)
        nchw[n*C*H*W + c*H*W + h*W + w] = nhwc[n*C*H*W + c + w*C + h*C*W];
```

### 2. 單線程配置

```cpp
sessionOptions.SetIntraOpNumThreads(1);  // No thread pool
sessionOptions.SetInterOpNumThreads(1);
```

### 3. Thread 消除

| 原有 Thread | 狀態 |
|------------|------|
| Main pthread (native-lib.cpp) | ⏳ Phase 3 待移除 |
| NNEvaluator server threads | ✅ 已繞過 (singleThreadedMode) |
| Search worker threads | ⏳ Phase 3 (numSearchThreads=1) |

---

## 編譯過程解決的問題

1. **Include path 錯誤**: `<onnxruntime/onnxruntime_cxx_api.h>` → `<onnxruntime_cxx_api.h>`
2. **NNAPI provider 不存在**: 移除 NNAPI 呼叫，使用 CPU provider
3. **Duplicate symbols**: 排除 dummybackend.cpp
4. **Missing libraries**: 加入所有 4 個架構的 libonnxruntime.so

---

## APK 詳情

**Build Command:**
```bash
cd mobile && flutter build apk --debug
```

**Build Time:** ~30 秒 (clean build)

**APK Size:** 預估 ~25-30MB (含 ONNX Runtime libraries)

**支援架構:**
- arm64-v8a (主要)
- armeabi-v7a (舊設備)
- x86_64 (模擬器)
- x86 (舊模擬器)

---

## 待完成工作 (Phase 3-5)

### ⏳ Phase 3: 同步 JNI API (預估 1-1.5 天)

**目標:** 移除 pthread，改用同步 JNI 呼叫

**主要工作:**
1. 重寫 `native-lib.cpp`:
   - 移除 pthread + pipe 架構
   - 新 JNI API: `initializeNative()`, `analyzePositionNative()`, `destroyNative()`
   - 直接使用 `Search` 類 (numThreads=1)
   - 啟用 `setSingleThreadedMode(true)`

2. 更新 `KataGoEngine.kt`:
   - 移除 pipe-based coroutine reader
   - 改用直接 JNI 呼叫 (blocking on Dispatchers.IO)

### ⏳ Phase 4: Dart 整合 (預估 0.5 天)

**主要工作:**
- 更新 `inference_factory.dart`: Android 優先使用 native KataGo
- 更新 `katago_service.dart`: 配合新的同步 API

### ⏳ Phase 5: 測試與驗證 (預估 0.5-1 天)

**測試項目:**
1. 實機測試 (ASUS Zenfone 12 Ultra 或類似設備)
2. 自動化測試腳本:
   ```bash
   adb install -r app-release.apk
   # 自動下棋 → 觸發 MCTS
   # 收集 logcat
   # 驗證無 crash + policy/value 正確
   ```
3. 品質驗證:
   - Top-1 move 一致率 ≥80% (vs desktop KataGo)
   - 分析延遲 ≤5 秒 (100 visits, 19x19)

---

## 當前狀態總結

✅ **Phase 1-2 完成** - ONNX Backend 和單線程 NNEvaluator 已實作並編譯成功

⏳ **Phase 3-5 待完成** - 需要重寫 JNI API、更新 Kotlin/Dart、實機測試

**預估剩餘工時:** 2-3 天

**風險評估:** 低 - 核心 backend 已完成，剩餘為整合工作

---

## 下一步建議

### 選項 A: 繼續完成 Phase 3-5
立即實作同步 JNI API，完成整個混合架構。

### 選項 B: 先測試當前實作
在不修改 JNI API 的情況下，先測試 ONNX backend 是否能正確運作（需要手動啟用 singleThreadedMode）。

### 選項 C: 分階段提交
將 Phase 1-2 作為獨立 feature 提交，Phase 3-5 作為後續 PR。

---

**建議**: 選項 A - 一鼓作氣完成整個方案，確保端到端可用。
