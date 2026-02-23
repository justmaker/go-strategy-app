#!/bin/bash
# Run depth 15 for both 13x13 and 19x19 sequentially
set -e
cd /source/go-strategy-app

echo "[$(date)] === Starting depth 15 generation ==="

# 13x13 first (faster)
echo "[$(date)] Starting 13x13 depth 15..."
python3 -m src.scripts.build_opening_book_parallel \
    --board-size 13 --depth 15 --visits 500 --batch-size 64 \
    > logs/build_13x13_d15.log 2>&1
echo "[$(date)] 13x13 depth 15 COMPLETED"
tail -10 logs/build_13x13_d15.log
echo ""

# Memory check between runs
echo "[$(date)] Memory check:"
free -h | head -2
echo ""

# 19x19 next
echo "[$(date)] Starting 19x19 depth 15..."
python3 -m src.scripts.build_opening_book_parallel \
    --board-size 19 --depth 15 --visits 500 --batch-size 64 \
    > logs/build_19x19_d15.log 2>&1
echo "[$(date)] 19x19 depth 15 COMPLETED"
tail -10 logs/build_19x19_d15.log
echo ""

# Final stats
echo "[$(date)] === Final DB Stats ==="
python3 -c "
import sqlite3
conn = sqlite3.connect('data/analysis.db')
for size in [9, 13, 19]:
    count = conn.execute('SELECT COUNT(*) FROM analysis_cache WHERE board_size=?', (size,)).fetchone()[0]
    print(f'  {size}x{size}: {count:,} positions')
conn.close()
"
echo "[$(date)] All done!"
