/// KataGo local engine service for Desktop platforms (macOS, Windows, Linux).
///
/// Uses dart:io Process to spawn and communicate with KataGo via Analysis API.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../models/models.dart';

/// Status of the KataGo engine
enum KataGoDesktopStatus { stopped, starting, running, error }

/// Progress information during analysis
class DesktopAnalysisProgress {
  final int currentVisits;
  final int maxVisits;
  final double winrate;
  final double scoreLead;
  final String? bestMove;
  final bool isComplete;

  DesktopAnalysisProgress({
    required this.currentVisits,
    required this.maxVisits,
    required this.winrate,
    required this.scoreLead,
    this.bestMove,
    this.isComplete = false,
  });

  double get progress => maxVisits > 0 ? currentVisits / maxVisits : 0;
}

/// Service for managing the local KataGo engine on Desktop platforms
class KataGoDesktopService {
  Process? _process;
  KataGoDesktopStatus _status = KataGoDesktopStatus.stopped;
  int _queryCounter = 0;
  String? _currentQueryId;

  StreamSubscription? _stdoutSubscription;
  StreamSubscription? _stderrSubscription;

  void Function(DesktopAnalysisProgress)? _progressCallback;
  void Function(AnalysisResult)? _resultCallback;
  void Function(String)? _errorCallback;

  int _currentBoardSize = 19;
  double _currentKomi = 7.5;
  int _currentMaxVisits = 100;
  String _currentMovesSequence = '';

  KataGoDesktopStatus get status => _status;
  bool get isRunning => _status == KataGoDesktopStatus.running;
  bool get isAnalyzing => _currentQueryId != null;

  /// Check if KataGo is available on this system
  static Future<String?> findKataGoPath() async {
    final possiblePaths = [
      '/opt/homebrew/bin/katago',
      '/usr/local/bin/katago',
      '/usr/bin/katago',
      'C:\\Program Files\\KataGo\\katago.exe',
    ];

    for (final path in possiblePaths) {
      if (await File(path).exists()) return path;
    }

    try {
      final result = await Process.run(Platform.isWindows ? 'where' : 'which', [
        'katago',
      ]);
      if (result.exitCode == 0) {
        final path = (result.stdout as String).trim().split('\n').first;
        if (path.isNotEmpty) return path;
      }
    } catch (e) {
      debugPrint('Error finding katago: $e');
    }
    return null;
  }

  /// Start the KataGo engine
  Future<bool> start({String? katagoPath, String? modelPath}) async {
    if (_status == KataGoDesktopStatus.running) return true;
    _status = KataGoDesktopStatus.starting;

    try {
      katagoPath ??= await findKataGoPath();
      if (katagoPath == null) {
        _status = KataGoDesktopStatus.error;
        return false;
      }

      final args = ['analysis'];
      if (modelPath != null) args.addAll(['-model', modelPath]);

      _process = await Process.start(katagoPath, args);

      _stdoutSubscription = _process!.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(_handleStdoutLine);

      _stderrSubscription = _process!.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(_handleStderrLine);

      await Future.delayed(const Duration(seconds: 2));

      if (_process != null) {
        _status = KataGoDesktopStatus.running;
        return true;
      }
      _status = KataGoDesktopStatus.error;
      return false;
    } catch (e) {
      _status = KataGoDesktopStatus.error;
      debugPrint('Error starting KataGo: $e');
      return false;
    }
  }

  Future<void> stop() async {
    if (_status == KataGoDesktopStatus.stopped) return;
    try {
      _sendCommand({'command': 'terminate'});
      await Future.delayed(const Duration(milliseconds: 500));
      _process?.kill();
    } finally {
      _process = null;
      _status = KataGoDesktopStatus.stopped;
      _currentQueryId = null;
      _stdoutSubscription?.cancel();
      _stderrSubscription?.cancel();
    }
  }

