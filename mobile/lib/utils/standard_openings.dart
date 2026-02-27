/// Standard opening injection for empty boards.
///
/// Injects hoshi (4-4), komoku (3-4), and san-san (3-3) points with
/// calibrated winrate ratios to form distinct rank groups.
library;

import '../models/models.dart';

class StandardOpenings {
  /// Inject standard opening moves for an empty board.
  ///
  /// Uses the [bestMove] winrate as reference to create calibrated winrates
  /// for hoshi/komoku/san-san, forming distinct rank groups on the board.
  ///
  /// [expandedMoves] and [seenMoves] are modified in place.
  /// Returns the number of moves injected.
  static int inject({
    required int boardSize,
    required MoveCandidate bestMove,
    required List<MoveCandidate> expandedMoves,
    required Set<String> seenMoves,
  }) {
    int injectedCount = 0;

    void injectIfMissing(
        BoardPoint basePoint, double winrateRatio, double scoreDrop) {
      final candidate = MoveCandidate(
        move: basePoint.toGtp(boardSize),
        winrate: bestMove.winrate * winrateRatio,
        scoreLead: bestMove.scoreLead - scoreDrop,
        visits: (bestMove.visits * 0.8).round(),
      );

      final x = basePoint.x;
      final y = basePoint.y;

      // Generate all 8 symmetric points
      final candidatesToAdd = [
        BoardPoint(x, y),
        BoardPoint(boardSize - 1 - x, y),
        BoardPoint(x, boardSize - 1 - y),
        BoardPoint(boardSize - 1 - x, boardSize - 1 - y),
        BoardPoint(y, x),
        BoardPoint(y, boardSize - 1 - x),
        BoardPoint(boardSize - 1 - y, x),
        BoardPoint(boardSize - 1 - y, boardSize - 1 - x),
      ];

      for (final pt in candidatesToAdd) {
        final s = pt.toGtp(boardSize);
        if (!seenMoves.contains(s)) {
          seenMoves.add(s);
          expandedMoves.add(MoveCandidate(
            move: s,
            winrate: candidate.winrate,
            scoreLead: candidate.scoreLead,
            visits: candidate.visits,
          ));
          injectedCount++;
        }
      }
    }

    // 4-4 star point (hoshi) — standard opening for 13x13 and 19x19
    // Use slightly higher winrate than DB komoku to form a separate rank
    if (boardSize >= 13) {
      injectIfMissing(const BoardPoint(3, 3), 1.02, -0.1);
    }
    // 3-4 komoku
    injectIfMissing(const BoardPoint(2, 3), 0.98, 0.2);
    // 3-3 san-san
    injectIfMissing(const BoardPoint(2, 2), 0.96, 0.4);

    return injectedCount;
  }
}
