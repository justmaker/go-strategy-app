# 我們嘗試過的所有方法

## 方法 1: Native KataGo (Android NDK) ❌

### 實作
- ✅ KataGo C++ source code
- ✅ Android NDK cross-compilation
- ✅ CMakeLists.txt 設定
- ✅ Eigen backend (CPU only)
- ✅ JNI bindings

### 檔案
- `mobile/android/app/src/main/cpp/CMakeLists.txt`
- `mobile/android/app/src/main/cpp/native-lib.cpp`
- `mobile/android/app/src/main/kotlin/.../KataGoEngine.kt`

### 失敗原因
**pthread_mutex crash** on Android 16 + Snapdragon 8 Gen 3
- std::thread → pthread (tried)
- Shared C++ runtime (tried)
- 4MB stack size (tried)
- 30s delay (tried)
- **所有方法都在 50ms 內 crash**

這是系統層級 bug，無法在 native code 層面解決。

## 方法 2: ONNX Runtime ✅ (當前)

### 為什麼換方法
Native pthread 在某些裝置上無解，需要純 Dart/Java solution。

### 實作
- ✅ KataGo model → ONNX 轉換
- ✅ ONNX Runtime Mobile
- ✅ 22 features encoding
- ✅ Tactical evaluator

### 問題
- ONNX model policy 太均勻（feature encoding mismatch）
- 需要 heuristic fallback

## 方法 3: Qualcomm QNN/SNPE (BadukAI 的方法) ⏸️

### BadukAI 使用
- Qualcomm QNN (Neural Network SDK)
- Qualcomm SNPE (Snapdragon NPE)
- 專用硬體加速

### 為什麼沒用
- 需要 Qualcomm SDK（商業授權）
- 需要 model 重新訓練/轉換
- 工程量巨大（1-2 月）

## 總結

| 方法 | 技術 | 狀態 | 品質 |
|------|------|------|------|
| Native NDK | KataGo C++ | ❌ Crash | N/A |
| ONNX Runtime | ONNX model | ✅ 可用 | ⚠️ 中等 |
| Qualcomm SDK | QNN/SNPE | ⏸️ 未實作 | ? 可能最好 |

**當前選擇**: ONNX Runtime（可用但品質有限）

**最佳長期方案**: Qualcomm SDK（如果願意投入時間）
