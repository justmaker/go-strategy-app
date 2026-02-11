/// Tests for OpeningBookService.
///
/// NOTE: The full load() method cannot be tested in unit tests because it
/// requires rootBundle (Flutter asset loading), which is only available in
/// widget tests or integration tests. We test the logic methods that don't
/// depend on asset loading: buildMoveKeyFromGtp, coordinate transforms, etc.
///
/// For full integration testing of the opening book, use:
///   flutter test integration_test/
/// or test within the running app.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:go_strategy_app/services/opening_book_service.dart';
import 'package:go_strategy_app/models/models.dart';

void main() {
  group('OpeningBookService initial state', () {
    test('starts unloaded', () {
      final service = OpeningBookService();
      expect(service.isLoaded, false);
      expect(service.totalEntries, 0);
      expect(service.loadError, isNull);
    });

    test('lookup returns null when not loaded', () {
      final service = OpeningBookService();
      expect(service.lookup('some_hash'), isNull);
    });

    test('lookupByMoves returns null when not loaded', () {
      final service = OpeningBookService();
      expect(service.lookupByMoves(19, 7.5, ['B Q16']), isNull);
    });

    test('contains returns false when not loaded', () {
      final service = OpeningBookService();
      expect(service.contains('some_hash'), false);
    });
  });

  group('OpeningBookService buildMoveKeyFromGtp', () {
    test('builds key for empty board', () {
      final service = OpeningBookService();
      final key = service.buildMoveKeyFromGtp(19, 7.5, []);
      expect(key, '19:7.5:');
    });

    test('builds key for single move', () {
      final service = OpeningBookService();
      final key = service.buildMoveKeyFromGtp(19, 7.5, ['B Q16']);
      expect(key, '19:7.5:B[Q16]');
    });

    test('builds key for multiple moves', () {
      final service = OpeningBookService();
      final key = service.buildMoveKeyFromGtp(19, 7.5, ['B Q16', 'W D4']);
      expect(key, '19:7.5:B[Q16];W[D4]');
    });

    test('builds key for 9x9 with different komi', () {
      final service = OpeningBookService();
      final key = service.buildMoveKeyFromGtp(9, 6.5, ['B E5']);
      expect(key, '9:6.5:B[E5]');
    });
  });

  group('OpeningBookService getStats', () {
    test('returns empty stats when not loaded', () {
      final service = OpeningBookService();
      final stats = service.getStats();

      expect(stats['is_loaded'], false);
      expect(stats['total_entries'], 0);
      expect(stats['indexed_entries'], 0);
    });
  });

  group('OpeningBookService clear', () {
    test('clear resets state', () {
      final service = OpeningBookService();
      service.clear();

      expect(service.isLoaded, false);
      expect(service.totalEntries, 0);
      expect(service.entriesByBoardSize, isEmpty);
    });
  });

  group('OpeningBookService countForBoardSize', () {
    test('returns 0 for unloaded service', () {
      final service = OpeningBookService();
      expect(service.countForBoardSize(19), 0);
      expect(service.countForBoardSize(9), 0);
    });
  });

  group('OpeningBookEntry', () {
    test('fromJson parses correctly', () {
      final json = {
        'h': 'abc123',
        's': 19,
        'k': 7.5,
        'm': 'B[Q16]',
        'v': 500,
        't': [
          {'move': 'D4', 'winrate': 0.52, 'scoreLead': 0.3, 'visits': 100},
        ],
      };

      final entry = OpeningBookEntry.fromJson(json);
      expect(entry.hash, 'abc123');
      expect(entry.boardSize, 19);
      expect(entry.komi, 7.5);
      expect(entry.movesSequence, 'B[Q16]');
      expect(entry.visits, 500);
      expect(entry.topMoves.length, 1);
      expect(entry.topMoves[0].move, 'D4');
    });

    test('toAnalysisResult converts correctly', () {
      final entry = OpeningBookEntry(
        hash: 'abc123',
        boardSize: 19,
        komi: 7.5,
        movesSequence: 'B[Q16]',
        topMoves: [
          MoveCandidate(
            move: 'D4',
            winrate: 0.52,
            scoreLead: 0.3,
            visits: 100,
          ),
        ],
        visits: 500,
      );

      final result = entry.toAnalysisResult();
      expect(result.boardHash, 'abc123');
      expect(result.boardSize, 19);
      expect(result.komi, 7.5);
      expect(result.engineVisits, 500);
      expect(result.modelName, 'bundled_opening_book');
      expect(result.fromCache, true);
      expect(result.topMoves.length, 1);
    });
  });
}
