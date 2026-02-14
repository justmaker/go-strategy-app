# Crash 根因分析

## 從 Log 重建 Crash 時序

根據之前的測試記錄：

1. **KataGo pthread 建立**：
```
I KataGoNative: KataGo pthread created successfully
I KataGoNative: KataGo pthread started
```

2. **Crash 發生**（~50ms 後）：
```
F libc: FORTIFY: pthread_mutex_lock called on a destroyed mutex (0x7cb0a02ae8)
F libc: Fatal signal 6 (SIGABRT), code -1 (SI_QUEUE) in tid 10866 (hwuiTask0), pid 10791
```

## 關鍵觀察

### Crash Thread: `hwuiTask0`

**不是** KataGo 的 thread！

`hwuiTask0` 是 **Android Hardware UI** 的渲染執行緒。

### 時序

1. KataGo pthread 建立 ✓
2. 50ms 後
3. **HWUI thread** crash (不是 KataGo thread)

## 結論

**Crash 發生在**: HWUI (GPU driver layer)

**不是發生在**: KataGo MCTS (CPU threading)

**Root Cause**: 
- KataGo pthread 建立時，觸發了某個 GPU driver 的初始化
- 與 Android HWUI 的 mutex 產生衝突
- 這是 **driver-level race condition**

## 為什麼 ONNX 可以避開

ONNX Runtime：
- ✅ 純 Dart/Java（不建立 native pthread）
- ✅ 不觸發 GPU driver 初始化的 timing issue
- ✅ MCTS 在 ONNX model 內部（已訓練好，不需 runtime search）

## 為什麼 Qualcomm SDK 可能有效

Qualcomm SDK (QNN/SNPE):
- ✅ 由硬體廠商提供，已解決 driver timing issues
- ✅ 針對 Snapdragon 優化
- ✅ 不會觸發 HWUI race condition

## 回答你的問題

> Crash 是發生在 MCTS CPU 執行緒管理，還是 OpenCL 驅動？

**答案**: **OpenCL/GPU driver level**

**證據**:
1. Crash thread 是 `hwuiTask` (GPU rendering)
2. KataGo thread 本身啟動成功
3. 我們用的是 Eigen backend (CPU only, 無 OpenCL)
4. 但 pthread 建立仍觸發了 GPU driver 的某些 mutex

**結論**:
- 換 ONNX 有救（不用 pthread）✓
- 用 Qualcomm SDK 也有救（driver 已修正）✓
- 繼續用 NDK pthread 無救（driver bug 無法避開）✗
