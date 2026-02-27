import 'package:flutter_test/flutter_test.dart';
import 'package:go_strategy_app/models/models.dart';
import 'package:go_strategy_app/utils/standard_openings.dart';

void main() {
  group('StandardOpenings.inject', () {
    test('injects moves on 19x19 empty board', () {
      final expanded = <MoveCandidate>[];
      final seen = <String>{};
      final bestMove = MoveCandidate(
        move: 'K10',
        winrate: 0.5,
        scoreLead: 0.0,
        visits: 1000,
      );

      final count = StandardOpenings.inject(
        boardSize: 19,
        bestMove: bestMove,
        expandedMoves: expanded,
        seenMoves: seen,
      );

      expect(count, greaterThan(0));
      expect(expanded.length, equals(count));
      // Should have hoshi, komoku, and san-san points
      expect(expanded.length, greaterThanOrEqualTo(8)); // at least 8 symmetric points for one category
    });

    test('injects moves on 9x9 board (no hoshi)', () {
      final expanded = <MoveCandidate>[];
      final seen = <String>{};
      final bestMove = MoveCandidate(
        move: 'E5',
        winrate: 0.5,
        scoreLead: 0.0,
        visits: 1000,
      );

      final count = StandardOpenings.inject(
        boardSize: 9,
        bestMove: bestMove,
        expandedMoves: expanded,
        seenMoves: seen,
      );

      // 9x9 should not inject hoshi (boardSize < 13)
      // But should inject komoku and san-san
      expect(count, greaterThan(0));
    });

    test('does not duplicate already-seen moves', () {
      final expanded = <MoveCandidate>[];
      final seen = <String>{'D4'}; // Pre-occupy D4
      final bestMove = MoveCandidate(
        move: 'K10',
        winrate: 0.5,
        scoreLead: 0.0,
        visits: 1000,
      );

      StandardOpenings.inject(
        boardSize: 19,
        bestMove: bestMove,
        expandedMoves: expanded,
        seenMoves: seen,
      );

      // D4 should not appear in expanded (it was in seen)
      final d4Moves = expanded.where((m) => m.move == 'D4');
      expect(d4Moves, isEmpty);
    });

    test('winrate ratios create distinct groups', () {
      final expanded = <MoveCandidate>[];
      final seen = <String>{};
      final bestMove = MoveCandidate(
        move: 'K10',
        winrate: 0.5,
        scoreLead: 0.0,
        visits: 1000,
      );

      StandardOpenings.inject(
        boardSize: 19,
        bestMove: bestMove,
        expandedMoves: expanded,
        seenMoves: seen,
      );

      // Collect distinct winrate values
      final winrates = expanded.map((m) => m.winrate).toSet();
      // Should have at least 2 distinct winrate groups (hoshi, komoku, san-san)
      expect(winrates.length, greaterThanOrEqualTo(2));
    });

    test('13x13 includes hoshi injection', () {
      final expanded = <MoveCandidate>[];
      final seen = <String>{};
      final bestMove = MoveCandidate(
        move: 'G7',
        winrate: 0.5,
        scoreLead: 0.0,
        visits: 1000,
      );

      StandardOpenings.inject(
        boardSize: 13,
        bestMove: bestMove,
        expandedMoves: expanded,
        seenMoves: seen,
      );

      // 13x13 should include hoshi (boardSize >= 13)
      // hoshi winrate = 0.5 * 1.02 = 0.51
      final hoshiMoves = expanded.where((m) => m.winrate > 0.5).toList();
      expect(hoshiMoves, isNotEmpty);
    });
  });
}
