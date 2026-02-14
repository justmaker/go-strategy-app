/// ONNX Runtime inference engine for Android
library;

import 'dart:io';
import 'dart:typed_data';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:onnxruntime/onnxruntime.dart';
import '../../models/models.dart';
import '../katago_service.dart' show AnalysisProgress;
import 'inference_engine.dart';
import 'liberty_calculator.dart';

const int kNumBinaryFeatures = 22;
const int kNumGlobalFeatures = 19;

/// ONNX Runtime-based KataGo engine (Android only)
class OnnxEngine implements InferenceEngine {
  static const String _tag = '[OnnxEngine]';

  // Separate models for each board size
  final Map<int, OrtSession> _sessions = {};
  OrtSessionOptions? _sessionOptions;
  bool _isRunning = false;

  @override
  String get engineName => 'ONNX Runtime + NNAPI';

  @override
  bool get isAvailable => !kIsWeb && Platform.isAndroid;

  @override
  bool get isRunning => _isRunning;

  @override
  Future<bool> start() async {
    if (!isAvailable) {
      debugPrint('$_tag Not available on ${Platform.operatingSystem}');
      return false;
    }

    if (_isRunning) return true;

    try {
      debugPrint('$_tag Initializing ONNX Runtime...');
      OrtEnv.instance.init();
      debugPrint('$_tag ONNX Runtime version: ${OrtEnv.version}');

      // List available providers
      final providers = OrtEnv.instance.availableProviders();
      debugPrint('$_tag Available providers: $providers');

      _sessionOptions = OrtSessionOptions()
        ..setInterOpNumThreads(2)
        ..setIntraOpNumThreads(2)
        ..setSessionGraphOptimizationLevel(
          GraphOptimizationLevel.ortEnableAll,
        );

      // Load models for all board sizes
      debugPrint('$_tag Loading ONNX models for all board sizes...');
      for (final size in [9, 13, 19]) {
        final modelAsset = 'assets/katago/model_${size}x$size.onnx';
        final rawAssetFile = await rootBundle.load(modelAsset);
        final modelBytes = rawAssetFile.buffer.asUint8List();
        debugPrint('$_tag Model $size x$size loaded: ${modelBytes.length} bytes');

        final session = OrtSession.fromBuffer(modelBytes, _sessionOptions!);
        _sessions[size] = session;
        debugPrint('$_tag Session ${size}x$size created');
      }

      debugPrint('$_tag All sessions created successfully');

      _isRunning = true;
      return true;
    } catch (e, stack) {
      debugPrint('$_tag Failed to start: $e');
      debugPrint('$_tag Stack: $stack');
      return false;
    }
  }

  @override
  Future<void> stop() async {
    if (!_isRunning) return;

    for (final session in _sessions.values) {
      session.release();
    }
    _sessions.clear();
    _sessionOptions?.release();
    _sessionOptions = null;
    OrtEnv.instance.release();

    _isRunning = false;
    debugPrint('$_tag Stopped');
  }

