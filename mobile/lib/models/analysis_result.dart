/// Data models for Go analysis results.
/// Mirrors the Python backend models for JSON serialization.
library;

class MoveCandidate {
  final String move;
  final double winrate;
  final double scoreLead;
  final int visits;

  MoveCandidate({
    required this.move,
    required this.winrate,
    required this.scoreLead,
    required this.visits,
  });

  factory MoveCandidate.fromJson(Map<String, dynamic> json) {
    return MoveCandidate(
      move: json['move'] as String,
      winrate: (json['winrate'] as num).toDouble(),
      // Support both snake_case (API) and camelCase (opening book)
      scoreLead: (json['scoreLead'] ?? json['score_lead'] as num).toDouble(),
      visits: json['visits'] as int,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'move': move,
      'winrate': winrate,
      'score_lead': scoreLead,
      'visits': visits,
    };
  }

  /// Winrate as percentage string
  String get winratePercent => '${(winrate * 100).toStringAsFixed(1)}%';

  /// Score lead with sign
  String get scoreLeadFormatted {
    final sign = scoreLead >= 0 ? '+' : '';
    return '$sign${scoreLead.toStringAsFixed(1)}';
  }

  @override
  String toString() {
    return 'MoveCandidate($move, wr=$winratePercent, lead=$scoreLeadFormatted, visits=$visits)';
  }
}

class AnalysisResult {
  final String boardHash;
  final int boardSize;
  final double komi;
  final String movesSequence;
  final List<MoveCandidate> topMoves;
  final int engineVisits;
  final String modelName;
  final bool fromCache;
  final String? timestamp;
  final double? calculationDuration;
  final bool? stoppedByLimit;
  final String? limitSetting;

  AnalysisResult({
    required this.boardHash,
    required this.boardSize,
    required this.komi,
    required this.movesSequence,
    required this.topMoves,
    required this.engineVisits,
    required this.modelName,
    this.fromCache = false,
    this.timestamp,
    this.calculationDuration,
    this.stoppedByLimit,
    this.limitSetting,
  });

  factory AnalysisResult.fromJson(Map<String, dynamic> json) {
    return AnalysisResult(
      boardHash: json['board_hash'] as String,
      boardSize: json['board_size'] as int,
      komi: (json['komi'] as num).toDouble(),
      movesSequence: json['moves_sequence'] as String? ?? '',
      topMoves: (json['top_moves'] as List)
          .map((m) => MoveCandidate.fromJson(m as Map<String, dynamic>))
          .toList(),
      engineVisits: json['engine_visits'] as int,
      modelName: json['model_name'] as String,
      fromCache: json['from_cache'] as bool? ?? false,
      timestamp: json['timestamp'] as String?,
      calculationDuration: json['calculation_duration'] as double?,
      stoppedByLimit: json['stopped_by_limit'] as bool?,
      limitSetting: json['limit_setting'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'board_hash': boardHash,
      'board_size': boardSize,
      'komi': komi,
      'moves_sequence': movesSequence,
      'top_moves': topMoves.map((m) => m.toJson()).toList(),
      'engine_visits': engineVisits,
      'model_name': modelName,
      'from_cache': fromCache,
      'timestamp': timestamp,
      'calculation_duration': calculationDuration,
      'stopped_by_limit': stoppedByLimit,
      'limit_setting': limitSetting,
    };
  }

  /// Get the best move (first in the list)
  MoveCandidate? get bestMove => topMoves.isNotEmpty ? topMoves.first : null;

  @override
  String toString() {
    return 'AnalysisResult(${boardSize}x$boardSize, komi=$komi, moves=${topMoves.length}, fromCache=$fromCache)';
  }
}

/// Request model for analysis
class AnalysisRequest {
  final int boardSize;
  final List<String> moves;
  final int handicap;
  final double komi;
  final int? visits;

  AnalysisRequest({
    this.boardSize = 19,
    this.moves = const [],
    this.handicap = 0,
    this.komi = 7.5,
    this.visits,
  });

  Map<String, dynamic> toJson() {
    return {
      'board_size': boardSize,
      'moves': moves,
      'handicap': handicap,
      'komi': komi,
      if (visits != null) 'visits': visits,
    };
  }
}
