/// Opening book service for offline-first analysis.
///
/// Loads bundled opening book data from assets and provides
/// fast lookups without network access.
library;

import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart' show rootBundle;
import '../models/models.dart';

/// Entry in the opening book (compact format from export)
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

  factory OpeningBookEntry.fromJson(Map<String, dynamic> json) {
    final topMovesJson = json['t'] as List;
    return OpeningBookEntry(
      hash: json['h'] as String,
      boardSize: json['s'] as int,
      komi: (json['k'] as num).toDouble(),
      movesSequence: json['m'] as String? ?? '',
      topMoves: topMovesJson
          .map((m) => MoveCandidate.fromJson(m as Map<String, dynamic>))
          .toList(),
      visits: json['v'] as int,
    );
  }

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

/// Service for managing bundled opening book data
class OpeningBookService {
  static const String _assetPath = 'assets/opening_book.json';
  static const String _compressedAssetPath = 'assets/opening_book.json.gz';

  /// In-memory index: hash -> entry (for Zobrist hash lookups)
  final Map<String, OpeningBookEntry> _index = {};

  /// Secondary index: moves_sequence -> entry (for move-based lookups)
  final Map<String, OpeningBookEntry> _moveIndex = {};

  /// Statistics
  int _totalEntries = 0;
  Map<int, int> _entriesByBoardSize = {};
  bool _isLoaded = false;
  String? _loadError;

  // Getters
  bool get isLoaded => _isLoaded;
  int get totalEntries => _totalEntries;
  Map<int, int> get entriesByBoardSize => Map.unmodifiable(_entriesByBoardSize);
  String? get loadError => _loadError;

  /// Build a move-based lookup key
  /// Format: "size:komi:moves" e.g. "9:7.5:B[E5];W[C3]"
  String _buildMoveKey(int boardSize, double komi, String movesSequence) {
    return '$boardSize:$komi:$movesSequence';
  }

  /// Build a move key from GTP move list
  /// Converts ["B E5", "W C3"] to "9:7.5:B[E5];W[C3]"
  String buildMoveKeyFromGtp(int boardSize, double komi, List<String> moves) {
    final movesSequence = moves.map((m) {
      final parts = m.split(' ');
      if (parts.length == 2) {
        return '${parts[0]}[${parts[1]}]';
      }
      return m;
    }).join(';');
    return _buildMoveKey(boardSize, komi, movesSequence);
  }

  /// Load opening book from bundled assets
  ///
  /// This should be called once during app initialization.
  /// The data is loaded into memory for fast lookups.
  Future<void> load() async {
    if (_isLoaded) return;

    try {
      String jsonStr;

      // Try compressed version first
      try {
        final compressedData = await rootBundle.load(_compressedAssetPath);
        final bytes = compressedData.buffer.asUint8List();
        final decompressed = gzip.decode(bytes);
        jsonStr = utf8.decode(decompressed);
      } catch (e) {
        // Fall back to uncompressed version
        jsonStr = await rootBundle.loadString(_assetPath);
      }

      final data = jsonDecode(jsonStr) as Map<String, dynamic>;

      // Parse metadata
      final stats = data['stats'] as Map<String, dynamic>?;
      if (stats != null) {
        _totalEntries = stats['total_entries'] as int? ?? 0;
        final bySize = stats['by_board_size'] as Map<String, dynamic>?;
        if (bySize != null) {
          _entriesByBoardSize = bySize.map(
            (k, v) => MapEntry(int.parse(k), v as int),
          );
        }
      }

      // Parse entries and build indices
      final entries = data['entries'] as List;
      for (final entryJson in entries) {
        try {
          final entry =
              OpeningBookEntry.fromJson(entryJson as Map<String, dynamic>);
          // Index by hash - keep the one with highest visits
          final existing = _index[entry.hash];
          if (existing == null || existing.visits < entry.visits) {
            _index[entry.hash] = entry;
          }

          // Also index by moves sequence for alternative lookup
          final moveKey =
              _buildMoveKey(entry.boardSize, entry.komi, entry.movesSequence);
          final existingByMove = _moveIndex[moveKey];
          if (existingByMove == null || existingByMove.visits < entry.visits) {
            _moveIndex[moveKey] = entry;
          }
        } catch (e) {
          // Skip invalid entries
        }
      }

      _isLoaded = true;
      _loadError = null;
    } catch (e) {
      _loadError = 'Failed to load opening book: $e';
      _isLoaded = false;
    }
  }

  /// Look up analysis for a board position by hash
  ///
  /// Returns null if not found in the opening book.
  AnalysisResult? lookup(String boardHash) {
    if (!_isLoaded) return null;

    final entry = _index[boardHash];
    return entry?.toAnalysisResult();
  }

  /// Look up with komi filtering (by hash)
  ///
  /// Returns null if not found or komi doesn't match.
  AnalysisResult? lookupWithKomi(String boardHash, double komi) {
    if (!_isLoaded) return null;

    final entry = _index[boardHash];
    if (entry == null) return null;

    // Check komi (allow small tolerance for floating point)
    if ((entry.komi - komi).abs() > 0.1) return null;

    return entry.toAnalysisResult();
  }

  /// Look up by moves sequence (alternative to hash lookup)
  /// This is the primary lookup method for the mobile app since
  /// implementing Zobrist hash in Dart is complex.
  ///
  /// Args:
  ///   boardSize: Board size (9, 13, or 19)
  ///   komi: Komi value
  ///   moves: List of moves in GTP format ["B E5", "W C3"]
  ///
  /// Returns null if not found.
  AnalysisResult? lookupByMoves(
      int boardSize, double komi, List<String> moves) {
    if (!_isLoaded) return null;

    final moveKey = buildMoveKeyFromGtp(boardSize, komi, moves);
    final entry = _moveIndex[moveKey];
    return entry?.toAnalysisResult();
  }

  /// Check if a position exists in the opening book
  bool contains(String boardHash) {
    return _index.containsKey(boardHash);
  }

  /// Check if a position exists by moves
  bool containsByMoves(int boardSize, double komi, List<String> moves) {
    final moveKey = buildMoveKeyFromGtp(boardSize, komi, moves);
    return _moveIndex.containsKey(moveKey);
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
      'indexed_entries': _index.length,
      'move_indexed_entries': _moveIndex.length,
      'by_board_size': _entriesByBoardSize,
      'load_error': _loadError,
    };
  }

  /// Clear the in-memory index (for memory management)
  void clear() {
    _index.clear();
    _moveIndex.clear();
    _isLoaded = false;
    _totalEntries = 0;
    _entriesByBoardSize = {};
  }
}
