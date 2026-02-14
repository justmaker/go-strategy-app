# ONNX Feature Encoding TODO

## 當前狀態 (2026-02-14)

✅ **Core 功能完成**: Android 不 crash，ONNX inference 運作
⚠️ **準確度問題**: 只有 4/22 features，預測不準確

## 已實作 Features (4/22)

| Channel | 名稱 | 狀態 | 實作位置 |
|---------|------|------|---------|
| 0 | On board | ✅ | `onnx_engine.dart:217` |
| 1 | Current player stones | ✅ | `onnx_engine.dart:203` |
| 2 | Opponent stones | ✅ | `onnx_engine.dart:212` |
| 3 | Current player color | ✅ | `onnx_engine.dart:223` |

## 待實作 Features (18/22)

### 高優先級（對準確度影響大）

| Channel | 名稱 | 難度 | 說明 |
|---------|------|------|------|
| 3-5 | Liberties (1, 2, 3+) | 🟡 中 | 需要 flood-fill 計算氣數 |
| 9-13 | Move history (last 5) | 🟢 易 | 標記最近 5 步的位置 |
| 6 | Ko ban | 🟢 易 | 劫爭禁止位置（需 game state） |

### 中優先級

| Channel | 名稱 | 難度 | 說明 |
|---------|------|------|------|
| 18-19 | Pass-alive territory | 🔴 難 | 需要複雜的 area 計算 |

### 低優先級（複雜且影響較小）

| Channel | 名稱 | 難度 | 說明 |
|---------|------|------|------|
| 14-17 | Ladder features | 🔴 難 | Ladder 檢測算法複雜 |
| 7-8 | Encore ko | 🟡 中 | 只在 encore 階段需要 |
| 20-21 | Reserved | - | 保留 |

## 測試結果

### 當前行為（4/22 features）

```
Policy logit range: [-4999, 3.0], >-10: 3
Top 5 indices:
  Index 81: prob=0.82 (pass move)
  Index 69: prob=0.08 (OCCUPIED)
  Index 58: prob=0.08 (OCCUPIED)
  Index 27: prob=0.0
  Index 4: prob=0.0
```

**問題**: Model 只有 3 個非零 probability（pass + 2 occupied），所有合法 moves 都是 prob=0。

### 預期行為（完整 features）

```
Policy logit range: [-20, 8], >-10: 30+
Top 5 indices:
  Index 40: prob=0.25 (E5)
  Index 49: prob=0.18 (F5)
  Index 31: prob=0.15 (D6)
  ...
```

## 實作建議

### 方案 A: 最小可用集（推薦）

實作 **Channels 0-2, 9-13**（當前棋子 + 歷史 5 步）
- 工作量: 1-2 小時
- 預期改善: 60-70% 準確度
- 足夠用於基本分析

### 方案 B: 完整實作

實作全部 22 channels
- 工作量: 1-2 天
- 預期改善: 95%+ 準確度
- 需要實作複雜算法（liberty counting, ladder, area）

## 參考資源

- [KataGo nninputs.cpp](https://github.com/lightvector/KataGo/blob/master/cpp/neuralnet/nninputs.cpp#L523) - fillRowV4() 完整實作
- [KataGo paper](https://arxiv.org/pdf/1902.10565) - Feature 設計說明

## 快速驗證

測試是否 features 足夠：

```dart
// 檢查 policy logits 分佈
Policy logit range: [-50, 5]  // Good: 大部分在 reasonable range
>-10 logits: 30+              // Good: 有足夠多的候選

vs.

Policy logit range: [-5000, 3] // Bad: 極端負值
>-10 logits: 3                 // Bad: 幾乎沒有候選
```

當 >-10 logits 達到 20-30 個時，預測應該就合理了。
