/// Opening book service for offline-first analysis.
///
/// Uses a bundled SQLite database for memory-efficient lookups
/// without loading all data into memory.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
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
  static const String _bundledDbAsset = 'assets/data/opening_book.db.gz';
  static const String _dbName = 'opening_book_v1.db';
  static const int _bundledVersion = 1;

  Database? _database;
  int _totalEntries = 0;
  Map<int, int> _entriesByBoardSize = {};
  bool _isLoaded = false;
  String? _loadError;

  // Getters
  bool get isLoaded => _isLoaded;
  int get totalEntries => _totalEntries;
  Map<int, int> get entriesByBoardSize => Map.unmodifiable(_entriesByBoardSize);
  String? get loadError => _loadError;

  /// Load opening book database from bundled assets
  Future<void> load() async {
    if (_isLoaded) return;

    if (kIsWeb) {
      _loadError = 'SQLite not supported on web';
      return;
    }

    try {
      String dbPath;

      if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
        initFfiDatabase();
        final appDir = await getApplicationSupportDirectory();
        dbPath = appDir.path;
        final dir = Directory(dbPath);
        if (!await dir.exists()) {
          await dir.create(recursive: true);
        }
      } else {
        dbPath = await getDatabasesPath();
      }

      final path = p.join(dbPath, _dbName);
      await _copyBundledDbIfNeeded(path);

      final file = File(path);
      if (!await file.exists() || await file.length() < 1024) {
        _loadError = 'Opening book database not found';
        return;
      }

      _database = await openDatabase(path, readOnly: false);

      // Ensure index exists (created on first launch, not in bundled DB)
      await _ensureIndex();

      // Load stats
      await _loadStats();

      _isLoaded = true;
      _loadError = null;
    } catch (e) {
      _loadError = 'Failed to load opening book: $e';
      _isLoaded = false;
      debugPrint('[OpeningBook] Load error: $e');
    }
  }

  /// Copy bundled database if not already present
  Future<void> _copyBundledDbIfNeeded(String targetPath) async {
    final targetFile = File(targetPath);
    final versionFile = File('$targetPath.version');

    // Check if already extracted and up to date
    if (await targetFile.exists() && await versionFile.exists()) {
      final currentVersion =
          int.tryParse(await versionFile.readAsString()) ?? 0;
      if (currentVersion >= _bundledVersion) {
        final size = await targetFile.length();
        debugPrint(
            '[OpeningBook] DB exists (${(size / 1024 / 1024).toStringAsFixed(1)} MB), version $currentVersion');
        return;
      }
    }

    debugPrint('[OpeningBook] Extracting bundled opening book database...');

    try {
      final data = await rootBundle.load(_bundledDbAsset);
      final gzBytes = data.buffer.asUint8List();
      debugPrint(
          '[OpeningBook] Loaded compressed asset (${(gzBytes.length / 1024 / 1024).toStringAsFixed(1)} MB), decompressing...');

      // Stream-decompress gzip to file to avoid holding both compressed
      // and decompressed data in memory simultaneously
      final sink = targetFile.openWrite();
      await sink.addStream(
          GZipCodec().decoder.bind(Stream.value(gzBytes)));
      await sink.close();

      final decompressedSize = await targetFile.length();
      await versionFile.writeAsString(_bundledVersion.toString());
      debugPrint(
          '[OpeningBook] Extracted DB (${(decompressedSize / 1024 / 1024).toStringAsFixed(1)} MB)');
    } catch (e) {
      debugPrint('[OpeningBook] No bundled DB found: $e');
    }
  }

  /// Create index if it doesn't exist (not in bundled DB to save space)
  Future<void> _ensureIndex() async {
    if (_database == null) return;

    try {
      final indices = await _database!.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='index' AND name='idx_lookup'");
      if (indices.isEmpty) {
        debugPrint('[OpeningBook] Creating lookup index (one-time)...');
        final sw = Stopwatch()..start();
        await _database!.execute(
            'CREATE INDEX idx_lookup ON opening_book(board_size, komi, moves_sequence)');
        sw.stop();
        debugPrint(
            '[OpeningBook] Index created in ${sw.elapsedMilliseconds}ms');
      }
    } catch (e) {
      debugPrint('[OpeningBook] Index creation failed: $e');
    }
  }

  /// Load stats from metadata table
  Future<void> _loadStats() async {
    if (_database == null) return;

    try {
      final metaRows = await _database!.rawQuery(
          "SELECT key, value FROM opening_book_meta WHERE key IN ('total_entries', 'by_board_size')");
      for (final row in metaRows) {
        final key = row['key'] as String;
        final value = row['value'] as String;
        if (key == 'total_entries') {
          _totalEntries = int.tryParse(value) ?? 0;
        } else if (key == 'by_board_size') {
          final map = jsonDecode(value) as Map<String, dynamic>;
          _entriesByBoardSize =
              map.map((k, v) => MapEntry(int.parse(k), v as int));
        }
      }
    } catch (e) {
      try {
        final countResult = await _database!
            .rawQuery('SELECT COUNT(*) as cnt FROM opening_book');
        _totalEntries = countResult.first['cnt'] as int;
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

      injectIfMissing(const BoardPoint(2, 3), 0.98, 0.2);
      injectIfMissing(const BoardPoint(2, 2), 0.96, 0.4);
    }

    expandedMoves.sort((a, b) => b.winrate.compareTo(a.winrate));

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
    if (!_isLoaded || _database == null) {
      return null;
    }

    debugPrint(
        '[OpeningBook] Looking up: ${moves.length} moves, ${boardSize}x$boardSize');

    // Try all 8 symmetry transformations
    for (int type = 0; type < 8; type++) {
      final tMoves =
          moves.map((m) => _transformGtp(m, boardSize, type)).toList();

      // Build the moves_sequence string matching DB format: "B[Q16];W[D4]"
      final movesSequence = tMoves.map((m) {
        final parts = m.split(' ');
        return parts.length == 2 ? '${parts[0]}[${parts[1]}]' : m;
      }).join(';');

      try {
        final results = await _database!.rawQuery(
          'SELECT top_moves, visits FROM opening_book '
          'WHERE board_size = ? AND komi = ? AND moves_sequence = ? '
          'ORDER BY visits DESC LIMIT 1',
          [boardSize, komi, movesSequence],
        );

        if (results.isNotEmpty) {
          final row = results.first;
          debugPrint('[OpeningBook] HIT on symmetry $type');

          final topMoves =
              _parseCompactTopMoves(row['top_moves'] as String);
          final visits = row['visits'] as int;

          // Inverse-transform result moves back to original orientation
          final inverseType = _getInverseSymmetry(type);
          final transformedMoves = topMoves.map((m) {
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
            visits: visits,
          );

          final finalEntry = _expandSymmetryWithMoves(entry, moves);

          return AnalysisResult(
            boardHash: '',
            boardSize: boardSize,
            komi: komi,
            movesSequence: moves.join(';'),
            topMoves: finalEntry.topMoves,
            engineVisits: finalEntry.visits,
            modelName: 'bundled_opening_book (sym$type)',
            fromCache: true,
          );
        }
      } catch (e) {
        debugPrint('[OpeningBook] Query error on sym$type: $e');
      }
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
      'load_error': _loadError,
    };
  }

  /// Clear resources
  void clear() {
    _database?.close();
    _database = null;
    _isLoaded = false;
    _totalEntries = 0;
    _entriesByBoardSize = {};
  }
}
