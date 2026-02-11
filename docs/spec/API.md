# API Specification v1.0

本文件定義 Go Strategy App 後端 API 的通訊規範，適用於 Python FastAPI 後端與任何調用方（如 Flutter App）。

## 1. 基礎資訊
- **Base URL**: `http://<host>:8000`
- **Content-Type**: `application/json`
- **座標系統**: 全面採用 **GTP (Go Text Protocol)** 標準（例如 `Q16`, `D4`），其中 'I' 字元會被跳過。

## 2. 端點列表 (Endpoints)

### 2.1 健康檢查 (Health Check)
用於確認服務狀態與 KataGo 引擎是否就緒。
- **URL**: `/health`
- **Method**: `GET`
- **Response**:
    ```json
    {
      "status": "ok",
      "cache_entries": 58734,
      "katago_running": true,
      "cache_only_mode": false
    }
    ```

### 2.2 提交分析 (Analyze)
分析指定的棋盤位置。若快取中有結果則立即返回，否則啟動 KataGo 分析。
- **URL**: `/analyze`
- **Method**: `POST`
- **Request Body**:
    ```json
    {
      "board_size": 19,
      "moves": ["B Q16", "W D4"],
      "handicap": 0,
      "komi": 7.5,
      "visits": 150,
      "force_refresh": false
    }
    ```
- **Response**: `AnalysisResponse` (見 3.1)

### 2.3 快速查詢 (Query Cache)
僅查詢快取，不啟動 KataGo。適用於快速導航。
- **URL**: `/query`
- **Method**: `POST`
- **Request Body**: (與 Analyze 類似，但不含 visits/force_refresh)
- **Response**:
    ```json
    {
      "found": true,
      "result": { ... AnalysisResponse ... }
    }
    ```

### 2.4 快取統計 (Cache Statistics)
取得分析快取的詳細統計資訊。
- **URL**: `/stats`
- **Method**: `GET`
- **Response**:
    ```json
    {
      "total_entries": 31590,
      "by_board_size": {
        "9": 10230,
        "13": 8543,
        "19": 12817
      },
      "by_model": {
        "kata1-b18c384": 31590
      },
      "db_size_bytes": 52428800,
      "db_path": "data/analysis.db"
    }
    ```

## 3. 資料模型 (Definitions)

### 3.1 AnalysisResponse
```json
{
  "board_hash": "a1b2c3d4e5f6g7h8",
  "board_size": 19,
  "komi": 7.5,
  "moves_sequence": "B[Q16];W[D4]",
  "top_moves": [
    {
      "move": "Q3",
      "winrate": 0.52,
      "score_lead": 0.5,
      "visits": 150
    }
  ],
  "engine_visits": 150,
  "model_name": "kata1-b18c384",
  "from_cache": true,
  "timestamp": "2024-01-21T20:00:00"
}
```

## 4. 錯誤處理
API 應回傳標準 HTTP 狀態碼：
- `200 OK`: 成功。
- `400 Bad Request`: 參數錯誤（如不支援的棋盤大小）。
- `404 Not Found`: 僅在 `/query` 找不到快取時出現。
- `500 Internal Server Error`: 伺服器內部錯誤或 KataGo 崩潰。
