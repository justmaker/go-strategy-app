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

# Ensure we are in the project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_ROOT"

echo "==================================================="
echo "   Go Strategy App - Opening Book Generation"
echo "==================================================="
echo "Starting generation sequence..."
echo ""

# 1. 19x19 Board (Primary Target)
echo "[1/3] Generating 19x19 data (Visits: 100, Depth: 30)..."
python -m src.scripts.build_opening_book --board-size 19 --visits 100 --depth 30 --start-at now
if [ $? -ne 0 ]; then
    echo "Error generating 19x19 data. Aborting."
    exit 1
fi
echo "Done 19x19."
echo ""

# 2. 13x13 Board
echo "[2/3] Generating 13x13 data (Visits: 100, Depth: 20)..."
python -m src.scripts.build_opening_book --board-size 13 --visits 100 --depth 20 --start-at now
if [ $? -ne 0 ]; then
    echo "Error generating 13x13 data. Aborting."
    exit 1
fi
echo "Done 13x13."
echo ""

# 3. 9x9 Board
echo "[3/3] Generating 9x9 data (Visits: 100, Depth: 15)..."
python -m src.scripts.build_opening_book --board-size 9 --visits 100 --depth 15 --start-at now
if [ $? -ne 0 ]; then
    echo "Error generating 9x9 data. Aborting."
    exit 1
fi
echo "Done 9x9."
echo ""

echo "==================================================="
echo "   All generation tasks completed successfully!"
echo "==================================================="
