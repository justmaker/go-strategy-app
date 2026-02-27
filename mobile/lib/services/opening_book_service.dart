/// Opening book service for offline-first analysis.
///
/// Uses per-board-size SQLite databases with lazy loading and streaming
/// decompression to minimize memory usage (critical for iOS memory limits).
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import '../models/models.dart';

// Conditional import for FFI (desktop only, not web)
import 'cache_service_ffi_stub.dart'
    if (dart.library.io) 'cache_service_ffi.dart';

/// Entry in the opening book
class OpeningBookEntry {
  final String hash;
  final int boardSize;
  final double komi;
  final String movesSequence;
  final List<MoveCandidate> topMoves;
  final int visits;

  OpeningBookEntry({
    required this.hash,
    required this.boardSize,
    required this.komi,
    required this.movesSequence,
    required this.topMoves,
    required this.visits,
  });

  /// Convert to AnalysisResult for consistent API
  AnalysisResult toAnalysisResult() {
    return AnalysisResult(
      boardHash: hash,
      boardSize: boardSize,
      komi: komi,
      movesSequence: movesSequence,
      topMoves: topMoves,
      engineVisits: visits,
      modelName: 'bundled_opening_book',
      fromCache: true,
      timestamp: null,
    );
  }
}

/// Service for managing bundled opening book data via SQLite
class OpeningBookService {
  static const int _bundledVersion = 10;
  /// Per-board-size databases, lazily loaded on first query
  final Map<int, Database> _databases = {};

  /// Track which board sizes are currently being loaded (prevent concurrent loads)
  final Map<int, Future<void>> _loadingFutures = {};

  int _totalEntries = 0;
  Map<int, int> _entriesByBoardSize = {};
  bool _isLoaded = false;
  String? _loadError;
  String? _dbBasePath;
  bool _ffiInitialized = false;

  // Getters
  bool get isLoaded => _isLoaded;
  int get totalEntries => _totalEntries;
  Map<int, int> get entriesByBoardSize => Map.unmodifiable(_entriesByBoardSize);
  String? get loadError => _loadError;

  /// Asset path for a given board size
  static String _assetPath(int boardSize) =>
      'assets/data/opening_book_${boardSize}x$boardSize.db.gz';

  /// DB file name for a given board size
  static String _dbFileName(int boardSize) =>
      'opening_book_${boardSize}x$boardSize.db';

