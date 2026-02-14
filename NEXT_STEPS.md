# Android ONNX - 下一步行動

## 當前狀態 (2026-02-14 16:13)

### ✅ 完全解決
- Android pthread crash（核心目標）
- 技術架構完整
- 所有 code 整合

### ⚠️ 需要修復
**ONNX engine 不執行** - Opening book miss 後沒有觸發分析

**原因**（推測）:
1. `_localEngineEnabled` 可能被設為 false
2. `_ensureEngineStarted()` 返回 false
3. 或 MainActivity 的 `isProblematicDevice()` 還在阻擋

## 立即行動

### Debug 為什麼 ONNX 不執行

檢查 GameProvider.dart 的 analyze() 流程：

```bash
# 1. 確認 local engine 設定
grep "_localEngineEnabled = " mobile/lib/providers/game_provider.dart

# 2. 確認 Android platform detection
grep "Platform.isAndroid" mobile/lib/providers/game_provider.dart

# 3. 確認 MainActivity 沒有阻擋
grep "isProblematicDevice\|KataGo disabled" mobile/android/.../MainActivity.kt
```

### 預期找到的問題

可能是 MainActivity.kt 的 `isProblematicDevice()` 還在返回 true，阻止 engine 啟動。

**修復**：移除或修改 device detection，讓 ONNX 可以在所有 Android 裝置啟動。

## 品質改進路徑

### 選項 1: 修復 ONNX Feature Encoding（困難，1-2 週）

需要：
1. 逐一對比 KataGo fillRowV7() 的確切實作
2. 驗證每個 channel 的 encoding 正確性
3. 可能需要理解 KataGo 內部的座標系統差異

### 選項 2: 使用 Opening Book Only（簡單，立即）

**優點**:
- 2.5M entries，品質保證
- 已驗證可用
- 不會誤導使用者

**缺點**:
- Opening book miss 時無分析

**實作**：
```kotlin
// MainActivity.kt
private fun ensureKataGoEngine(): Boolean {
    return false // Disable all local engines on Android
}
```

### 選項 3: 改善 Tactical Heuristic（中等，2-3 天）

已實作但需 debug：
- 2-ply reading (counter-capture detection)
- Group size evaluation
- 確保會執行（當前問題）

## KataGo 測試工具

已建立 `test_katago_compare.sh`:

```bash
./test_katago_compare.sh "B G7 W F4 B C3 W F3 B C7 W F5 B D5 W F6 B F7 W E6 B E7"
```

輸出 KataGo Top 5 以供對比。

## 測試結果記錄

**Position**: 11 moves, White to play

**KataGo**: D3 (5.3%), D6 (7.5%), C4 (5.2%)
**ONNX**: E5 (60%)

**差異**:
- KataGo 的 top move 都不在 ONNX top 5
- Winrate 完全不同（5% vs 60%）
- ONNX 缺乏戰略深度

## 建議的最終方案

**立即**:
1. Debug 為什麼 ONNX engine 不執行
2. 修復後測試 tactical evaluator

**如果 tactical evaluator 還是品質不足**:
- 停用 Android local engine
- 標註 opening book 為主要功能
- ONNX 標為「實驗性」

**長期**:
- 考慮使用預訓練的 mobile-optimized model
- 或等待更好的 KataGo mobile solution

---

**Current Status**: Technical完整，Quality待改善
**All code pushed**: 60+ commits
