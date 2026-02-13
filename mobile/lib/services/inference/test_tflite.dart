/// Quick test script for TFLite engine
/// Run this to verify TFLite works without crashes on Android
library;

import 'package:flutter/material.dart';
import 'inference_factory.dart';

Future<void> testTFLiteEngine() async {
  debugPrint('[TFLite Test] Starting...');

  try {
    final engine = createInferenceEngine();
    debugPrint('[TFLite Test] Created engine: ${engine.engineName}');
    debugPrint('[TFLite Test] Available: ${engine.isAvailable}');

    if (!engine.isAvailable) {
      debugPrint('[TFLite Test] Engine not available on this platform');
      return;
    }

    debugPrint('[TFLite Test] Starting engine...');
    final started = await engine.start();
    debugPrint('[TFLite Test] Started: $started');

    if (started) {
      debugPrint('[TFLite Test] Engine is running: ${engine.isRunning}');

      // Test analysis with empty board
      debugPrint('[TFLite Test] Running test analysis...');
      final result = await engine.analyze(
        boardSize: 19,
        moves: [],
        komi: 7.5,
        maxVisits: 100,
      );

      debugPrint('[TFLite Test] Analysis complete:');
      debugPrint('[TFLite Test]   Model: ${result.modelName}');
      debugPrint('[TFLite Test]   Visits: ${result.visits}');
      debugPrint('[TFLite Test]   Top moves: ${result.topMoves.length}');

      await engine.stop();
      debugPrint('[TFLite Test] ✓ All tests passed!');
    } else {
      debugPrint('[TFLite Test] ✗ Failed to start engine');
    }
  } catch (e, stack) {
    debugPrint('[TFLite Test] ✗ Error: $e');
    debugPrint('[TFLite Test] Stack: $stack');
  }
}
