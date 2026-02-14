/// Game provider for state management.
/// Implements offline-first logic with bundled opening book, local cache,
/// local KataGo engine, and API fallback.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import '../models/models.dart';
import '../services/services.dart';
import '../services/inference/inference_engine.dart';
import '../services/inference/inference_factory.dart';

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
  final KataGoDesktopService _kataGoDesktop;

  // New inference engine (Android uses ONNX, others use KataGo)
  InferenceEngine? _inferenceEngine;

  BoardState _board;
  AnalysisResult? _lastAnalysis;
  AnalysisSource _lastAnalysisSource = AnalysisSource.none;
  bool _isAnalyzing = false;
  String? _error;
  ConnectionStatus _connectionStatus = ConnectionStatus.checking;
  bool _openingBookLoaded = false;

  // Local engine state
  bool _localEngineEnabled = true;
  String? _engineError;
  AnalysisProgress? _analysisProgress;
  DesktopAnalysisProgress? _desktopAnalysisProgress;

  // Visual preferences
  bool _showMoveNumbers = true;

  // Move confirmation feature
  bool _moveConfirmationEnabled = false;
  BoardPoint? _pendingMove;

  // Settings - Dual slider system
  int _lookupVisits;
  int _computeVisits;
  final List<int> _availableLookupVisits;
  final List<int> _availableComputeVisits;

  List<int> get availableLookupVisits => _availableLookupVisits;
  List<int> get availableComputeVisits => _availableComputeVisits;

  GameProvider({
    required ApiService api,
    required CacheService cache,
    OpeningBookService? openingBook,
    KataGoService? kataGo,
    KataGoDesktopService? kataGoDesktop,
    int boardSize = 19,
    double komi = 7.5,
    int defaultLookupVisits = 100,
    int defaultComputeVisits = 50,
    List<int> availableLookupVisits = const [100, 200, 500, 1000, 2000, 5000],
    List<int> availableComputeVisits = const [10, 20, 50, 100, 200],
  }) : _api = api,
       _cache = cache,
       _openingBook = openingBook ?? OpeningBookService(),
       _kataGo = kataGo ?? KataGoService(),
       _kataGoDesktop = kataGoDesktop ?? KataGoDesktopService(),
       _board = BoardState(size: boardSize, komi: komi),
       _lookupVisits = defaultLookupVisits,
       _computeVisits = defaultComputeVisits,
       _availableLookupVisits = availableLookupVisits,
       _availableComputeVisits = availableComputeVisits;

  // Getters
  BoardState get board => _board;
  AnalysisResult? get lastAnalysis => _lastAnalysis;
  AnalysisSource get lastAnalysisSource => _lastAnalysisSource;
  bool get isAnalyzing => _isAnalyzing;
  String? get error => _error;
  ConnectionStatus get connectionStatus => _connectionStatus;
  int get lookupVisits => _lookupVisits;
  int get computeVisits => _computeVisits;
  bool get isOnline => _connectionStatus == ConnectionStatus.online;
  bool get isOpeningBookLoaded => _openingBookLoaded;
  OpeningBookService get openingBook => _openingBook;

  // Local engine getters
  bool get localEngineEnabled => _localEngineEnabled;
  bool get localEngineRunning {
    // Android: check inference engine
    if (!kIsWeb && Platform.isAndroid && _inferenceEngine != null) {
      return _inferenceEngine!.isRunning;
    }
    // Desktop/iOS: check KataGo services
    return _isDesktop ? _kataGoDesktop.isRunning : _kataGo.isRunning;
  }
  String? get engineError => _engineError;
  AnalysisProgress? get analysisProgress => _analysisProgress;
  DesktopAnalysisProgress? get desktopAnalysisProgress =>
      _desktopAnalysisProgress;
  KataGoService get kataGoService => _kataGo;
  KataGoDesktopService get kataGoDesktopService => _kataGoDesktop;
  bool get showMoveNumbers => _showMoveNumbers;

  // Move confirmation getters
  bool get moveConfirmationEnabled => _moveConfirmationEnabled;
  BoardPoint? get pendingMove => _pendingMove;

  // Platform detection
  bool get _isDesktop =>
      !kIsWeb && (Platform.isMacOS || Platform.isWindows || Platform.isLinux);

  /// Initialize the provider
  Future<void> init() async {
    // Load opening book first (for instant offline access)
    await _loadOpeningBook();

    // Initialize local cache
    await _cache.init();

    // Check server connection (non-blocking for UI)
    checkConnection();

    // KataGo engine starts lazily on first analysis request (not in opening book).
    // Eager startup during init causes HWUI mutex crash on some Qualcomm/Adreno devices
    // because the native library thread creation conflicts with GPU driver initialization.

    // Trigger initial analysis (for empty board)
    // Use validation to prevent race conditions
    if (_lastAnalysis == null) {
      analyze();
    }
  }

  /// Initialize local inference engine (platform-specific)
  Future<void> _initLocalEngine() async {
    if (!_localEngineEnabled) return;

    // On Android, use new inference engine (ONNX Runtime)
    if (!kIsWeb && Platform.isAndroid) {
      try {
        _inferenceEngine ??= createInferenceEngine();
        final success = await _inferenceEngine!.start(boardSize: _board.size);
        debugPrint(success
            ? 'Android inference engine started: ${_inferenceEngine!.engineName}'
            : 'Android inference engine failed to start');
        if (success) {
          _engineError = null;
        }
        notifyListeners();
        return;
      } catch (e) {
        _engineError = e.toString();
        debugPrint('Error starting Android inference engine: $e');
        return;
      }
    }

    // Desktop/iOS: use original KataGo
    try {
      bool success;
      if (_isDesktop) {
        // Extract assets for Desktop KataGo
        final appDir = await getApplicationSupportDirectory();
        final katagoDir = Directory(path.join(appDir.path, 'katago'));
        if (!await katagoDir.exists()) {
          await katagoDir.create(recursive: true);
        }

        final configPath = await _extractAsset(
          'assets/katago/analysis.cfg',
          path.join(katagoDir.path, 'analysis.cfg'),
        );

        final modelPath = await _extractAsset(
          'assets/katago/model.bin.gz',
          path.join(katagoDir.path, 'model.bin.gz'),
        );

        success = await _kataGoDesktop.start(
          configPath: configPath,
          modelPath: modelPath,
        );
        debugPrint(
          success ? 'Desktop KataGo started' : 'Desktop KataGo failed',
        );
      } else {
        success = await _kataGo.start();
        debugPrint(success ? 'Mobile KataGo started' : 'Mobile KataGo failed');
      }
      if (success) {
        _engineError = null;
      }
      notifyListeners();
    } catch (e) {
      _engineError = e.toString();
      debugPrint('Error starting local engine: $e');
    }
  }

  /// Ensure the local engine is started, attempting a restart if needed.
  /// Returns true if the engine is running after the attempt.
  Future<bool> _ensureEngineStarted() async {
    if (localEngineRunning) return true;
    await _initLocalEngine();
    return localEngineRunning;
  }

  /// Restart the local engine (stop then start).
  /// Returns true if the engine is running after the restart.
  Future<bool> restartEngine() async {
    if (_isDesktop) {
      await _kataGoDesktop.stop();
    } else {
      await _kataGo.stop();
    }
    await _initLocalEngine();
    return localEngineRunning;
  }

  /// Helper to extract bundled asset to filesystem
  Future<String> _extractAsset(String assetPath, String targetPath) async {
    final file = File(targetPath);
    if (!await file.exists()) {
      try {
        final data = await rootBundle.load(assetPath);
        await file.writeAsBytes(
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        );
      } catch (e) {
        debugPrint('Error extracting asset $assetPath: $e');
        // Return target path anyway, maybe it exists or service handles missing file
      }
    }
    return targetPath;
  }

  /// Load bundled opening book
  Future<void> _loadOpeningBook() async {
    try {
      await _openingBook.load();
      _openingBookLoaded = _openingBook.isLoaded;
      if (_openingBook.isLoaded) {
        debugPrint('Opening book loaded: ${_openingBook.totalEntries} entries');
        debugPrint('Breakdown: ${_openingBook.entriesByBoardSize}');
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
    _connectionStatus = isHealthy
        ? ConnectionStatus.online
        : ConnectionStatus.offline;
    notifyListeners();
  }

  /// Toggle local engine
  void setLocalEngineEnabled(bool enabled) {
    _localEngineEnabled = enabled;
    if (enabled && !localEngineRunning) {
      _initLocalEngine();
    } else if (!enabled) {
      if (_isDesktop) {
        _kataGoDesktop.stop();
      } else {
        _kataGo.stop();
      }
    }
    notifyListeners();
  }

  /// Toggle move numbers on stones
  void setShowMoveNumbers(bool show) {
    _showMoveNumbers = show;
    notifyListeners();
  }

  /// Toggle move confirmation mode
  void setMoveConfirmationEnabled(bool enabled) {
    _moveConfirmationEnabled = enabled;
    // Clear pending move when disabling
    if (!enabled) {
      _pendingMove = null;
    }
    notifyListeners();
  }

  /// Set pending move (preview before confirmation)
  void setPendingMove(BoardPoint? point) {
    // Only allow pending move if the position is empty
    if (point != null && !_board.isEmpty(point.x, point.y)) {
      return;
    }
    _pendingMove = point;
    notifyListeners();
  }

  /// Move pending move in a direction (for adjustment)
  void movePendingMove(int dx, int dy) {
    if (_pendingMove == null) return;

    final newX = (_pendingMove!.x + dx).clamp(0, _board.size - 1);
    final newY = (_pendingMove!.y + dy).clamp(0, _board.size - 1);
    final newPoint = BoardPoint(newX, newY);

    // Only move if the new position is empty
    if (_board.isEmpty(newX, newY)) {
      _pendingMove = newPoint;
      notifyListeners();
    }
  }

  /// Confirm and place the pending move
  Future<void> confirmPendingMove() async {
    if (_pendingMove == null) return;

    final point = _pendingMove!;
    _pendingMove = null;
    notifyListeners();

    // Place the stone
    await placeStone(point);
  }

  /// Cancel pending move
  void cancelPendingMove() {
    _pendingMove = null;
    notifyListeners();
  }

  /// Set board size
  void setBoardSize(int size) {
    if (size != _board.size) {
      _board = BoardState(
        size: size,
        komi: _board.komi,
        handicap: _board.handicap,
      );
      _lastAnalysis = null;
      _lastAnalysisSource = AnalysisSource.none;
      _analysisProgress = null;
      _desktopAnalysisProgress = null;
      _error = null;
      notifyListeners();
      
      // Trigger new analysis for the new board size
      analyze();
    }
  }

  /// Set komi
  void setKomi(double komi) {
    _board.komi = komi;
    _lastAnalysis = null;
    _lastAnalysisSource = AnalysisSource.none;
    notifyListeners();
  }

  /// Set lookup visits threshold (for DB/book queries)
  void setLookupVisits(int visits) {
    if (_availableLookupVisits.contains(visits)) {
      _lookupVisits = visits;
      notifyListeners();
    }
  }

  /// Set compute visits (for live KataGo analysis)
  void setComputeVisits(int visits) {
    if (_availableComputeVisits.contains(visits)) {
      _computeVisits = visits;
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
    _desktopAnalysisProgress = null;
    _error = null;
    notifyListeners();

    await analyze();
  }

  /// Analyze current position (offline-first with opening book)
  Future<void> analyze({bool forceRefresh = false}) async {
    if (_isAnalyzing) return;

    _isAnalyzing = true;
    _error = null;
    _analysisProgress = null;
    _desktopAnalysisProgress = null;
    notifyListeners();

    try {
      final boardHash = _computeSimpleHash();

      // Test mode disabled - opening book works perfectly
      const bool FORCE_NATIVE_TEST = false;

      // Step 1: Try bundled opening book first
      if (!FORCE_NATIVE_TEST && !forceRefresh && _openingBookLoaded) {
        final bookResult = await _openingBook.lookupByMoves(
          _board.size,
          _board.komi,
          _board.movesGtp,
        );
        if (bookResult != null) {
          debugPrint('[GameProvider] Opening book returned ${bookResult.topMoves.length} moves:');
          for (final move in bookResult.topMoves) {
            debugPrint('  ${move.move}: Win=${move.winratePercent} Lead=${move.scoreLeadFormatted}');
          }
          _lastAnalysis = bookResult;
          _lastAnalysisSource = AnalysisSource.openingBook;
          _isAnalyzing = false;
          notifyListeners();
          return;
        }
      }

      if (FORCE_NATIVE_TEST) {
        debugPrint('[TEST] === FORCING NATIVE ENGINE (SKIP OPENING BOOK) ===');
      }

      // Step 2: Cache lookup disabled — only use opening book + live engine
      // if (!forceRefresh) {
      //   final cachedResult = await _cache.get(
      //     boardHash: boardHash,
      //     komi: _board.komi,
      //   );
      //   if (cachedResult != null) {
      //     _lastAnalysis = cachedResult;
      //     _lastAnalysisSource = AnalysisSource.localCache;
      //     _isAnalyzing = false;
      //     notifyListeners();
      //     return;
      //   }
      // }

      // Step 3: Try local engine (Offline-first key principle)
      debugPrint('[GameProvider] Step 3: localEngineEnabled=$_localEngineEnabled, isAndroid=${!kIsWeb && Platform.isAndroid}');
      if (_localEngineEnabled) {
        debugPrint('[GameProvider] Calling _ensureEngineStarted()...');
        final engineReady = await _ensureEngineStarted();
        debugPrint('[GameProvider] Engine ready: $engineReady, inferenceEngine=$_inferenceEngine, isRunning=${_inferenceEngine?.isRunning}');
        if (engineReady) {
          debugPrint('[GameProvider] Engine is ready, choosing analysis method...');
          // Android: use inference engine
          if (!kIsWeb && Platform.isAndroid && _inferenceEngine != null) {
            await _analyzeWithInferenceEngine();
          } else if (_isDesktop) {
            await _analyzeWithDesktopEngine();
          } else {
            await _analyzeWithMobileEngine();
          }
          return;
        }
      }

      // Step 4: Try API only as a last resort (or disabled in pure offline mode)
      if (_connectionStatus == ConnectionStatus.online) {
        try {
          final result = await _api.analyze(
            boardSize: _board.size,
            moves: _board.movesGtp,
            handicap: _board.handicap,
            komi: _board.komi,
            visits: _lookupVisits,
          );

          _lastAnalysis = result;
          _lastAnalysisSource = AnalysisSource.api;
          // Cache save disabled
          // await _cache.put(result);
          _isAnalyzing = false;
          notifyListeners();
          return;
        } on ApiException catch (e) {
          debugPrint('API error: ${e.message}');
        }
      }

      // Step 5: No analysis available
      final parts = <String>['Position not in opening book/cache'];
      if (_localEngineEnabled && !localEngineRunning) {
        parts.add('local engine enabled but not running${_engineError != null ? ' ($_engineError)' : ''}');
      } else if (!_localEngineEnabled) {
        parts.add('local engine disabled');
      }
      if (_connectionStatus != ConnectionStatus.online) {
        parts.add('API offline');
      }
      _error = parts.join('; ');
      _lastAnalysisSource = AnalysisSource.none;
    } catch (e) {
      _error = 'Error: $e';
      _lastAnalysisSource = AnalysisSource.none;
    } finally {
      _isAnalyzing = false;
      notifyListeners();
    }
  }

  /// Analyze using inference engine (Android ONNX Runtime)
  Future<void> _analyzeWithInferenceEngine() async {
    try {
      debugPrint('[GameProvider] Using inference engine for analysis');
      final result = await _inferenceEngine!.analyze(
        boardSize: _board.size,
        moves: _board.movesGtp,
        komi: _board.komi,
        maxVisits: _computeVisits,
      ).timeout(
        const Duration(seconds: 120),
        onTimeout: () => throw TimeoutException('Engine analysis timed out after 120s'),
      );

      // Convert EngineAnalysisResult to AnalysisResult
      _lastAnalysis = AnalysisResult(
        boardHash: _computeSimpleHash(),
        boardSize: _board.size,
        komi: _board.komi,
        movesSequence: _board.movesGtp.join(' '),
        topMoves: result.topMoves,
        engineVisits: result.visits,
        modelName: result.modelName,
        fromCache: false,
        timestamp: DateTime.now().toIso8601String(),
      );
      _lastAnalysisSource = AnalysisSource.localEngine;
      _isAnalyzing = false;

      // Cache save disabled
      // await _cache.put(_lastAnalysis!);

      notifyListeners();
      debugPrint('[GameProvider] Inference engine analysis complete');
    } catch (e) {
      _error = 'Inference engine error: $e';
      _isAnalyzing = false;
      notifyListeners();
      debugPrint('[GameProvider] Inference engine analysis failed: $e');
    }
  }

  /// Analyze using mobile KataGo engine (platform channel)
  Future<void> _analyzeWithMobileEngine() async {
    final completer = Completer<void>();

    await _kataGo.analyze(
      boardSize: _board.size,
      moves: _board.movesGtp,
      komi: _board.komi,
      maxVisits: _computeVisits,
      onProgress: (progress) {
        _analysisProgress = progress;
        notifyListeners();
      },
      onResult: (result) {
        _lastAnalysis = result;
        _lastAnalysisSource = AnalysisSource.localEngine;
        _analysisProgress = null;
        _isAnalyzing = false;
        
        // Cache save disabled
        // _cache.put(result);
        
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

    try {
      await completer.future.timeout(
        const Duration(seconds: 120),
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

  /// Analyze using desktop KataGo engine (subprocess)
  Future<void> _analyzeWithDesktopEngine() async {
    final completer = Completer<void>();

    await _kataGoDesktop.analyze(
      boardSize: _board.size,
      moves: _board.movesGtp,
      komi: _board.komi,
      maxVisits: _computeVisits,
      onProgress: (progress) {
        _desktopAnalysisProgress = progress;
        notifyListeners();
      },
      onResult: (result) {
        _lastAnalysis = result;
        _lastAnalysisSource = AnalysisSource.localEngine;
        _desktopAnalysisProgress = null;
        _isAnalyzing = false;
        // Cache save disabled
        // _cache.put(result);
        notifyListeners();
        if (!completer.isCompleted) completer.complete();
      },
      onError: (error) {
        _error = 'Desktop engine error: $error';
        _isAnalyzing = false;
        notifyListeners();
        if (!completer.isCompleted) completer.complete();
      },
    );

    try {
      await completer.future.timeout(
        const Duration(seconds: 120),
        onTimeout: () {
          _kataGoDesktop.cancelAnalysis();
          _error = 'Analysis timed out';
          _isAnalyzing = false;
          notifyListeners();
        },
      );
    } catch (e) {
      debugPrint('Desktop analysis error: $e');
    }
  }

  /// Cancel ongoing analysis
  Future<void> cancelAnalysis() async {
    if (!_isAnalyzing) return;

    if (_isDesktop) {
      await _kataGoDesktop.cancelAnalysis();
    } else {
      await _kataGo.cancelAnalysis();
    }
    _isAnalyzing = false;
    _analysisProgress = null;
    _desktopAnalysisProgress = null;
    _error = 'Analysis cancelled';
    notifyListeners();
  }

  /// Compute a stable MD5 hash for the current board position
  String _computeSimpleHash() {
    final movesStr = _board.movesGtp.join(';');
    final data = '${_board.size}:${_board.komi}:$movesStr';
    return md5.convert(utf8.encode(data)).toString();
  }

  /// Undo last move
  void undo() {
    if (_board.undo()) {
      _lastAnalysis = null;
      _lastAnalysisSource = AnalysisSource.none;
      _analysisProgress = null;
      _desktopAnalysisProgress = null;
      _error = null;
      notifyListeners();
      
      analyze();
    }
  }

  /// Clear the board
  void clear() {
    if (_isAnalyzing) {
      cancelAnalysis();
    }
    _board.clear();
    _lastAnalysis = null;
    _lastAnalysisSource = AnalysisSource.none;
    _analysisProgress = null;
    _desktopAnalysisProgress = null;
    _error = null;
    notifyListeners();
    
    analyze();
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
        'running': localEngineRunning,
        'is_desktop': _isDesktop,
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
    _kataGoDesktop.dispose();
    _api.dispose();
    _cache.close();
    _openingBook.clear();
    super.dispose();
  }
}
