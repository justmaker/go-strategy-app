/// Board state model for tracking game position.
library;

enum StoneColor { empty, black, white }

/// Represents a point on the Go board
///
/// Coordinate system (matches GTP standard):
/// - x: 0 to boardSize-1, left to right (A to T, skipping I)
/// - y: 0 to boardSize-1, BOTTOM to TOP (row 1 to 19)
///
/// This means y=0 is the BOTTOM row (row 1 in GTP).
class BoardPoint {
  final int x; // 0-based, left to right
  final int y; // 0-based, bottom to top (GTP standard)

  const BoardPoint(this.x, this.y);

  /// Convert to GTP coordinate (e.g., "Q16")
  String toGtp(int boardSize) {
    // GTP columns: A-T (skip I), from left
    // GTP rows: 1-19, from bottom (y=0 is row 1)
    const columns = 'ABCDEFGHJKLMNOPQRST'; // Note: no 'I'
    final col = columns[x];
    final row = y + 1; // y=0 -> row 1, y=18 -> row 19
    return '$col$row';
  }

  /// Parse from GTP coordinate
  static BoardPoint? fromGtp(String gtp, int boardSize) {
    if (gtp.length < 2) return null;
    if (gtp.toUpperCase() == 'PASS') return null;

    const columns = 'ABCDEFGHJKLMNOPQRST';
    final col = gtp[0].toUpperCase();
    final colIndex = columns.indexOf(col);
    if (colIndex == -1) return null;

    final row = int.tryParse(gtp.substring(1));
    if (row == null || row < 1 || row > boardSize) return null;

    // row 1 -> y=0, row 19 -> y=18
    return BoardPoint(colIndex, row - 1);
  }

  /// Convert to display coordinates (y=0 at top for rendering)
  /// Use this when drawing on screen where y=0 is at the top
  BoardPoint toDisplayCoords(int boardSize) {
    return BoardPoint(x, boardSize - 1 - y);
  }

  /// Convert from display coordinates (y=0 at top) to GTP coordinates
  /// Use this when converting screen taps to board positions
  static BoardPoint fromDisplayCoords(
      int displayX, int displayY, int boardSize) {
    return BoardPoint(displayX, boardSize - 1 - displayY);
  }

  @override
  bool operator ==(Object other) =>
      other is BoardPoint && other.x == x && other.y == y;

  @override
  int get hashCode => x.hashCode ^ y.hashCode;

  @override
  String toString() => 'BoardPoint($x, $y)';
}

/// Represents a move in the game
class GameMove {
  final StoneColor color;
  final BoardPoint point;

  const GameMove(this.color, this.point);

  /// Convert to GTP format (e.g., "B Q16")
  String toGtp(int boardSize) {
    final colorStr = color == StoneColor.black ? 'B' : 'W';
    return '$colorStr ${point.toGtp(boardSize)}';
  }

  /// Parse from GTP format
  static GameMove? fromGtp(String gtp, int boardSize) {
    final parts = gtp.trim().split(RegExp(r'\s+'));
    if (parts.length != 2) return null;

    final colorStr = parts[0].toUpperCase();
    final color = colorStr == 'B'
        ? StoneColor.black
        : colorStr == 'W'
            ? StoneColor.white
            : null;
    if (color == null) return null;

    final point = BoardPoint.fromGtp(parts[1], boardSize);
    if (point == null) return null;

    return GameMove(color, point);
  }

  @override
  String toString() => 'GameMove($color, $point)';
}

/// Manages the board state
///
/// Internal storage uses GTP coordinates (y=0 at bottom).
/// For display purposes, use getStoneForDisplay() which flips the y-axis.
class BoardState {
  final int size;
  final List<List<StoneColor>> _stones;
  final List<GameMove> _moves;
  double komi;
  int handicap;

  BoardState({
    this.size = 19,
    this.komi = 7.5,
    this.handicap = 0,
  })  : _stones = List.generate(
          size,
          (_) => List.filled(size, StoneColor.empty),
        ),
        _moves = [];

