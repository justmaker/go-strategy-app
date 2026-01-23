/// Game provider for state management.
/// Implements offline-first logic with bundled opening book, local cache, and API fallback.

import 'package:flutter/foundation.dart';
import '../models/models.dart';
import '../services/services.dart';

/// Connection status
enum ConnectionStatus { online, offline, checking }

/// Analysis source indicator
enum AnalysisSource { openingBook, localCache, api, none }

/// Game state provider
class GameProvider extends ChangeNotifier {
  final ApiService _api;
  final CacheService _cache;
  final OpeningBookService _openingBook;

  BoardState _board;
  AnalysisResult? _lastAnalysis;
  AnalysisSource _lastAnalysisSource = AnalysisSource.none;
  bool _isAnalyzing = false;
  String? _error;
  ConnectionStatus _connectionStatus = ConnectionStatus.checking;
  bool _openingBookLoaded = false;

  // Settings
  int _selectedVisits;
  final List<int> _availableVisits;
  
  List<int> get availableVisits => _availableVisits;

  GameProvider({
    required ApiService api,
    required CacheService cache,
    OpeningBookService? openingBook,
    int boardSize = 19,
    double komi = 7.5,
    int defaultVisits = 100,
    List<int> availableVisits = const [10, 50, 100, 200, 500, 1000, 2000, 5000],
  })  : _api = api,
        _cache = cache,
        _openingBook = openingBook ?? OpeningBookService(),
        _board = BoardState(size: boardSize, komi: komi),
        _selectedVisits = defaultVisits,
        _availableVisits = availableVisits;

  // Getters
  BoardState get board => _board;
  AnalysisResult? get lastAnalysis => _lastAnalysis;
  AnalysisSource get lastAnalysisSource => _lastAnalysisSource;
  bool get isAnalyzing => _isAnalyzing;
  String? get error => _error;
  ConnectionStatus get connectionStatus => _connectionStatus;
  int get selectedVisits => _selectedVisits;
  bool get isOnline => _connectionStatus == ConnectionStatus.online;
  bool get isOpeningBookLoaded => _openingBookLoaded;
  OpeningBookService get openingBook => _openingBook;

  /// Initialize the provider
  Future<void> init() async {
    // Load opening book first (for instant offline access)
    await _loadOpeningBook();
    
    // Initialize local cache
    await _cache.init();
    
    // Check server connection (non-blocking for UI)
    checkConnection();
  }
  
  /// Load bundled opening book
  Future<void> _loadOpeningBook() async {
    try {
      await _openingBook.load();
      _openingBookLoaded = _openingBook.isLoaded;
      if (_openingBook.isLoaded) {
        debugPrint('Opening book loaded: ${_openingBook.totalEntries} entries');
      } else if (_openingBook.loadError != null) {
        debugPrint('Opening book load error: ${_openingBook.loadError}');
      }
    } catch (e) {
      debugPrint('Failed to load opening book: $e');
      _openingBookLoaded = false;
    }
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
      _lastAnalysisSource = AnalysisSource.none;
      _error = null;
      notifyListeners();
    }
  }

  /// Set komi
  void setKomi(double komi) {
    _board.komi = komi;
    _lastAnalysis = null;
    _lastAnalysisSource = AnalysisSource.none;
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
    _lastAnalysisSource = AnalysisSource.none;
    _error = null;
    notifyListeners();

    await analyze();
  }

  /// Analyze current position (offline-first with opening book)
  /// 
  /// Priority order:
  /// 1. Bundled opening book (instant, always available)
  /// 2. Local SQLite cache (fast, persisted)
  /// 3. API call (requires network, caches result)
  Future<void> analyze({bool forceRefresh = false}) async {
    if (_isAnalyzing) return;

    _isAnalyzing = true;
    _error = null;
    notifyListeners();

    try {
      // Compute a simple hash for lookups
      // Note: This is a simplified hash - the real implementation should use Zobrist hashing
      final boardHash = _computeSimpleHash();
      
      // Step 1: Try bundled opening book first (unless force refresh)
      if (!forceRefresh && _openingBookLoaded) {
        final bookResult = _openingBook.lookupWithKomi(boardHash, _board.komi);
        if (bookResult != null) {
          _lastAnalysis = bookResult;
          _lastAnalysisSource = AnalysisSource.openingBook;
          _isAnalyzing = false;
          notifyListeners();
          return;
        }
      }

      // Step 2: Try local cache (unless force refresh)
      if (!forceRefresh) {
        final cachedResult = await _cache.get(
          boardHash: boardHash,
          komi: _board.komi,
        );
        if (cachedResult != null) {
          _lastAnalysis = cachedResult;
          _lastAnalysisSource = AnalysisSource.localCache;
          _isAnalyzing = false;
          notifyListeners();
          return;
        }
      }

      // Step 3: Try API
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
          _lastAnalysisSource = AnalysisSource.api;

          // Cache the result locally for future offline access
          await _cache.put(result);

          _isAnalyzing = false;
          notifyListeners();
          return;
        } on ApiException catch (e) {
          // API failed, continue to offline fallback
          _error = 'API error: ${e.message}';
        }
      }

      // Step 4: Offline mode - show appropriate message
      if (_lastAnalysis == null) {
        if (_connectionStatus == ConnectionStatus.offline) {
          _error = 'Offline: Position not in opening book or cache';
        } else {
          _error = 'Failed to analyze position';
        }
        _lastAnalysisSource = AnalysisSource.none;
      }
    } catch (e) {
      _error = 'Error: $e';
      _lastAnalysisSource = AnalysisSource.none;
    } finally {
      _isAnalyzing = false;
      notifyListeners();
    }
  }
  
  /// Compute a simple hash for the current board position
  /// 
  /// This is a placeholder - for production, implement proper Zobrist hashing
  /// that matches the server's implementation.
  String _computeSimpleHash() {
    // Build a string representation of the position
    final buffer = StringBuffer();
    buffer.write('${_board.size}:${_board.komi}:');
    buffer.write(_board.movesGtp.join(';'));
    
    // Use Dart's built-in hash (not cryptographically secure, but fast)
    // For production, should use Zobrist hashing to match server
    return buffer.toString().hashCode.toRadixString(16).padLeft(16, '0');
  }

  /// Undo last move
  void undo() {
    if (_board.undo()) {
      _lastAnalysis = null;
      _lastAnalysisSource = AnalysisSource.none;
      _error = null;
      notifyListeners();
    }
  }

  /// Clear the board
  void clear() {
    _board.clear();
    _lastAnalysis = null;
    _lastAnalysisSource = AnalysisSource.none;
    _error = null;
    notifyListeners();
  }

  /// Get combined statistics
  Future<Map<String, dynamic>> getCacheStats() async {
    final localStats = await _cache.getStats();
    final bookStats = _openingBook.getStats();
    
    return {
      'local_cache': localStats,
      'opening_book': bookStats,
    };
  }
  
  /// Get opening book statistics
  Map<String, dynamic> getOpeningBookStats() {
    return _openingBook.getStats();
  }

  @override
  void dispose() {
    _api.dispose();
    _cache.close();
    _openingBook.clear();
    super.dispose();
  }
}
