/// Single source of truth for move ranking logic.
///
/// Both the board widget and analysis panel consume [RankedMove] objects
/// produced by [MoveRanking.rank()], eliminating duplicate ranking code.
library;

import '../models/models.dart';

/// Wrapper that pairs a [MoveCandidate] with its display rank.
///
/// Rank is a transient display property (not persisted), determined by
/// the player's perspective and signature grouping.
class RankedMove {
  final MoveCandidate candidate;

  /// 1-based display rank (1 = best group).
  final int rank;

  const RankedMove({required this.candidate, required this.rank});
}

class MoveRanking {
  /// Compute display ranks for a pre-sorted list of [MoveCandidate].
  ///
  /// Moves with identical [signature] share the same rank.
  /// Moves outside [minWinrate, maxWinrate] are filtered out.
  ///
  /// The input list must already be sorted by player winrate (best first),
  /// which is the contract from [OpeningBookService].
  static List<RankedMove> rank(
    List<MoveCandidate> moves, {
    double minWinrate = 0.01,
    double maxWinrate = 0.99,
  }) {
    final filtered = moves.where((m) {
      return m.winrate >= minWinrate && m.winrate <= maxWinrate;
    }).toList();

    if (filtered.isEmpty) return [];

    final result = <RankedMove>[];
    int currentRank = 0;
    String? lastSig;

    for (final move in filtered) {
      final sig = signature(move);
      if (sig != lastSig) {
        currentRank++;
        lastSig = sig;
      }
      result.add(RankedMove(candidate: move, rank: currentRank));
    }

    return result;
  }

  /// Signature string used to group equivalent moves into the same rank.
  ///
  /// Two moves with the same winrate percentage and score lead formatting
  /// are considered equivalent (same rank).
  static String signature(MoveCandidate move) {
    return '${move.winratePercent}_${move.scoreLeadFormatted}';
  }
}
