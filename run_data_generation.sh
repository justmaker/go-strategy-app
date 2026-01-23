#!/bin/bash
# Convenient script to generate opening book data with optimal settings

# Ensure virtual environment is activated
if [[ -z "$VIRTUAL_ENV" ]]; then
    if [[ -d "venv" ]]; then
        source venv/bin/activate
    else
        echo "Error: Virtual environment not found or not activated."
        echo "Please run 'source venv/bin/activate' first."
        exit 1
    fi
fi

echo "==================================================="
echo "   Go Strategy App - Opening Book Generation"
echo "==================================================="
echo "Starting generation sequence..."
echo ""

# 1. 9x9 Board (Fast)
echo "[1/3] Generating 9x9 data (Visits: 100, Depth: 12)..."
python -m src.scripts.build_opening_book --board-size 9 --visits 100 --depth 12 --start-at now
if [ $? -ne 0 ]; then
    echo "Error generating 9x9 data. Aborting."
    exit 1
fi
echo "Done 9x9."
echo ""

# 2. 13x13 Board (Fast)
echo "[2/3] Generating 13x13 data (Visits: 100, Depth: 8)..."
python -m src.scripts.build_opening_book --board-size 13 --visits 100 --depth 8 --start-at now
if [ $? -ne 0 ]; then
    echo "Error generating 13x13 data. Aborting."
    exit 1
fi
echo "Done 13x13."
echo ""

# 3. 19x19 Board (Fast)
echo "[3/3] Generating 19x19 data (Visits: 100, Depth: 4)..."
python -m src.scripts.build_opening_book --board-size 19 --visits 100 --depth 4 --start-at now
if [ $? -ne 0 ]; then
    echo "Error generating 19x19 data. Aborting."
    exit 1
fi
echo "Done 19x19."
echo ""

echo "==================================================="
echo "   All generation tasks completed successfully!"
echo "==================================================="
