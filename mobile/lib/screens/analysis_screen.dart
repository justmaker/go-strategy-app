/// Main analysis screen with Go board and move suggestions.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
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
                    onTap: game.isAnalyzing ? null : (point) => game.placeStone(point),
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
          return const Padding(
            padding: EdgeInsets.all(16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 12),
                Text('Analyzing...'),
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
                Expanded(child: Text(game.error!, style: const TextStyle(color: Colors.red))),
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
                  if (analysis.fromCache)
                    Chip(
                      label: const Text('Cached'),
                      backgroundColor: Colors.blue.shade100,
                      padding: EdgeInsets.zero,
                      labelStyle: const TextStyle(fontSize: 10),
                    ),
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
            decoration: BoxDecoration(
              color: rankColor,
              shape: BoxShape.circle,
            ),
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
          Text(
            move.move,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
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
              Text('Settings', style: Theme.of(context).textTheme.headlineSmall),
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

              // Visits
              const Text('Analysis Visits'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: GameProvider.availableVisits.map((v) {
                  return ChoiceChip(
                    label: Text('$v'),
                    selected: game.selectedVisits == v,
                    onSelected: (selected) {
                      if (selected) game.setVisits(v);
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

              // Cache stats
              FutureBuilder<Map<String, dynamic>>(
                future: game.getCacheStats(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const Text('Loading cache stats...');
                  }
                  final stats = snapshot.data!;
                  return Text(
                    'Local Cache: ${stats['total_entries']} positions',
                    style: TextStyle(color: Colors.grey.shade600),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }
}
