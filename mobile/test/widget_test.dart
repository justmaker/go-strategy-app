/// Basic Flutter widget tests for Go Strategy App.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:go_strategy_app/models/models.dart';

void main() {
  group('BoardPoint', () {
    // GTP coordinate system: y=0 is bottom row (row 1), y=18 is top row (row 19)
    test('converts to GTP correctly', () {
      // (0, 0) = bottom-left = A1
      expect(const BoardPoint(0, 0).toGtp(19), 'A1');
      // (15, 15) = Q16 (column Q, row 16)
      expect(const BoardPoint(15, 15).toGtp(19), 'Q16');
      // (3, 3) = D4 (column D, row 4)
      expect(const BoardPoint(3, 3).toGtp(19), 'D4');
      // (0, 18) = top-left = A19
      expect(const BoardPoint(0, 18).toGtp(19), 'A19');
    });

    test('parses from GTP correctly', () {
      // Q16 = column Q (index 15), row 16 (y=15)
      final point = BoardPoint.fromGtp('Q16', 19);
      expect(point?.x, 15);
      expect(point?.y, 15);

      // A1 = bottom-left
      final bottomLeft = BoardPoint.fromGtp('A1', 19);
      expect(bottomLeft?.x, 0);
      expect(bottomLeft?.y, 0);

      // T19 = top-right
      final topRight = BoardPoint.fromGtp('T19', 19);
      expect(topRight?.x, 18);
      expect(topRight?.y, 18);
    });
  });

  group('MoveCandidate', () {
    test('formats winrate correctly', () {
      final move = MoveCandidate(
        move: 'Q16',
        winrate: 0.523,
        scoreLead: 1.5,
        visits: 100,
      );
      expect(move.winratePercent, '52.3%');
    });

    test('formats score lead correctly', () {
      final positive = MoveCandidate(
        move: 'Q16',
        winrate: 0.5,
        scoreLead: 1.5,
        visits: 100,
      );
      expect(positive.scoreLeadFormatted, '+1.5');

      final negative = MoveCandidate(
        move: 'D4',
        winrate: 0.5,
        scoreLead: -2.3,
        visits: 100,
      );
      expect(negative.scoreLeadFormatted, '-2.3');
    });
  });

  group('BoardState', () {
    test('starts with empty board', () {
      final board = BoardState(size: 9);
      expect(board.isEmpty(4, 4), true);
      expect(board.moveCount, 0);
    });

    test('places stones correctly', () {
      final board = BoardState(size: 9);
      expect(board.nextPlayer, StoneColor.black);

      board.placeStone(const BoardPoint(4, 4));
      expect(board.getStone(4, 4), StoneColor.black);
      expect(board.nextPlayer, StoneColor.white);
      expect(board.moveCount, 1);
    });

    test('undoes moves correctly', () {
      final board = BoardState(size: 9);
      board.placeStone(const BoardPoint(4, 4));
      board.undo();
      expect(board.isEmpty(4, 4), true);
      expect(board.moveCount, 0);
    });
  });
}
