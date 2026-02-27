import 'package:flutter_test/flutter_test.dart';
import 'package:go_strategy_app/models/models.dart';
import 'package:go_strategy_app/utils/move_ranking.dart';

void main() {
  group('MoveRanking.rank', () {
    test('empty list returns empty', () {
      expect(MoveRanking.rank([]), isEmpty);
    });

    test('single move gets rank 1', () {
      final moves = [
        MoveCandidate(move: 'Q16', winrate: 0.55, scoreLead: 2.5, visits: 1000),
      ];
      final ranked = MoveRanking.rank(moves);
      expect(ranked.length, equals(1));
      expect(ranked[0].rank, equals(1));
      expect(ranked[0].candidate.move, equals('Q16'));
    });

    test('moves with same signature share same rank', () {
      final moves = [
        MoveCandidate(move: 'Q16', winrate: 0.55, scoreLead: 2.5, visits: 1000),
        MoveCandidate(move: 'D4', winrate: 0.55, scoreLead: 2.5, visits: 800),
        MoveCandidate(move: 'Q4', winrate: 0.55, scoreLead: 2.5, visits: 600),
      ];
      final ranked = MoveRanking.rank(moves);
      expect(ranked.length, equals(3));
      expect(ranked[0].rank, equals(1));
      expect(ranked[1].rank, equals(1));
      expect(ranked[2].rank, equals(1));
    });

    test('moves with different winrate get different ranks', () {
      final moves = [
        MoveCandidate(move: 'Q16', winrate: 0.55, scoreLead: 2.5, visits: 1000),
        MoveCandidate(move: 'D4', winrate: 0.50, scoreLead: 1.0, visits: 800),
        MoveCandidate(move: 'Q4', winrate: 0.45, scoreLead: -0.5, visits: 600),
      ];
      final ranked = MoveRanking.rank(moves);
      expect(ranked.length, equals(3));
      expect(ranked[0].rank, equals(1));
      expect(ranked[1].rank, equals(2));
      expect(ranked[2].rank, equals(3));
    });

    test('filters out moves below minWinrate', () {
      final moves = [
        MoveCandidate(move: 'Q16', winrate: 0.55, scoreLead: 2.5, visits: 1000),
        MoveCandidate(move: 'D4', winrate: 0.005, scoreLead: -10.0, visits: 100),
      ];
      final ranked = MoveRanking.rank(moves);
      expect(ranked.length, equals(1));
      expect(ranked[0].candidate.move, equals('Q16'));
    });

    test('filters out moves above maxWinrate', () {
      final moves = [
        MoveCandidate(move: 'Q16', winrate: 0.55, scoreLead: 2.5, visits: 1000),
        MoveCandidate(move: 'D4', winrate: 0.995, scoreLead: 50.0, visits: 100),
      ];
      final ranked = MoveRanking.rank(moves);
      expect(ranked.length, equals(1));
      expect(ranked[0].candidate.move, equals('Q16'));
    });

    test('all moves filtered returns empty', () {
      final moves = [
        MoveCandidate(move: 'D4', winrate: 0.005, scoreLead: -10.0, visits: 100),
        MoveCandidate(move: 'Q4', winrate: 0.995, scoreLead: 50.0, visits: 100),
      ];
      final ranked = MoveRanking.rank(moves);
      expect(ranked, isEmpty);
    });

    test('rank numbers are consecutive (no gaps)', () {
      final moves = [
        MoveCandidate(move: 'Q16', winrate: 0.55, scoreLead: 2.5, visits: 1000),
        MoveCandidate(move: 'D4', winrate: 0.55, scoreLead: 2.5, visits: 800),
        MoveCandidate(move: 'Q4', winrate: 0.50, scoreLead: 1.0, visits: 600),
        MoveCandidate(move: 'D16', winrate: 0.50, scoreLead: 1.0, visits: 400),
        MoveCandidate(move: 'K10', winrate: 0.45, scoreLead: -0.5, visits: 200),
      ];
      final ranked = MoveRanking.rank(moves);
      final ranks = ranked.map((r) => r.rank).toSet().toList()..sort();
      expect(ranks, equals([1, 2, 3]));
    });
  });

  group('MoveRanking.signature', () {
    test('same winrate and scoreLead produce same signature', () {
      final m1 = MoveCandidate(move: 'Q16', winrate: 0.55, scoreLead: 2.5, visits: 1000);
      final m2 = MoveCandidate(move: 'D4', winrate: 0.55, scoreLead: 2.5, visits: 500);
      expect(MoveRanking.signature(m1), equals(MoveRanking.signature(m2)));
    });

    test('different winrate produces different signature', () {
      final m1 = MoveCandidate(move: 'Q16', winrate: 0.55, scoreLead: 2.5, visits: 1000);
      final m2 = MoveCandidate(move: 'D4', winrate: 0.50, scoreLead: 2.5, visits: 1000);
      expect(MoveRanking.signature(m1), isNot(equals(MoveRanking.signature(m2))));
    });

    test('different scoreLead produces different signature', () {
      final m1 = MoveCandidate(move: 'Q16', winrate: 0.55, scoreLead: 2.5, visits: 1000);
      final m2 = MoveCandidate(move: 'D4', winrate: 0.55, scoreLead: 1.0, visits: 1000);
      expect(MoveRanking.signature(m1), isNot(equals(MoveRanking.signature(m2))));
    });
  });

  group('Board-panel consistency', () {
    test('same input produces same ranks for board and panel use cases', () {
      // Simulate what board widget and analysis panel both receive
      final topMoves = [
        MoveCandidate(move: 'Q16', winrate: 0.55, scoreLead: 2.5, visits: 1000),
        MoveCandidate(move: 'D16', winrate: 0.55, scoreLead: 2.5, visits: 800),
        MoveCandidate(move: 'Q4', winrate: 0.50, scoreLead: 1.0, visits: 600),
        MoveCandidate(move: 'D4', winrate: 0.50, scoreLead: 1.0, visits: 400),
        MoveCandidate(move: 'K10', winrate: 0.45, scoreLead: -0.5, visits: 200),
      ];

      // Board widget: ranks all moves (including symmetry duplicates)
      final boardRanked = MoveRanking.rank(topMoves);

      // Analysis panel: deduplicates first, then ranks
      final uniqueMoves = <MoveCandidate>[];
      final seenMoves = <String>{};
      for (final move in topMoves) {
        if (!seenMoves.contains(move.move)) {
          seenMoves.add(move.move);
          uniqueMoves.add(move);
        }
      }
      final panelRanked = MoveRanking.rank(uniqueMoves);

      // For the same move, both should produce the same rank
      final boardRankMap = {for (final rm in boardRanked) rm.candidate.move: rm.rank};
      final panelRankMap = {for (final rm in panelRanked) rm.candidate.move: rm.rank};

      for (final move in panelRankMap.keys) {
        expect(boardRankMap[move], equals(panelRankMap[move]),
            reason: '$move should have same rank in board ($boardRankMap) and panel ($panelRankMap)');
      }
    });
  });
}
