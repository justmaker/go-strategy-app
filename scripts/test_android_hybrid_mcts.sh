#!/bin/bash
# Automated test script for Android Hybrid MCTS+ONNX implementation

set -e

echo "=== Android Hybrid MCTS+ONNX Test Script ==="
echo ""

# Clear old logs
adb logcat -c
echo "✓ Cleared logcat"

# Launch app
adb shell am start -n com.gostratefy.go_strategy_app/.MainActivity
echo "✓ Launched app"
echo "  Waiting 20 seconds for initialization..."
sleep 20

# Automated tap sequence (10 moves to trigger opening book miss → MCTS analysis)
echo ""
echo "=== Automated gameplay (10 moves) ==="
for i in {1..10}; do
    x=$((380 + (i % 4) * 90))
    y=$((790 + (i / 4) * 85))
    echo "  Move $i: tap ($x, $y)"
    adb shell "input tap $x $y"
    sleep 4  # Wait for MCTS analysis (single-threaded may take 2-3 seconds)
done

echo ""
echo "  Waiting 10 seconds for final analysis..."
sleep 10

# Collect logs
echo ""
echo "=== Collecting logs ==="
LOG_FILE="/tmp/android_hybrid_test_$(date +%Y%m%d_%H%M%S).log"
adb logcat -d > "$LOG_FILE"
echo "✓ Saved to: $LOG_FILE"

# Analysis
echo ""
echo "=== Test Results ==="
echo ""

echo "1. Crash Check"
CRASHES=$(grep -c "FORTIFY\|SIGABRT\|Fatal signal" "$LOG_FILE" || true)
if [ "$CRASHES" -eq 0 ]; then
    echo "  ✅ No crashes detected"
else
    echo "  ❌ Found $CRASHES crash(es)"
    grep "FORTIFY\|SIGABRT\|Fatal signal" "$LOG_FILE" | head -5
fi

echo ""
echo "2. ONNX Backend Initialization"
if grep -q "ONNX backend" "$LOG_FILE"; then
    echo "  ✅ ONNX backend initialized"
    grep "ONNX backend\|ONNX Runtime\|ONNX session" "$LOG_FILE" | head -5
else
    echo "  ⚠️ ONNX backend not found in logs"
fi

echo ""
echo "3. Single-threaded Mode"
if grep -q "Single-threaded mode enabled\|single-threaded" "$LOG_FILE"; then
    echo "  ✅ Single-threaded mode active"
    grep -i "single-threaded" "$LOG_FILE" | head -3
else
    echo "  ⚠️ Single-threaded mode not confirmed"
fi

echo ""
echo "4. Search Execution"
SEARCHES=$(grep -c "analyzePositionNative\|Starting search" "$LOG_FILE" || true)
echo "  Found $SEARCHES search call(s)"
if [ "$SEARCHES" -gt 0 ]; then
    echo "  Sample:"
    grep "analyzePositionNative\|Starting search\|Search completed" "$LOG_FILE" | tail -10
fi

echo ""
echo "5. ONNX Inference"
INFERENCES=$(grep -c "ONNX inference completed" "$LOG_FILE" || true)
echo "  ONNX inference calls: $INFERENCES"
if [ "$INFERENCES" -gt 0 ]; then
    echo "  ✅ ONNX inference working"
else
    echo "  ⚠️ No ONNX inference detected"
fi

echo ""
echo "6. Move Quality Check"
if grep -q "moveInfos\|move.*winrate" "$LOG_FILE"; then
    echo "  ✅ Analysis results generated"
    grep "moveInfos\|Analysis result" "$LOG_FILE" | tail -5
else
    echo "  ⚠️ No analysis results found"
fi

echo ""
echo "=== Full log available at: $LOG_FILE ==="
echo ""

# Summary
echo "=== Summary ==="
if [ "$CRASHES" -eq 0 ] && [ "$INFERENCES" -gt 0 ]; then
    echo "✅ TEST PASSED: No crashes, ONNX inference working"
    exit 0
else
    echo "⚠️ TEST INCOMPLETE: Check log for details"
    exit 1
fi
