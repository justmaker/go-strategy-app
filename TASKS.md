# Opening Book Enhancement Tasks

## Status Overview
- **9x9**: Completed (1,519,000 entries from KataGo official book)
- **13x13**: 8,543 entries (needs depth 12 expansion)
- **19x19**: 13,270 entries (needs depth 12 expansion)

---

## This Machine (GPU) - go-strategy-app server

### Task 1: Generate 19x19 Depth 12 Opening Book
```bash
# Run KataGo analysis to expand 19x19 opening book to depth 12
python3 -m src.scripts.generate_opening_book --board-size 19 --max-depth 12 --min-visits 500
```

### Task 2: Generate 13x13 Depth 12 Opening Book
```bash
# Run KataGo analysis to expand 13x13 opening book to depth 12
python3 -m src.scripts.generate_opening_book --board-size 13 --max-depth 12 --min-visits 500
```

---

## Other Server (No GPU)

### Task 1: Clean Low-Visit Data
```bash
# Delete entries with visits < 500 from 13x13 & 19x19
python3 -c "
import sqlite3
conn = sqlite3.connect('data/analysis.db')
cur = conn.cursor()
cur.execute('DELETE FROM analysis_cache WHERE board_size IN (13, 19) AND visits < 500')
print(f'Deleted {cur.rowcount} rows')
conn.commit()
conn.close()
"
```

### Task 2: Re-export Opening Book
```bash
# Export opening book with min-visits 500 filter
python3 -m src.scripts.export_opening_book --min-visits 500
```

---

## Execution Order

1. **[GPU Machine]** Run 19x19 depth 12 generation
2. **[GPU Machine]** Run 13x13 depth 12 generation
3. **[Other Server]** Clean visits < 500 data
4. **[Other Server]** Re-export Opening Book

**Note**: Steps 3-4 should be done AFTER steps 1-2 complete and database is synced.
