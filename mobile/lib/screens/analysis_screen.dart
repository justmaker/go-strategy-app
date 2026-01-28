/// Main analysis screen with Go board and move suggestions.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config.dart';
import '../models/models.dart';
import '../providers/providers.dart';
import '../widgets/widgets.dart';
import 'settings_screen.dart';

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
                  child: Column(
                    children: [
                      const Expanded(child: _AnalysisPanel()),
                      const Divider(height: 1),
                      const _ControlsPanel(),
                      const SizedBox(height: 16),
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
                SizedBox(
                  height: 240,
                  child: const _AnalysisPanel(),
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
          onTap: game.isAnalyzing
              ? null
              : (point) => game.placeStone(point),
        );
      },
    );
  }

  void _showSettings(BuildContext context) {
    // Capture the provider from the current context
    final gameProvider = Provider.of<GameProvider>(context, listen: false);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => ChangeNotifierProvider.value(
        value: gameProvider,
        child: const _SettingsSheet(),
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
                ...() {
                  // Deduplicate moves with similar winrate/lead for the list
                  final uniqueMoves = <MoveCandidate>[];
                  final seenMetrics = <String>{};

                  for (final move in analysis.topMoves) {
                    // Create a signature based on winrate (1 decimal) and lead (1 decimal)
                    final signature = '${move.winratePercent}_${move.scoreLeadFormatted}';
                    if (!seenMetrics.contains(signature)) {
                      seenMetrics.add(signature);
                      uniqueMoves.add(move);
                    }
                  }

                  // Only show top 3 tiers
                  final topTiers = uniqueMoves.take(3).toList();

                  return topTiers.asMap().entries.map((entry) {
                    final i = entry.key;
                    final move = entry.value;
                    // Use the tier index for dense ranking (1, 2, 3)
                    return _MoveRow(rank: i + 1, move: move);
                  });
                }(),
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
    Color rankColor;
    switch (rank) {
      case 1:
        rankColor = Colors.blue;
        break;
      case 2:
        rankColor = Colors.green;
        break;
      default:
        rankColor = Colors.orange;
    }

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
        return Container(
          padding: const EdgeInsets.all(12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
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
            ],
          ),
        );
      },
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
      ],
    );
  }
}

class _SettingsSheet extends StatelessWidget {
  const _SettingsSheet();

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
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) => const SettingsScreen(),
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