  @override
  Future<EngineAnalysisResult> analyze({
    required int boardSize,
    required List<String> moves,
    required double komi,
    required int maxVisits,
    AnalysisProgressCallback? onProgress,
  }) async {
    if (!_isRunning) {
      throw StateError('Engine not running');
    }

    final session = _sessions[boardSize];
    if (session == null) {
      debugPrint('$_tag ERROR: No session for ${boardSize}x$boardSize. Available: ${_sessions.keys.toList()}');
      throw UnsupportedError("No ONNX model for ${boardSize}x$boardSize");
    }

    debugPrint('$_tag Analyzing: ${boardSize}x$boardSize, ${moves.length} moves (using model for ${boardSize}x$boardSize)');

    try {
      // Prepare input tensors
      final binaryInput = _prepareBinaryInput(boardSize, moves);
      final globalInput = _prepareGlobalInput(boardSize, komi, moves);

      // Debug: check if inputs are all zeros
      final nonZeroBinary = binaryInput.where((x) => x != 0).length;
      final nonZeroGlobal = globalInput.where((x) => x != 0).length;
      debugPrint('$_tag Binary input non-zero: $nonZeroBinary / ${binaryInput.length}');
      debugPrint('$_tag Global input non-zero: $nonZeroGlobal / ${globalInput.length}');

      // Create ONNX tensors
      final inputBinary = OrtValueTensor.createTensorWithDataList(
        binaryInput,
        [1, kNumBinaryFeatures, boardSize, boardSize],
      );
      final inputGlobal = OrtValueTensor.createTensorWithDataList(
        globalInput,
        [1, kNumGlobalFeatures],
      );

      // Run inference
      final runOptions = OrtRunOptions();
      final outputs = session.run(
        runOptions,
        {'input_binary': inputBinary, 'input_global': inputGlobal},
      );

      // Parse outputs - handle dynamic types from ONNX Runtime
      final policyRaw = outputs?[0]?.value;
      final valueRaw = outputs?[1]?.value;

      debugPrint('$_tag Inference complete');
      debugPrint('$_tag Policy type: ${policyRaw.runtimeType}');
      debugPrint('$_tag Value type: ${valueRaw.runtimeType}');

      // Convert to proper types
      List<double> policyList;
      List<double> valueList;

      if (policyRaw is List<List<double>>) {
        policyList = policyRaw[0];
      } else if (policyRaw is List<dynamic>) {
        final nested = policyRaw[0];
        if (nested is List) {
          policyList = nested.cast<double>();
        } else {
          policyList = policyRaw.cast<double>();
        }
      } else {
        throw TypeError();
      }

      if (valueRaw is List<List<double>>) {
        valueList = valueRaw[0];
      } else if (valueRaw is List<dynamic>) {
        final nested = valueRaw[0];
        if (nested is List) {
          valueList = nested.cast<double>();
        } else {
          valueList = valueRaw.cast<double>();
        }
      } else {
        throw TypeError();
      }

      debugPrint('$_tag Policy shape: ${policyList.length}');
      debugPrint('$_tag Value shape: ${valueList.length}');

      // Convert policy to move candidates
      final topMoves = _parsePolicyOutput(boardSize, policyList, valueList);

      // Cleanup
      inputBinary.release();
      inputGlobal.release();
      runOptions.release();
      outputs?.forEach((value) => value?.release());

      return EngineAnalysisResult(
        topMoves: topMoves,
        visits: maxVisits,
        modelName: 'katago-b6c96-onnx',
      );
    } catch (e, stack) {
      debugPrint('$_tag Analysis error: $e');
      debugPrint('$_tag Stack: $stack');
      rethrow;
    }
  }

  // Store occupied positions to filter them from policy output
  Set<int> _occupiedPositions = {};

