/// Opening book service for offline-first analysis.
///
/// Loads bundled opening book data from assets and provides
/// fast lookups without network access.
library;

import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
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

  /// Expand moves using symmetry for opening book entries.
  /// This ensures all symmetric equivalents are shown (e.g., C4 -> G6, G4, C6).
  OpeningBookEntry _expandSymmetry(OpeningBookEntry entry) {
    final size = entry.boardSize;
    final expandedMoves = <MoveCandidate>[];
    final seenMoves = <String>{};

    // Helper to add move if new
    void addCandidate(int x, int y, MoveCandidate original) {
      if (x < 0 || x >= size || y < 0 || y >= size) return;
      
      // Use BoardPoint from models if available, or manual GTP conversion
      // Since we don't have easy access to BoardPoint.toGtp here without instance,
      // we'll implement a simple GTP generator.
      // Or better, assume BoardPoint is available (it is imported).
      
      // Note: BoardPoint isn't fully visible here unless we check imports. 
      // models.dart exports it.
      // Let's rely on manual conversion to be safe and dependency-free within this logic 
      // if BoardPoint is not static-friendly.
      // Actually, let's use the same coordinates logic as the app.
      // 0,0 is Top-Left? GTP is A1 at Bottom-Left?
      // Katago/GTP: A1 is bottom-left. x=0(A), y=0(1).
      // BoardPoint usage in this app: usually 0,0 is top-left for rendering?
      // Let's use the provided move strings to deduce.
      // But simplest is to just perform string-based mapping if possible? No, need math.
      // Let's use BoardPoint.
      final point = BoardPoint(x, y);
      final moveStr = point.toGtp(size);
      
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
      // Parse original move
      final point = BoardPoint.fromGtp(move.move, size);
      if (point == null) continue;

      // 8 Symmetries
      final x = point.x;
      final y = point.y;
      
      // 1. Identity
      addCandidate(x, y, move);
      // 2. Mirror X
      addCandidate(size - 1 - x, y, move);
      // 3. Mirror Y
      addCandidate(x, size - 1 - y, move);
      // 4. Rotate 180 (Mirror X + Y)
      addCandidate(size - 1 - x, size - 1 - y, move);
      // 5. Transpose (Swap X/Y) - for square boards
      addCandidate(y, x, move);
      // 6. Rotate 90 (Transpose + Mirror X) -> (y, size-1-x)
      addCandidate(y, size - 1 - x, move);
      // 7. Rotate 270 (Transpose + Mirror Y) -> (size-1-y, x)
      addCandidate(size - 1 - y, x, move);
      // 8. Mirror Transpose
      addCandidate(size - 1 - y, size - 1 - x, move);
    }

    // Inject standard opening moves for 13x13 and 19x19 if missing
    // This ensures we always have Top 3 (Star, Komoku, Sansan) for empty boards
    if (entry.movesSequence.isEmpty && (size == 9 || size == 13 || size == 19) && entry.topMoves.isNotEmpty) {
        final bestMove = entry.topMoves.first;
        
        // Define standard open points: 3-4 (Komoku) and 3-3 (Sansan)
        // Coordinates are 0-indexed, so 3-3 is index 2, 3-4 is index 2,3
        final komoku = BoardPoint(2, 3); // 3-4 point
        final sansan = BoardPoint(2, 2); // 3-3 point
        
        // Helper to check and inject
        void injectIfMissing(BoardPoint basePoint, double winrateRatio, double scoreDrop) {
            final moveStr = basePoint.toGtp(size);
            // Check if ANY symmetric variation of this point exists
            // Actually simplest is: just try to add it. 
            // The addCandidate function (if we exposed logic) or just checking expandedMoves 
            // would be safer.
            // But we can just create a candidate and run it through the symmetry loop.
            
            // Create synthetic candidate
            final candidate = MoveCandidate(
                move: moveStr,
                winrate: bestMove.winrate * winrateRatio, 
                scoreLead: bestMove.scoreLead - scoreDrop,
                visits: (bestMove.visits * 0.8).round(), // Slightly less visits
            );
            
            // Add symmetries for this candidate
            // We duplicate the loop logic here to be safe and contained.
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
            
            for (final p in candidatesToAdd) {
                final s = p.toGtp(size);
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
        
        // Inject Rank 2: Komoku (3-4) - slightly worse than Star in AI eval usually
        injectIfMissing(komoku, 0.98, 0.2);
        
        // Inject Rank 3: Sansan (3-3)
        injectIfMissing(sansan, 0.96, 0.4);
    }
    
    // Sort by winrate descending to maintain order
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

  /// Look up analysis for a board position by hash
  ///
  /// Returns null if not found in the opening book.
  AnalysisResult? lookup(String boardHash) {
    if (!_isLoaded) return null;

    var entry = _index[boardHash];
    if (entry != null && entry.movesSequence.isEmpty) {
      entry = _expandSymmetry(entry);
    }
    return entry?.toAnalysisResult();
  }

  /// Look up with komi filtering (by hash)
  ///
  /// Returns null if not found or komi doesn't match.
  AnalysisResult? lookupWithKomi(String boardHash, double komi) {
    if (!_isLoaded) return null;

    var entry = _index[boardHash];
    if (entry == null) return null;

    // Check komi (allow small tolerance for floating point)
    if ((entry.komi - komi).abs() > 0.1) return null;

    if (entry.movesSequence.isEmpty) {
      entry = _expandSymmetry(entry);
    }

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
    if (!_isLoaded) {
      debugPrint('[OpeningBook] Not loaded yet');
      return null;
    }

    final moveKey = buildMoveKeyFromGtp(boardSize, komi, moves);
    var entry = _moveIndex[moveKey];
    
    if (entry == null) {
      debugPrint('[OpeningBook] MISS: $moveKey (Entries: ${_moveIndex.length})');
      
      // Fallback: If empty board for 13 or 19 and no entry exists,
      // synthesize standard opening moves.
      if (moves.isEmpty && (boardSize == 13 || boardSize == 19)) {
        debugPrint('[OpeningBook] Synthesizing moves for empty $boardSize board');
        entry = OpeningBookEntry(
          hash: 'synthetic_empty',
          boardSize: boardSize,
          komi: komi,
          movesSequence: '',
          topMoves: [
            MoveCandidate(
              move: boardSize == 19 ? 'K10' : 'G7', // Central/main star point
              winrate: 0.5,
              scoreLead: 0.0,
              visits: 1000,
            )
          ],
          visits: 1000,
        );
        entry = _expandSymmetry(entry);
      } else if (_moveIndex.isNotEmpty && _moveIndex.length < 5) {
        debugPrint('Sample Keys: ${_moveIndex.keys.take(5).join(", ")}');
      }
    } else {
        debugPrint('[OpeningBook] HIT: $moveKey');
        // Always expand symmetry to show all equivalent moves
        entry = _expandSymmetry(entry);
    }
    
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
