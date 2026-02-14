/// Native KataGo inference engine wrapper
///
/// For iOS, macOS, Windows, Linux platforms.
/// Wraps the existing KataGoService and KataGoDesktopService.
library;

import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import '../../models/models.dart';
import '../katago_service.dart' show KataGoService, AnalysisProgress;
import '../katago_desktop_service.dart';
import 'inference_engine.dart';

/// Native KataGo engine (desktop platforms)
class KataGoEngine implements InferenceEngine {
  static const String _tag = '[KataGoEngine]';

  final bool _isDesktop = !kIsWeb &&
      (Platform.isMacOS || Platform.isWindows || Platform.isLinux);

  late final dynamic _engine;

  KataGoEngine() {
    if (_isDesktop) {
      _engine = KataGoDesktopService();
    } else {
      _engine = KataGoService();
    }
  }

  @override
  String get engineName => _isDesktop ? 'KataGo Desktop' : 'KataGo Mobile';

  @override
  bool get isAvailable => !kIsWeb;  // Available on all platforms (Android now uses ONNX C++ backend)

  @override
  bool get isRunning {
    if (_isDesktop) {
      return (_engine as KataGoDesktopService).isRunning;
    } else {
      return (_engine as KataGoService).isRunning;
    }
  }

  @override
  Future<bool> start() async {
    if (!isAvailable) {
      debugPrint('$_tag KataGo not available on this platform');
      return false;
    }

    try {
      final success = await _engine.start();
      if (success) {
        debugPrint('$_tag Native KataGo started');
      }
      return success;
    } catch (e) {
      debugPrint('$_tag Failed to start: $e');
      return false;
    }
  }

  @override
  Future<void> stop() async {
    await _engine.stop();
  }

  @override
  Future<EngineAnalysisResult> analyze({
    required int boardSize,
    required List<String> moves,
    required double komi,
    required int maxVisits,
    AnalysisProgressCallback? onProgress,
  }) async {
    try {
      debugPrint('$_tag analyze() called: ${moves.length} moves, $maxVisits visits');

      // For KataGoService (Android/iOS), use the existing analyze method
      if (_engine is KataGoService) {
        final completer = Completer<EngineAnalysisResult>();

        await (_engine as KataGoService).analyze(
          boardSize: boardSize,
          moves: moves,
          komi: komi,
          maxVisits: maxVisits,
          onProgress: onProgress,  // Pass through directly
          onResult: (result) {
            // AnalysisResult already has topMoves (List<MoveCandidate>)
            completer.complete(EngineAnalysisResult(
              topMoves: result.topMoves,
              visits: maxVisits,
              modelName: 'kata1-b6c96',
            ));
          },
          onError: (error) {
            completer.completeError(error);
          },
        );

        return await completer.future;
      }

      // For desktop service
      throw UnimplementedError('Desktop KataGo engine analyze() not yet wrapped');
    } catch (e) {
      debugPrint('$_tag analyze() error: $e');
      rethrow;
    }
  }

  @override
  void cancelAnalysis() {
    // TODO: Wrap cancelAnalysis
  }

  @override
  void dispose() {
    stop();
  }
}