  /// Initialize service — resolves paths but does NOT decompress any DB.
  /// Actual DB extraction happens lazily on first query per board size.
  Future<void> load() async {
    if (_isLoaded) return;

    if (kIsWeb) {
      _loadError = 'SQLite not supported on web';
      return;
    }

    try {
      if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
        if (!_ffiInitialized) {
          initFfiDatabase();
          _ffiInitialized = true;
        }
        final appDir = await getApplicationSupportDirectory();
        _dbBasePath = appDir.path;
        final dir = Directory(_dbBasePath!);
        if (!await dir.exists()) {
          await dir.create(recursive: true);
        }
      } else {
        _dbBasePath = await getDatabasesPath();
      }

      _isLoaded = true;
      _loadError = null;
      debugPrint('[OpeningBook] Service initialized (lazy loading enabled)');
    } catch (e) {
      _loadError = 'Failed to initialize opening book: $e';
      _isLoaded = false;
      debugPrint('[OpeningBook] Init error: $e');
    }
  }

  /// Ensure a specific board size DB is loaded, extracting from assets if needed
  Future<void> _ensureBoardSizeLoaded(int boardSize) async {
    if (_databases.containsKey(boardSize)) return;

    // Prevent concurrent loads for the same board size
    if (_loadingFutures.containsKey(boardSize)) {
      await _loadingFutures[boardSize];
      return;
    }

    final future = _loadBoardSize(boardSize);
    _loadingFutures[boardSize] = future;
    try {
      await future;
    } finally {
      _loadingFutures.remove(boardSize);
    }
  }

  Future<void> _loadBoardSize(int boardSize) async {
    if (_dbBasePath == null) return;

    final dbPath = p.join(_dbBasePath!, _dbFileName(boardSize));
    final sw = Stopwatch()..start();

    debugPrint('[OpeningBook] Loading ${boardSize}x$boardSize DB...');

    await _extractAssetIfNeeded(boardSize, dbPath);

    final file = File(dbPath);
    if (!await file.exists() || await file.length() < 1024) {
      debugPrint('[OpeningBook] DB file not found for ${boardSize}x$boardSize');
      return;
    }

    final db = await openDatabase(dbPath, readOnly: false);
    _databases[boardSize] = db;

    await _ensureIndex(db, boardSize);
    await _loadStatsForBoardSize(db, boardSize);

    sw.stop();
    debugPrint(
        '[OpeningBook] ${boardSize}x$boardSize loaded in ${sw.elapsedMilliseconds}ms');
  }

  /// Extract a board-size-specific asset if not already present or outdated
  Future<void> _extractAssetIfNeeded(int boardSize, String targetPath) async {
    final targetFile = File(targetPath);
    final versionFile = File('$targetPath.version');

    if (await targetFile.exists() && await versionFile.exists()) {
      final currentVersion =
          int.tryParse(await versionFile.readAsString()) ?? 0;
      if (currentVersion >= _bundledVersion) {
        final size = await targetFile.length();
        debugPrint(
            '[OpeningBook] ${boardSize}x$boardSize DB exists '
            '(${(size / 1024 / 1024).toStringAsFixed(1)} MB), version $currentVersion');
        return;
      }
    }

    final assetPath = _assetPath(boardSize);
    debugPrint('[OpeningBook] Extracting ${boardSize}x$boardSize from $assetPath...');

    try {
      await _extractAssetStreaming(assetPath, targetPath);

      final decompressedSize = await targetFile.length();
      await versionFile.writeAsString(_bundledVersion.toString());
      debugPrint(
          '[OpeningBook] Extracted ${boardSize}x$boardSize '
          '(${(decompressedSize / 1024 / 1024).toStringAsFixed(1)} MB)');
    } catch (e) {
      debugPrint('[OpeningBook] Extraction failed for ${boardSize}x$boardSize: $e');
    }
  }

  /// Stream-decompress a gzipped asset to a target file.
  ///
  /// On iOS/macOS, reads directly from the bundle file path to avoid loading
  /// the entire compressed file into RAM via rootBundle.load(). This is
  /// critical for the 9x9 DB (~144 MB compressed, ~674 MB decompressed)
  /// which would cause iOS SIGKILL if loaded entirely into memory.
  Future<void> _extractAssetStreaming(String assetPath, String targetPath) async {
    // iOS/macOS: stream directly from bundle file path
    final bundlePath = _resolveAssetFilePath(assetPath);
    if (bundlePath != null && await File(bundlePath).exists()) {
      debugPrint('[OpeningBook] Streaming from bundle path: $bundlePath');
      final inputStream = File(bundlePath).openRead();
      final sink = File(targetPath).openWrite();
      await sink.addStream(GZipCodec().decoder.bind(inputStream));
      await sink.close();
      return;
    }

    // Fallback: rootBundle.load() — used on Android and other platforms.
    // Safe for small DBs (13x13, 19x19). For large DBs on memory-constrained
    // platforms, the streaming path above should be used.
    debugPrint('[OpeningBook] Fallback: rootBundle.load($assetPath)');
    final data = await rootBundle.load(assetPath);
    final gzBytes = data.buffer.asUint8List();
    debugPrint(
        '[OpeningBook] Loaded compressed asset '
        '(${(gzBytes.length / 1024 / 1024).toStringAsFixed(1)} MB), decompressing...');

    final sink = File(targetPath).openWrite();
    await sink.addStream(GZipCodec().decoder.bind(Stream.value(gzBytes)));
    await sink.close();
  }

  /// Resolve the actual file path for a Flutter asset in the platform bundle.
  /// Returns null on platforms where direct file access is not available.
  String? _resolveAssetFilePath(String assetPath) {
    if (Platform.isIOS) {
      final appDir = File(Platform.resolvedExecutable).parent.path;
      return '$appDir/Frameworks/App.framework/flutter_assets/$assetPath';
    } else if (Platform.isMacOS) {
      final appDir = File(Platform.resolvedExecutable).parent.path;
      return '$appDir/../Frameworks/App.framework/Resources/flutter_assets/$assetPath';
    }
    return null; // Android/Windows/Linux: use rootBundle fallback
  }

  /// Create index if it doesn't exist
  Future<void> _ensureIndex(Database db, int boardSize) async {
    try {
      final indices = await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='index' AND name='idx_lookup'");
      if (indices.isEmpty) {
        debugPrint('[OpeningBook] Creating index for ${boardSize}x$boardSize...');
        final sw = Stopwatch()..start();
        await db.execute(
            'CREATE INDEX idx_lookup ON opening_book(board_size, komi, moves_sequence)');
        sw.stop();
        debugPrint(
            '[OpeningBook] Index created in ${sw.elapsedMilliseconds}ms');
      }
    } catch (e) {
      debugPrint('[OpeningBook] Index creation failed: $e');
    }
  }

  /// Load stats from a single board-size database
  Future<void> _loadStatsForBoardSize(Database db, int boardSize) async {
    try {
      final metaRows = await db.rawQuery(
          "SELECT key, value FROM opening_book_meta WHERE key IN ('total_entries', 'by_board_size')");
      for (final row in metaRows) {
        final key = row['key'] as String;
        final value = row['value'] as String;
        if (key == 'total_entries') {
          final count = int.tryParse(value) ?? 0;
          _entriesByBoardSize[boardSize] = count;
          _totalEntries = _entriesByBoardSize.values.fold(0, (a, b) => a + b);
        }
      }
    } catch (e) {
      try {
        final countResult = await db
            .rawQuery('SELECT COUNT(*) as cnt FROM opening_book');
        final count = countResult.first['cnt'] as int;
        _entriesByBoardSize[boardSize] = count;
        _totalEntries = _entriesByBoardSize.values.fold(0, (a, b) => a + b);
      } catch (_) {}
    }
  }

  /// Build a move key from GTP move list (for debug logging)
  String buildMoveKeyFromGtp(int boardSize, double komi, List<String> moves) {
    final movesSequence = moves.map((m) {
      final parts = m.split(' ');
      if (parts.length == 2) {
        return '${parts[0]}[${parts[1]}]';
      }
      return m;
    }).join(';');
    return '$boardSize:$komi:$movesSequence';
  }

  /// Compute which symmetry transforms preserve the given stone positions.
  List<int> _computeValidSymmetries(int size, List<String> moves) {
    if (moves.isEmpty) {
      return [0, 1, 2, 3, 4, 5, 6, 7];
    }

    final stones = <Point<int>>[];
    for (final move in moves) {
      final parts = move.split(' ');
      if (parts.length != 2) continue;
      final point = BoardPoint.fromGtp(parts[1], size);
      if (point != null) {
        stones.add(Point(point.x, point.y));
      }
    }

    final validSymmetries = <int>[];
    for (int type = 0; type < 8; type++) {
      bool isValid = true;
      for (final stone in stones) {
        final transformed = _transformPoint(stone.x, stone.y, size, type);
        if (transformed.x != stone.x || transformed.y != stone.y) {
          isValid = false;
          break;
        }
      }
      if (isValid) {
        validSymmetries.add(type);
      }
    }

    return validSymmetries.isEmpty ? [0] : validSymmetries;
  }

  /// Expand moves using symmetry for display
  OpeningBookEntry _expandSymmetryWithMoves(
      OpeningBookEntry entry, List<String> existingMoves) {
    final size = entry.boardSize;
    final expandedMoves = <MoveCandidate>[];
    final seenMoves = <String>{};

    final validSymmetries = _computeValidSymmetries(size, existingMoves);

    final occupiedPositions = <String>{};
    for (final move in existingMoves) {
      final parts = move.split(' ');
      if (parts.length == 2) {
        occupiedPositions.add(parts[1]);
      }
    }

    void addCandidate(int x, int y, MoveCandidate original) {
      if (x < 0 || x >= size || y < 0 || y >= size) return;
      final point = BoardPoint(x, y);
      final moveStr = point.toGtp(size);
      if (occupiedPositions.contains(moveStr)) return;
      if (!seenMoves.contains(moveStr)) {
        seenMoves.add(moveStr);
        expandedMoves.add(MoveCandidate(
          move: moveStr,
          winrate: original.winrate,
          scoreLead: original.scoreLead,
          visits: original.visits,
        ));
      }
    }

    for (final move in entry.topMoves) {
      final point = BoardPoint.fromGtp(move.move, size);
      if (point == null) continue;

      for (final symType in validSymmetries) {
        final transformed =
            _transformPoint(point.x, point.y, size, symType);
        addCandidate(transformed.x, transformed.y, move);
      }
    }

    // Inject standard opening moves for empty boards
    if (entry.movesSequence.isEmpty &&
        (size == 9 || size == 13 || size == 19) &&
        entry.topMoves.isNotEmpty) {
      final bestMove = entry.topMoves.first;

      void injectIfMissing(
          BoardPoint basePoint, double winrateRatio, double scoreDrop) {
        final candidate = MoveCandidate(
          move: basePoint.toGtp(size),
          winrate: bestMove.winrate * winrateRatio,
          scoreLead: bestMove.scoreLead - scoreDrop,
          visits: (bestMove.visits * 0.8).round(),
        );

        final x = basePoint.x;
        final y = basePoint.y;

        final candidatesToAdd = [
          BoardPoint(x, y),
          BoardPoint(size - 1 - x, y),
          BoardPoint(x, size - 1 - y),
          BoardPoint(size - 1 - x, size - 1 - y),
          BoardPoint(y, x),
          BoardPoint(y, size - 1 - x),
          BoardPoint(size - 1 - y, x),
          BoardPoint(size - 1 - y, size - 1 - x),
        ];

        for (final pt in candidatesToAdd) {
          final s = pt.toGtp(size);
          if (!seenMoves.contains(s)) {
            seenMoves.add(s);
            expandedMoves.add(MoveCandidate(
              move: s,
              winrate: candidate.winrate,
              scoreLead: candidate.scoreLead,
              visits: candidate.visits,
            ));
          }
        }
      }

      // 4-4 star point (hoshi) — standard opening for 13x13 and 19x19
      // Use slightly higher winrate than DB komoku to form a separate rank
      if (size >= 13) {
        injectIfMissing(const BoardPoint(3, 3), 1.02, -0.1);
      }
      // 3-4 komoku
      injectIfMissing(const BoardPoint(2, 3), 0.98, 0.2);
      // 3-3 san-san
      injectIfMissing(const BoardPoint(2, 2), 0.96, 0.4);
    }

    // Sort by current player's winrate (best moves first), with visits as
    // tiebreaker. Winrate is stored from Black's perspective.
    final moveCount = entry.movesSequence.isEmpty
        ? 0
        : entry.movesSequence.split(';').length;
    final isBlackTurn = moveCount % 2 == 0;

    expandedMoves.sort((a, b) {
      final aPlayerWr = isBlackTurn ? a.winrate : 1.0 - a.winrate;
      final bPlayerWr = isBlackTurn ? b.winrate : 1.0 - b.winrate;
      // Primary: higher winrate first
      final wrCmp = bPlayerWr.compareTo(aPlayerWr);
      if (wrCmp != 0) return wrCmp;
      // Secondary: higher score lead first (from Black's perspective, matching display)
      final leadCmp = b.scoreLead.compareTo(a.scoreLead);
      if (leadCmp != 0) return leadCmp;
      // Tertiary: more visits first
      return b.visits.compareTo(a.visits);
    });

    return OpeningBookEntry(
      hash: entry.hash,
      boardSize: entry.boardSize,
      komi: entry.komi,
      movesSequence: entry.movesSequence,
      topMoves: expandedMoves,
      visits: entry.visits,
    );
  }

  OpeningBookEntry _expandSymmetry(OpeningBookEntry entry) {
    return _expandSymmetryWithMoves(entry, []);
  }

  /// Transform a GTP move string based on symmetry type (0-7)
  String _transformGtp(String move, int boardSize, int type) {
    if (move == 'pass' || move.isEmpty) return move;

    String? color;
    String coordStr;

    if (move.contains('[')) {
      final parts = move.split('[');
      color = parts[0];
      coordStr = parts[1].replaceAll(']', '');
    } else {
      final parts = move.split(' ');
      if (parts.length == 2) {
        color = parts[0];
        coordStr = parts[1];
      } else {
        coordStr = move;
      }
    }

    final point = BoardPoint.fromGtp(coordStr, boardSize);
    if (point == null) return move;

    final tPoint = _transformPoint(point.x, point.y, boardSize, type);
    final tCoord =
        BoardPoint(tPoint.x.toInt(), tPoint.y.toInt()).toGtp(boardSize);

    if (color != null) {
      if (move.contains('[')) {
        return '$color[$tCoord]';
      } else {
        return '$color $tCoord';
      }
    }
    return tCoord;
  }

  /// Transform coordinates (0-indexed)
  Point<int> _transformPoint(int x, int y, int size, int type) {
    switch (type) {
      case 0:
        return Point(x, y);
      case 1:
        return Point(y, size - 1 - x);
      case 2:
        return Point(size - 1 - x, size - 1 - y);
      case 3:
        return Point(size - 1 - y, x);
      case 4:
        return Point(size - 1 - x, y);
      case 5:
        return Point(x, size - 1 - y);
      case 6:
        return Point(y, x);
      case 7:
        return Point(size - 1 - y, size - 1 - x);
      default:
        return Point(x, y);
    }
  }

  /// Get the inverse symmetry type
  int _getInverseSymmetry(int type) {
    switch (type) {
      case 1:
        return 3;
      case 3:
        return 1;
      default:
        return type;
    }
  }

  /// Parse compact top_moves JSON from SQLite: [{m, w, s, v}, ...]
  List<MoveCandidate> _parseCompactTopMoves(String jsonStr) {
    final list = jsonDecode(jsonStr) as List;
    return list.map((item) {
      final m = item as Map<String, dynamic>;
      return MoveCandidate(
        move: m['m'] as String,
        winrate: (m['w'] as num).toDouble(),
        scoreLead: (m['s'] as num).toDouble(),
        visits: m['v'] as int,
      );
    }).toList();
  }

  /// Look up analysis by moves sequence using SQLite with symmetry search
  Future<AnalysisResult?> lookupByMoves(
      int boardSize, double komi, List<String> moves) async {
    if (!_isLoaded) {
      return null;
    }

    // Lazy load the DB for this board size
    await _ensureBoardSizeLoaded(boardSize);
    final db = _databases[boardSize];
    if (db == null) {
      return null;
    }

    debugPrint(
        '[OpeningBook] Looking up: ${moves.length} moves, ${boardSize}x$boardSize');

    // Try all 8 symmetry transformations, pick the one with highest visits
    int bestSymType = -1;
    int bestVisits = -1;
    List<MoveCandidate>? bestTopMoves;

    for (int type = 0; type < 8; type++) {
      final tMoves =
          moves.map((m) => _transformGtp(m, boardSize, type)).toList();

      // Build the moves_sequence string matching DB format: "B[Q16];W[D4]"
      final movesSequence = tMoves.map((m) {
        final parts = m.split(' ');
        return parts.length == 2 ? '${parts[0]}[${parts[1]}]' : m;
      }).join(';');

      try {
        final results = await db.rawQuery(
          'SELECT top_moves, visits FROM opening_book '
          'WHERE board_size = ? AND komi = ? AND moves_sequence = ? '
          'ORDER BY visits DESC LIMIT 1',
          [boardSize, komi, movesSequence],
        );

        if (results.isNotEmpty) {
          final row = results.first;
          final visits = row['visits'] as int;
          debugPrint('[OpeningBook] HIT on symmetry $type (visits=$visits)');

          if (visits > bestVisits) {
            bestVisits = visits;
            bestSymType = type;
            bestTopMoves =
                _parseCompactTopMoves(row['top_moves'] as String);
          }
        }
      } catch (e) {
        debugPrint('[OpeningBook] Query error on sym$type: $e');
      }
    }

    if (bestTopMoves != null) {
      debugPrint('[OpeningBook] Best match: symmetry $bestSymType (visits=$bestVisits)');

      // Inverse-transform result moves back to original orientation
      final inverseType = _getInverseSymmetry(bestSymType);
      final transformedMoves = bestTopMoves.map((m) {
        final tMove = _transformGtp(m.move, boardSize, inverseType);
        return MoveCandidate(
          move: tMove,
          winrate: m.winrate,
          scoreLead: m.scoreLead,
          visits: m.visits,
        );
      }).toList();

      final entry = OpeningBookEntry(
        hash: '',
        boardSize: boardSize,
        komi: komi,
        movesSequence: moves.join(';'),
        topMoves: transformedMoves,
        visits: bestVisits,
      );

      final finalEntry = _expandSymmetryWithMoves(entry, moves);

      return AnalysisResult(
        boardHash: '',
        boardSize: boardSize,
        komi: komi,
        movesSequence: moves.join(';'),
        topMoves: finalEntry.topMoves,
        engineVisits: finalEntry.visits,
        modelName: 'bundled_opening_book (sym$bestSymType)',
        fromCache: true,
      );
    }

    debugPrint('[OpeningBook] MISS after checking all symmetries');

    // Synthesize for empty board if missed
    if (moves.isEmpty && (boardSize == 13 || boardSize == 19)) {
      debugPrint(
          '[OpeningBook] Synthesizing moves for empty $boardSize board');
      final entry = OpeningBookEntry(
        hash: 'synthetic_empty',
        boardSize: boardSize,
        komi: komi,
        movesSequence: '',
        topMoves: [
          MoveCandidate(
            move: boardSize == 19 ? 'K10' : 'G7',
            winrate: 0.5,
            scoreLead: 0.0,
            visits: 1000,
          )
        ],
        visits: 1000,
      );
      return _expandSymmetry(entry).toAnalysisResult();
    }

    return null;
  }

  /// Get count of entries for a specific board size
  int countForBoardSize(int boardSize) {
    return _entriesByBoardSize[boardSize] ?? 0;
  }

  /// Get statistics about the loaded opening book
  Map<String, dynamic> getStats() {
    return {
      'is_loaded': _isLoaded,
      'total_entries': _totalEntries,
      'by_board_size': _entriesByBoardSize,
      'loaded_board_sizes': _databases.keys.toList(),
      'load_error': _loadError,
    };
  }

  /// Clear resources
  void clear() {
    for (final db in _databases.values) {
      db.close();
    }
    _databases.clear();
    _loadingFutures.clear();
    _isLoaded = false;
    _totalEntries = 0;
    _entriesByBoardSize = {};
  }
}
