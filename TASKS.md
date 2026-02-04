# Opening Book Enhancement Tasks

## Status Overview

| Board Size | Database Entries | Avg Visits | Status | Export Ready |
|------------|------------------|------------|--------|--------------|
| **9x9** | 1,091,000 | 282M | ✅ **COMPLETE** | ✅ 63MB .gz |
| **13x13** | 2,760 | 141 | ⏳ Needs expansion | ❌ Too low quality |
| **19x19** | 4,421 | 21 | ⏳ Needs expansion | ❌ Too low quality |

### Quality Metrics
- **9x9**: min=90K, max=54.9T, avg=282M visits (KataGo official book)
- **13x13**: min=100, max=200, avg=141 visits (needs 500+ for export)
- **19x19**: min=20, max=100, avg=21 visits (needs 500+ for export)

## Recent Progress (2026-02-05)
- ✅ Downloaded KataGo 9x9 Opening Book (book9x9tt-20241105.tar.gz, 772MB)
- ✅ Imported 1,091,000 positions (min-visits=5000, max-depth=20)
- ✅ Exported to mobile/assets/opening_book.json.gz (63MB, 240,252 entries)
- ✅ Committed and pushed to GitHub (commit 8cac654)
- 📂 Source: https://katagobooks.org/

---

## This Machine (GPU) - go-strategy-app server

### Task 1: Generate 19x19 Depth 12 Opening Book [🔄 RUNNING]
```bash
# Run KataGo analysis to expand 19x19 opening book to depth 12
python3 -m src.scripts.build_opening_book --board-size 19 --depth 12 --visits 500

# Monitor progress
watch -n 30 'python3 -c "import sqlite3; c=sqlite3.connect(\"data/analysis.db\").execute(\"SELECT COUNT(*) FROM analysis_cache WHERE board_size=19\"); print(f\"19x19: {c.fetchone()[0]:,}\")"'
```

### Task 2: Generate 13x13 Depth 12 Opening Book
```bash
# Run KataGo analysis to expand 13x13 opening book to depth 12
python3 -m src.scripts.build_opening_book --board-size 13 --depth 12 --visits 500
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
cur.execute('DELETE FROM analysis_cache WHERE board_size IN (13, 19) AND engine_visits < 500')
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