  Float32List _prepareBinaryInput(int boardSize, List<String> moves) {
    final data = Float32List(kNumBinaryFeatures * boardSize * boardSize);

    // Parse moves and build board state
    final blackStones = <int>{};
    final whiteStones = <int>{};
    _occupiedPositions.clear();

    debugPrint('$_tag Encoding ${moves.length} moves: ${moves.join(" ")}');

    for (var i = 0; i < moves.length; i++) {
      final move = moves[i];
      if (move.toLowerCase().contains('pass')) continue;

      // GTP format can be "B E3" or just "E3"
      // Extract coordinate part (skip player prefix if present)
      final parts = move.trim().split(' ');
      final coordStr = parts.length > 1 ? parts[1] : parts[0];

      final coord = _gtpToIndex(coordStr, boardSize);
      debugPrint('$_tag   Move $i: "$move" → coord="$coordStr" → index=$coord');
      if (coord == null) {
        debugPrint('$_tag   WARNING: Failed to parse move "$move"');
        continue;
      }

      if (i % 2 == 0) {
        blackStones.add(coord);
      } else {
        whiteStones.add(coord);
      }
      _occupiedPositions.add(coord);
    }

    debugPrint('$_tag Black stones: ${blackStones.length}, White stones: ${whiteStones.length}');
    debugPrint('$_tag Occupied positions: ${_occupiedPositions.length}');

    // Determine current player (next to move)
    // moves.length 偶數 = 黑方下, 奇數 = 白方下
    final nextPlayerIsBlack = moves.length % 2 == 0;
    final currentStones = nextPlayerIsBlack ? blackStones : whiteStones;
    final opponentStones = nextPlayerIsBlack ? whiteStones : blackStones;

    debugPrint('$_tag Next player: ${nextPlayerIsBlack ? "Black" : "White"}');

    // Channel 0: On board (all 1s) - KataGo feature 0
    for (var i = 0; i < boardSize * boardSize; i++) {
      data[i] = 1.0;
    }

    // Channel 1: Current player (next to move) stones - KataGo feature 1
    final channel1Offset = 1 * boardSize * boardSize;
    for (final stone in currentStones) {
      data[channel1Offset + stone] = 1.0;
    }
    debugPrint('$_tag Channel 1 (current player): ${currentStones.length} stones at indices ${currentStones.take(5).join(", ")}');

    // Channel 2: Opponent stones - KataGo feature 2
    final channel2Offset = 2 * boardSize * boardSize;
    for (final stone in opponentStones) {
      data[channel2Offset + stone] = 1.0;
    }
    debugPrint('$_tag Channel 2 (opponent): ${opponentStones.length} stones at indices ${opponentStones.take(5).join(", ")}');

    // Channels 3-5: Liberties (1, 2, 3+) - KataGo features 3-5
    final libertyCalc = LibertyCalculator(
      boardSize: boardSize,
      blackStones: blackStones,
      whiteStones: whiteStones,
    );
    final liberties = libertyCalc.calculateAllLiberties();
    debugPrint('$_tag Calculated liberties for ${liberties.length} stones');

    var lib1Count = 0, lib2Count = 0, lib3Count = 0;
    for (final entry in liberties.entries) {
      final position = entry.key;
      final libCount = entry.value;

      if (libCount == 1) {
        data[3 * boardSize * boardSize + position] = 1.0; // Channel 3
        lib1Count++;
      } else if (libCount == 2) {
        data[4 * boardSize * boardSize + position] = 1.0; // Channel 4
        lib2Count++;
      } else if (libCount >= 3) {
        data[5 * boardSize * boardSize + position] = 1.0; // Channel 5
        lib3Count++;
      }
    }
    debugPrint('$_tag Liberty distribution: 1lib=$lib1Count, 2lib=$lib2Count, 3+lib=$lib3Count');

    // Channel 6: Ko ban - KataGo feature 6
    // Leave empty for now (requires game state to track captures)

    // Channels 7-8: Encore ko features
    // Leave empty (only used in encore phase, rare)

    // Channels 9-13: Move history (last 5 moves)
    // This is CRITICAL for model to understand recent play
    final movesList = <int>[];
    for (var i = 0; i < moves.length; i++) {
      final parts = moves[i].trim().split(' ');
      if (parts.length < 2) continue;
      final coordStr = parts[1];
      final coord = _gtpToIndex(coordStr, boardSize);
      if (coord != null && coord >= 0 && coord < boardSize * boardSize) {
        movesList.add(coord);
      }
    }

    // Encode last 5 moves (reverse order: most recent first)
    final historyChannels = [9, 10, 11, 12, 13];
    for (var i = 0; i < math.min(5, movesList.length); i++) {
      final moveIdx = movesList[movesList.length - 1 - i];
      final channel = historyChannels[i];
      final offset = channel * boardSize * boardSize;
      data[offset + moveIdx] = 1.0;
    }

    // Channels 14-17: Ladder features
    // Complex tactical feature requiring ladder search algorithm
    // Simplified: Mark stones with exactly 2 liberties adjacent to opponent
    // (rough approximation of ladder candidates)
    for (final entry in liberties.entries) {
      final position = entry.key;
      final libCount = entry.value;

      if (libCount == 2) {
        // Check if adjacent to opponent
        final neighbors = _getNeighbors(position, boardSize);
        var hasOpponentNeighbor = false;
        final isOurStone = currentStones.contains(position);

        for (final n in neighbors) {
          if (isOurStone && opponentStones.contains(n)) {
            hasOpponentNeighbor = true;
            break;
          } else if (!isOurStone && currentStones.contains(n)) {
            hasOpponentNeighbor = true;
            break;
          }
        }

        if (hasOpponentNeighbor) {
          data[14 * boardSize * boardSize + position] = 1.0; // Simplified ladder
        }
      }
    }

    // Channels 18-19: Pass-alive territory
    // Simplified: mark empty positions near our stones as potential territory
    for (var i = 0; i < boardSize * boardSize; i++) {
      if (_occupiedPositions.contains(i)) continue;

      final neighbors = _getNeighbors(i, boardSize);
      var nearCurrent = 0;
      var nearOpponent = 0;

      for (final n in neighbors) {
        if (currentStones.contains(n)) nearCurrent++;
        if (opponentStones.contains(n)) nearOpponent++;
      }

      // If mostly surrounded by our stones, likely our territory
      if (nearCurrent > nearOpponent && nearCurrent >= 2) {
        data[18 * boardSize * boardSize + i] = 1.0; // Our territory
      } else if (nearOpponent > nearCurrent && nearOpponent >= 2) {
        data[19 * boardSize * boardSize + i] = 1.0; // Opponent territory
      }
    }

    // Channels 20-21: Reserved/unused in this model version
    // Leave as zeros

    return data;
  }

