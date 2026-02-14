#!/bin/bash
# Auto-run: wait for 19x19 to finish, swap model, start 13x13
set -e
cd /source/go-strategy-app

PID_19x19=103590
MODEL_DIR=katago
MODEL_NAME=kata1-b18c384nbt-s9996604416-d4316597426.bin.gz

echo "[$(date)] Waiting for 19x19 generation (PID $PID_19x19) to finish..."

# Wait for 19x19 process to complete
while kill -0 $PID_19x19 2>/dev/null; do
    # Print progress every 60 seconds
    LAST_LINE=$(grep "Processed:" logs/build_19x19_d12.log 2>/dev/null | tail -1)
    echo "[$(date)] 19x19 running: $LAST_LINE"
    sleep 60
done

echo "[$(date)] 19x19 generation COMPLETED!"
echo "--- 19x19 Summary ---"
tail -20 logs/build_19x19_d12.log
echo ""

# Swap model: small -> large
echo "[$(date)] Swapping model to real b18c384 (94MB)..."
mv "$MODEL_DIR/$MODEL_NAME" "$MODEL_DIR/$MODEL_NAME.small"
mv "$MODEL_DIR/$MODEL_NAME.real" "$MODEL_DIR/$MODEL_NAME"
ls -lh "$MODEL_DIR/$MODEL_NAME"
echo "[$(date)] Model swapped successfully."

# Start 13x13 depth 12 generation
echo "[$(date)] Starting 13x13 depth 12 generation with large model..."
python3 -m src.scripts.build_opening_book_parallel \
    --board-size 13 --depth 12 --visits 500 --batch-size 64 \
    > logs/build_13x13_d12.log 2>&1

echo "[$(date)] 13x13 generation COMPLETED!"
echo "--- 13x13 Summary ---"
tail -20 logs/build_13x13_d12.log

# Show final DB stats
echo ""
echo "[$(date)] Final DB stats:"
python3 -c "
import sqlite3
conn = sqlite3.connect('data/analysis.db')
for size in [9, 13, 19]:
    count = conn.execute('SELECT COUNT(*) FROM analysis_cache WHERE board_size=?', (size,)).fetchone()[0]
    print(f'  {size}x{size}: {count:,} positions')
conn.close()
"
echo "[$(date)] All done!"
