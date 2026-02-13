# KataGo Model Conversion to TensorFlow Lite

This document explains how to convert KataGo `.bin.gz` models to TensorFlow Lite `.tflite` format for Android deployment.

## Why TFLite?

TFLite avoids the `pthread_mutex_lock destroyed` crash on Android 16 + Qualcomm Snapdragon 8 Gen 3 devices that affects native KataGo pthread implementations.

## Current Status

- ✅ **ONNX Model Available**: `/tmp/katago_b6c96.onnx` (4.3MB)
- ⚠️ **TFLite Conversion**: Blocked by dynamic shape issues
- ✅ **Placeholder Model**: `model.tflite` (2.8MB) - random weights for testing only

## Conversion Steps

### 1. KataGo .bin.gz → ONNX (✅ Working)

```bash
# Download model
curl -L "https://katagoarchive.org/g170/neuralnets/g170-b6c96-s175395328-d26788732.zip" -o katago_model.zip
unzip katago_model.zip
gunzip g170-b6c96-s175395328-d26788732/model.txt.gz

# Clone converter
git clone https://github.com/isty2e/KataGoONNX.git
cd KataGoONNX

# Setup Python environment
python3 -m venv venv
source venv/bin/activate
pip install torch onnx onnxmltools packaging

# Add missing config field
python3 -c "
import json
config = json.load(open('../g170-b6c96-s175395328-d26788732/model.config.json'))
config['use_scoremean_as_lead'] = False
json.dump(config, open('../g170-b6c96-s175395328-d26788732/model.config.json', 'w'), indent=2)
"

# Convert to ONNX
python convert.py \
  --model ../g170-b6c96-s175395328-d26788732/model.txt \
  --model-config ../g170-b6c96-s175395328-d26788732/model.config.json \
  --output ../katago_b6c96.onnx

# Result: katago_b6c96.onnx (4.3MB)
```

### 2. ONNX → TFLite (❌ Issues)

**Problem**: onnx2tf cannot handle dynamic shapes in KataGo model.

**Error**: `Matrix size-incompatible` at MatMul operations due to dynamic tensor ranks.

**Attempted Solutions**:
```bash
# Fix ONNX shapes to 19x19 board
python3 -c "
import onnx
model = onnx.load('katago_b6c96.onnx')
for input_tensor in model.graph.input:
    if input_tensor.name == 'input_binary':
        input_tensor.type.tensor_type.shape.dim[0].dim_value = 1
        input_tensor.type.tensor_type.shape.dim[2].dim_value = 19
        input_tensor.type.tensor_type.shape.dim[3].dim_value = 19
    elif input_tensor.name == 'input_global':
        input_tensor.type.tensor_type.shape.dim[0].dim_value = 1
onnx.save(model, 'katago_b6c96_fixed.onnx')
"

# Try conversion with fixed shapes
onnx2tf -i katago_b6c96_fixed.onnx -o katago_tflite -osd
# Still fails at Squeeze → MatMul operations
```

## Alternative Approaches

### Option A: Use ONNX Runtime Mobile (Recommended)

Instead of TFLite, use ONNX Runtime which natively supports the ONNX model:

```yaml
# pubspec.yaml
dependencies:
  onnxruntime: ^1.17.0  # Native ONNX inference
```

Advantages:
- No conversion needed (use ONNX directly)
- Better shape handling
- Similar performance to TFLite with NNAPI

### Option B: Manual ONNX Graph Surgery

Fix the MatMul operations using onnx-graphsurgeon before onnx2tf:

```python
import onnx
import onnx_graphsurgeon as gs

graph = gs.import_onnx(onnx.load('katago_b6c96.onnx'))
# Manually fix problematic MatMul nodes
# ... (requires deep ONNX knowledge)
onnx.save(gs.export_onnx(graph), 'katago_fixed.onnx')
```

### Option C: Train TFLite-Native Model

Retrain KataGo directly targeting TFLite from the start (not practical).

## Temporary Solution

The current `model.tflite` is a **placeholder with random weights** created for architecture testing:

```python
# Creates 2.8MB model with correct shapes but random weights
import tensorflow as tf

class PlaceholderModel(tf.keras.Model):
    # ... see creation script in commit 4234719
```

## TODO

1. Resolve ONNX → TFLite conversion (use ONNX Runtime or fix MatMul shapes)
2. Replace placeholder `model.tflite` with real converted model
3. Verify accuracy matches native KataGo (±2% winrate tolerance)

## References

- [KataGoONNX](https://github.com/isty2e/KataGoONNX)
- [onnx2tf](https://github.com/PINTO0309/onnx2tf)
- [Kaya ONNX Models](https://huggingface.co/kaya-go/kaya)
- [TFLite Converter](https://www.tensorflow.org/lite/convert)