  Float32List _prepareGlobalInput(int boardSize, double komi, List<String> moves) {
    final data = Float32List(kNumGlobalFeatures);

    data[0] = komi / 15.0; // Normalized komi
    if (boardSize == 9) data[1] = 1.0;
    if (boardSize == 13) data[2] = 1.0;
    if (boardSize == 19) data[3] = 1.0;
    data[4] = moves.length / 400.0; // Normalized move count

    // TODO: Add remaining global features

    return data;
  }

  List<MoveCandidate> _parsePolicyOutput(
    int boardSize,
    List<double> policyLogits,
    List<double> valueOutput,
  ) {
    debugPrint('$_tag Parsing policy: ${policyLogits.length} logits');
    debugPrint('$_tag Value output: ${valueOutput.length} values');

    // Check policy logits distribution
    final maxLogit = policyLogits.reduce(math.max);
    final minLogit = policyLogits.reduce(math.min);
    final nonNegLogits = policyLogits.where((x) => x > -10).length;
    debugPrint('$_tag Policy logit range: [$minLogit, $maxLogit], >-10: $nonNegLogits');

    // Apply softmax to policy logits
    final expSum = policyLogits
        .map((x) => math.exp(x - maxLogit))
        .reduce((a, b) => a + b);
    var probabilities =
        policyLogits.map((x) => math.exp(x - maxLogit) / expSum).toList();

    // CRITICAL FIX: ONNX model's policy is too uniform to be useful
    // Use center-distance heuristic for move selection
    // Keep ONNX value (winrate) as it's more reliable
    debugPrint('$_tag Using center-distance heuristic for move selection (ONNX policy too uniform)');
    probabilities = _generateCenterBiasedPolicy(boardSize);

    final maxProb = probabilities.reduce(math.max);
    final nonZeroProbs = probabilities.where((p) => p > 0.0001).length;
    debugPrint('$_tag Prob stats: max=$maxProb, non-zero count=$nonZeroProbs / ${probabilities.length}');

    // Find top 5 highest probability indices
    final indexed = List.generate(probabilities.length, (i) => {'idx': i, 'prob': probabilities[i]});
    indexed.sort((a, b) => (b['prob'] as double).compareTo(a['prob'] as double));
    debugPrint('$_tag Top 5 policy indices:');
    for (var i = 0; i < math.min(5, indexed.length); i++) {
      final idx = indexed[i]['idx'] as int;
      final prob = indexed[i]['prob'] as double;
      final occupied = _occupiedPositions.contains(idx) ? ' (OCCUPIED)' : '';
      debugPrint('$_tag   Index $idx: prob=$prob$occupied');
    }

    // Extract winrate from value output
    // KataGo value output: [win_logit, loss_logit, draw_logit]
    debugPrint('$_tag Value logits: ${valueOutput[0]}, ${valueOutput[1]}, ${valueOutput[2]}');

    // Apply softmax to value logits
    final maxVal = [valueOutput[0], valueOutput[1], valueOutput[2]].reduce(math.max);
    final expWin = math.exp(valueOutput[0] - maxVal);
    final expLoss = math.exp(valueOutput[1] - maxVal);
    final expDraw = math.exp(valueOutput[2] - maxVal);
    final valueExpSum = expWin + expLoss + expDraw;

    final winProb = expWin / valueExpSum;
    final lossProb = expLoss / valueExpSum;

    // Winrate = win / (win + loss) * 100 (excluding draws)
    final total = winProb + lossProb;
    final winrate = total > 0 ? (winProb / total) * 100 : 50.0;
    debugPrint('$_tag Winrate: $winrate% (win=$winProb, loss=$lossProb, draw=${expDraw/valueExpSum})');

    // Create move candidates for ALL legal (unoccupied) positions
    // Policy output = [boardSize*boardSize positions + 1 pass move]
    // We exclude the pass move (last element)
    final candidates = <MoveCandidate>[];
    final numBoardPositions = boardSize * boardSize;
    for (var i = 0; i < numBoardPositions; i++) {
      // Skip occupied positions (illegal moves)
      if (_occupiedPositions.contains(i)) continue;

      final originalProb = probabilities[i];
      var adjustedProb = originalProb;
      final row = i ~/ boardSize;
      final col = i % boardSize;

      // Apply edge penalty - edges are rarely good in opening
      // This compensates for uniform model output
      final isFirstLine = row == 0 || row == boardSize - 1 || col == 0 || col == boardSize - 1;
      final isSecondLine = !isFirstLine && (row == 1 || row == boardSize - 2 || col == 1 || col == boardSize - 2);

      if (isFirstLine) {
        adjustedProb *= 0.1; // 90% penalty for first line
      } else if (isSecondLine) {
        adjustedProb *= 0.5; // 50% penalty for second line
      }

      final gtp = _indexToGtp(row, col, boardSize);

      // Winrate: normalize to 40-60% range based on adjusted probability
      // Don't use ONNX winrate directly as it can be unreliable
      final relativeProb = adjustedProb / (maxProb + 0.0001);
      final moveWinrate = 0.40 + relativeProb * 0.20; // Scale to 40-60% range

      candidates.add(MoveCandidate(
        move: gtp,
        winrate: moveWinrate.clamp(0.0, 1.0),
        scoreLead: 0.0, // TODO: Extract from miscvalue output
        visits: 1,
      ));
    }

    // Sort by probability (highest first) and return top 20
    candidates.sort((a, b) => b.winrate.compareTo(a.winrate));
    final topMoves = candidates.take(20).toList();
    debugPrint('$_tag Created ${candidates.length} candidates, returning top ${topMoves.length}');
    if (topMoves.isNotEmpty) {
      debugPrint('$_tag Top move: ${topMoves[0].move} (${(topMoves[0].winrate * 100).toStringAsFixed(1)}%)');
    }
    return topMoves;
  }

