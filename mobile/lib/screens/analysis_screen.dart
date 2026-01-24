/// Main analysis screen with Go board and move suggestions.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config.dart';
import '../models/models.dart';
import '../providers/providers.dart';
import '../widgets/widgets.dart';

class AnalysisScreen extends StatelessWidget {
  const AnalysisScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Go Strategy'),
        actions: [
          // Connection status indicator
          Consumer<GameProvider>(
            builder: (context, game, _) {
              IconData icon;
              Color color;
              switch (game.connectionStatus) {
                case ConnectionStatus.online:
                  icon = Icons.cloud_done;
                  color = Colors.green;
                  break;
                case ConnectionStatus.offline:
                  icon = Icons.cloud_off;
                  color = Colors.red;
                  break;
                case ConnectionStatus.checking:
                  icon = Icons.cloud_sync;
                  color = Colors.orange;
                  break;
              }
              return IconButton(
                icon: Icon(icon, color: color),
                onPressed: () => game.checkConnection(),
                tooltip: game.connectionStatus.name,
              );
            },
          ),
          // Settings
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => _showSettings(context),
          ),
        ],
      ),
      body: Column(
        children: [
          // Board
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Consumer<GameProvider>(
                builder: (context, game, _) {
                  return GoBoardWidget(
                    board: game.board,
                    suggestions: game.lastAnalysis?.topMoves,
                    onTap: game.isAnalyzing
                        ? null
                        : (point) => game.placeStone(point),
                  );
                },
              ),
            ),
          ),

          // Analysis panel
          const _AnalysisPanel(),

          // Controls
          const _ControlsPanel(),
        ],
      ),
    );
  }

  void _showSettings(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (context) => const _SettingsSheet(),
    );
  }
}

class _AnalysisPanel extends StatelessWidget {
  const _AnalysisPanel();

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
          color: Colors.grey.shade100,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    'Top Moves',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const Spacer(),
                  _SourceChip(source: game.lastAnalysisSource),
                ],
              ),
              const SizedBox(height: 8),
              ...analysis.topMoves.asMap().entries.map((entry) {
                final i = entry.key;
                final move = entry.value;
                return _MoveRow(rank: i + 1, move: move);
              }),
            ],
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
        backgroundColor = Colors.green.shade100;
        icon = Icons.menu_book;
        break;
      case AnalysisSource.localCache:
        label = 'Cache';
        backgroundColor = Colors.blue.shade100;
        icon = Icons.save;
        break;
      case AnalysisSource.localEngine:
        label = 'Local';
        backgroundColor = Colors.purple.shade100;
        icon = Icons.memory;
        break;
      case AnalysisSource.api:
        label = 'Live';
        backgroundColor = Colors.orange.shade100;
        icon = Icons.cloud;
        break;
      case AnalysisSource.none:
        return const SizedBox.shrink();
    }

    return Chip(
      avatar: Icon(icon, size: 14),
      label: Text(label),
      backgroundColor: backgroundColor,
      padding: EdgeInsets.zero,
      labelStyle: const TextStyle(fontSize: 10),
      visualDensity: VisualDensity.compact,
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
          Text(move.move, style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(width: 16),
          Text('Win: ${move.winratePercent}'),
          const SizedBox(width: 16),
          Text('Lead: ${move.scoreLeadFormatted}'),
          const Spacer(),
          Text(
            '${move.visits}v',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
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
                onPressed: game.isAnalyzing || game.board.moveCount == 0
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
        return Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Settings',
                style: Theme.of(context).textTheme.headlineSmall,
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

              // Local engine toggle
              SwitchListTile(
                title: const Text('Local KataGo Engine'),
                subtitle: Text(
                  game.localEngineRunning
                      ? 'Running (offline analysis available)'
                      : game.localEngineEnabled
                          ? 'Starting...'
                          : 'Disabled',
                  style: TextStyle(
                    fontSize: 12,
                    color: game.localEngineRunning ? Colors.green : Colors.grey,
                  ),
                ),
                value: game.localEngineEnabled,
                onChanged: (value) => game.setLocalEngineEnabled(value),
                secondary: Icon(
                  Icons.memory,
                  color: game.localEngineRunning ? Colors.green : Colors.grey,
                ),
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
