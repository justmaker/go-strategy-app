/// Main analysis screen with Go board and move suggestions.
library;

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../config.dart';
import '../models/models.dart';
import '../providers/providers.dart';
import '../services/services.dart';
import '../widgets/widgets.dart';
import 'settings_screen.dart';
import '../models/game_record.dart' as record;

class AnalysisScreen extends StatelessWidget {
  const AnalysisScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Go Strategy'),
        actions: [
          // Board size selector
          Consumer<GameProvider>(
            builder: (context, game, _) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0),
              child: SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 9, label: Text('9')),
                  ButtonSegment(value: 13, label: Text('13')),
                  ButtonSegment(value: 19, label: Text('19')),
                ],
                selected: {game.board.size},
                onSelectionChanged: (sizes) {
                  game.setBoardSize(sizes.first);
                },
                style: ButtonStyle(
                  visualDensity: VisualDensity.compact,
                  padding: MaterialStateProperty.all(EdgeInsets.zero),
                ),
                showSelectedIcon: false,
              ),
            ),
          ),
          // SGF Import/Export menu
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            tooltip: '匯入/匯出',
            onSelected: (value) {
              switch (value) {
                case 'import_sgf':
                  _importSgf(context);
                  break;
                case 'export_sgf':
                  _exportSgf(context);
                  break;
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'import_sgf',
                child: ListTile(
                  leading: Icon(Icons.file_open),
                  title: Text('匯入 SGF'),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: 'export_sgf',
                enabled: Provider.of<GameProvider>(context, listen: false)
                        .board
                        .moveCount >
                    0,
                child: const ListTile(
                  leading: Icon(Icons.file_download),
                  title: Text('匯出 SGF'),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
          // Settings
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => _showSettings(context),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth > 700;

          if (isWide) {
            // Landscape layout for tablets/desktop
            return Row(
              children: [
                // Logic: Board on the left (Square if possible)
                Expanded(
                  flex: 2,
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Center(
                      child: AspectRatio(
                        aspectRatio: 1.0,
                        child: _buildBoard(context),
                      ),
                    ),
                  ),
                ),
                // Sidebar on the right
                Container(
                  width: 350,
                  decoration: BoxDecoration(
                    border: Border(left: BorderSide(color: Colors.grey.shade300)),
                    color: Colors.grey.shade50,
                  ),
                  child: const Column(
                    children: [
                      Expanded(child: _AnalysisPanel()),
                      Divider(height: 1),
                      _ControlsPanel(),
                      // Removed SizedBox to prevent overflow on smaller screens
                    ],
                  ),
                ),
              ],
            );
          } else {
            // Portrait layout (Standard Mobile)
            return Column(
              children: [
                // Board
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: _buildBoard(context),
                  ),
                ),
                // Analysis panel
                const Expanded(
                  child: _AnalysisPanel(),
                ),
                // Controls
                const _ControlsPanel(),
              ],
            );
          }
        },
      ),
    );
  }

  Widget _buildBoard(BuildContext context) {
    return Consumer<GameProvider>(
      builder: (context, game, _) {
        return GoBoardWidget(
          board: game.board,
          suggestions: game.lastAnalysis?.topMoves,
          showMoveNumbers: game.showMoveNumbers,
          pendingMove: game.pendingMove,
          onTap: game.isAnalyzing
              ? null
              : (point) {
                  // If move confirmation is enabled, set pending move
                  // Otherwise, place stone directly
                  if (game.moveConfirmationEnabled) {
                    game.setPendingMove(point);
                  } else {
                    game.placeStone(point);
                  }
                },
        );
      },
    );
  }

  /// Import an SGF file and load it onto the board
  Future<void> _importSgf(BuildContext context) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowMultiple: false,
      );

      if (result == null || result.files.isEmpty) return;

      String sgfContent;
      if (kIsWeb) {
        // On web, read from bytes
        final bytes = result.files.first.bytes;
        if (bytes == null) return;
        sgfContent = String.fromCharCodes(bytes);
      } else {
        // On desktop/mobile, read from path
        final filePath = result.files.first.path;
        if (filePath == null) return;
        sgfContent = await File(filePath).readAsString();
      }

      if (!context.mounted) return;

      final gameRecord = record.GameRecord.fromSgf(
        sgfContent,
        name: result.files.first.name.replaceAll('.sgf', ''),
      );

      if (gameRecord == null) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('無法解析 SGF 檔案')),
          );
        }
        return;
      }

      // Load the game onto the board
      final game = Provider.of<GameProvider>(context, listen: false);
      game.setBoardSize(gameRecord.boardSize);
      game.setKomi(gameRecord.komi);
      game.clear();

      // Replay all moves
      for (final move in gameRecord.moves) {
        if (move.coordinate.toLowerCase() != 'pass') {
          final coord = move.coordinate;
          // Parse GTP coordinate to BoardPoint
          final col = coord[0].toUpperCase();
          final row = int.tryParse(coord.substring(1));
          if (row == null) continue;

          int colIndex = col.codeUnitAt(0) - 'A'.codeUnitAt(0);
          if (col.codeUnitAt(0) > 'I'.codeUnitAt(0)) colIndex--;

          final y = gameRecord.boardSize - row;
          final point = BoardPoint(colIndex, y);
          game.board.placeStone(point);
        }
      }
      game.analyze();

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('已匯入：${gameRecord.name} (${gameRecord.moves.length} 手)'),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('匯入失敗：$e')),
        );
      }
    }
  }

  /// Export the current game as SGF
  Future<void> _exportSgf(BuildContext context) async {
    final game = Provider.of<GameProvider>(context, listen: false);
    if (game.board.moveCount == 0) return;

    // Build a temporary GameRecord from current board state
    final moves = <record.GameMove>[];
    for (int i = 0; i < game.board.movesGtp.length; i++) {
      final moveGtp = game.board.movesGtp[i];
      final parts = moveGtp.split(' ');
      if (parts.length >= 2) {
        moves.add(record.GameMove(
          player: parts[0],
          coordinate: parts[1],
          moveNumber: i + 1,
        ));
      }
    }

    final now = DateTime.now();
    final gameRecord = record.GameRecord(
      name: 'GoStrategy_${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}',
      boardSize: game.board.size,
      komi: game.board.komi,
      handicap: game.board.handicap,
      moves: moves,
    );

    final sgfContent = gameRecord.toSgf();
    final fileName = '${gameRecord.name}.sgf';

    try {
      if (kIsWeb) {
        // On web, use share_plus or download
        await Share.share(sgfContent, subject: fileName);
      } else if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
        // On desktop, use save file dialog
        final outputPath = await FilePicker.platform.saveFile(
          dialogTitle: '匯出 SGF',
          fileName: fileName,
          type: FileType.any,
        );

        if (outputPath != null) {
          await File(outputPath).writeAsString(sgfContent);
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('已匯出至：$outputPath')),
            );
          }
        }
      } else {
        // On mobile, use share
        await Share.share(sgfContent, subject: fileName);
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('匯出失敗：$e')),
        );
      }
    }
  }

  void _showSettings(BuildContext context) {
    // Capture the provider from the current context
    final gameProvider = Provider.of<GameProvider>(context, listen: false);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (bottomSheetContext) => ChangeNotifierProvider.value(
        value: gameProvider,
        child: _SettingsSheet(
          // Pass the parent context so we can navigate with full Provider access
          parentContext: context,
        ),
      ),
    );
  }
}

