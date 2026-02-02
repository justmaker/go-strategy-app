#!/bin/bash
set -e

# Configuration
KATAGO_RELEASE="https://github.com/lightvector/KataGo/releases/download/v1.15.3/katago-v1.15.3-linux-x64.zip"
MODEL_URL="https://media.katagotraining.org/uploaded/networks/models/kata1/kata1-b18c384nbt-s9131461376-d4050212089.bin.gz" # Strong 18b model
WORK_DIR="katago_env"

echo "Setting up environment in $WORK_DIR..."
mkdir -p $WORK_DIR
cd $WORK_DIR

# 1. Download KataGo
if [ ! -f "katago" ]; then
    echo "Downloading KataGo..."
    wget -q $KATAGO_RELEASE -O katago.zip
    unzip -q -o katago.zip
    chmod +x katago
    rm katago.zip
fi

# 2. Download Model
if [ ! -f "model.bin.gz" ]; then
    echo "Downloading Model..."
    wget -q $MODEL_URL -O model.bin.gz
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
