import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_strategy_app/utils/board_symmetry.dart';

void main() {
  group('BoardSymmetry.transformPoint', () {
    test('identity (type 0) returns same point', () {
      final p = BoardSymmetry.transformPoint(3, 4, 19, 0);
      expect(p, equals(const Point(3, 4)));
    });

    test('90° CW rotation (type 1) on 9x9', () {
      // (0,0) -> (0,8), (8,0) -> (0,0)
      expect(BoardSymmetry.transformPoint(0, 0, 9, 1), equals(const Point(0, 8)));
      expect(BoardSymmetry.transformPoint(8, 0, 9, 1), equals(const Point(0, 0)));
    });

    test('180° rotation (type 2) on 9x9', () {
      expect(BoardSymmetry.transformPoint(0, 0, 9, 2), equals(const Point(8, 8)));
      expect(BoardSymmetry.transformPoint(4, 4, 9, 2), equals(const Point(4, 4))); // center is fixed
    });

    test('270° CW rotation (type 3) on 9x9', () {
      expect(BoardSymmetry.transformPoint(0, 0, 9, 3), equals(const Point(8, 0)));
    });

    test('horizontal flip (type 4) on 19x19', () {
      expect(BoardSymmetry.transformPoint(3, 5, 19, 4), equals(const Point(15, 5)));
    });

    test('vertical flip (type 5) on 19x19', () {
      expect(BoardSymmetry.transformPoint(3, 5, 19, 5), equals(const Point(3, 13)));
    });

    test('diagonal flip (type 6)', () {
      expect(BoardSymmetry.transformPoint(3, 5, 19, 6), equals(const Point(5, 3)));
    });

    test('anti-diagonal flip (type 7) on 9x9', () {
      expect(BoardSymmetry.transformPoint(0, 0, 9, 7), equals(const Point(8, 8)));
    });

    test('all 8 transforms of center point are identity on odd board', () {
      for (int type = 0; type < 8; type++) {
        final p = BoardSymmetry.transformPoint(4, 4, 9, type);
        expect(p, equals(const Point(4, 4)), reason: 'type=$type should fix center');
      }
    });
  });

  group('BoardSymmetry.inverseSymmetry', () {
    test('applying transform then inverse returns identity', () {
      for (int type = 0; type < 8; type++) {
        final inv = BoardSymmetry.inverseSymmetry(type);
        // Apply type, then inv — should get back original
        final p = BoardSymmetry.transformPoint(2, 5, 19, type);
        final back = BoardSymmetry.transformPoint(p.x, p.y, 19, inv);
        expect(back, equals(const Point(2, 5)),
            reason: 'type=$type, inv=$inv should round-trip');
      }
    });

    test('type 1 inverse is 3 and vice versa', () {
      expect(BoardSymmetry.inverseSymmetry(1), equals(3));
      expect(BoardSymmetry.inverseSymmetry(3), equals(1));
    });

    test('self-inverse types', () {
      for (final type in [0, 2, 4, 5, 6, 7]) {
        expect(BoardSymmetry.inverseSymmetry(type), equals(type));
      }
    });
  });

  group('BoardSymmetry.transformGtp', () {
    test('pass moves are unchanged', () {
      expect(BoardSymmetry.transformGtp('pass', 19, 1), equals('pass'));
    });

    test('empty moves are unchanged', () {
      expect(BoardSymmetry.transformGtp('', 19, 1), equals(''));
    });

    test('transforms "B Q16" format correctly', () {
      final result = BoardSymmetry.transformGtp('B Q16', 19, 0);
      expect(result, equals('B Q16'));
    });

    test('transforms "B[Q16]" bracket format correctly', () {
      final result = BoardSymmetry.transformGtp('B[Q16]', 19, 0);
      expect(result, equals('B[Q16]'));
    });

    test('180° rotation of corner move on 19x19', () {
      // A1 (0,0) -> T19 (18,18)
      final result = BoardSymmetry.transformGtp('B A1', 19, 2);
      expect(result, equals('B T19'));
    });

    test('bare coordinate (no color) transforms correctly', () {
      final result = BoardSymmetry.transformGtp('A1', 19, 2);
      expect(result, equals('T19'));
    });
  });

  group('BoardSymmetry.validSymmetries', () {
    test('empty board returns all 8 symmetries', () {
      final syms = BoardSymmetry.validSymmetries(19, []);
      expect(syms, equals([0, 1, 2, 3, 4, 5, 6, 7]));
    });

    test('single center stone on 9x9 preserves all 8', () {
      // E5 = (4, 4) center of 9x9
      final syms = BoardSymmetry.validSymmetries(9, ['B E5']);
      expect(syms, equals([0, 1, 2, 3, 4, 5, 6, 7]));
    });

    test('single corner stone preserves identity and diagonal flip', () {
      // A1 = (0, 0) — preserved by identity (0) and diagonal flip (6: swap x,y)
      final syms = BoardSymmetry.validSymmetries(9, ['B A1']);
      expect(syms, contains(0));
      expect(syms, contains(6)); // diagonal flip preserves (0,0)
      expect(syms.length, equals(2));
    });

    test('two symmetric stones preserve some symmetries', () {
      // D4 and F4 on 9x9: (3,3) and (5,3)
      // These are horizontally symmetric around center column
      final syms = BoardSymmetry.validSymmetries(9, ['B D4', 'W F4']);
      expect(syms, contains(0)); // identity always valid
    });

    test('returns at least identity even with asymmetric position', () {
      final syms = BoardSymmetry.validSymmetries(19, ['B D4', 'W Q16', 'B C3']);
      expect(syms, isNotEmpty);
      expect(syms, contains(0));
    });
  });
}
