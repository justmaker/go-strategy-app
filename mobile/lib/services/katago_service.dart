/// KataGo local engine service for on-device analysis.
///
/// Uses Platform Channels to communicate with the native KataGo engine.
library;

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../models/models.dart';

/// Status of the KataGo engine
enum KataGoStatus { stopped, starting, running, error }

/// Progress information during analysis
class AnalysisProgress {
  final int currentVisits;
  final int maxVisits;
  final double winrate;
  final double scoreLead;
  final String? bestMove;
  final bool isComplete;

  AnalysisProgress({
    required this.currentVisits,
    required this.maxVisits,
    required this.winrate,
    required this.scoreLead,
    this.bestMove,
    this.isComplete = false,
  });

  double get progress => maxVisits > 0 ? currentVisits / maxVisits : 0;
}

/// Service for managing the local KataGo engine
class KataGoService {
  static const _methodChannel =
      MethodChannel('com.gostratefy.go_strategy_app/katago');
  static const _eventChannel =
      EventChannel('com.gostratefy.go_strategy_app/katago_events');

  KataGoStatus _status = KataGoStatus.stopped;
  String? _currentQueryId;
  StreamSubscription? _eventSubscription;

  // Callbacks
  void Function(AnalysisProgress)? _progressCallback;
  void Function(AnalysisResult)? _resultCallback;
  void Function(String)? _errorCallback;

  KataGoStatus get status => _status;
  bool get isRunning => _status == KataGoStatus.running;
  bool get isAnalyzing => _currentQueryId != null;

  /// Start the KataGo engine
  Future<bool> start() async {
    if (_status == KataGoStatus.running) return true;

    _status = KataGoStatus.starting;

    try {
      // Set up event listener
      _setupEventListener();

      // Start the engine
      final success =
          await _methodChannel.invokeMethod<bool>('startEngine') ?? false;

      if (success) {
        _status = KataGoStatus.running;
        debugPrint('KataGo engine started successfully');
      } else {
        _status = KataGoStatus.error;
        debugPrint('KataGo engine failed to start');
      }

      return success;
    } catch (e) {
      _status = KataGoStatus.error;
      debugPrint('Error starting KataGo: $e');
      _errorCallback?.call('Failed to start engine: $e');
      return false;
    }
  }

  /// Stop the KataGo engine
  Future<void> stop() async {
    if (_status == KataGoStatus.stopped) return;

    try {
      await _methodChannel.invokeMethod('stopEngine');
    } catch (e) {
      debugPrint('Error stopping KataGo: $e');
    } finally {
      _status = KataGoStatus.stopped;
      _currentQueryId = null;
      _eventSubscription?.cancel();
      _eventSubscription = null;
    }
  }

  /// Analyze a position
  ///
  /// Returns the query ID for tracking/cancellation.
  Future<String?> analyze({
    required int boardSize,
    required List<String> moves,
    required double komi,
    int maxVisits = 100,
    void Function(AnalysisProgress)? onProgress,
    void Function(AnalysisResult)? onResult,
    void Function(String)? onError,
  }) async {
    if (!isRunning) {
      onError?.call('Engine not running');
      return null;
    }

    if (_currentQueryId != null) {
      // Cancel previous analysis
      await cancelAnalysis();
    }

    _progressCallback = onProgress;
    _resultCallback = onResult;
    _errorCallback = onError;

    try {
      final queryId = await _methodChannel.invokeMethod<String>('analyze', {
        'boardSize': boardSize,
        'moves': moves,
        'komi': komi,
        'maxVisits': maxVisits,
      });

      _currentQueryId = queryId;
      return queryId;
    } catch (e) {
      debugPrint('Error starting analysis: $e');
      onError?.call('Analysis failed: $e');
      return null;
    }
  }

  /// Cancel ongoing analysis
  Future<void> cancelAnalysis() async {
    if (_currentQueryId == null) return;

    try {
      await _methodChannel.invokeMethod('cancelAnalysis', {
        'queryId': _currentQueryId,
      });
    } catch (e) {
      debugPrint('Error cancelling analysis: $e');
    } finally {
      _currentQueryId = null;
    }
  }

