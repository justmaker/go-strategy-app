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

  const GoBoardWidget({
    super.key,
    required this.board,
    this.suggestions,
    this.onTap,
    this.theme = const BoardTheme(),
    this.showCoordinates = true,
  });

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1.0,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = constraints.maxWidth;
          return GestureDetector(
            onTapDown:
                onTap != null ? (details) => _handleTap(details, size) : null,
            child: CustomPaint(
              size: Size(size, size),
              painter: _BoardPainter(
                board: board,
                suggestions: suggestions,
                theme: theme,
                showCoordinates: showCoordinates,
              ),
            ),
          );
        },
      ),
    );
  }

  void _handleTap(TapDownDetails details, double widgetSize) {
    final padding = showCoordinates ? widgetSize * 0.05 : 0.0;
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

  _BoardPainter({
    required this.board,
    this.suggestions,
    required this.theme,
    required this.showCoordinates,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final padding = showCoordinates ? size.width * 0.05 : 0.0;
    final boardSize = size.width - padding * 2;
    final cellSize = boardSize / (board.size - 1);

    // Draw board background
    final boardRect = Rect.fromLTWH(
      padding - cellSize / 2,
      padding - cellSize / 2,
      boardSize + cellSize,
      boardSize + cellSize,
    );
    canvas.drawRect(boardRect, Paint()..color = theme.boardColor);

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

    // Draw stones
    _drawStones(canvas, padding, cellSize);
  }

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
      fontSize: cellSize * 0.4,
      fontWeight: FontWeight.w500,
    );

    for (int i = 0; i < board.size; i++) {
      // Column labels (A-T)
      final colLabel = columns[i];
      final colPainter = TextPainter(
        text: TextSpan(text: colLabel, style: textStyle),
        textDirection: TextDirection.ltr,
      )..layout();

      final colX = padding + i * cellSize - colPainter.width / 2;
      colPainter.paint(canvas, Offset(colX, size.height - padding * 0.8));

      // Row labels (1-19)
      final rowLabel = '${board.size - i}';
      final rowPainter = TextPainter(
        text: TextSpan(text: rowLabel, style: textStyle),
        textDirection: TextDirection.ltr,
      )..layout();

      final rowY = padding + i * cellSize - rowPainter.height / 2;
      rowPainter.paint(canvas, Offset(padding * 0.1, rowY));
    }
  }

  void _drawSuggestions(Canvas canvas, double padding, double cellSize) {
    if (suggestions == null || suggestions!.isEmpty) return;

    final bestWinrate = suggestions!.first.winrate;

    for (int i = 0; i < suggestions!.length; i++) {
      final suggestion = suggestions![i];
      final gtpPoint = BoardPoint.fromGtp(suggestion.move, board.size);
      if (gtpPoint == null) continue;

      // Convert GTP coordinates to display coordinates for rendering
      final point = gtpPoint.toDisplayCoords(board.size);

      // Determine color based on winrate difference (matching GUI logic)
      Color color;
      final winrateDrop = bestWinrate - suggestion.winrate;
      if (winrateDrop <= 0.005) {
        // Best move (drop <= 0.5%)
        color = theme.bestMoveColor;
      } else if (winrateDrop <= 0.03) {
        // Good move (drop <= 3%)
        color = theme.goodMoveColor;
      } else if (winrateDrop <= 0.10) {
        // OK move (drop <= 10%)
        color = theme.okMoveColor;
      } else {
        // Skip moves with >10% winrate drop
        continue;
      }

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

      // Draw rank number
      final textPainter = TextPainter(
        text: TextSpan(
          text: '${i + 1}',
          style: TextStyle(
            color: Colors.white,
            fontSize: cellSize * 0.35,
            fontWeight: FontWeight.bold,
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
      }
    }
  }

  @override
  bool shouldRepaint(covariant _BoardPainter oldDelegate) {
    return oldDelegate.board != board ||
        oldDelegate.suggestions != suggestions ||
        oldDelegate.theme != theme;
  }
}
