/// Standalone ONNX Runtime test
/// Run this in main() to test ONNX engine without GameProvider
library;

import 'package:flutter/material.dart';
import 'services/inference/onnx_engine.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  debugPrint('[ONNX Test] Starting standalone test...');

  final engine = OnnxEngine();

  debugPrint('[ONNX Test] Engine created: ${engine.engineName}');
  debugPrint('[ONNX Test] Available: ${engine.isAvailable}');

  if (!engine.isAvailable) {
    debugPrint('[ONNX Test] ONNX not available on this platform');
    runApp(const MaterialApp(
      home: Scaffold(
        body: Center(child: Text('ONNX not available on this platform')),
      ),
    ));
    return;
  }

  debugPrint('[ONNX Test] Starting engine...');
  final started = await engine.start();
  debugPrint('[ONNX Test] Started: $started');

  if (started) {
    debugPrint('[ONNX Test] Engine running: ${engine.isRunning}');

    try {
      debugPrint('[ONNX Test] Running analysis...');
      final result = await engine.analyze(
        boardSize: 19,
        moves: [],
        komi: 7.5,
        maxVisits: 100,
      );

      debugPrint('[ONNX Test] ✓ Analysis completed!');
      debugPrint('[ONNX Test]   Model: ${result.modelName}');
      debugPrint('[ONNX Test]   Visits: ${result.visits}');
      debugPrint('[ONNX Test]   Moves: ${result.topMoves.length}');

      runApp(MaterialApp(
        home: Scaffold(
          body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.check_circle, size: 64, color: Colors.green),
                const SizedBox(height: 16),
                const Text('ONNX Runtime 測試成功！'),
                const SizedBox(height: 8),
                Text('模型: ${result.modelName}'),
                Text('Top moves: ${result.topMoves.length}'),
              ],
            ),
          ),
        ),
      ));
    } catch (e, stack) {
      debugPrint('[ONNX Test] ✗ Analysis failed: $e');
      debugPrint('[ONNX Test] Stack: $stack');

      runApp(MaterialApp(
        home: Scaffold(
          body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error, size: 64, color: Colors.red),
                const SizedBox(height: 16),
                const Text('ONNX Runtime 測試失敗'),
                const SizedBox(height: 8),
                Text('錯誤: $e'),
              ],
            ),
          ),
        ),
      ));
    }
  } else {
    debugPrint('[ONNX Test] ✗ Engine failed to start');
    runApp(const MaterialApp(
      home: Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error, size: 64, color: Colors.red),
              SizedBox(height: 16),
              Text('ONNX Engine 啟動失敗'),
            ],
          ),
        ),
      ),
    ));
  }
}