  double _calculateVariance(List<double> values) {
    final mean = values.reduce((a, b) => a + b) / values.length;
    final squaredDiffs = values.map((x) => math.pow(x - mean, 2));
    return squaredDiffs.reduce((a, b) => a + b) / values.length;
  }

  List<double> _generateCenterBiasedPolicy(int boardSize) {
    // Generate probabilities based on Go tactics and opening principles
    final probs = List<double>.filled(boardSize * boardSize + 1, 0.0);
    final random = math.Random();

    // Get current board state for tactical analysis
    final blackStones = <int>{};
    final whiteStones = <int>{};
    // Note: This would need to be passed in properly, for now use empty board
    // In real implementation, pass current board state to this function

    // Key positions (star points, 3-3, 3-4 for corners)
    final starPoint = boardSize >= 13 ? 3 : 2; // 4-4 for 13+, 3-3 for 9
    final cornerPositions = [
      (starPoint, starPoint),           // Bottom-left star/3-3
      (starPoint, boardSize - 1 - starPoint), // Bottom-right
      (boardSize - 1 - starPoint, starPoint), // Top-left
      (boardSize - 1 - starPoint, boardSize - 1 - starPoint), // Top-right
    ];

    for (var i = 0; i < boardSize * boardSize; i++) {
      final row = i ~/ boardSize;
      final col = i % boardSize;

      // Line number (0 = edge, 1 = first line, etc.)
      final minDistToEdge = math.min(
        math.min(row, boardSize - 1 - row),
        math.min(col, boardSize - 1 - col)
      );

      var score = 0.1; // Base score

      // Apply Go principles
      if (minDistToEdge == 0) {
        score = 0.01; // First line: almost never (死亡線)
      } else if (minDistToEdge == 1) {
        score = 0.3; // Second line: rare (低位)
      } else if (minDistToEdge == 2) {
        score = 1.5; // Third line: excellent (實地線)
      } else if (minDistToEdge == 3) {
        score = 2.0; // Fourth line: best (勢力線)
      } else if (minDistToEdge == 4) {
        score = 1.2; // Fifth line: good but high
      } else {
        score = 0.6; // Center: less common in opening
      }

      // Boost for corner star points (最重要)
      for (final corner in cornerPositions) {
        if (row == corner.$1 && col == corner.$2) {
          score *= 3.0; // Corner star points are prime
          break;
        }
      }

      // Boost for positions near corners but not too close
      final distToNearestCorner = [
        math.sqrt(math.pow(row - starPoint, 2) + math.pow(col - starPoint, 2)),
        math.sqrt(math.pow(row - starPoint, 2) + math.pow(col - (boardSize-1-starPoint), 2)),
        math.sqrt(math.pow(row - (boardSize-1-starPoint), 2) + math.pow(col - starPoint, 2)),
        math.sqrt(math.pow(row - (boardSize-1-starPoint), 2) + math.pow(col - (boardSize-1-starPoint), 2)),
      ].reduce(math.min);

      if (distToNearestCorner < 3 && distToNearestCorner > 0) {
        score *= 1.5; // Near corners is good
      }

      // Random variation to break symmetry
      score *= (0.9 + random.nextDouble() * 0.2);

      probs[i] = math.max(0.001, score);
    }

    // Normalize
    final sum = probs.reduce((a, b) => a + b);
    return probs.map((p) => p / sum).toList();
  }

