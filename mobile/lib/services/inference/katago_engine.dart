/// Native KataGo inference engine wrapper
///
/// For iOS, macOS, Windows, Linux platforms.
/// Wraps the existing KataGoService and KataGoDesktopService.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../../models/models.dart';
import '../katago_service.dart' show KataGoService, AnalysisProgress;
import '../katago_desktop_service.dart';
import 'inference_engine.dart';

/// Native KataGo engine (desktop platforms)
class KataGoEngine implements InferenceEngine {
  static const String _tag = '[KataGoEngine]';
  static const _methodChannel =
      MethodChannel('com.gostratefy.go_strategy_app/katago');

  final bool _isDesktop = !kIsWeb &&
      (Platform.isMacOS || Platform.isWindows || Platform.isLinux);

  late final dynamic _engine;
  bool _nativeRunning = false; // Track native engine state directly

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
  bool get isAvailable => !kIsWeb;

  @override
  bool get isRunning {
    if (_isDesktop) {
      return (_engine as KataGoDesktopService).isRunning;
    }
    // Android: use our own tracking since we bypass KataGoService.start()
    return _nativeRunning;
  }

  @override
  Future<bool> start({int boardSize = 19}) async {
    if (!isAvailable) {
      debugPrint('$_tag KataGo not available on this platform');
      return false;
    }

    try {
      // On Android, pass boardSize via MethodChannel so the native engine
      // initialises with the correct ONNX model (model_9x9.onnx, etc.)
      if (!_isDesktop && _engine is KataGoService) {
        final success = await _methodChannel
                .invokeMethod<bool>('startEngine', {'boardSize': boardSize}) ??
            false;
        _nativeRunning = success;
        if (success) {
          debugPrint('$_tag Native KataGo started for ${boardSize}x$boardSize');
        }
        return success;
      }

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
    _nativeRunning = false;
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

      // On Android, use direct MethodChannel call which returns the JSON result
      // The EventChannel approach has reliability issues, so we use the
      // synchronous MethodChannel result directly.
      if (!_isDesktop && _engine is KataGoService) {
        final response = await _methodChannel.invokeMethod<String>('analyze', {
          'boardSize': boardSize,
          'moves': moves,
          'komi': komi,
          'maxVisits': maxVisits,
        });

        if (response == null || response.isEmpty) {
          throw Exception('Empty response from native engine');
        }

        debugPrint('$_tag Got response: ${response.length} bytes');
        debugPrint('$_tag Raw response: ${response.substring(0, response.length.clamp(0, 300))}');
        return _parseNativeResponse(response, maxVisits);
      }

      // For desktop service
      throw UnimplementedError('Desktop KataGo engine analyze() not yet wrapped');
    } catch (e) {
      debugPrint('$_tag analyze() error: $e');
      rethrow;
    }
  }

  /// Parse the JSON response from the native KataGo engine
  EngineAnalysisResult _parseNativeResponse(String jsonStr, int maxVisits) {
    final data = jsonDecode(jsonStr);

    if (data is Map<String, dynamic> && data.containsKey('error')) {
      throw Exception(data['error']);
    }

    // The native engine returns KataGo GTP analysis format
    final moveInfos = data['moveInfos'] as List? ?? [];
    final rootInfo = data['rootInfo'] as Map<String, dynamic>? ?? {};

    final topMoves = moveInfos.take(10).map((info) {
      final moveInfo = info as Map<String, dynamic>;
      return MoveCandidate(
        move: moveInfo['move'] as String? ?? 'pass',
        winrate: ((moveInfo['winrate'] as num?)?.toDouble() ?? 0.5).clamp(0.0, 1.0),
        scoreLead: (moveInfo['scoreLead'] as num?)?.toDouble() ?? 0.0,
        visits: moveInfo['visits'] as int? ?? 0,
      );
    }).toList();

    final visits = rootInfo['visits'] as int? ?? maxVisits;
    debugPrint('$_tag Parsed ${topMoves.length} moves, $visits visits');
    for (final m in topMoves.take(3)) {
      debugPrint('$_tag  ${m.move}: wr=${m.winrate}, lead=${m.scoreLead}, v=${m.visits}');
    }

    return EngineAnalysisResult(
      topMoves: topMoves,
      visits: visits,
      modelName: 'kata1-b6c96',
    );
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
