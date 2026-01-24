#!/bin/bash
#
# KataGo Setup Script for Go Strategy Analysis Tool
# 
# This script automatically downloads and configures KataGo for CPU-only environments.
# Designed for WSL (Ubuntu/Linux).
#
# Usage:
#   chmod +x setup_katago.sh
#   ./setup_katago.sh
#

set -e  # Exit on error

# ============================================================================
# Configuration
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Katago is in the project root, which is one level up from scripts/
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
KATAGO_DIR="${PROJECT_ROOT}/katago"
CONFIG_FILE="${PROJECT_ROOT}/config.yaml"

# KataGo release info (using Eigen backend for CPU-only, no GPU required)
# Eigen backend is pure C++ and works on any CPU without OpenCL/CUDA
KATAGO_VERSION="v1.15.3"
KATAGO_RELEASE_URL="https://github.com/lightvector/KataGo/releases/download/${KATAGO_VERSION}"
KATAGO_ARCHIVE="katago-${KATAGO_VERSION}-eigen-linux-x64.zip"
KATAGO_DOWNLOAD_URL="${KATAGO_RELEASE_URL}/${KATAGO_ARCHIVE}"

# Lightweight model for CPU (b18c384 is a good balance of speed and strength)
# For even faster analysis, you can switch to b10c128 or b15c192
MODEL_NAME="kata1-b18c384nbt-s9996604416-d4316597426.bin.gz"
MODEL_URL="https://media.katagotraining.org/uploaded/networks/models/kata1/${MODEL_NAME}"

# Alternative: Even lighter model (uncomment to use instead)
# MODEL_NAME="kata1-b10c128nbt-s1141046784-d204142634.bin.gz"
# MODEL_URL="https://media.katagotraining.org/uploaded/networks/models/kata1/${MODEL_NAME}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ============================================================================
# Helper Functions
# ============================================================================

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_command() {
    if ! command -v "$1" &> /dev/null; then
        log_error "$1 is required but not installed."
        exit 1
    fi
}

# Python-based unzip function (fallback if unzip not available)
python_unzip() {
    local zip_file="$1"
    local dest_dir="$2"
    python3 << EOF
import zipfile
import os
with zipfile.ZipFile('${zip_file}', 'r') as zip_ref:
    zip_ref.extractall('${dest_dir}')
print("Extracted successfully")
EOF
}

# ============================================================================
# Main Script
# ============================================================================

echo ""
echo "========================================"
echo "  KataGo Setup for Go Strategy App"
echo "========================================"
echo ""

# Check required tools
log_info "Checking required tools..."
check_command "curl"
check_command "python3"
log_success "All required tools are available."

# Create katago directory
log_info "Creating KataGo directory: ${KATAGO_DIR}"
mkdir -p "${KATAGO_DIR}"

# ============================================================================
# Step 1: Download KataGo Binary
# ============================================================================

KATAGO_ZIP="${KATAGO_DIR}/${KATAGO_ARCHIVE}"

if [[ -f "${KATAGO_DIR}/katago" ]]; then
    log_warning "KataGo binary already exists. Skipping download."
else
    log_info "Downloading KataGo ${KATAGO_VERSION} (Eigen backend for CPU)..."
    log_info "URL: ${KATAGO_DOWNLOAD_URL}"
    
    curl -L --progress-bar -o "${KATAGO_ZIP}" "${KATAGO_DOWNLOAD_URL}"
    
    if [[ ! -f "${KATAGO_ZIP}" ]]; then
        log_error "Failed to download KataGo."
        exit 1
    fi
    
    log_info "Extracting KataGo..."
    python_unzip "${KATAGO_ZIP}" "${KATAGO_DIR}"
    
    # Find and move the katago binary to the root of katago dir
    EXTRACTED_KATAGO=$(find "${KATAGO_DIR}" -name "katago" -type f | head -n 1)
    if [[ -n "${EXTRACTED_KATAGO}" && "${EXTRACTED_KATAGO}" != "${KATAGO_DIR}/katago" ]]; then
        mv "${EXTRACTED_KATAGO}" "${KATAGO_DIR}/katago"
    fi
    
    # Also copy default configs if they exist
    find "${KATAGO_DIR}" -name "*.cfg" -type f -exec cp {} "${KATAGO_DIR}/" \; 2>/dev/null || true
    
    # Make executable
    chmod +x "${KATAGO_DIR}/katago"
    
    # Clean up zip
    rm -f "${KATAGO_ZIP}"
    
    # Clean up extracted subdirectory if exists
    find "${KATAGO_DIR}" -mindepth 1 -maxdepth 1 -type d -exec rm -rf {} \; 2>/dev/null || true
    
    log_success "KataGo binary installed."
fi

# ============================================================================
# Step 2: Download Neural Network Model
# ============================================================================

MODEL_PATH="${KATAGO_DIR}/${MODEL_NAME}"

if [[ -f "${MODEL_PATH}" ]]; then
    log_warning "Model already exists: ${MODEL_NAME}. Skipping download."
else
    log_info "Downloading neural network model..."
    log_info "Model: ${MODEL_NAME}"
    log_info "This may take a few minutes..."
    
    curl -L --progress-bar -o "${MODEL_PATH}" "${MODEL_URL}"
    
    if [[ ! -f "${MODEL_PATH}" ]]; then
        log_error "Failed to download model."
        exit 1
    fi
    
    log_success "Model downloaded: ${MODEL_NAME}"
