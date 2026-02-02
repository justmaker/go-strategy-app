#!/bin/bash
set -e

# Configuration
KATAGO_RELEASE="https://github.com/lightvector/KataGo/releases/download/v1.15.3/katago-v1.15.3-linux-x64.zip"
MODEL_URL="https://media.katagotraining.org/uploaded/networks/models/kata1/kata1-b18c384nbt-s9131461376-d4050212089.bin.gz" # Strong 18b model
WORK_DIR="katago_env"

echo "Setting up environment in $WORK_DIR..."
mkdir -p $WORK_DIR
cd $WORK_DIR

# 1. Setup KataGo
if [ ! -f "katago" ]; then
    if [ ! -f "katago.zip" ]; then
        echo "Downloading KataGo..."
        wget -q --show-progress $KATAGO_RELEASE -O katago.zip
    else
        echo "Found existing katago.zip, skipping download."
    fi
    echo "Unzipping KataGo..."
    unzip -q -o katago.zip
    chmod +x katago
fi

# 2. Download Model
if [ ! -f "model.bin.gz" ]; then
    echo "Downloading Model..."
    wget -q --show-progress $MODEL_URL -O model.bin.gz
fi

# Check KataGo dependencies
echo "Checking KataGo dependencies..."
if ldd ./katago | grep -q "not found"; then
    echo "ERROR: Missing dependencies for KataGo:"
    ldd ./katago | grep "not found"
    echo "Attempting to continue, but might fail..."
fi

# 3. Create Config
if [ ! -f "analysis.cfg" ]; then
    echo "Creating Config..."
    # Generate a default analysis config
    ./katago genconfig -model model.bin.gz -output analysis.cfg --noprompt
    # Or write a specific one
    cat > analysis_custom.cfg <<EOF
logDir = gtp_logs
logAllGTPCommunication = true
logSearchInfo = true
rules = chinese
allowResignation = true
resignThreshold = -0.90
resignConsecTurns = 3
EOF
fi

# 4. Run Analysis
echo "Running constrained self-play..."
python3 ../constrained_selfplay.py --katago ./katago --config analysis_custom.cfg --model model.bin.gz --output ./results

echo "Done! Results are in $WORK_DIR/results"
ls -l ./results
