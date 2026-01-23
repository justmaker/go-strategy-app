# KataGo Model Files

This directory should contain the KataGo neural network model file.

## Downloading Models

Due to file size and GitHub download limitations, you need to manually download the model.

### Recommended: b6c96 Model (~15MB, smaller, faster)
Download from: https://katagotraining.org/networks/kata1/

1. Go to the above URL
2. Download `kata1-b6c96-s175395328-d26788732.bin.gz` (or similar b6 model)
3. Rename to `model.bin.gz` and place in this directory

### Alternative: b18c384 Model (~60MB, stronger)
Download from: https://github.com/lightvector/KataGo/releases

1. Find the latest release
2. Download a `b18c384*.bin.gz` file
3. Rename to `model.bin.gz` and place in this directory

## File Structure

After downloading, this directory should contain:
```
katago/
├── README.md
└── model.bin.gz  <-- Downloaded model file
```

## Model Comparison

| Model | Size | Strength | Speed on Mobile |
|-------|------|----------|-----------------|
| b6c96 | ~15MB | ~5d amateur | Fast (5-15s) |
| b10c128 | ~30MB | ~7d amateur | Medium (15-30s) |
| b18c384 | ~60MB | ~9d+ | Slow (30-60s) |

For mobile devices, b6c96 is recommended for a balance of strength and speed.
