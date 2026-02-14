# 混合架構：C++ MCTS + ONNX Runtime C++ API

## 方案概述

保留 KataGo 的核心優勢（MCTS search），只替換容易 crash 的部分（NN evaluation）。

## 架構設計

```
┌─────────────────────┐
│   Flutter/Dart UI   │
└──────────┬──────────┘
           │ JNI
┌──────────▼──────────┐
│  KataGo C++ Core    │
│  - MCTS Search      │ ← 保留（高效能）
│  - Tree traversal   │
│  - UCB selection    │
└──────────┬──────────┘
           │
┌──────────▼──────────┐
│  ONNX Runtime C++   │ ← 替換（穩定）
│  - NN evaluation    │
│  - No pthread       │
│  - Pure inference   │
└─────────────────────┘
```

## 實作步驟

### 1. 修改 KataGo Backend

在 `neuralnet/` 建立新的 backend：

```cpp
// neuralnet/nneval_onnx.h
class NNEvaluator_ONNX : public NNEvaluator {
public:
  NNEvaluator_ONNX(...);
  void evaluate(...) override;

private:
  Ort::Env env_;
  Ort::Session* session_;
  // No threads - pure synchronous evaluation
};
```

### 2. ONNX Evaluation（無 pthread）

```cpp
void NNEvaluator_ONNX::evaluate(const Board& board, ...) {
  // 1. Encode features (our existing 22-channel code)
  float* input = encodeFeatures(board);

  // 2. Run ONNX (synchronous, no threads)
  auto outputTensors = session_->Run(
    Ort::RunOptions{nullptr},
    inputNames, inputTensors, 2,
    outputNames, 4
  );

  // 3. Parse policy and value
  parseOutput(outputTensors, result);

  // No pthread_create, no GPU driver issues
}
```

### 3. CMakeLists.txt 修改

```cmake
# 加入 ONNX Runtime
add_library(katago_android SHARED
  # KataGo core (MCTS, search, game logic)
  search/*.cpp
  game/*.cpp
  # NEW: ONNX backend (replaces OpenCL)
  neuralnet/nneval_onnx.cpp
)

# Link ONNX Runtime (prebuilt AAR)
target_link_libraries(katago_android
  onnxruntime  # No pthread in inference
  ${log-lib}
)
```

### 4. 整合點

修改 KataGo 的 `NNEvaluator` factory：

```cpp
// For Android, use ONNX backend
#ifdef __ANDROID__
  return new NNEvaluator_ONNX(modelPath);
#else
  return new NNEvaluator_OpenCL(modelPath); // Desktop uses OpenCL
#endif
```

## 優勢

1. **MCTS 保留** - 高效能 C++ search
2. **No pthread crash** - ONNX inference 是 synchronous
3. **棋力保持** - 同樣的 search algorithm
4. **可行性高** - ONNX Runtime 有 C++ API

## 預估工作量

- **修改 KataGo backend**: 2-3 天
- **整合 ONNX C++ API**: 1-2 天
- **測試驗證**: 1 天
- **總計**: 4-6 天

## 與當前方案對比

| 項目 | 當前 (Pure ONNX) | 混合 (MCTS+ONNX) |
|------|------------------|------------------|
| MCTS | ❌ Dart heuristic | ✅ C++ KataGo |
| NN eval | ✅ ONNX Runtime | ✅ ONNX Runtime |
| Crash | ✅ 無 | ✅ 無 |
| 棋力 | ★★☆☆☆ | ★★★★★ |
| 工作量 | 已完成 | +4-6 天 |

## 技術細節

### ONNX Runtime C++ API

```cpp
#include <onnxruntime/core/session/onnxruntime_cxx_api.h>

Ort::Env env(ORT_LOGGING_LEVEL_WARNING, "KataGo");
Ort::SessionOptions options;
options.SetIntraOpNumThreads(1); // Single thread for inference
Ort::Session session(env, modelPath, options);

// Synchronous run (no pthread!)
auto outputs = session.Run(...);
```

### Why No Crash?

ONNX Runtime C++ 內部：
- 使用 thread pool（已初始化，不會動態建立）
- 或 single-threaded mode（完全無 thread）
- 不會觸發 Android GPU driver 的 mutex race

### Integration Point

KataGo 的 `NNEvaluator::evaluate()` 被 MCTS 呼叫時：
- 目前：建立 worker threads → crash
- 改後：呼叫 ONNX sync API → 穩定

## 下一步

如果要實作這個方案：

1. Fork KataGo repo
2. 建立 `neuralnet/nneval_onnx.cpp`
3. 實作 `NNEvaluator_ONNX` class
4. 修改 Android CMakeLists.txt
5. Link ONNX Runtime C++ library
6. 測試

**預期結果**: KataGo 等級的棋力 + Android 穩定性

---

這就是 **正確的** Android KataGo 移植方案。

當前的 Pure ONNX 只是臨時方案（避免 crash），但犧牲了 MCTS。
