/// Simplified ONNX Runtime engine - stub for now
/// Full implementation pending ONNX Runtime API研究
library;

import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import '../../models/models.dart';
import '../katago_service.dart' show AnalysisProgress;
import 'inference_engine.dart';

/// ONNX Runtime engine (Android only) - Stub implementation
class OnnxEngine implements InferenceEngine {
  static const String _tag = '[OnnxEngine]';

  bool _isRunning = false;

  @override
  String get engineName => 'ONNX Runtime (stub)';

  @override
  bool get isAvailable => !kIsWeb && Platform.isAndroid;

  @override
  bool get isRunning => _isRunning;

  @override
  Future<bool> start() async {
    if (!isAvailable) return false;

    debugPrint('$_tag Starting (stub - ONNX Runtime integration pending)');
    _isRunning = true;
    return true;
  }

  @override
  Future<void> stop() async {
    _isRunning = false;
  }

  @override
  Future<EngineAnalysisResult> analyze({
    required int boardSize,
    required List<String> moves,
    required double komi,
    required int maxVisits,
    AnalysisProgressCallback? onProgress,
  }) async {
    debugPrint('$_tag Analyze called (stub - returning empty)');

    // Return empty result - ONNX implementation pending
    return EngineAnalysisResult(
      topMoves: [],
      visits: maxVisits,
      modelName: 'onnx-stub',
    );
  }

  @override
  void cancelAnalysis() {}

  @override
  void dispose() {
    stop();
  }
}