  /// Check if engine is running
  Future<bool> checkEngineStatus() async {
    try {
      final running =
          await _methodChannel.invokeMethod<bool>('isEngineRunning') ?? false;
      _status = running ? KataGoStatus.running : KataGoStatus.stopped;
      return running;
    } catch (e) {
      debugPrint('Error checking engine status: $e');
      return false;
    }
  }

  /// Set up event listener for streaming results
  void _setupEventListener() {
    _eventSubscription?.cancel();

    _eventSubscription = _eventChannel.receiveBroadcastStream().listen(
      (event) {
        if (event is Map) {
          final type = event['type'] as String?;

          switch (type) {
            case 'analysis':
              _handleAnalysisEvent(event['data'] as String?);
              break;
            case 'error':
              _errorCallback?.call(event['message'] as String? ?? 'Unknown error');
              break;
          }
        }
      },
      onError: (error) {
        debugPrint('Event stream error: $error');
        _errorCallback?.call('Stream error: $error');
      },
    );
  }

  /// Handle analysis event from KataGo
  void _handleAnalysisEvent(String? jsonData) {
    if (jsonData == null) return;

    try {
      final data = jsonDecode(jsonData) as Map<String, dynamic>;

      // Check for errors
      if (data.containsKey('error')) {
        _errorCallback?.call(data['error'] as String);
        _currentQueryId = null;
        return;
      }

      // Check if this is a progress update or final result
      final isDuringSearch = data['isDuringSearch'] as bool? ?? false;
      final rootInfo = data['rootInfo'] as Map<String, dynamic>?;
      final moveInfos = data['moveInfos'] as List?;

      if (rootInfo != null) {
        final visits = rootInfo['visits'] as int? ?? 0;
        final winrate = rootInfo['winrate'] as double? ?? 0.5;
        final scoreLead = rootInfo['scoreLead'] as double? ?? 0.0;

        String? bestMove;
        if (moveInfos != null && moveInfos.isNotEmpty) {
          bestMove = (moveInfos[0] as Map<String, dynamic>)['move'] as String?;
        }

        // Send progress update
        final progress = AnalysisProgress(
          currentVisits: visits,
          maxVisits: 100, // Will be updated from config
          winrate: winrate,
          scoreLead: scoreLead,
          bestMove: bestMove,
          isComplete: !isDuringSearch,
        );
        _progressCallback?.call(progress);
        // If complete, convert to AnalysisResult
        if (!isDuringSearch && moveInfos != null) {
          final result = _convertToAnalysisResult(data);
          _resultCallback?.call(result);
          _currentQueryId = null;
        }
      }
    } catch (e) {
      debugPrint('Error parsing analysis event: $e');
    }
  }

  /// Convert KataGo JSON response to AnalysisResult
  AnalysisResult _convertToAnalysisResult(Map<String, dynamic> data) {
    final moveInfos = data['moveInfos'] as List? ?? [];
    final rootInfo = data['rootInfo'] as Map<String, dynamic>? ?? {};

    final topMoves = moveInfos.take(10).map((info) {
      final moveInfo = info as Map<String, dynamic>;
      return MoveCandidate(
        move: moveInfo['move'] as String? ?? 'pass',
        winrate: (moveInfo['winrate'] as num?)?.toDouble() ?? 0.5,
        scoreLead: (moveInfo['scoreLead'] as num?)?.toDouble() ?? 0.0,
        visits: moveInfo['visits'] as int? ?? 0,
      );
    }).toList();

    return AnalysisResult(
      boardHash: data['id'] as String? ?? '',
      boardSize: 19, // Will be set by caller
      komi: 7.5, // Will be set by caller
      movesSequence: '',
      topMoves: topMoves,
      engineVisits: rootInfo['visits'] as int? ?? 0,
      modelName: 'katago_local',
      fromCache: false,
    );
  }

  /// Dispose resources
  void dispose() {
    stop();
    _eventSubscription?.cancel();
  }
}
