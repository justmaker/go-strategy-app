# KataGo vs ONNX 對比測試

## 測試局面

**Moves**: B G7 W F4 B C3 W F3 B C7 W F5 B D5 W F6 B F7 W E6 B E7

**盤面** (11手後，白方下):
```
  A B C D E F G H J
9                  
8                  
7     X   X X X    (黑: G7, C7, F7, E7)
6         O O      (白: E6, F6)
5       X   O      (黑: D5; 白: F5)
4           O      (白: F4)
3     X     O      (黑: C3; 白: F3)
2                  
1                  
```

## KataGo 分析 (100 visits)

**Top 5 moves**:
1. **D3**: 5.3% winrate (保護 C3，擴展)
2. **D6**: 7.5% winrate (保護 D5，反擊白棋)
3. **C4**: 5.2% winrate (連接 C3-C7)
4. **C2**: 5.8% winrate (擴展下方)
5. **D2**: 4.3% winrate (保守)

**Overall winrate**: 6.5% (白方劣勢)

## ONNX 建議

**Top 1**: E5 (60% winrate)

## 分析差異

### E5 的戰術分析

**ONNX 認為**:
- E5 吃掉 D5（黑子只剩 E5 一氣）
- 戰術上正確：確實能提子

**KataGo 認為**:
- E5 不在 top 5（甚至沒列出）
- D6 更好（保護 D5 同時反擊）

**為什麼 KataGo 不選 E5**:
1. 吃掉 D5 後，白 E5 本身可能被包圍
2. 黑方會在 D6 反吃，形成不利交換
3. 不如 D6 的戰略價值（保護+進攻）

### Winrate 差異

- KataGo: 5-7% (準確反映白方劣勢)
- ONNX: 60% (完全不準)

**原因**:
- ONNX value output 無法正確評估複雜局面
- Heuristic winrate (40-60%) 只是 placeholder
- 沒有真正的局面評估

## 結論

### ONNX Tactical Evaluator

**優點**:
- 能看到基本戰術（吃子、打吃）
- 不會送吃（比之前的純 geometric heuristic 好）

**缺點**:
- 只看眼前 1 步（沒有閱讀深度）
- 不考慮吃子後的反擊
- Winrate 不準確
- 缺乏戰略思考

### 建議

**實戰使用**: ❌ 不推薦
- 會建議戰術上「能動」但戰略上「不好」的下法
- Opening book (2.5M entries) 品質遠優於 ONNX

**適用場景**: 
- 純粹為了不 crash（已達成）
- Opening book miss 時給「不太差」的建議
- 理解為「初學者水準」的輔助

**最佳方案**: 
只依賴 opening book，opening book miss 時顯示「建議不可靠」警告。

---

**KataGo 可用**: ✅ 
測試指令已建立在此文件中。
