// Basic Flutter widget tests for Go Strategy App.

import 'package:flutter_test/flutter_test.dart';

import 'package:go_strategy_app/models/models.dart';

void main() {
  group('BoardPoint', () {
    test('converts to GTP correctly', () {
      expect(BoardPoint(0, 0).toGtp(19), 'A19');
      expect(BoardPoint(15, 3).toGtp(19), 'Q16');
      expect(BoardPoint(3, 15).toGtp(19), 'D4');
    });

    test('parses from GTP correctly', () {
      final point = BoardPoint.fromGtp('Q16', 19);
      expect(point?.x, 15);
      expect(point?.y, 3);
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
      
      board.placeStone(BoardPoint(4, 4));
      expect(board.getStone(4, 4), StoneColor.black);
      expect(board.nextPlayer, StoneColor.white);
      expect(board.moveCount, 1);
    });

    test('undoes moves correctly', () {
      final board = BoardState(size: 9);
      board.placeStone(BoardPoint(4, 4));
      board.undo();
      expect(board.isEmpty(4, 4), true);
      expect(board.moveCount, 0);
    });
  });
}
