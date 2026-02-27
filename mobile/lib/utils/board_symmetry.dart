/// Pure geometric utilities for 8-way board symmetry transformations.
///
/// Supports 4 rotations (0°, 90°, 180°, 270°) and 4 reflections
/// (horizontal, vertical, diagonal, anti-diagonal).
library;

import 'dart:math';
import '../models/models.dart';

class BoardSymmetry {
  /// Transform coordinates (0-indexed) by symmetry type (0-7).
  ///
  /// Types: 0=identity, 1=90°CW, 2=180°, 3=270°CW,
  ///        4=flip-horizontal, 5=flip-vertical, 6=flip-diagonal, 7=flip-anti-diagonal
  static Point<int> transformPoint(int x, int y, int boardSize, int type) {
    switch (type) {
      case 0:
        return Point(x, y);
      case 1:
        return Point(y, boardSize - 1 - x);
      case 2:
        return Point(boardSize - 1 - x, boardSize - 1 - y);
      case 3:
        return Point(boardSize - 1 - y, x);
      case 4:
        return Point(boardSize - 1 - x, y);
      case 5:
        return Point(x, boardSize - 1 - y);
      case 6:
        return Point(y, x);
      case 7:
        return Point(boardSize - 1 - y, boardSize - 1 - x);
      default:
        return Point(x, y);
    }
  }

  /// Get the inverse symmetry type (to undo a transformation).
  static int inverseSymmetry(int type) {
    switch (type) {
      case 1:
        return 3;
      case 3:
        return 1;
      default:
        return type; // 0,2,4,5,6,7 are self-inverse
    }
  }

  /// Transform a GTP move string by symmetry type.
  ///
  /// Supports both "B Q16" and "B[Q16]" formats.
  /// Returns unchanged for 'pass' or empty moves.
  static String transformGtp(String move, int boardSize, int type) {
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

    final tPoint = transformPoint(point.x, point.y, boardSize, type);
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

  /// Compute which symmetry transforms preserve the given stone positions.
  ///
  /// For an empty board (no moves), all 8 symmetries are valid.
  /// Returns at least [0] (identity) if no other symmetry preserves positions.
  static List<int> validSymmetries(int boardSize, List<String> moves) {
    if (moves.isEmpty) {
      return [0, 1, 2, 3, 4, 5, 6, 7];
    }

    final stones = <Point<int>>[];
    for (final move in moves) {
      final parts = move.split(' ');
      if (parts.length != 2) continue;
      final point = BoardPoint.fromGtp(parts[1], boardSize);
      if (point != null) {
        stones.add(Point(point.x, point.y));
      }
    }

    final result = <int>[];
    for (int type = 0; type < 8; type++) {
      bool isValid = true;
      for (final stone in stones) {
        final transformed = transformPoint(stone.x, stone.y, boardSize, type);
        if (transformed.x != stone.x || transformed.y != stone.y) {
          isValid = false;
          break;
        }
      }
      if (isValid) {
        result.add(type);
      }
    }

    return result.isEmpty ? [0] : result;
  }
}
