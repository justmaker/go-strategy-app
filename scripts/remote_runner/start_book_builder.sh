#!/bin/bash
# Script to run book builders in sequence or parallel
# Parallel might be too much for 8GB GPU memory if batch sizes are high, 
# so we'll run them sequentially or with careful batch settings.

export PYTHONPATH=$PYTHONPATH:.

# Clean up previous logs
mkdir -p logs

echo "Starting Parallel Book Building (9, 13, 19)..."

export PYTHONPATH=$PYTHONPATH:.

python3 -m src.scripts.build_opening_book --board-size 9 --visits 500 --depth 10 > logs/build_9.log 2>&1 &
PID9=$!

python3 -m src.scripts.build_opening_book --board-size 13 --visits 500 --depth 10 > logs/build_13.log 2>&1 &
PID13=$!

python3 -m src.scripts.build_opening_book --board-size 19 --visits 500 --depth 10 > logs/build_19.log 2>&1 &
PID19=$!

echo "Processes started: 9x9($PID9), 13x13($PID13), 19x19($PID19)"
echo "Waiting for completion..."

wait $PID9 $PID13 $PID19

echo "All Book Building Done! Exporting..."
python3 -m src.scripts.export_opening_book --compress --output mobile/assets/opening_book.json
