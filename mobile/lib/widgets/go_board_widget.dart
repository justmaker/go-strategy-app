/// Interactive Go board widget with move suggestions overlay.
library;

import 'package:flutter/material.dart';
import '../models/models.dart';

/// Configuration for board appearance
class BoardTheme {
  final Color boardColor;
  final Color lineColor;
  final Color blackStoneColor;
  final Color whiteStoneColor;
  final Color starPointColor;
  final Color bestMoveColor;
  final Color goodMoveColor;
  final Color okMoveColor;

  const BoardTheme({
    this.boardColor = const Color(0xFFDEB887), // Burlywood
    this.lineColor = Colors.black87,
    this.blackStoneColor = Colors.black,
    this.whiteStoneColor = Colors.white,
    this.starPointColor = Colors.black,
    this.bestMoveColor = Colors.blue,
    this.goodMoveColor = Colors.green,
    this.okMoveColor = Colors.orange,
  });
}

/// Widget that displays an interactive Go board
class GoBoardWidget extends StatelessWidget {
  final BoardState board;
  final List<MoveCandidate>? suggestions;
  final void Function(BoardPoint)? onTap;
  final BoardTheme theme;
  final bool showCoordinates;
  final bool showMoveNumbers;
  final BoardPoint? pendingMove; // For move confirmation preview

  const GoBoardWidget({
    super.key,
    required this.board,
    this.suggestions,
    this.onTap,
    this.theme = const BoardTheme(),
    this.showCoordinates = true,
    this.showMoveNumbers = false,
    this.pendingMove,
  });

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1.0,
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Ensure we use the smaller dimension to stay square
          final size = constraints.maxWidth < constraints.maxHeight
              ? constraints.maxWidth
              : constraints.maxHeight;

