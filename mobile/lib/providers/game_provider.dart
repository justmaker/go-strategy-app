/// Game provider for state management.
/// Implements offline-first logic with bundled opening book, local cache,
/// local KataGo engine, and API fallback.

import 'dart:async';

import 'package:flutter/foundation.dart';
import '../models/models.dart';
import '../services/services.dart';

/// Connection status
enum ConnectionStatus { online, offline, checking }

/// Analysis source indicator
enum AnalysisSource { openingBook, localCache, localEngine, api, none }

/// Game state provider
class GameProvider extends ChangeNotifier {
  final ApiService _api;
  final CacheService _cache;
  final OpeningBookService _openingBook;
  final KataGoService _kataGo;

  BoardState _board;
  AnalysisResult? _lastAnalysis;
  AnalysisSource _lastAnalysisSource = AnalysisSource.none;
  bool _isAnalyzing = false;
  String? _error;
  ConnectionStatus _connectionStatus = ConnectionStatus.checking;
  bool _openingBookLoaded = false;

  // Local engine state
  bool _localEngineEnabled = true;
  AnalysisProgress? _analysisProgress;

  // Settings
  int _selectedVisits;
  final List<int> _availableVisits;

  List<int> get availableVisits => _availableVisits;

  GameProvider({
    required ApiService api,
    required CacheService cache,
    OpeningBookService? openingBook,
    KataGoService? kataGo,
    int boardSize = 19,
    double komi = 7.5,
    int defaultVisits = 100,
    List<int> availableVisits = const [10, 50, 100, 200, 500, 1000, 2000, 5000],
  })  : _api = api,
        _cache = cache,
        _openingBook = openingBook ?? OpeningBookService(),
        _kataGo = kataGo ?? KataGoService(),
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

  // Local engine getters
  bool get localEngineEnabled => _localEngineEnabled;
  bool get localEngineRunning => _kataGo.isRunning;
  AnalysisProgress? get analysisProgress => _analysisProgress;
  KataGoService get kataGoService => _kataGo;

  /// Initialize the provider
  Future<void> init() async {
    // Load opening book first (for instant offline access)
    await _loadOpeningBook();

    // Initialize local cache
    await _cache.init();

    // Check server connection (non-blocking for UI)
    checkConnection();

    // Try to start local engine (non-blocking)
    _initLocalEngine();
  }

  /// Initialize local KataGo engine
  Future<void> _initLocalEngine() async {
    if (!_localEngineEnabled) return;

    try {
      final success = await _kataGo.start();
      if (success) {
        debugPrint('Local KataGo engine started');
      } else {
        debugPrint('Local KataGo engine failed to start');
      }
      notifyListeners();
    } catch (e) {
      debugPrint('Error starting local engine: $e');
    }
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
    _connectionStatus =
        isHealthy ? ConnectionStatus.online : ConnectionStatus.offline;
    notifyListeners();
  }

  /// Toggle local engine
  void setLocalEngineEnabled(bool enabled) {
    _localEngineEnabled = enabled;
    if (enabled && !_kataGo.isRunning) {
      _initLocalEngine();
    } else if (!enabled && _kataGo.isRunning) {
      _kataGo.stop();
    }
    notifyListeners();
  }