  Future<String?> analyze({
    required int boardSize,
    required List<String> moves,
    required double komi,
    int maxVisits = 100,
    void Function(DesktopAnalysisProgress)? onProgress,
    void Function(AnalysisResult)? onResult,
    void Function(String)? onError,
  }) async {
    if (!isRunning) {
      onError?.call('Engine not running');
      return null;
    }

    if (_currentQueryId != null) await cancelAnalysis();

    _progressCallback = onProgress;
    _resultCallback = onResult;
    _errorCallback = onError;
    _currentBoardSize = boardSize;
    _currentKomi = komi;
    _currentMaxVisits = maxVisits;
    _currentMovesSequence = moves.join(',');

    _queryCounter++;
    final queryId = 'q$_queryCounter';
    _currentQueryId = queryId;

    final formattedMoves = _formatMovesForKataGo(moves);
    final query = {
      'id': queryId,
      'moves': formattedMoves,
      'rules': 'chinese',
      'komi': komi,
      'boardXSize': boardSize,
      'boardYSize': boardSize,
      'maxVisits': maxVisits,
      'reportDuringSearchEvery': 0.5,
    };

    _sendCommand(query);
    return queryId;
  }

  Future<void> cancelAnalysis() async {
    if (_currentQueryId == null) return;
    _sendCommand({'command': 'terminate', 'id': _currentQueryId});
    _currentQueryId = null;
  }

  List<List<String>> _formatMovesForKataGo(List<String> moves) {
    final result = <List<String>>[];
    var isBlack = true;
    for (final move in moves) {
      result.add([isBlack ? 'B' : 'W', move.toUpperCase()]);
      isBlack = !isBlack;
    }
    return result;
  }

  void _sendCommand(Map<String, dynamic> command) {
    if (_process == null) return;
    _process!.stdin.write('${jsonEncode(command)}\n');
  }

  void _handleStdoutLine(String line) {
    if (line.isEmpty) return;
    try {
      final data = jsonDecode(line) as Map<String, dynamic>;
      final id = data['id'] as String?;
      if (id != _currentQueryId) return;

      if (data.containsKey('error')) {
        _errorCallback?.call(data['error'] as String);
        _currentQueryId = null;
        return;
      }

      final isDuringSearch = data['isDuringSearch'] as bool? ?? false;
      final rootInfo = data['rootInfo'] as Map<String, dynamic>?;
      final moveInfos = data['moveInfos'] as List?;

      if (rootInfo != null) {
        final visits = rootInfo['visits'] as int? ?? 0;
        final winrate = (rootInfo['winrate'] as num?)?.toDouble() ?? 0.5;
        final scoreLead = (rootInfo['scoreLead'] as num?)?.toDouble() ?? 0.0;

        String? bestMove;
        if (moveInfos != null && moveInfos.isNotEmpty) {
          bestMove = (moveInfos[0] as Map<String, dynamic>)['move'] as String?;
        }

        _progressCallback?.call(
          DesktopAnalysisProgress(
            currentVisits: visits,
            maxVisits: _currentMaxVisits,
            winrate: winrate,
            scoreLead: scoreLead,
            bestMove: bestMove,
            isComplete: !isDuringSearch,
          ),
        );

        if (!isDuringSearch && moveInfos != null) {
          _resultCallback?.call(_convertToAnalysisResult(data));
          _currentQueryId = null;
        }
      }
    } catch (e) {
      debugPrint('Error parsing KataGo response: $e');
    }
  }

  void _handleStderrLine(String line) {
    if (line.contains('Error')) _errorCallback?.call(line);
  }

  AnalysisResult _convertToAnalysisResult(Map<String, dynamic> data) {
    final moveInfos = data['moveInfos'] as List? ?? [];
    final rootInfo = data['rootInfo'] as Map<String, dynamic>? ?? {};

    final topMoves = moveInfos.take(10).map((info) {
      final m = info as Map<String, dynamic>;
      return MoveCandidate(
        move: m['move'] as String? ?? 'pass',
        winrate: (m['winrate'] as num?)?.toDouble() ?? 0.5,
        scoreLead: (m['scoreLead'] as num?)?.toDouble() ?? 0.0,
        visits: m['visits'] as int? ?? 0,
      );
    }).toList();

    return AnalysisResult(
      boardHash: data['id'] as String? ?? '',
      boardSize: _currentBoardSize,
      komi: _currentKomi,
      movesSequence: _currentMovesSequence,
      topMoves: topMoves,
      engineVisits: rootInfo['visits'] as int? ?? 0,
      modelName: 'katago_local',
      fromCache: false,
    );
  }

  void dispose() => stop();
}
