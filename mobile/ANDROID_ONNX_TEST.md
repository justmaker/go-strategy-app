# Android ONNX Runtime 測試指南

## 版本資訊

- **APK**: `build/app/outputs/flutter-apk/app-release.apk` (222.6MB)
- **ONNX Model**: `assets/katago/model.onnx` (3.9MB, 19x19 fixed)
- **Engine**: ONNX Runtime 1.15.1 with NNAPI
- **Status**: ✅ 編譯成功，整合完成

## 已修復的問題

✅ Android 16 + Snapdragon 8 Gen 3 pthread crash
✅ Platform-specific inference (Android=ONNX, 其他=KataGo)
✅ ONNX Runtime 整合到 GameProvider
✅ Model shape issues (fixed 19x19)

## 測試步驟

### 1. 安裝 APK
```bash
adb -s S4AIOC4884805UP install -r build/app/outputs/flutter-apk/app-release.apk
```

### 2. 啟動並監控 log
```bash
adb -s S4AIOC4884805UP logcat -c
adb -s S4AIOC4884805UP shell am start -n com.gostratefy.go_strategy_app/.MainActivity
adb -s S4AIOC4884805UP logcat | grep -E "ONNX|Inference|Analysis"
```

### 3. 測試場景

#### 場景 A: Opening Book HIT（9x9 前幾手）
- **預期**: 立即返回 opening book 結果
- **不會**: 觸發 ONNX engine

#### 場景 B: Opening Book MISS（19x19 深度移動）
- **預期**:
  1. `[InferenceFactory] Creating ONNX Runtime engine for Android`
  2. `[OnnxEngine] Initializing ONNX Runtime...`
  3. `[OnnxEngine] ONNX Runtime version: 1.15.1`
  4. `[OnnxEngine] Available providers: [NNAPI, XNNPACK, CPU]`
  5. `[OnnxEngine] Model loaded: 4146202 bytes`
  6. `[OnnxEngine] Session created successfully`
  7. `[OnnxEngine] Analyzing: 19x19, N moves`
  8. `[OnnxEngine] Inference complete`
  9. `[OnnxEngine] Policy shape: 1x362`
  10. `[GameProvider] Inference engine analysis complete`

## 已知限制

1. **僅支援 19x19 棋盤** - ONNX model 固定 shape
   - 9x9/13x13 會拋出 UnsupportedError
   - 解決方案：為每個棋盤 size 轉換獨立 model

2. **Feature encoding 簡化** - 只實作 2/22 channels
   - Channel 0: 當前玩家棋子
   - Channel 1: 對手棋子
   - 其餘 20 channels（劫爭、氣數等）待實作

3. **Score lead 待實作** - 目前固定為 0.0
   - 需要解析 output_miscvalue

## 效能指標

- Model 載入: ~60ms
- Session 建立: ~40ms
- 單次 inference: 待測試
- Memory: 待測試

## 下一步

1. ✅ 測試 19x19 opening book miss 觸發 ONNX 分析
2. ⏳ 驗證分析結果正確性
3. ⏳ 實作完整 22 channels feature encoding
4. ⏳ 加入 9x9 和 13x13 model variants
5. ⏳ Benchmark 效能

## Troubleshooting

### App crashes on start
- Check: `adb logcat | grep FORTIFY`
- Should NOT see pthread_mutex errors (ONNX uses pure Dart/Java)

### ONNX engine fails to start
- Check: `adb logcat | grep OnnxEngine`
- Look for error in model loading or session creation

### Analysis returns empty
- Check: Board size (must be 19x19 currently)
- Check: ONNX engine is actually running (`isRunning = true`)

## 成功標準

✅ App 不 crash（最重要！）
✅ ONNX engine 啟動成功
✅ Model 載入成功
⏳ Inference 執行並返回合理的 moves
⏳ Winrate 在合理範圍（0-100%）
