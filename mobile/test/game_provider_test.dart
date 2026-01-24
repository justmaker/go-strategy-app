/// Tests for GameProvider dual slider functionality.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:go_strategy_app/models/models.dart';
import 'package:go_strategy_app/providers/game_provider.dart';
import 'package:go_strategy_app/services/services.dart';

// Mock services for testing
class MockApiService extends ApiService {
  MockApiService() : super(baseUrl: 'http://localhost:8000');

  @override
  Future<bool> healthCheck() async => false;
}

class MockCacheService extends CacheService {
  @override
  Future<void> init() async {}
}

void main() {
  group('GameProvider dual slider', () {
    late GameProvider provider;
    late MockApiService mockApi;
    late MockCacheService mockCache;

    setUp(() {
      mockApi = MockApiService();
      mockCache = MockCacheService();
      provider = GameProvider(
        api: mockApi,
        cache: mockCache,
        boardSize: 9,
        komi: 6.5,
        defaultLookupVisits: 200,
        defaultComputeVisits: 50,
        availableLookupVisits: [100, 200, 500, 1000],
        availableComputeVisits: [10, 20, 50, 100],
      );
    });

    test('initializes with correct default values', () {
      expect(provider.lookupVisits, 200);
      expect(provider.computeVisits, 50);
      expect(provider.availableLookupVisits, [100, 200, 500, 1000]);
      expect(provider.availableComputeVisits, [10, 20, 50, 100]);
    });

    test('setLookupVisits updates value when valid', () {
      provider.setLookupVisits(500);
      expect(provider.lookupVisits, 500);
    });

    test('setLookupVisits ignores invalid values', () {
      provider.setLookupVisits(999); // Not in available list
      expect(provider.lookupVisits, 200); // Unchanged
    });

    test('setComputeVisits updates value when valid', () {
      provider.setComputeVisits(100);
      expect(provider.computeVisits, 100);
    });

    test('setComputeVisits ignores invalid values', () {
      provider.setComputeVisits(75); // Not in available list
      expect(provider.computeVisits, 50); // Unchanged
    });

    test('board size changes reset analysis state', () {
      provider.setBoardSize(13);
      expect(provider.board.size, 13);
      expect(provider.lastAnalysis, isNull);
      expect(provider.analysisProgress, isNull);
      expect(provider.desktopAnalysisProgress, isNull);
    });

    test('komi changes invalidate analysis', () {
      provider.setKomi(7.5);
      expect(provider.board.komi, 7.5);
      expect(provider.lastAnalysis, isNull);
    });

    test('clear resets board and analysis', () {
      // Place a stone first
      provider.board.placeStone(const BoardPoint(4, 4));
      expect(provider.board.moveCount, 1);

      provider.clear();
      expect(provider.board.moveCount, 0);
      expect(provider.lastAnalysis, isNull);
    });

    test('undo removes last move', () {
      provider.board.placeStone(const BoardPoint(4, 4));
      provider.board.placeStone(const BoardPoint(3, 3));
      expect(provider.board.moveCount, 2);

      provider.undo();
      expect(provider.board.moveCount, 1);
      expect(provider.lastAnalysis, isNull);
    });
  });

  group('GameProvider analysis source', () {
    test('AnalysisSource enum has all values', () {
      expect(AnalysisSource.values, contains(AnalysisSource.openingBook));
      expect(AnalysisSource.values, contains(AnalysisSource.localCache));
      expect(AnalysisSource.values, contains(AnalysisSource.localEngine));
      expect(AnalysisSource.values, contains(AnalysisSource.api));
      expect(AnalysisSource.values, contains(AnalysisSource.none));
    });
  });

  group('GameProvider connection status', () {
    test('ConnectionStatus enum has all values', () {
      expect(ConnectionStatus.values, contains(ConnectionStatus.online));
      expect(ConnectionStatus.values, contains(ConnectionStatus.offline));
      expect(ConnectionStatus.values, contains(ConnectionStatus.checking));
    });
  });
}