fi

# ============================================================================
# Step 3: Create Analysis Config
# ============================================================================

ANALYSIS_CFG="${KATAGO_DIR}/analysis.cfg"

if [[ -f "${ANALYSIS_CFG}" ]]; then
    log_warning "Analysis config already exists. Skipping creation."
else
    log_info "Creating analysis configuration..."
    
    cat > "${ANALYSIS_CFG}" << 'EOF'
# KataGo Analysis Configuration
# Optimized for CPU-only environments

# Anthropic Claude generated config for Go Strategy App

# ============================================================================
# Search Limits (CPU Optimized)
# ============================================================================

# Maximum visits per move analysis
# Lower values = faster but less accurate
# The application will override this with dynamic visits (150 for 19x19, 500 for smaller)
maxVisits = 500

# Number of threads for search
# For CPU: use number of physical cores minus 1
numSearchThreads = 4

# ============================================================================
# Neural Network
# ============================================================================

# Use CPU backend (Eigen)
# No GPU required
nnMaxBatchSize = 1
nnCacheSizePowerOfTwo = 20
nnMutexPoolSizePowerOfTwo = 14

# ============================================================================
# Search Parameters
# ============================================================================

# These are good defaults for analysis
chosenMoveTemperature = 0
chosenMoveTemperatureEarly = 0
chosenMoveSubtract = 0
chosenMovePrune = 1

# Root noise (disable for pure analysis)
rootNoiseEnabled = false

# ============================================================================
# Reporting
# ============================================================================

# Report all legal moves in analysis
reportAnalysisWinratesAs = SIDETOMOVE

# For GTP analysis, return more info
EOF

    log_success "Analysis config created: ${ANALYSIS_CFG}"
fi

# ============================================================================
# Step 4: Update config.yaml
# ============================================================================

log_info "Updating config.yaml..."

# Backup existing config if it exists
if [[ -f "${CONFIG_FILE}" ]]; then
    cp "${CONFIG_FILE}" "${CONFIG_FILE}.backup"
    log_info "Backed up existing config to config.yaml.backup"
fi

cat > "${CONFIG_FILE}" << EOF
# Go Strategy Analysis Tool - Configuration
# Auto-generated by setup_katago.sh

katago:
  # Path to KataGo executable (Linux binary)
  katago_path: "${KATAGO_DIR}/katago"
  
  # Path to neural network model
  # Using lightweight b18 model optimized for CPU
  model_path: "${MODEL_PATH}"
  
  # Path to KataGo config file
  config_path: "${ANALYSIS_CFG}"

analysis:
  # Default komi value
  default_komi: 7.5
  
  # Number of visits for 19x19 board (lower for CPU performance)
  # 150 visits typically takes 5-10 seconds on CPU
  visits_19x19: 150
  
  # Number of visits for 9x9 and 13x13 boards
  # Smaller boards can use more visits while staying fast
  visits_small: 500
  
  # Number of top candidate moves to return
  top_moves_count: 3

database:
  # Path to SQLite database file (relative to project root)
  path: "data/analysis.db"
EOF

log_success "config.yaml updated with local KataGo paths."

# ============================================================================
# Step 5: Verify Installation
# ============================================================================

echo ""
log_info "Verifying installation..."

# Check binary exists and is executable
if [[ -x "${KATAGO_DIR}/katago" ]]; then
    log_success "KataGo binary is executable."
else
    log_error "KataGo binary is not executable."
    exit 1
fi

# Check model exists
if [[ -f "${MODEL_PATH}" ]]; then
    MODEL_SIZE=$(du -h "${MODEL_PATH}" | cut -f1)
    log_success "Model file exists (${MODEL_SIZE})."
else
    log_error "Model file not found."
    exit 1
fi

# Check config exists
if [[ -f "${ANALYSIS_CFG}" ]]; then
    log_success "Analysis config exists."
else
    log_error "Analysis config not found."
    exit 1
fi

# Try running KataGo version command
log_info "Testing KataGo binary..."
KATAGO_VER=$("${KATAGO_DIR}/katago" version 2>&1 || echo "Failed")
if [[ "${KATAGO_VER}" == *"KataGo"* ]]; then
    log_success "KataGo responds correctly: ${KATAGO_VER}"
else
    log_warning "Could not verify KataGo version. It may still work."
    log_warning "Output: ${KATAGO_VER}"
fi

# ============================================================================
# Summary
# ============================================================================

echo ""
echo "========================================"
echo "  Installation Complete!"
echo "========================================"
echo ""
echo "Installed components:"
echo "  - KataGo binary:  ${KATAGO_DIR}/katago"
echo "  - Neural network: ${MODEL_PATH}"
echo "  - Config file:    ${ANALYSIS_CFG}"
echo ""
echo "config.yaml has been updated with the correct paths."
echo ""
echo "You can now run the analysis tool:"
echo ""
echo "  cd ${SCRIPT_DIR}"
echo "  python -m src.cli --size 19 --moves \"B Q16\" \"W D4\""
echo ""
echo "Or test KataGo directly:"
echo ""
echo "  ${KATAGO_DIR}/katago version"
echo "  ${KATAGO_DIR}/katago benchmark -model ${MODEL_PATH} -config ${ANALYSIS_CFG}"
echo ""
log_success "Setup complete!"
