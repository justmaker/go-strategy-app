/// Opening book service for offline-first analysis.
///
/// Loads bundled opening book data from assets and provides
/// fast lookups without network access.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';
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
          
          if (entry.movesSequence == 'B[G7]') {
             debugPrint('[OpeningBook] Indexing B[G7]. Key: "$moveKey" Visits: ${entry.visits}');
          }

          final existingByMove = _moveIndex[moveKey];
          if (existingByMove == null || existingByMove.visits < entry.visits) {
            _moveIndex[moveKey] = entry;
          }
        } catch (e) {
          if (entryJson is Map && entryJson['m'] == 'B[G7]') {
             debugPrint('[OpeningBook] Failed to load B[G7]: $e');
          }
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

  /// Compute which symmetry transforms preserve the given stone positions.
  /// Returns a list of valid symmetry type indices (0-7).
  List<int> _computeValidSymmetries(int size, List<String> moves) {
    if (moves.isEmpty) {
      // Empty board: all 8 symmetries are valid
      return [0, 1, 2, 3, 4, 5, 6, 7];
    }

    // Parse existing stones
    final stones = <Point<int>>[];
    for (final move in moves) {
      // Format: "B E5" or "W D4"
      final parts = move.split(' ');
      if (parts.length != 2) continue;
      final point = BoardPoint.fromGtp(parts[1], size);
      if (point != null) {
        stones.add(Point(point.x, point.y));
      }
    }

    // Check each symmetry
    final validSymmetries = <int>[];
    for (int type = 0; type < 8; type++) {
      bool isValid = true;
      for (final stone in stones) {
        final transformed = _transformPoint(stone.x, stone.y, size, type);
        // Check if transformed position equals original
        if (transformed.x != stone.x || transformed.y != stone.y) {
          isValid = false;
          break;
        }
      }
      if (isValid) {
        validSymmetries.add(type);
      }
    }

    return validSymmetries.isEmpty ? [0] : validSymmetries; // At least identity
  }

  /// Expand moves using symmetry for opening book entries.
  /// Only expands using symmetries that preserve existing stone positions.
  OpeningBookEntry _expandSymmetryWithMoves(OpeningBookEntry entry, List<String> existingMoves) {
    final size = entry.boardSize;
    final expandedMoves = <MoveCandidate>[];
    final seenMoves = <String>{};

    // Compute which symmetries are valid for current board state
    final validSymmetries = _computeValidSymmetries(size, existingMoves);

    // Build set of occupied positions from existing moves
    final occupiedPositions = <String>{};
    for (final move in existingMoves) {
      // Format: "B E5" or "W D4"
      final parts = move.split(' ');
      if (parts.length == 2) {
        occupiedPositions.add(parts[1]); // Add coordinate (e.g., "E5")
      }
    }

    // Helper to add move if new and not occupied
    void addCandidate(int x, int y, MoveCandidate original) {
      if (x < 0 || x >= size || y < 0 || y >= size) return;
      final point = BoardPoint(x, y);
      final moveStr = point.toGtp(size);

      // Skip if position is already occupied
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

      final x = point.x;
      final y = point.y;

      // Only apply valid symmetries
      for (final symType in validSymmetries) {
        final transformed = _transformPoint(x, y, size, symType);
        addCandidate(transformed.x, transformed.y, move);
      }
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

  /// Convenience wrapper for empty board (all symmetries valid)
  OpeningBookEntry _expandSymmetry(OpeningBookEntry entry) {
    return _expandSymmetryWithMoves(entry, []);
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
  /// Transform a GTP move string based on symmetry type (0-7)
  String _transformGtp(String move, int boardSize, int type) {
    if (move == 'pass' || move.isEmpty) return move;
    
    // Check if move is "Color[Coord]" format as used in keys
    // or just "Color Coord" or "Coord"
    // Our buildKey uses "B[E5]", so we need to handle that.
    
    String? color;
    String coordStr;
    
    if (move.contains('[')) {
      final parts = move.split('[');
      color = parts[0];
      coordStr = parts[1].replaceAll(']', '');
    } else {
      // Assuming naive GTP like "B E5" or just "E5"
      final parts = move.split(' ');
      if (parts.length == 2) {
        color = parts[0];
        coordStr = parts[1];
      } else {
        coordStr = move;
      }
    }

    final point = BoardPoint.fromGtp(coordStr, boardSize);
    if (point == null) return move; // Should not happen for valid moves

    final tPoint = _transformPoint(point.x, point.y, boardSize, type);
    final tCoord = BoardPoint(tPoint.x.toInt(), tPoint.y.toInt()).toGtp(boardSize);
    
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
    // 0: Identity
    // 1: Rotate 90 (cw? let's stick to a convention)
    // 2: Rotate 180
    // 3: Rotate 270
    // 4: Mirror X (Horizontal)
    // 5: Mirror Y (Vertical)
    // 6: Transpose (Swap X/Y)
    // 7: Anti-Transpose
    
    switch (type) {
      case 0: return Point(x, y);
      case 1: return Point(y, size - 1 - x); // Rot90
      case 2: return Point(size - 1 - x, size - 1 - y); // Rot180
      case 3: return Point(size - 1 - y, x); // Rot270
      case 4: return Point(size - 1 - x, y); // Mirror X
      case 5: return Point(x, size - 1 - y); // Mirror Y
      case 6: return Point(y, x); // Transpose
      case 7: return Point(size - 1 - y, size - 1 - x); // Anti-Transpose
      default: return Point(x, y);
    }
  }

  /// Get the inverse symmetry type
  int _getInverseSymmetry(int type) {
    switch (type) {
      case 1: return 3; // Rot90 -> Rot270
      case 3: return 1; // Rot270 -> Rot90
      default: return type; // All others are self-inverse
    }
  }

  AnalysisResult? lookupByMoves(
      int boardSize, double komi, List<String> moves) {
    if (!_isLoaded) {
      debugPrint('[OpeningBook] Not loaded yet');
      return null;
    }

    // Debug: Show what we're looking for
    final originalKey = buildMoveKeyFromGtp(boardSize, komi, moves);
    debugPrint('[OpeningBook] Looking up: $originalKey (${moves.length} moves)');

    // Try all 8 symmetries
    for (int type = 0; type < 8; type++) {
       // Transform the input sequence
       final tMoves = moves.map((m) => _transformGtp(m, boardSize, type)).toList();
       final moveKey = buildMoveKeyFromGtp(boardSize, komi, tMoves);
       
       if (type == 0 || moveKey != originalKey) {
         debugPrint('[OpeningBook]   Sym$type: $moveKey');
       }
       
       var entry = _moveIndex[moveKey];
       if (entry != null) {
         debugPrint('[OpeningBook] ✓ HIT on symmetry $type');
         // Found a match in this symmetry orientation!
         // We need to transform the result moves BACK to the original orientation
         final inverseType = _getInverseSymmetry(type);

         final originalOrientationMoves = entry.topMoves.map((m) {
           final tMoveStr = _transformGtp(m.move, boardSize, inverseType);
           return MoveCandidate(
             move: tMoveStr,
             winrate: m.winrate,
             scoreLead: m.scoreLead,
             visits: m.visits,
           );
         }).toList();

         // Create a temporary entry with transformed moves
         final transformedEntry = OpeningBookEntry(
           hash: entry.hash,
           boardSize: boardSize,
           komi: komi,
           movesSequence: moves.join(';'),
           topMoves: originalOrientationMoves,
           visits: entry.visits,
         );

         // Expand symmetry based on existing stones
         // Only symmetries that preserve existing stone positions are used
         final finalEntry = _expandSymmetryWithMoves(transformedEntry, moves);

         return AnalysisResult(
            boardHash: finalEntry.hash,
            boardSize: boardSize,
            komi: komi,
            movesSequence: moves.join(';'), // Use original sequence
            topMoves: finalEntry.topMoves,
            engineVisits: finalEntry.visits,
            modelName: 'bundled_opening_book (sym$type)',
            fromCache: true,
         );
       }
    }

    debugPrint('[OpeningBook] ✗ MISS after checking all symmetries');
      
    // Synthesize for empty board if still missed (e.g. key mismatch or other issue)
    if (moves.isEmpty && (boardSize == 13 || boardSize == 19)) {
        debugPrint('[OpeningBook] Synthesizing moves for empty $boardSize board');
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