class _AnalysisPanel extends StatefulWidget {
  const _AnalysisPanel();

  @override
  State<_AnalysisPanel> createState() => _AnalysisPanelState();
}

class _AnalysisPanelState extends State<_AnalysisPanel>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          height: 36,
          child: TabBar(
            controller: _tabController,
            tabs: const [Tab(text: 'Analysis'), Tab(text: 'History Record')],
            labelColor: Theme.of(context).primaryColor,
            indicatorColor: Theme.of(context).primaryColor,
            unselectedLabelColor: Colors.grey,
            labelStyle:
                const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: const [
              SingleChildScrollView(child: _AnalysisView()),
              _HistoryView(),
            ],
          ),
        ),
      ],
    );
  }
}

class _HistoryView extends StatelessWidget {
  const _HistoryView();

  @override
  Widget build(BuildContext context) {
    return Consumer<GameProvider>(
      builder: (context, game, _) {
        final moves = game.board.movesGtp;
        if (moves.isEmpty) {
          return const Center(
            child: Text('No moves played yet',
                style: TextStyle(color: Colors.grey)),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: moves.length,
          itemBuilder: (context, index) {
            final moveStr = moves[index];
            final parts = moveStr.split(' ');
            final colorCode = parts[0];
            final coord = parts.length > 1 ? parts[1] : '';
            final isBlack = colorCode == 'B';

            return Container(
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
              ),
              child: ListTile(
                dense: true,
                visualDensity: VisualDensity.compact,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
                leading: Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isBlack ? Colors.black : Colors.white,
                    border: isBlack ? null : Border.all(color: Colors.black),
                  ),
                  child: Center(
                    child: Text(
                      '${index + 1}',
                      style: TextStyle(
                        color: isBlack ? Colors.white : Colors.black,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                title: Text(
                  '${isBlack ? "Black" : "White"} placed at $coord',
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _AnalysisView extends StatelessWidget {
  const _AnalysisView();

  @override
  Widget build(BuildContext context) {
    return Consumer<GameProvider>(
      builder: (context, game, _) {
        if (game.isAnalyzing) {
          // Support both mobile and desktop progress
          final mobileProgress = game.analysisProgress;
          final desktopProgress = game.desktopAnalysisProgress;
          final hasProgress = mobileProgress != null || desktopProgress != null;

          // Extract current/max visits from whichever is active
          int? currentVisits;
          int? maxVisits;
          if (mobileProgress != null) {
            currentVisits = mobileProgress.currentVisits;
            maxVisits = mobileProgress.maxVisits;
          } else if (desktopProgress != null) {
            currentVisits = desktopProgress.currentVisits;
            maxVisits = desktopProgress.maxVisits;
          }

          return Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      hasProgress
                          ? 'Analyzing locally... $currentVisits/$maxVisits visits'
                          : 'Analyzing...',
                    ),
                    if (hasProgress) ...[
                      const SizedBox(width: 12),
                      IconButton(
                        icon: const Icon(Icons.cancel, size: 20),
                        onPressed: () => game.cancelAnalysis(),
                        tooltip: 'Cancel',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ],
                ),
                if (hasProgress &&
                    currentVisits != null &&
                    maxVisits != null) ...[
                  const SizedBox(height: 8),
                  LinearProgressIndicator(
                    value: currentVisits / maxVisits,
                    backgroundColor: Colors.grey.shade300,
                  ),
                ],
              ],
            ),
          );
        }

        if (game.error != null) {
          final showRetry = !game.localEngineRunning && game.localEngineEnabled;
          return Container(
            padding: const EdgeInsets.all(12),
            color: Colors.red.shade100,
            child: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.red),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    game.error!,
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
                if (showRetry)
                  TextButton(
                    onPressed: () async {
                      await game.restartEngine();
                      if (game.localEngineRunning) {
                        game.analyze();
                      }
                    },
                    child: const Text('Retry'),
                  ),
              ],
            ),
          );
        }

        final analysis = game.lastAnalysis;
        if (analysis == null) {
          return const Padding(
            padding: EdgeInsets.all(16.0),
            child: Text(
              'Tap on the board to place a stone',
              style: TextStyle(color: Colors.grey),
            ),
          );
        }

        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.grey.shade900,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey.shade800),
          ),
          child: DefaultTextStyle(
            style: const TextStyle(color: Colors.white),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'Top Moves',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const Spacer(),
                    _SourceChip(source: game.lastAnalysisSource),
                  ],
                ),
                const SizedBox(height: 8),
                // Make the moves list scrollable
                SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ...() {
                        // Show all moves without limitation
                        // Go players understand symmetry, so seeing all equivalent moves is informative
                        final uniqueMoves = <MoveCandidate>[];
                        final seenMoves = <String>{};

                        for (final move in analysis.topMoves) {
                          // Only deduplicate exact same move coordinates
                          if (!seenMoves.contains(move.move)) {
                            seenMoves.add(move.move);
                            uniqueMoves.add(move);
                          }
                        }

                        // Calculate display ranks based on winrate grouping
                        // This matches the logic in go_board_widget.dart
                        final moveRanks = <int, int>{}; // index -> displayRank
                        int currentRank = 0;
                        String? lastSignature;

                        for (int i = 0; i < uniqueMoves.length; i++) {
                          final move = uniqueMoves[i];
                          // Group by winrate and scoreLead signature
                          final signature = '${move.winratePercent}_${move.scoreLeadFormatted}';

                          if (signature != lastSignature) {
                            currentRank++;
                            lastSignature = signature;
                          }
                          moveRanks[i] = currentRank;
                        }

                        // Display all moves with grouped ranks
                        return uniqueMoves.asMap().entries.map((entry) {
                          final i = entry.key;
                          final move = entry.value;
                          final displayRank = moveRanks[i]!;
                          return _MoveRow(rank: displayRank, move: move);
                        });
                      }(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Chip showing the source of the analysis
class _SourceChip extends StatelessWidget {
  final AnalysisSource source;

  const _SourceChip({required this.source});

  @override
  Widget build(BuildContext context) {
    String label;
    Color backgroundColor;
    IconData icon;

    switch (source) {
      case AnalysisSource.openingBook:
        label = 'Book';
        backgroundColor = Colors.green.shade900;
        icon = Icons.menu_book;
        break;
      case AnalysisSource.localCache:
        label = 'Cache';
        backgroundColor = Colors.blue.shade900;
        icon = Icons.save;
        break;
      case AnalysisSource.localEngine:
        label = 'Local';
        backgroundColor = Colors.purple.shade900;
        icon = Icons.memory;
        break;
      case AnalysisSource.api:
        label = 'Live';
        backgroundColor = Colors.orange.shade900;
        icon = Icons.cloud;
        break;
      case AnalysisSource.none:
        return const SizedBox.shrink();
    }

    return Chip(
      avatar: Icon(icon, size: 14, color: Colors.white),
      label: Text(label),
      backgroundColor: backgroundColor,
      padding: EdgeInsets.zero,
      labelStyle: const TextStyle(fontSize: 10, color: Colors.white),
      visualDensity: VisualDensity.compact,
      side: BorderSide.none,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
    );
  }
}

class _MoveRow extends StatelessWidget {
  final int rank;
  final MoveCandidate move;

  const _MoveRow({required this.rank, required this.move});

  @override
  Widget build(BuildContext context) {
    // Extended color palette matching the board widget
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

    final colorIndex = (rank - 1).clamp(0, rankColors.length - 1);
    final rankColor = rankColors[colorIndex];

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(color: rankColor, shape: BoxShape.circle),
            child: Center(
              child: Text(
                '$rank',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(move.move,
              style: const TextStyle(
                  fontWeight: FontWeight.bold, color: Colors.white)),
          const SizedBox(width: 16),
          Text('Win: ${move.winratePercent}',
              style: const TextStyle(color: Colors.white)),
          const SizedBox(width: 16),
          Text('Lead: ${move.scoreLeadFormatted}',
              style: const TextStyle(color: Colors.white)),
          const Spacer(),
          Text(
            '${move.visits}v',
            style: TextStyle(color: Colors.grey.shade400, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _ControlsPanel extends StatelessWidget {
  const _ControlsPanel();

  @override
  Widget build(BuildContext context) {
    return Consumer<GameProvider>(
      builder: (context, game, _) {
        // If there's a pending move, show confirmation controls
        if (game.pendingMove != null) {
          return Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              border: Border(top: BorderSide(color: Colors.blue.shade200)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Adjust position with arrow keys',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Up arrow
                    Column(
                      children: [
                        IconButton(
                          onPressed: () => game.movePendingMove(0, -1),
                          icon: const Icon(Icons.arrow_upward),
                          style: IconButton.styleFrom(
                            backgroundColor: Colors.blue.shade100,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Left arrow
                    IconButton(
                      onPressed: () => game.movePendingMove(-1, 0),
                      icon: const Icon(Icons.arrow_back),
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.blue.shade100,
                      ),
                    ),
                    const SizedBox(width: 16),
                    // Confirm button
                    ElevatedButton.icon(
                      onPressed: () => game.confirmPendingMove(),
                      icon: const Icon(Icons.check),
                      label: const Text('Confirm'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 16),
                    // Right arrow
                    IconButton(
                      onPressed: () => game.movePendingMove(1, 0),
                      icon: const Icon(Icons.arrow_forward),
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.blue.shade100,
                      ),
                    ),
                  ],
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Down arrow
                    IconButton(
                      onPressed: () => game.movePendingMove(0, 1),
                      icon: const Icon(Icons.arrow_downward),
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.blue.shade100,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                TextButton.icon(
                  onPressed: () => game.cancelPendingMove(),
                  icon: const Icon(Icons.close, size: 16),
                  label: const Text('Cancel'),
                  style: TextButton.styleFrom(foregroundColor: Colors.red),
                ),
              ],
            ),
          );
        }

        // Normal controls
        return Container(
          padding: const EdgeInsets.all(12),
          child: Wrap(
            alignment: WrapAlignment.spaceEvenly,
            spacing: 8,
            runSpacing: 8,
            children: [
              ElevatedButton.icon(
                onPressed: game.board.moveCount > 0 ? () => game.undo() : null,
                icon: const Icon(Icons.undo),
                label: const Text('Undo'),
              ),
              ElevatedButton.icon(
                onPressed: game.board.moveCount > 0 ? () => game.clear() : null,
                icon: const Icon(Icons.clear),
                label: const Text('Clear'),
              ),
              ElevatedButton.icon(
                onPressed: game.isAnalyzing
                    ? null
                    : () => game.analyze(forceRefresh: true),
                icon: const Icon(Icons.refresh),
                label: const Text('Re-analyze'),
              ),
              ElevatedButton.icon(
                onPressed: game.board.moveCount > 0
                    ? () => _showSaveGameDialog(context)
                    : null,
                icon: const Icon(Icons.save),
                label: const Text('Save'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Show dialog to save current game
  static void _showSaveGameDialog(BuildContext context) {
    final nameController = TextEditingController();
    final blackPlayerController = TextEditingController();
    final whitePlayerController = TextEditingController();
    final notesController = TextEditingController();

    // Auto-generate default name with timestamp
    final now = DateTime.now();
    nameController.text = 'Game ${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('儲存棋譜'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: '棋譜名稱 *',
                  hintText: '請輸入棋譜名稱',
                ),
                autofocus: true,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: blackPlayerController,
                decoration: const InputDecoration(
                  labelText: '黑方棋手',
                  hintText: '選填',
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: whitePlayerController,
                decoration: const InputDecoration(
                  labelText: '白方棋手',
                  hintText: '選填',
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: notesController,
                decoration: const InputDecoration(
                  labelText: '備註',
                  hintText: '選填',
                ),
                maxLines: 3,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () async {
              final name = nameController.text.trim();
              if (name.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('請輸入棋譜名稱')),
                );
                return;
              }

              Navigator.of(dialogContext).pop();

              // Get game state and services
              final game = Provider.of<GameProvider>(context, listen: false);
              final recordService =
                  Provider.of<GameRecordService>(context, listen: false);

              // Convert BoardState moves to GameMove objects
              final moves = <record.GameMove>[];
              for (int i = 0; i < game.board.movesGtp.length; i++) {
                final moveGtp = game.board.movesGtp[i];
                final parts = moveGtp.split(' ');
                if (parts.length >= 2) {
                  moves.add(record.GameMove(
                    player: parts[0], // 'B' or 'W'
                    coordinate: parts[1], // GTP coordinate
                    moveNumber: i + 1,
                  ));
                }
              }

              // Create GameRecord
              final gameRecord = record.GameRecord(
                name: name,
                boardSize: game.board.size,
                komi: game.board.komi,
                handicap: game.board.handicap,
                moves: moves,
                blackPlayer: blackPlayerController.text.trim().isEmpty
                    ? null
                    : blackPlayerController.text.trim(),
                whitePlayer: whitePlayerController.text.trim().isEmpty
                    ? null
                    : whitePlayerController.text.trim(),
                notes: notesController.text.trim().isEmpty
                    ? null
                    : notesController.text.trim(),
              );

              // Save record
              final savedRecord = await recordService.saveRecord(gameRecord);

              if (savedRecord != null) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('棋譜已儲存：${savedRecord.name}'),
                      action: SnackBarAction(
                        label: '查看',
                        onPressed: () {
                          // Navigate to settings > records list
                          final authService =
                              Provider.of<AuthService>(context, listen: false);
                          final cloudStorage = Provider.of<CloudStorageManager>(
                              context,
                              listen: false);

                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (context) => MultiProvider(
                                providers: [
                                  ChangeNotifierProvider.value(
                                      value: authService),
                                  ChangeNotifierProvider.value(
                                      value: cloudStorage),
                                  ChangeNotifierProvider.value(
                                      value: recordService),
                                ],
                                child: const SettingsScreen(),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  );
                }
              } else {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                          '儲存失敗：${recordService.error ?? "未知錯誤"}'),
                    ),
                  );
                }
              }
            },
            child: const Text('儲存'),
          ),
        ],
      ),
    );
  }
}

/// Widget showing data statistics (opening book + cache)
class _DataStatsWidget extends StatelessWidget {
  final GameProvider game;

  const _DataStatsWidget({required this.game});

  @override
  Widget build(BuildContext context) {
    final bookStats = game.getOpeningBookStats();
    final isBookLoaded = bookStats['is_loaded'] as bool? ?? false;
    final bookEntries = bookStats['total_entries'] as int? ?? 0;
    final byBoardSize = bookStats['by_board_size'] as Map<int, int>? ?? {};

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Opening book status
        Row(
          children: [
            Icon(
              isBookLoaded ? Icons.check_circle : Icons.error,
              color: isBookLoaded ? Colors.green : Colors.red,
              size: 16,
            ),
            const SizedBox(width: 8),
            Text(
              isBookLoaded
                  ? 'Opening Book: $bookEntries positions'
                  : 'Opening Book: Not loaded',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
            ),
          ],
        ),
        if (isBookLoaded && byBoardSize.isNotEmpty) ...[
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 24),
            child: Text(
              byBoardSize.entries
                  .map((e) => '${e.key}x${e.key}: ${e.value}')
                  .join(' | '),
              style: TextStyle(color: Colors.grey.shade500, fontSize: 10),
            ),
          ),
        ],
        const SizedBox(height: 8),
        // Local cache stats
        FutureBuilder<Map<String, dynamic>>(
          future: game.getCacheStats(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return Text(
                'Local Cache: Loading...',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
              );
            }
            final stats = snapshot.data!;
            final localCache = stats['local_cache'] as Map<String, dynamic>?;
            final localEntries = localCache?['total_entries'] as int? ?? 0;
            return Row(
              children: [
                Icon(Icons.save, color: Colors.blue.shade300, size: 16),
                const SizedBox(width: 8),
                Text(
                  'Local Cache: $localEntries positions',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 8),
        // Engine status
        _buildEngineStatus(context),
      ],
    );
  }

  Widget _buildEngineStatus(BuildContext context) {
    if (!game.localEngineEnabled) {
      return Row(
        children: [
          const Icon(Icons.block, color: Colors.grey, size: 16),
          const SizedBox(width: 8),
          Text(
            'Local Engine: Disabled',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
          ),
        ],
      );
    }

    if (game.localEngineRunning) {
      return Row(
        children: [
          const Icon(Icons.check_circle, color: Colors.green, size: 16),
          const SizedBox(width: 8),
          Text(
            'Local Engine: Running',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
          ),
        ],
      );
    }

    // Enabled but not running
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.error, color: Colors.red, size: 16),
            const SizedBox(width: 8),
            Text(
              'Local Engine: Not running',
              style: TextStyle(color: Colors.red.shade400, fontSize: 12),
            ),
            const SizedBox(width: 8),
            SizedBox(
              height: 24,
              child: TextButton(
                onPressed: () => game.restartEngine(),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text('Restart', style: TextStyle(fontSize: 11)),
              ),
            ),
          ],
        ),
        if (game.engineError != null) ...[
          const SizedBox(height: 2),
          Padding(
            padding: const EdgeInsets.only(left: 24),
            child: Text(
              game.engineError!,
              style: TextStyle(color: Colors.red.shade300, fontSize: 10),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ],
    );
  }
}

class _SettingsSheet extends StatelessWidget {
  final BuildContext parentContext;

  const _SettingsSheet({required this.parentContext});

  @override
  Widget build(BuildContext context) {
    return Consumer<GameProvider>(
      builder: (context, game, _) {
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Settings',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  TextButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      // Capture all required providers from parentContext
                      final authService = Provider.of<AuthService>(parentContext, listen: false);
                      final cloudStorage = Provider.of<CloudStorageManager>(parentContext, listen: false);
                      final gameRecordService = Provider.of<GameRecordService>(parentContext, listen: false);

                      // Navigate with providers
                      Navigator.of(parentContext).push(
                        MaterialPageRoute(
                          builder: (context) => MultiProvider(
                            providers: [
                              ChangeNotifierProvider.value(value: authService),
                              ChangeNotifierProvider.value(value: cloudStorage),
                              ChangeNotifierProvider.value(value: gameRecordService),
                            ],
                            child: const SettingsScreen(),
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.account_circle, size: 20),
                    label: const Text('帳號與雲端'),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Board size
              const Text('Board Size'),
              const SizedBox(height: 8),
              SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 9, label: Text('9x9')),
                  ButtonSegment(value: 13, label: Text('13x13')),
                  ButtonSegment(value: 19, label: Text('19x19')),
                ],
                selected: {game.board.size},
                onSelectionChanged: (sizes) {
                  game.setBoardSize(sizes.first);
                  Navigator.pop(context);
                },
              ),
              const SizedBox(height: 16),

              // Lookup Visits (for opening book / database queries)
              const Text('Lookup Visits (Book/Cache threshold)'),
              const SizedBox(height: 4),
              Text(
                'Minimum visits required to use cached analysis',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: game.availableLookupVisits.map((v) {
                  return ChoiceChip(
                    label: Text('$v'),
                    selected: game.lookupVisits == v,
                    onSelected: (selected) {
                      if (selected) game.setLookupVisits(v);
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),

              // Compute Visits (for live KataGo analysis)
              const Text('Compute Visits (Live analysis)'),
              const SizedBox(height: 4),
              Text(
                'Visits for local KataGo engine',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: game.availableComputeVisits.map((v) {
                  return ChoiceChip(
                    label: Text('$v'),
                    selected: game.computeVisits == v,
                    onSelected: (selected) {
                      if (selected) game.setComputeVisits(v);
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),

              // Komi
              Row(
                children: [
                  const Text('Komi: '),
                  Text(
                    '${game.board.komi}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Slider(
                      value: game.board.komi,
                      min: 0,
                      max: 9,
                      divisions: 18,
                      label: '${game.board.komi}',
                      onChanged: (value) => game.setKomi(value),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              const Divider(),

              // Visual Settings
              SwitchListTile(
                title: const Text('Show Move Numbers'),
                subtitle: const Text('Display sequence numbers on stones'),
                value: game.showMoveNumbers,
                onChanged: (value) => game.setShowMoveNumbers(value),
                secondary: const Icon(Icons.numbers),
              ),
              SwitchListTile(
                title: const Text('Move Confirmation'),
                subtitle: const Text('Confirm moves with arrow keys to avoid mis-taps'),
                value: game.moveConfirmationEnabled,
                onChanged: (value) => game.setMoveConfirmationEnabled(value),
                secondary: const Icon(Icons.touch_app),
              ),
              const Divider(),

              // Opening book & cache stats
              _DataStatsWidget(game: game),

              const Divider(),

              // Version info
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Version ${AppConfig.fullVersion}',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade500,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
