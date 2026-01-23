/// Game provider for state management.
/// Implements offline-first logic with local cache and API fallback.

import 'package:flutter/foundation.dart';
import '../models/models.dart';
import '../services/services.dart';

/// Connection status
enum ConnectionStatus { online, offline, checking }

/// Game state provider
class GameProvider extends ChangeNotifier {
  final ApiService _api;
  final CacheService _cache;

  BoardState _board;
  AnalysisResult? _lastAnalysis;
  bool _isAnalyzing = false;
  String? _error;
  ConnectionStatus _connectionStatus = ConnectionStatus.checking;

  // Settings
  int _selectedVisits;
  final List<int> _availableVisits;
  
  List<int> get availableVisits => _availableVisits;

  GameProvider({
    required ApiService api,
    required CacheService cache,
    int boardSize = 19,
    double komi = 7.5,
    int defaultVisits = 100,
    List<int> availableVisits = const [10, 50, 100, 200, 500, 1000, 2000, 5000],
  })  : _api = api,
        _cache = cache,
        _board = BoardState(size: boardSize, komi: komi),
        _selectedVisits = defaultVisits,
        _availableVisits = availableVisits;

  // Getters
  BoardState get board => _board;
  AnalysisResult? get lastAnalysis => _lastAnalysis;
  bool get isAnalyzing => _isAnalyzing;
  String? get error => _error;
  ConnectionStatus get connectionStatus => _connectionStatus;
  int get selectedVisits => _selectedVisits;
  bool get isOnline => _connectionStatus == ConnectionStatus.online;

  /// Initialize the provider
  Future<void> init() async {
    await _cache.init();
    await checkConnection();
  }

  /// Check server connection
  Future<void> checkConnection() async {
    _connectionStatus = ConnectionStatus.checking;
    notifyListeners();

    final isHealthy = await _api.healthCheck();
    _connectionStatus = isHealthy ? ConnectionStatus.online : ConnectionStatus.offline;
    notifyListeners();
  }

  /// Set board size
  void setBoardSize(int size) {
    if (size != _board.size) {
      _board = BoardState(size: size, komi: _board.komi, handicap: _board.handicap);
      _lastAnalysis = null;
      _error = null;
      notifyListeners();
    }
  }

  /// Set komi
  void setKomi(double komi) {
    _board.komi = komi;
    _lastAnalysis = null;
    notifyListeners();
  }

  /// Set visits for analysis
  void setVisits(int visits) {
    if (_availableVisits.contains(visits)) {
      _selectedVisits = visits;
      notifyListeners();
    }
  }

  /// Place a stone and analyze
  Future<void> placeStone(BoardPoint point) async {
    if (_isAnalyzing) return;
    if (!_board.isEmpty(point.x, point.y)) return;

    _board.placeStone(point);
    _lastAnalysis = null;
    _error = null;
    notifyListeners();

    await analyze();
  }

  /// Analyze current position (offline-first)
  Future<void> analyze({bool forceRefresh = false}) async {
    if (_isAnalyzing) return;

    _isAnalyzing = true;
    _error = null;
    notifyListeners();

    try {
      // Step 1: Try local cache first (unless force refresh)
      if (!forceRefresh) {
        // TODO: Compute board hash for cache lookup
        // For now, skip local cache lookup since we don't have hash computation
      }

      // Step 2: Try API
      if (_connectionStatus == ConnectionStatus.online) {
        try {
          final result = await _api.analyze(
            boardSize: _board.size,
            moves: _board.movesGtp,
            handicap: _board.handicap,
            komi: _board.komi,
            visits: _selectedVisits,
          );

          _lastAnalysis = result;

          // Cache the result locally
          await _cache.put(result);

          _isAnalyzing = false;
          notifyListeners();
          return;
        } on ApiException catch (e) {
          // API failed, will try offline
          _error = 'API error: ${e.message}';
        }
      }

      // Step 3: Offline mode - show error if no cached result
      if (_lastAnalysis == null) {
        _error = _connectionStatus == ConnectionStatus.offline
            ? 'Offline: No cached analysis available'
            : 'Failed to analyze position';
      }
    } catch (e) {
      _error = 'Error: $e';
    } finally {
      _isAnalyzing = false;
      notifyListeners();
    }
  }

  /// Undo last move
  void undo() {
    if (_board.undo()) {
      _lastAnalysis = null;
      _error = null;
      notifyListeners();
    }
  }

  /// Clear the board
  void clear() {
    _board.clear();
    _lastAnalysis = null;
    _error = null;
    notifyListeners();
  }

  /// Get cache statistics
  Future<Map<String, dynamic>> getCacheStats() async {
    return await _cache.getStats();
  }

  @override
  void dispose() {
    _api.dispose();
    _cache.close();
    super.dispose();
  }
}