  /// Set board size
  void setBoardSize(int size) {
    if (size != _board.size) {
      _board =
          BoardState(size: size, komi: _board.komi, handicap: _board.handicap);
      _lastAnalysis = null;
      _lastAnalysisSource = AnalysisSource.none;
      _analysisProgress = null;
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
    _analysisProgress = null;
    _error = null;
    notifyListeners();

    await analyze();
  }

  /// Analyze current position (offline-first with opening book)
  ///
  /// Priority order:
  /// 1. Bundled opening book (instant, always available)
  /// 2. Local SQLite cache (fast, persisted)
  /// 3. Local KataGo engine (slow but works offline)
  /// 4. API call (requires network, caches result)
  Future<void> analyze({bool forceRefresh = false}) async {
    if (_isAnalyzing) return;

    _isAnalyzing = true;
    _error = null;
    _analysisProgress = null;
    notifyListeners();

    try {
      // Compute a simple hash for lookups
      final boardHash = _computeSimpleHash();

      // Step 1: Try bundled opening book first (unless force refresh)
      // Use move-based lookup since we don't have Zobrist hash in Dart
      if (!forceRefresh && _openingBookLoaded) {
        final bookResult = _openingBook.lookupByMoves(
          _board.size,
          _board.komi,
          _board.movesGtp,
        );
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

      // Step 3: Try API first if online (faster than local engine)
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

          // Cache the result locally
          await _cache.put(result);

          _isAnalyzing = false;
          notifyListeners();
          return;
        } on ApiException catch (e) {
          debugPrint('API error: ${e.message}, falling back to local engine');
        }
      }

      // Step 4: Try local KataGo engine
      if (_localEngineEnabled && _kataGo.isRunning) {
        await _analyzeWithLocalEngine();
        return;
      }

      // Step 5: No analysis available
      _error = _connectionStatus == ConnectionStatus.offline
          ? 'Offline: Position not in opening book or cache'
          : 'Failed to analyze position';
      _lastAnalysisSource = AnalysisSource.none;
    } catch (e) {
      _error = 'Error: $e';
      _lastAnalysisSource = AnalysisSource.none;
    } finally {
      _isAnalyzing = false;
      notifyListeners();
    }
  }

  /// Analyze using local KataGo engine
  Future<void> _analyzeWithLocalEngine() async {
    final completer = Completer<void>();

    await _kataGo.analyze(
      boardSize: _board.size,
      moves: _board.movesGtp,
      komi: _board.komi,
      maxVisits: _selectedVisits,
      onProgress: (progress) {
        _analysisProgress = progress;
        notifyListeners();
      },
      onResult: (result) {
        _lastAnalysis = result;
        _lastAnalysisSource = AnalysisSource.localEngine;
        _analysisProgress = null;
        _isAnalyzing = false;

        // Cache the result
        _cache.put(result);

        notifyListeners();
        if (!completer.isCompleted) completer.complete();
      },
      onError: (error) {
        _error = 'Local engine error: $error';
        _isAnalyzing = false;
        notifyListeners();
        if (!completer.isCompleted) completer.complete();
      },
    );

    // Wait for completion with timeout
    try {
      await completer.future.timeout(
        Duration(seconds: 120),
        onTimeout: () {
          _kataGo.cancelAnalysis();
          _error = 'Analysis timed out';
          _isAnalyzing = false;
          notifyListeners();
        },
      );
    } catch (e) {
      debugPrint('Analysis error: $e');
    }
  }

  /// Cancel ongoing analysis
  Future<void> cancelAnalysis() async {
    if (!_isAnalyzing) return;

    await _kataGo.cancelAnalysis();
    _isAnalyzing = false;
    _analysisProgress = null;
    _error = 'Analysis cancelled';
    notifyListeners();
  }

  /// Compute a simple hash for the current board position
  String _computeSimpleHash() {
    final buffer = StringBuffer();
    buffer.write('${_board.size}:${_board.komi}:');
    buffer.write(_board.movesGtp.join(';'));
    return buffer.toString().hashCode.toRadixString(16).padLeft(16, '0');
  }

  /// Undo last move
  void undo() {
    if (_board.undo()) {
      _lastAnalysis = null;
      _lastAnalysisSource = AnalysisSource.none;
      _analysisProgress = null;
      _error = null;
      notifyListeners();
    }
  }

  /// Clear the board
  void clear() {
    _board.clear();
    _lastAnalysis = null;
    _lastAnalysisSource = AnalysisSource.none;
    _analysisProgress = null;
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
      'local_engine': {
        'enabled': _localEngineEnabled,
        'running': _kataGo.isRunning,
      },
    };
  }

  /// Get opening book statistics
  Map<String, dynamic> getOpeningBookStats() {
    return _openingBook.getStats();
  }

  @override
  void dispose() {
    _kataGo.dispose();
    _api.dispose();
    _cache.close();
    _openingBook.clear();
    super.dispose();
  }
}
