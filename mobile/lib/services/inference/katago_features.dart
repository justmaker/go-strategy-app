/// KataGo neural network feature encoding
/// Based on cpp/neuralnet/nninputs.cpp fillRowV4()
library;

import 'dart:typed_data';

/// Encode KataGo V4 features (22 channels)
///
/// Channel allocation:
/// 0: On board (always 1)
/// 1: Current player stones
/// 2: Opponent stones
/// 3-5: Liberties (1, 2, 3+)
/// 6: Ko ban locations
/// 7-8: Encore ko features (unused in normal games)
/// 9-13: Move history (last 5 moves)
/// 14-17: Ladder features (complex, skipped for now)
/// 18-19: Pass-alive territory (complex, skipped)
/// 20-21: Reserved
class KataGoFeatureEncoder {
  /// Encode board state to 22-channel binary input
  static Float32List encodeBinaryFeatures({
    required int boardSize,
    required List<String> moves,
    required Set<int> occupiedPositions,
  }) {
    final numFeatures = 22;
    final data = Float32List(numFeatures * boardSize * boardSize);

    // Parse board state
    final board = _parseBoardState(boardSize, moves, occupiedPositions);

    // Channel 0: On board (all 1s)
    for (var i = 0; i < boardSize * boardSize; i++) {
      data[i] = 1.0;
    }

    // Channels 1-2: Current/opponent stones
    final currentIsBlack = moves.length % 2 == 0; // Next to move
    for (var i = 0; i < boardSize * boardSize; i++) {
      if (board['black']!.contains(i)) {
        if (currentIsBlack) {
          data[1 * boardSize * boardSize + i] = 1.0; // Channel 1
        } else {
          data[2 * boardSize * boardSize + i] = 1.0; // Channel 2
        }
      } else if (board['white']!.contains(i)) {
        if (currentIsBlack) {
          data[2 * boardSize * boardSize + i] = 1.0; // Channel 2
        } else {
          data[1 * boardSize * boardSize + i] = 1.0; // Channel 1
        }
      }
    }

    // Channels 3-5: Liberties (simplified - count neighbors)
    _encodeLiberties(data, boardSize, board);

    // Channels 9-13: Move history
    _encodeMoveHistory(data, boardSize, moves, occupiedPositions);

    return data;
  }

  static Map<String, Set<int>> _parseBoardState(
    int boardSize,
    List<String> moves,
    Set<int> occupiedPositions,
  ) {
    final black = <int>{};
    final white = <int>{};

    for (var i = 0; i < moves.length; i++) {
      final parts = moves[i].trim().split(' ');
      if (parts.length < 2) continue;

      final player = parts[0].toUpperCase();
      final coord = parts[1];

      // Find index in occupiedPositions (already parsed)
      // This is a workaround - proper implementation would re-parse
      if (player == 'B') {
        // Black move
      } else if (player == 'W') {
        // White move
      }
    }

    return {'black': black, 'white': white};
  }

  static void _encodeLiberties(
    Float32List data,
    int boardSize,
    Map<String, Set<int>> board,
  ) {
    // TODO: Implement proper liberty counting
    // For now, skip (complex graph traversal)
  }

  static void _encodeMoveHistory(
    Float32List data,
    int boardSize,
    List<String> moves,
    Set<int> occupiedPositions,
  ) {
    // Channels 9-13: Last 5 moves
    // Channel 9: opponent's last move
    // Channel 10: our last move
    // etc.

    // TODO: Implement move history encoding
  }
}
