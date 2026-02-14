/// Abstract interface for Go AI inference engines
///
/// Platform-specific implementations:
/// - Android: TFLite + NNAPI (tflite_engine.dart)
/// - iOS/macOS/Desktop: Native KataGo (katago_engine.dart)
library;

import '../../models/models.dart';
import '../katago_service.dart' show AnalysisProgress;

/// Analysis progress callback
typedef AnalysisProgressCallback = void Function(AnalysisProgress progress);

/// Analysis result from AI engine
class EngineAnalysisResult {
  final List<MoveCandidate> topMoves;
  final int visits;
  final String modelName;

  EngineAnalysisResult({
    required this.topMoves,
    required this.visits,
    required this.modelName,
  });
}

/// Abstract AI inference engine interface
abstract class InferenceEngine {
  /// Engine name (e.g., "KataGo Native", "TFLite + NNAPI")
  String get engineName;

  /// Check if engine is available on current platform
  bool get isAvailable;

  /// Check if engine is currently running
  bool get isRunning;

  /// Start the inference engine for the given board size
  Future<bool> start({int boardSize = 19});

  /// Stop the inference engine
  Future<void> stop();

  /// Analyze a board position
  Future<EngineAnalysisResult> analyze({
    required int boardSize,
    required List<String> moves,
    required double komi,
    required int maxVisits,
    AnalysisProgressCallback? onProgress,
  });

  /// Cancel ongoing analysis
  void cancelAnalysis();

  /// Dispose resources
  void dispose();
}
