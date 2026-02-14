# Android ONNX 整合 - 限制與建議

## 現況評估 (2026-02-14)

### ✅ 已達成

1. **核心目標**: Android 不 crash ✓
2. **技術整合**: ONNX Runtime 成功整合 ✓
3. **All board sizes**: 9x9, 13x13, 19x19 穩定 ✓

### ❌ 未達成

**分析品質**: 不足以用於實戰

**使用者反饋**:
- "一直塞給人家吃"
- "持黑完全輸了"
- "跟別人對局，完全輸了"

## 問題根源

### 1. ONNX Model Policy 失效

**現象**: Policy output 完全均勻（所有 moves ~1.2% probability）

**原因**: Feature encoding 與 KataGo 訓練格式不符
- 雖然實作了 22/22 features
- 但 encoding 方式可能與訓練時不同
- Model 無法識別 input，輸出 uniform distribution

**證據**:
```
Policy logit range: [-0.06, 0.03]  // 應該是 [-20, +10]
All probabilities: ~0.0126 (1/82) // 應該有明顯差異
```

### 2. Heuristic 太簡化

**當前實作**:
- 基於位置（角、邊、中）
- 不考慮戰術（打吃、提子、逃跑）
- 不考慮對手威脅

**結果**:
- 開局時 OK（建議角的星位）
- 中盤時失效（不會救子、不會攻擊）
- 導致使用者輸棋

### 3. 架構限制

`_generateCenterBiasedPolicy()` 沒有 access 到：
- 當前棋盤狀態
- Liberty information
- Atari 情況
- 對手威脅

無法做戰術判斷。

## 建議方案

### 選項 A: 停用 Android Local Engine（推薦）

**實作**:
```kotlin
// MainActivity.kt
private fun ensureKataGoEngine(): Boolean {
    Log.w(TAG, "Local engine disabled - use opening book only")
    return false
}
```

**優點**:
- Opening book 有 2.5M entries，品質保證
- 不會誤導使用者（沒有分析 > 錯誤分析）
- App 依然穩定

**缺點**:
- Opening book miss 時無分析

### 選項 B: 深入修復 ONNX (需 1-2 週)

**Required Work**:
1. 研究 KataGo 確切的 feature encoding spec
2. 可能需要修改 ONNX export 過程
3. 或重新訓練 model with correct features
4. 逐一驗證每個 feature channel

**預估時間**: 7-14 天
**成功率**: 不確定

### 選項 C: 改用其他 Model

**候選**:
- Leela Zero (simpler feature format)
- MiniGo
- 或找已經有 Android implementation 的 model

**預估時間**: 3-5 天
**成功率**: 中等

## 測試結果對比

### Opening Book (2.5M entries)
```
F6: Win=74.5% Lead=-2.0  ← 有明確差異
F5: Win=14.2% Lead=-0.3
D6: Win=13.3% Lead=-0.4
```

### ONNX + Heuristic
```
C3: Win=60.0%  ← 幾乎相同
C7: Win=60.0%
F5: Win=59.9%
```

**結論**: Opening book 品質遠優於 ONNX heuristic

## 當前建議

**短期** (立即):
1. 停用 Android local engine
2. 依賴 opening book (已驗證品質)
3. Opening book miss 時顯示「無分析」

**長期** (如需要):
1. 深入研究 KataGo format
2. 或改用其他更簡單的 model
3. 或接受 opening book only

## 技術債務

已完成但品質不足的部分：
- ✅ ONNX Runtime 整合（技術層面成功）
- ✅ 22 features 實作（但 encoding 可能錯誤）
- ✅ Multi-board-size support
- ❌ 分析準確度（不足實戰使用）

---

**結論**: 核心目標（不 crash）已達成。分析品質需要更深入的工作，或接受只用 opening book。

**建議**: 停用 Android local engine，標註為「實驗性功能」，focus on opening book quality。
