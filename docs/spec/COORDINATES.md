# 座標系統規範

本文件定義了 Go Strategy App 中使用的所有座標系統及其轉換規則。
所有座標相關程式碼**必須**參照本規範。

## 總覽

專案涉及 4 種座標系統：

| 系統 | 原點 | X 軸 | Y 軸 | 範例（9x9 星位） |
|------|------|------|------|-----------------|
| **GTP** | 左下 | A-J（跳過 I） | 1-9（底部=1） | `G7` |
| **Internal (x, y)** | 左上 | 0-8 左→右 | 0-8 上→下 | `(6, 2)` |
| **KataGo 棋盤陣列** | 左上 | 行 | 列 | `board[y*9+x]` = y-major |
| **KataGo Book HTML link idx** | 左上 | 行 | 列 | `idx = x*9+y` = **x-major** |

## GTP 格式（標準）

用途：App UI、DB 中的 moves_sequence、top_moves、API 通訊

```
     A B C D E F G H J        （欄位：跳過 'I'）
  9  . . . . . . . . .   9    第 9 列 = 頂部
  8  . . . . . . . . .   8
  7  . . + . . . + . .   7    '+' = 星位
  6  . . . . . . . . .   6
  5  . . . . + . . . .   5    中心 = E5
  4  . . . . . . . . .   4
  3  . . + . . . + . .   3
  2  . . . . . . . . .   2
  1  . . . . . . . . .   1    第 1 列 = 底部
     A B C D E F G H J
```

規則：
- 欄位字母：`A B C D E F G H J`（永遠跳過 `I`）
- 欄位索引：A=0, B=1, C=2, D=3, E=4, F=5, G=6, H=7, J=8
- 列號：1（底部）到 boardSize（頂部）
- 格式：`{欄位字母}{列號}`，如 `E5`、`Q16`

## Internal 座標系統 (x, y)

用途：Dart 棋盤邏輯、Python 分析工具

```
     x=0 x=1 x=2 ... x=8
y=0   .   .   .       .     ← 頂列（GTP 第 9 列）
y=1   .   .   .       .
y=2   .   .   .       .
 ...
y=8   .   .   .       .     ← 底列（GTP 第 1 列）
```

- `x` = 欄位索引（0 起始，左到右）= 與 GTP 欄位索引相同
- `y` = 列索引（0 起始，**由上到下**）= 與 GTP 列方向相反

## 座標轉換

### Internal ↔ GTP

```
GTP_COLUMNS = "ABCDEFGHJ"   // 永遠跳過 'I'

// Internal (x, y) → GTP 字串
col_letter = GTP_COLUMNS[x]
row_number = boardSize - y
gtp = "{col_letter}{row_number}"

// GTP 字串 → Internal (x, y)
x = GTP_COLUMNS.indexOf(col_letter)
y = boardSize - row_number
```

範例（9x9）：

| Internal (x, y) | GTP | 說明 |
|-----------------|-----|------|
| (0, 0) | A9 | 左上角 |
| (8, 0) | J9 | 右上角 |
| (0, 8) | A1 | 左下角 |
| (8, 8) | J1 | 右下角 |
| (4, 4) | E5 | 中心 |
| (6, 2) | G7 | 星位 |

### Python `coords_to_gtp(x, y)` 函式

**注意**：Python 的 `coords_to_gtp(x, y)` 使用 **y_bottom**（y=0 = 底部 = GTP 第 1 列），
與 Internal 的 y（y=0 = 頂部）不同：

```python
def coords_to_gtp(x, y):
    col = GTP_COLUMNS[x]
    row = y + 1          # y=0 → row 1（底部）
    return f"{col}{row}"
```

轉換：`y_bottom = boardSize - 1 - y_top`

### KataGo 棋盤陣列 ↔ Internal

KataGo 棋盤陣列（HTML 中的 `const board = [...]`）使用 **y-major** 排列：

```
flat_index = y * boardSize + x       // y-major（列優先）

// 展開：
x = flat_index % boardSize
y = flat_index // boardSize
```

值：0 = 空、1 = 黑、2 = 白

### KataGo Book HTML Link Index ↔ Internal

**重要**：link index（`const links = {idx: 'path'}`）使用 **x-major** 排列，
與棋盤陣列**不同**！這是造成座標 bug 的根因。

```
link_idx = x * boardSize + y         // x-major（欄優先）

// 展開：
x = link_idx // boardSize
y = link_idx % boardSize
```

### KataGo Book HTML Move `xy` 欄位 ↔ Internal

`const moves = [...]` 中的 `xy:[[x,y]]` 欄位使用：

```
// xy[0] = x（欄位，0 起始，左到右）
// xy[1] = y（列，0 起始，由上到下）
// 與 Internal (x, y) 相同
```

### 關鍵轉換：Link Index → GTP

```python
# KataGo book link_idx → GTP 座標
x = link_idx // boardSize           # 欄位
y_top = link_idx % boardSize        # 從頂部算起的列
y_bottom = boardSize - 1 - y_top    # 轉換為 coords_to_gtp 所需的 y_bottom
gtp_coord = coords_to_gtp(x, y_bottom)
```

也可以直接用 GTP 欄位和列號：
```python
col = GTP_COLUMNS[x]
row = boardSize - y_top
gtp = f"{col}{row}"
```

**絕對不要**用 `link_idx % boardSize` 當作 x — 那拿到的是 y！

## 對稱變換

8 種對稱類型（恆等 + 3 旋轉 + 4 鏡射）：

| 類型 | 名稱 | 變換 (x, y) → |
|------|------|--------------|
| 0 | 恆等 | (x, y) |
| 1 | 順時針旋轉 90° | (n-1-y, x) |
| 2 | 旋轉 180° | (n-1-x, n-1-y) |
| 3 | 順時針旋轉 270° | (y, n-1-x) |
| 4 | 水平鏡射 | (n-1-x, y) |
| 5 | 垂直鏡射 | (x, n-1-y) |
| 6 | 主對角線鏡射 | (y, x) |
| 7 | 反對角線鏡射 | (n-1-y, n-1-x) |

其中 `n = boardSize`。

逆變換對應：{0↔0, 1↔3, 2↔2, 3↔1, 4↔4, 5↔5, 6↔6, 7↔7}

## DB 中的 moves_sequence 格式

```
"B[E5];W[C3];B[G7]"
```

- 每步棋：`{顏色}[{GTP座標}]`
- 顏色：`B` 或 `W`
- 分隔符：`;`
- 空棋盤：`""`（空字串）

## 座標程式碼 Checklist

撰寫或審查座標轉換程式碼時，逐項確認：

- [ ] GTP 欄位字母跳過 'I'（`ABCDEFGHJ`，不是 `ABCDEFGHI`）
- [ ] GTP 第 1 列在底部，第 N 列在頂部
- [ ] Internal y=0 在頂部
- [ ] KataGo 棋盤陣列使用 y-major：`index = y * size + x`
- [ ] KataGo book link index 使用 x-major：`index = x * size + y`
- [ ] Python `coords_to_gtp(x, y)` 的 y 是 y_bottom（y=0 = 底部）
- [ ] 轉換公式：`row = boardSize - y_top`（不是 `y_top + 1`）
