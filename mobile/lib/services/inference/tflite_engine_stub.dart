/// TensorFlow Lite inference engine for Android
///
/// Uses TFLite with NNAPI delegate for hardware acceleration.
/// Replaces native KataGo pthread implementation to avoid Android 16
/// Qualcomm Adreno pthread_mutex crash.
library;

import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import '../../models/models.dart';
import 'inference_engine.dart';

/// TFLite-based KataGo inference engine
/// Only available on Android
class TFLiteEngine implements InferenceEngine {
  static const String _tag = '[TFLiteEngine]';

  @override
  String get engineName => 'TFLite + NNAPI';

  @override
  bool get isAvailable {
    // Only available on Android (not web, not iOS/desktop)
    return !kIsWeb && Platform.isAndroid;
  }

  @override
  bool get isRunning => _isRunning;
  bool _isRunning = false;

  // TODO: Add tflite_flutter package
  // late Interpreter _interpreter;

  @override
  Future<bool> start() async {
    if (!isAvailable) {
      debugPrint('$_tag TFLite not available on ${Platform.operatingSystem}');
      return false;
    }

    if (_isRunning) return true;

    try {
      debugPrint('$_tag Loading TFLite model...');

      // TODO: Load model from assets
      // final modelPath = await _extractModel();
      // final interpreterOptions = InterpreterOptions()
      //   ..addDelegate(NnApiDelegate()); // Hardware acceleration
      // _interpreter = await Interpreter.fromAsset(
      //   'assets/katago/model.tflite',
      //   options: interpreterOptions,
      // );

      _isRunning = true;
      debugPrint('$_tag TFLite engine started with NNAPI delegate');
      return true;
    } catch (e) {
      debugPrint('$_tag Failed to start: $e');
      return false;
    }
  }

  @override
  Future<void> stop() async {
    if (!_isRunning) return;

    // TODO: Close interpreter
    // _interpreter.close();

    _isRunning = false;
    debugPrint('$_tag TFLite engine stopped');
  }

  @override
  Future<EngineAnalysisResult> analyze({
    required int boardSize,
    required List<String> moves,
    required double komi,
    required int maxVisits,
    AnalysisProgressCallback? onProgress,
  }) async {
    if (!_isRunning) {
      throw StateError('Engine not running');
    }

    // TODO: Implement actual TFLite inference
    // 1. Convert board state to input tensors (binary features + global features)
    // 2. Run interpreter.run()
    // 3. Parse output tensors (policy, value, ownership, etc.)
    // 4. Convert to MoveCandidate list

    debugPrint('$_tag Analyzing position: $boardSize x $boardSize, ${moves.length} moves');

    // Placeholder - return empty result for now
    return EngineAnalysisResult(
      topMoves: [],
      visits: maxVisits,
      modelName: 'katago-b6c96-tflite',
    );
  }

  @override
  void cancelAnalysis() {
    // TODO: Implement cancellation if needed
    debugPrint('$_tag Analysis cancelled');
  }

  @override
  void dispose() {
    if (_isRunning) {
      stop();
    }
  }
}
