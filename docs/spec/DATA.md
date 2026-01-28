# Data Generation Specification

本文件定義 Opening Book 的生成標準、存儲格式以及導出流程，確保數據的準確性與可交換性。

## 1. 生成標準 (Generation Standards)

為了確保 AI 建議的品質，Opening Book 的生成應遵循以下參數：

### 1.1 棋盤規格
| 棋盤大小 | 目標深度 (Depth) | 建議 Visits | 覆蓋範圍 |
| :--- | :--- | :--- | :--- |
| **9x9** | 20 | 1000+ | 完整開局庫 (Empty to Mid-game) |
| **13x13** | 15 | 300+ | 主要角部與邊線變換 |
| **19x19** | 10 | 100+ | 核心定式 (Star, Komoku等) |

### 1.2 引擎設定
- **Model**: 必須使用與 App 內建一致的神經網路（例如 `kata1-b18c384...`）。
- **Komi**: 預設 7.5 (無讓子) 或 0.5 (有讓子)。

## 2. 導出格式 (Export Format)

導出文件 `opening_book.json.gz` 的內部結構應採取扁平化設計以節省空間：

```json
{
  "metadata": {
    "generated_at": "2026-01-28",
    "model": "katago-v1",
    "total_positions": 7500
  },
  "positions": [
    {
      "h": "a1b2c3d4",
      "s": 19,
      "k": 7.5,
      "v": 1000,
      "m": [
        {"c": "Q16", "w": 0.52, "l": 0.5},
        {"c": "D4", "w": 0.51, "l": 0.3}
      ]
    }
  ]
}
```
*欄位縮寫說明：`h`: hash, `s`: size, `k`: komi, `v`: visits, `m`: moves, `c`: coord, `w`: winrate, `l`: lead。*

## 3. 執行腳本 (CLI Usage)

### 3.1 啟動數據生成
```bash
python -m src.scripts.build_opening_book --board-size 9 --depth 20 --visits 1000
```

### 3.2 導出壓縮庫
```bash
python -m src.scripts.export_opening_book --min-visits 300 --compress
```

## 4. 品質保證 (QA)
- 導出前必須執行 `cleanup_db.py` 移除 Visits 過低 (<10) 的無效嘗試數據。
- 每月應定期重新生成關鍵節點，以反映更新的模型棋力。