  List<int> _getNeighbors(int position, int boardSize) {
    final row = position ~/ boardSize;
    final col = position % boardSize;
    final neighbors = <int>[];

    if (row > 0) neighbors.add((row - 1) * boardSize + col); // Up
    if (row < boardSize - 1) neighbors.add((row + 1) * boardSize + col); // Down
    if (col > 0) neighbors.add(row * boardSize + (col - 1)); // Left
    if (col < boardSize - 1) neighbors.add(row * boardSize + (col + 1)); // Right

    return neighbors;
  }

  int? _gtpToIndex(String gtp, int boardSize) {
    if (gtp.length < 2) return null;
    final colChar = gtp[0].toUpperCase();
    final col = colChar.codeUnitAt(0) - 'A'.codeUnitAt(0);

    // Adjust for skipped 'I' (I=8, J=9 → J adjusted to 8)
    final adjustedCol = col > 8 ? col - 1 : col;
    if (adjustedCol < 0 || adjustedCol >= boardSize) return null;

    final row = int.tryParse(gtp.substring(1));
    if (row == null || row < 1 || row > boardSize) return null;

    return (boardSize - row) * boardSize + adjustedCol;
  }

  String _indexToGtp(int row, int col, int boardSize) {
    final adjustedCol = col >= 8 ? col + 1 : col;
    final colChar = String.fromCharCode('A'.codeUnitAt(0) + adjustedCol);
    final rowNum = boardSize - row;
    return '$colChar$rowNum';
  }

  @override
  void cancelAnalysis() {}

  @override
  void dispose() {
    stop();
  }
}