  /// Get stone at GTP coordinates (y=0 at bottom)
  StoneColor getStone(int x, int y) {
    if (x < 0 || x >= size || y < 0 || y >= size) {
      return StoneColor.empty;
    }
    return _stones[y][x];
  }

  /// Get stone at display coordinates (y=0 at top, for rendering)
  StoneColor getStoneForDisplay(int displayX, int displayY) {
    final gtpY = size - 1 - displayY;
    return getStone(displayX, gtpY);
  }

  /// Get stone at board point (GTP coordinates)
  StoneColor getStoneAt(BoardPoint point) => getStone(point.x, point.y);

  /// Check if position is empty (GTP coordinates)
  bool isEmpty(int x, int y) => getStone(x, y) == StoneColor.empty;

  /// Check if position is empty (display coordinates)
  bool isEmptyForDisplay(int displayX, int displayY) {
    final gtpY = size - 1 - displayY;
    return isEmpty(displayX, gtpY);
  }

  /// Get the next player to move
  StoneColor get nextPlayer {
    if (_moves.isEmpty) {
      // Handicap games: White moves first after handicap stones
      return handicap > 0 ? StoneColor.white : StoneColor.black;
    }
    return _moves.last.color == StoneColor.black
        ? StoneColor.white
        : StoneColor.black;
  }

  /// Get all moves as GTP strings
  List<String> get movesGtp => _moves.map((m) => m.toGtp(size)).toList();

  /// Get number of moves played
  int get moveCount => _moves.length;

  /// Place a stone (without capture logic for now)
  bool placeStone(BoardPoint point) {
    if (!isEmpty(point.x, point.y)) {
      return false;
    }

    final color = nextPlayer;
    _stones[point.y][point.x] = color;
    _moves.add(GameMove(color, point));
    return true;
  }

  /// Undo the last move
  bool undo() {
    if (_moves.isEmpty) return false;

    final lastMove = _moves.removeLast();
    _stones[lastMove.point.y][lastMove.point.x] = StoneColor.empty;
    return true;
  }

  /// Clear the board
  void clear() {
    for (var row in _stones) {
      row.fillRange(0, size, StoneColor.empty);
    }
    _moves.clear();
  }

  /// Copy the board state
  BoardState copy() {
    final newBoard = BoardState(size: size, komi: komi, handicap: handicap);
    for (int y = 0; y < size; y++) {
      for (int x = 0; x < size; x++) {
        newBoard._stones[y][x] = _stones[y][x];
      }
    }
    newBoard._moves.addAll(_moves);
    return newBoard;
  }

  /// Get star points for the board (in GTP coordinates, y=0 at bottom)
  List<BoardPoint> get starPoints {
    // Star points in GTP coordinates (x, y) where y=0 is bottom
    switch (size) {
      case 9:
        // 9x9: C3, G3, E5, C7, G7 -> (2,2), (6,2), (4,4), (2,6), (6,6)
        return const [
          BoardPoint(2, 2),
          BoardPoint(6, 2),
          BoardPoint(4, 4),
          BoardPoint(2, 6),
          BoardPoint(6, 6),
        ];
      case 13:
        // 13x13: D4, K4, G7, D10, K10 -> (3,3), (9,3), (6,6), (3,9), (9,9)
        return const [
          BoardPoint(3, 3),
          BoardPoint(9, 3),
          BoardPoint(6, 6),
          BoardPoint(3, 9),
          BoardPoint(9, 9),
        ];
      case 19:
        // 19x19: D4, K4, Q4, D10, K10, Q10, D16, K16, Q16
        return const [
          BoardPoint(3, 3),
          BoardPoint(9, 3),
          BoardPoint(15, 3),
          BoardPoint(3, 9),
          BoardPoint(9, 9),
          BoardPoint(15, 9),
          BoardPoint(3, 15),
          BoardPoint(9, 15),
          BoardPoint(15, 15),
        ];
      default:
        return [];
    }
  }

  /// Get star points in display coordinates (y=0 at top, for rendering)
  List<BoardPoint> get starPointsForDisplay {
    return starPoints.map((p) => p.toDisplayCoords(size)).toList();
  }
}