          return SizedBox(
            width: size,
            height: size,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown:
                  onTap != null ? (details) => _handleTap(details, size) : null,
              child: CustomPaint(
                size: Size(size, size),
                painter: _BoardPainter(
                  board: board,
                  suggestions: suggestions,
                  theme: theme,
                  showCoordinates: showCoordinates,
                  showMoveNumbers: showMoveNumbers,
                  pendingMove: pendingMove,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  void _handleTap(TapDownDetails details, double widgetSize) {
    // Use same padding logic as paint method
    double paddingRatio;
    if (showCoordinates) {
      if (board.size >= 19) {
        paddingRatio = 0.06;
      } else if (board.size >= 13) {
        paddingRatio = 0.07;
      } else {
        paddingRatio = 0.08;
      }
    } else {
      paddingRatio = 0.02;
    }

    final padding = widgetSize * paddingRatio;
    final boardSizePixels = widgetSize - padding * 2;
    final cellSize = boardSizePixels / (board.size - 1);

    // Display coordinates (y=0 at top of screen)
    final displayX = ((details.localPosition.dx - padding) / cellSize).round();
    final displayY = ((details.localPosition.dy - padding) / cellSize).round();

    if (displayX >= 0 &&
        displayX < board.size &&
        displayY >= 0 &&
        displayY < board.size) {
      // Convert display coordinates to GTP coordinates (y=0 at bottom)
      final gtpPoint =
          BoardPoint.fromDisplayCoords(displayX, displayY, board.size);
      onTap?.call(gtpPoint);
    }
  }
}

class _BoardPainter extends CustomPainter {
  final BoardState board;
  final List<MoveCandidate>? suggestions;
  final BoardTheme theme;
  final bool showCoordinates;
  final bool showMoveNumbers;
  final BoardPoint? pendingMove;

  _BoardPainter({
    required this.board,
    this.suggestions,
    required this.theme,
    required this.showCoordinates,
    required this.showMoveNumbers,
    this.pendingMove,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Dynamic padding based on board size for better space utilization
    // Smaller boards (9x9) can afford more padding, larger boards (19x19) need less
    double paddingRatio;
    if (showCoordinates) {
      if (board.size >= 19) {
        paddingRatio = 0.06; // 6% for 19x19 (tighter for small screens)
      } else if (board.size >= 13) {
        paddingRatio = 0.07; // 7% for 13x13
      } else {
        paddingRatio = 0.08; // 8% for 9x9
      }
    } else {
      paddingRatio = 0.02; // No coordinates
    }

    final padding = size.width * paddingRatio;
    final boardSize = size.width - padding * 2;
    final cellSize = boardSize / (board.size - 1);

    // Draw board background
    canvas.drawRect(Offset.zero & size, Paint()..color = theme.boardColor);

    // Draw grid lines
    _drawGrid(canvas, padding, cellSize);

    // Draw star points
    _drawStarPoints(canvas, padding, cellSize);

    // Draw coordinates
    if (showCoordinates) {
      _drawCoordinates(canvas, padding, cellSize, size);
    }

    // Draw suggestions
    if (suggestions != null && suggestions!.isNotEmpty) {
      _drawSuggestions(canvas, padding, cellSize);
    }

    // Draw stones with optional move numbers
    _drawStones(canvas, padding, cellSize);

    // Draw pending move preview (dashed circle)
    if (pendingMove != null) {
      _drawPendingMove(canvas, padding, cellSize);
    }
  }

  // ... (keep _drawGrid, _drawStarPoints, _drawCoordinates, _drawSuggestions as they are) ...
  // Wait, the tool replaces CONTIGUOUS blocks. I need to be careful not to delete methods not shown.
  // I will target the class Definition + paint + _drawStones.
  // Actually, split this into:
  // 1. Class definition and Constructor.
  // 2. _drawStones method.
  
  // Let's do Class Def + Constructor + paint first.
  // Actually, I can just replace the Constructor and paint method.
  // But wait, `_drawStones` is at the end. I need to modify it.
  
  // Let's Replace `_BoardPainter` class start up to `paint` method end.
  // Wait, I can't overwrite hidden methods.
  // I'll do 2 replacements.
  
  // Replacement 1: Constructor and Fields.
  
  // Replacement 2: `_drawStones` and `shouldRepaint`.
  
  // Let's do Replacement 1.





  void _drawGrid(Canvas canvas, double padding, double cellSize) {
    final paint = Paint()
      ..color = theme.lineColor
      ..strokeWidth = 1.0;

    for (int i = 0; i < board.size; i++) {
      final pos = padding + i * cellSize;

      // Horizontal line
      canvas.drawLine(
        Offset(padding, pos),
        Offset(padding + (board.size - 1) * cellSize, pos),
        paint,
      );

      // Vertical line
      canvas.drawLine(
        Offset(pos, padding),
        Offset(pos, padding + (board.size - 1) * cellSize),
        paint,
      );
    }
  }

  void _drawStarPoints(Canvas canvas, double padding, double cellSize) {
    final paint = Paint()..color = theme.starPointColor;
    final radius = cellSize * 0.12;

    // Use display coordinates for rendering (y=0 at top)
    for (final point in board.starPointsForDisplay) {
      final x = padding + point.x * cellSize;
      final y = padding + point.y * cellSize;
      canvas.drawCircle(Offset(x, y), radius, paint);
    }
  }

  void _drawCoordinates(
    Canvas canvas,
    double padding,
    double cellSize,
    Size size,
  ) {
    const columns = 'ABCDEFGHJKLMNOPQRST';
    final textStyle = TextStyle(
      color: theme.lineColor,
      fontSize: (cellSize * 0.5).clamp(10.0, 16.0),
      fontWeight: FontWeight.bold,
      height: 1.0,
    );

    // Calculate grid boundaries based on width (since grid is width-based)
    // The grid is always square based on width logic
    final gridBottomY = padding + (board.size - 1) * cellSize;
    
    // Center labels in the padding area relative to grid
    // Top Y center: padding / 2
    // Bottom Y center: gridBottomY + padding / 2
    final topYCenter = padding / 2;
    final bottomYCenter = gridBottomY + padding / 2;

    for (int i = 0; i < board.size; i++) {
      // Column labels (A-T)
      final colLabel = columns[i];
      final colPainter = TextPainter(
        text: TextSpan(text: colLabel, style: textStyle),
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
      )..layout();

      // Horizontal center for column labels is fixed by the grid line
      final colX = padding + i * cellSize - colPainter.width / 2;
      
      // Top labels
      colPainter.paint(canvas, Offset(colX, topYCenter - colPainter.height / 2));
      
      // Bottom labels
      colPainter.paint(canvas, Offset(colX, bottomYCenter - colPainter.height / 2));

      // Row labels (1-19)
      final rowLabel = '${board.size - i}';
      final rowPainter = TextPainter(
        text: TextSpan(text: rowLabel, style: textStyle),
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
      )..layout();

      // Vertical center for row labels is fixed by the grid line
      final rowY = padding + i * cellSize - rowPainter.height / 2;
      final halfPadding = padding / 2;
      
      // Left labels: Center horizontally in left padding
      rowPainter.paint(canvas, Offset(halfPadding - rowPainter.width / 2, rowY));
      
      // Right labels: Center horizontally in right padding
      rowPainter.paint(canvas, Offset(size.width - halfPadding - rowPainter.width / 2, rowY));
    }
  }

  void _drawSuggestions(Canvas canvas, double padding, double cellSize) {
    if (suggestions == null || suggestions!.isEmpty) return;

    final bestWinrate = suggestions!.first.winrate;

    // Pre-calculate display ranks to group equivalent moves
    final moveRanks = <int, int>{}; // index -> displayRank
    int currentRank = 0;
    String? lastSignature;

    for (int i = 0; i < suggestions!.length; i++) {
      final move = suggestions![i];
      // Use the same signature logic as the list to group equivalent moves
      final signature = '${move.winratePercent}_${move.scoreLeadFormatted}';
      
      if (signature != lastSignature) {
        currentRank++;
        lastSignature = signature;
      }
      moveRanks[i] = currentRank;
    }

    for (int i = 0; i < suggestions!.length; i++) {
      final suggestion = suggestions![i];
      final gtpPoint = BoardPoint.fromGtp(suggestion.move, board.size);
      if (gtpPoint == null) continue;

      // Convert GTP coordinates to display coordinates for rendering
      final point = gtpPoint.toDisplayCoords(board.size);

      final displayRank = moveRanks[i]!;

      // Filter out moves that are too bad (10% drop)
      final winrateDrop = bestWinrate - suggestion.winrate;
      if (winrateDrop > 0.10) {
        continue;
      }

      // Determine color based on rank with extended color palette
      // Rank 1: Blue (Best), Rank 2: Green (Good), Rank 3: Orange,
      // Rank 4: Yellow, Rank 5: Purple, Rank 6+: Grey
      final rankColors = [
        Colors.blue,        // Rank 1
        Colors.green,       // Rank 2
        Colors.orange,      // Rank 3
        Colors.yellow,      // Rank 4
        Colors.purple,      // Rank 5
        Colors.pink,        // Rank 6
        Colors.cyan,        // Rank 7
        Colors.lime,        // Rank 8
        Colors.grey,        // Rank 9+
      ];

      final colorIndex = (displayRank - 1).clamp(0, rankColors.length - 1);
      final color = rankColors[colorIndex];

      final x = padding + point.x * cellSize;
      final y = padding + point.y * cellSize;
      final radius = cellSize * 0.35;

      // Draw suggestion circle
      final paint = Paint()
        ..color = color.withValues(alpha: 0.7)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(x, y), radius, paint);

      // Draw border
      final borderPaint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;
      canvas.drawCircle(Offset(x, y), radius, borderPaint);

      // Draw rank number (using the grouped rank)
      final textPainter = TextPainter(
        text: TextSpan(
          text: '$displayRank',
          style: TextStyle(
            color: Colors.white,
            fontSize: (cellSize * 0.45).clamp(10.0, 18.0),
            fontWeight: FontWeight.bold,
            height: 1.0,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      textPainter.paint(
        canvas,
        Offset(x - textPainter.width / 2, y - textPainter.height / 2),
      );
    }
  }

  void _drawStones(Canvas canvas, double padding, double cellSize) {
    final stoneRadius = cellSize * 0.45;
    
    // Pre-calculate move numbers if needed
    final moveNumbers = <int, int>{}; // (displayY * size + displayX) -> moveNum
    if (showMoveNumbers) {
      // We need to access moves. Assuming BoardState exposes movesGtp or moves.
      // GameProvider uses movesGtp, so it should be available.
      // We iterate forward, so later moves overwrite earlier ones (which is correct for current state 
      // as long as the stone wasn't captured and the spot is empty).
      // Since we only draw if the board has a stone, mapping the *last* move at a coordinate is correct.
      for (int i = 0; i < board.movesGtp.length; i++) {
        final moveStr = board.movesGtp[i];
        final gameMove = GameMove.fromGtp(moveStr, board.size);
        final point = gameMove?.point;
        
        if (point != null) {
          final displayPoint = point.toDisplayCoords(board.size);
          final index = displayPoint.y * board.size + displayPoint.x;
          moveNumbers[index] = i + 1;
        }
      }
    }

    // Iterate in display coordinates (y=0 at top for rendering)
    for (int displayY = 0; displayY < board.size; displayY++) {
      for (int displayX = 0; displayX < board.size; displayX++) {
        // Get stone using display coordinates
        final stone = board.getStoneForDisplay(displayX, displayY);
        if (stone == StoneColor.empty) continue;

        final centerX = padding + displayX * cellSize;
        final centerY = padding + displayY * cellSize;

        // Draw stone shadow
        final shadowPaint = Paint()
          ..color = Colors.black.withValues(alpha: 0.3)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);
        canvas.drawCircle(
          Offset(centerX + 2, centerY + 2),
          stoneRadius,
          shadowPaint,
        );

        // Draw stone
        final stonePaint = Paint()
          ..color = stone == StoneColor.black
              ? theme.blackStoneColor
              : theme.whiteStoneColor;
        canvas.drawCircle(Offset(centerX, centerY), stoneRadius, stonePaint);

        // Draw white stone border
        if (stone == StoneColor.white) {
          final borderPaint = Paint()
            ..color = Colors.black54
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.0;
          canvas.drawCircle(Offset(centerX, centerY), stoneRadius, borderPaint);
        }

        // Draw stone highlight (3D effect)
        final highlightPaint = Paint()
          ..shader = RadialGradient(
            center: const Alignment(-0.3, -0.3),
            radius: 0.8,
            colors: stone == StoneColor.black
                ? [Colors.grey.shade600, Colors.black]
                : [Colors.white, Colors.grey.shade300],
          ).createShader(
            Rect.fromCircle(
              center: Offset(centerX, centerY),
              radius: stoneRadius,
            ),
          );
        canvas.drawCircle(
            Offset(centerX, centerY), stoneRadius, highlightPaint);
            
        // Draw move number
        if (showMoveNumbers) {
          final index = displayY * board.size + displayX;
          if (moveNumbers.containsKey(index)) {
            final moveNum = moveNumbers[index]!;
            final textColor = stone == StoneColor.black ? Colors.white : Colors.black;
            
            final textPainter = TextPainter(
              text: TextSpan(
                text: '$moveNum',
                style: TextStyle(
                  color: textColor,
                  fontSize: (cellSize * 0.5).clamp(10.0, 20.0),
                  fontWeight: FontWeight.bold,
                ),
              ),
              textDirection: TextDirection.ltr,
              textAlign: TextAlign.center,
            )..layout();
            
            textPainter.paint(
              canvas,
              Offset(centerX - textPainter.width / 2, centerY - textPainter.height / 2),
            );
          }
        }
      }
    }
  }

  void _drawPendingMove(Canvas canvas, double padding, double cellSize) {
    if (pendingMove == null) return;

    // Convert GTP coordinates to display coordinates
    final displayPoint = pendingMove!.toDisplayCoords(board.size);
    final centerX = padding + displayPoint.x * cellSize;
    final centerY = padding + displayPoint.y * cellSize;
    final radius = cellSize * 0.45;

    // Determine stone color (next player's color)
    final isBlackNext = board.nextPlayer == StoneColor.black;
    final stoneColor = isBlackNext ? Colors.black : Colors.white;

    // Draw dashed circle
    final paint = Paint()
      ..color = stoneColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;

    // Create dashed circle effect
    const dashCount = 16;
    const dashAngle = (2 * 3.14159) / dashCount;
    for (int i = 0; i < dashCount; i += 2) {
      final startAngle = i * dashAngle;
      final endAngle = startAngle + dashAngle;

      canvas.drawArc(
        Rect.fromCircle(center: Offset(centerX, centerY), radius: radius),
        startAngle,
        dashAngle,
        false,
        paint,
      );
    }

    // Draw semi-transparent fill for visibility
    final fillPaint = Paint()
      ..color = stoneColor.withValues(alpha: 0.2)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(centerX, centerY), radius, fillPaint);
  }

  @override
  bool shouldRepaint(covariant _BoardPainter oldDelegate) {
    return oldDelegate.board != board ||
        oldDelegate.suggestions != suggestions ||
        oldDelegate.theme != theme ||
        oldDelegate.showCoordinates != showCoordinates ||
        oldDelegate.showMoveNumbers != showMoveNumbers ||
        oldDelegate.pendingMove != pendingMove;
  }
}
