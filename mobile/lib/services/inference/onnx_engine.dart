/// ONNX Runtime inference engine for Android
library;

import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:onnxruntime/onnxruntime.dart';
import '../../models/models.dart';
import 'inference_engine.dart';
import 'liberty_calculator.dart';

const int kNumBinaryFeatures = 22;
const int kNumGlobalFeatures = 19;

/// ONNX Runtime-based KataGo engine (Android only)
class OnnxEngine implements InferenceEngine {
  static const String _tag = '[OnnxEngine]';

  // Single shared session for all board sizes (model has dynamic dimensions)
  OrtSession? _session;
  OrtSessionOptions? _sessionOptions;
  bool _isRunning = false;

  @override
  String get engineName => 'ONNX Runtime + NNAPI';

  @override
  bool get isAvailable => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  @override
  bool get isRunning => _isRunning;

  @override
  Future<bool> start({int boardSize = 19}) async {
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

      // Load single model (b20c256, dynamic board size)
      const modelAsset = 'assets/katago/model.onnx';
      debugPrint('$_tag Loading ONNX model: $modelAsset');
      final rawAssetFile = await rootBundle.load(modelAsset);
      final modelBytes = rawAssetFile.buffer.asUint8List();
      debugPrint('$_tag Model loaded: ${modelBytes.length} bytes');

      _session = OrtSession.fromBuffer(modelBytes, _sessionOptions!);
      debugPrint('$_tag Session created (dynamic board size)');

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

    _session?.release();
    _session = null;
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

    final session = _session;
    if (session == null) {
      throw StateError('ONNX session not initialized');
    }

    debugPrint('$_tag Analyzing: ${boardSize}x$boardSize, ${moves.length} moves');

    try {
      // Prepare input tensors (identity transform — also sets _occupiedPositions)
      final binaryInput = _prepareBinaryInput(boardSize, moves);
      final globalInput = _prepareGlobalInput(boardSize, komi, moves);

      // Debug: check if inputs are all zeros
      final nonZeroBinary = binaryInput.where((x) => x != 0).length;
      final nonZeroGlobal = globalInput.where((x) => x != 0).length;
      debugPrint('$_tag Binary input non-zero: $nonZeroBinary / ${binaryInput.length}');
      debugPrint('$_tag Global input non-zero: $nonZeroGlobal / ${globalInput.length}');

      final numPositions = boardSize * boardSize;

      // Run inference with all 8 board symmetries and average PROBABILITIES
      // (averaging logits flattens the distribution; averaging probs preserves it)
      final avgPolicyProbs = List<double>.filled(numPositions + 1, 0.0);
      double avgWinrate = 0.0;
      final runOptions = OrtRunOptions();

      for (int sym = 0; sym < 8; sym++) {
        final transformedInput = sym == 0
            ? binaryInput
            : _transformSpatialInput(binaryInput, boardSize, sym);

        final inputBinary = OrtValueTensor.createTensorWithDataList(
          transformedInput,
          [1, kNumBinaryFeatures, boardSize, boardSize],
        );
        final inputGlobal = OrtValueTensor.createTensorWithDataList(
          globalInput,
          [1, kNumGlobalFeatures],
        );

        final outputs = session.run(
          runOptions,
          {'input_binary': inputBinary, 'input_global': inputGlobal},
        );

        // Parse raw outputs
        final policyRaw = outputs[0]!.value;
        final valueRaw = outputs[1]!.value;

        List<double> policyList;
        List<double> valueList;

        if (policyRaw is List<List<double>>) {
          policyList = policyRaw[0];
        } else if (policyRaw is List<dynamic>) {
          final nested = policyRaw[0];
          policyList = nested is List ? nested.cast<double>() : policyRaw.cast<double>();
        } else {
          throw TypeError();
        }

        if (valueRaw is List<List<double>>) {
          valueList = valueRaw[0];
        } else if (valueRaw is List<dynamic>) {
          final nested = valueRaw[0];
          valueList = nested is List ? nested.cast<double>() : valueRaw.cast<double>();
        } else {
          throw TypeError();
        }

        // Softmax policy logits → probabilities (per symmetry)
        final maxLogit = policyList.reduce(math.max);
        final expSum = policyList
            .map((x) => math.exp(x - maxLogit))
            .reduce((a, b) => a + b);
        final probs = policyList
            .map((x) => math.exp(x - maxLogit) / expSum)
            .toList();

        // Inverse-transform probabilities back to original coordinate space
        final originalProbs = sym == 0
            ? probs
            : _inverseTransformPolicy(probs, boardSize, sym);

        // Accumulate probabilities
        for (int i = 0; i < originalProbs.length && i < avgPolicyProbs.length; i++) {
          avgPolicyProbs[i] += originalProbs[i];
        }

        // Softmax value logits → winrate (per symmetry)
        final maxVal = valueList.reduce(math.max);
        final expWin = math.exp(valueList[0] - maxVal);
        final expLoss = math.exp(valueList[1] - maxVal);
        final expDraw = math.exp(valueList[2] - maxVal);
        final valSum = expWin + expLoss + expDraw;
        final winProb = expWin / valSum;
        final lossProb = expLoss / valSum;
        final total = winProb + lossProb;
        avgWinrate += total > 0 ? winProb / total : 0.5;

        // Cleanup tensors
        inputBinary.release();
        inputGlobal.release();
        for (final v in outputs) {
          v?.release();
        }
      }

      runOptions.release();

      // Average over 8 symmetries
      for (int i = 0; i < avgPolicyProbs.length; i++) {
        avgPolicyProbs[i] /= 8.0;
      }
      avgWinrate /= 8.0;

      debugPrint('$_tag Symmetry-averaged inference complete (8 transforms)');
      debugPrint('$_tag Averaged winrate: ${(avgWinrate * 100).toStringAsFixed(1)}%');

      // Log policy quality (symmetry averaging naturally spreads probability
      // across equivalent positions, so lower max is expected and correct)
      final maxProb = avgPolicyProbs.reduce(math.max);
      final avgProb = avgPolicyProbs.reduce((a, b) => a + b) / avgPolicyProbs.length;
      debugPrint('$_tag Policy: max=$maxProb, avg=$avgProb, ratio=${maxProb / avgProb}');

      final finalProbs = avgPolicyProbs;

      // Create move candidates from averaged probabilities
      final topMoves = _createMoveCandidates(boardSize, finalProbs, avgWinrate);

      return EngineAnalysisResult(
        topMoves: topMoves,
        visits: maxVisits,
        modelName: 'katago-b20c256-onnx',
      );
    } catch (e, stack) {
      debugPrint('$_tag Analysis error: $e');
      debugPrint('$_tag Stack: $stack');
      rethrow;
    }
  }

  // Store occupied positions to filter them from policy output
  final Set<int> _occupiedPositions = {};


  Float32List _prepareBinaryInput(int boardSize, List<String> moves) {
    final data = Float32List(kNumBinaryFeatures * boardSize * boardSize);

    // Parse moves and build board state
    final blackStones = <int>{};
    final whiteStones = <int>{};
    final moveHistory = <int>[]; // Track move positions in order
    _occupiedPositions.clear();

    debugPrint('$_tag Encoding ${moves.length} moves: ${moves.join(" ")}');

    for (var i = 0; i < moves.length; i++) {
      final move = moves[i];
      if (move.toLowerCase().contains('pass')) {
        moveHistory.add(-1); // -1 = pass move
        continue;
      }

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
      moveHistory.add(coord);
    }

    debugPrint('$_tag Black stones: ${blackStones.length}, White stones: ${whiteStones.length}');
    debugPrint('$_tag Occupied positions: ${_occupiedPositions.length}');

    // Determine current player (next to move)
    // moves.length 偶數 = 黑方下, 奇數 = 白方下
    final nextPlayerIsBlack = moves.length % 2 == 0;
    final currentStones = nextPlayerIsBlack ? blackStones : whiteStones;
    final opponentStones = nextPlayerIsBlack ? whiteStones : blackStones;

    debugPrint('$_tag Next player: ${nextPlayerIsBlack ? "Black" : "White"}');

    // Channel 0: On board (all 1s)
    for (var i = 0; i < boardSize * boardSize; i++) {
      data[i] = 1.0;
    }

    // Channel 1: Current player stones
    final channel1Offset = 1 * boardSize * boardSize;
    for (final stone in currentStones) {
      data[channel1Offset + stone] = 1.0;
    }
    debugPrint('$_tag Channel 1 (current player): ${currentStones.length} stones');

    // Channel 2: Opponent stones
    final channel2Offset = 2 * boardSize * boardSize;
    for (final stone in opponentStones) {
      data[channel2Offset + stone] = 1.0;
    }
    debugPrint('$_tag Channel 2 (opponent): ${opponentStones.length} stones');

    // Channel 3: Ko-banned locations
    // Simplified: mark the last capture location if it was a single stone capture
    if (moveHistory.length >= 2) {
      final lastMove = moveHistory[moveHistory.length - 1];
      final prevMove = moveHistory[moveHistory.length - 2];
      // Simple ko detection: if last move captured a single stone at prevMove
      // In full implementation, would check if move was a recapture
      // For now, leave empty (complex to implement without full game tree)
    }

    // Channels 4-5: Encore ko features (leave empty - rare)

    // Channels 6-10: Move history (last 5 moves, alternating players)
    // Channel 6: opponent's last move (most recent)
    // Channel 7: current player's move 2 turns ago
    // Channel 8: opponent's move 3 turns ago
    // Channel 9: current player's move 4 turns ago
    // Channel 10: opponent's move 5 turns ago
    final historyChannels = [6, 7, 8, 9, 10];
    for (var i = 0; i < math.min(5, moveHistory.length); i++) {
      final moveIdx = moveHistory[moveHistory.length - 1 - i];
      if (moveIdx >= 0 && moveIdx < boardSize * boardSize) {
        final channel = historyChannels[i];
        final offset = channel * boardSize * boardSize;
        data[offset + moveIdx] = 1.0;
      }
    }
    debugPrint('$_tag Encoded ${math.min(5, moveHistory.length)} moves in history');

    // Channels 11-13: Reserved for future move history

    // Channels 14-17: Ladder features
    // Channel 14: Groups in atari or capturable by ladder
    final libertyCalc = LibertyCalculator(
      boardSize: boardSize,
      blackStones: blackStones,
      whiteStones: whiteStones,
    );
    final liberties = libertyCalc.calculateAllLiberties();

    var atariCount = 0;
    for (final entry in liberties.entries) {
      final position = entry.key;
      final libCount = entry.value;

      if (libCount == 1) {
        data[14 * boardSize * boardSize + position] = 1.0; // Atari (1 liberty)
        atariCount++;
      }
    }
    debugPrint('$_tag Channel 14 (atari): $atariCount stones');

    // Channels 15-17: Ladder history and escape moves (leave simplified)

    // Channels 18-19: Territory/area estimation
    // Use more sophisticated flood-fill based territory detection
    final territories = _calculateTerritories(boardSize, currentStones, opponentStones);
    for (final entry in territories.entries) {
      final position = entry.key;
      final owner = entry.value; // 1 = current, 2 = opponent

      if (owner == 1) {
        data[18 * boardSize * boardSize + position] = 1.0;
      } else if (owner == 2) {
        data[19 * boardSize * boardSize + position] = 1.0;
      }
    }

    // Channels 20-21: Encore phase stones (leave empty - not in main game)

    return data;
  }

  // Calculate territory ownership using flood-fill from stones
  Map<int, int> _calculateTerritories(int boardSize, Set<int> currentStones, Set<int> opponentStones) {
    final territories = <int, int>{};
    final visited = <int>{};

    // For each empty position, do flood fill to determine ownership
    for (var i = 0; i < boardSize * boardSize; i++) {
      if (_occupiedPositions.contains(i) || visited.contains(i)) continue;

      // Flood fill from this empty point
      final region = <int>{};
      final queue = <int>[i];
      var touchesCurrent = false;
      var touchesOpponent = false;

      while (queue.isNotEmpty) {
        final pos = queue.removeAt(0);
        if (visited.contains(pos)) continue;

        visited.add(pos);
        region.add(pos);

        for (final neighbor in _getNeighbors(pos, boardSize)) {
          if (currentStones.contains(neighbor)) {
            touchesCurrent = true;
          } else if (opponentStones.contains(neighbor)) {
            touchesOpponent = true;
          } else if (!visited.contains(neighbor)) {
            queue.add(neighbor);
          }
        }
      }

      // Assign ownership if region touches only one color
      if (touchesCurrent && !touchesOpponent) {
        for (final pos in region) {
          territories[pos] = 1; // Current player
        }
      } else if (touchesOpponent && !touchesCurrent) {
        for (final pos in region) {
          territories[pos] = 2; // Opponent
        }
      }
      // If touches both or neither, leave as neutral (no territory)
    }

    return territories;
  }

  Float32List _prepareGlobalInput(int boardSize, double komi, List<String> moves) {
    final data = Float32List(kNumGlobalFeatures);

    // Features 0-4: Pass move indicators for last 5 turns
    for (var i = 0; i < 5 && i < moves.length; i++) {
      final move = moves[moves.length - 1 - i];
      if (move.toLowerCase().contains('pass')) {
        data[i] = 1.0;
      }
    }

    // Feature 5: Self-komi from current player's perspective, normalized by 20.0
    // Black's turn: negative (black gives komi to white)
    // White's turn: positive (white receives komi)
    final isBlackTurn = moves.length % 2 == 0;
    final selfKomi = isBlackTurn ? -komi : komi;
    data[5] = selfKomi / 20.0;

    // Features 6-7: Ko rule encoding
    // 6 = positional superko, 7 = situational superko
    // Default to simple ko (neither flag set)
    data[6] = 0.0; // Not using positional superko
    data[7] = 0.0; // Not using situational superko

    // Feature 8: Multi-stone suicide legality (1.0 = allowed)
    // Standard rules forbid suicide
    data[8] = 0.0;

    // Feature 9: Territory scoring (1.0 = territory, 0.0 = area)
    // Using area scoring (Chinese rules)
    data[9] = 0.0;

    // Features 10-11: Tax rules (rare variants)
    data[10] = 0.0; // No seki tax
    data[11] = 0.0; // No all-stone tax

    // Features 12-13: Encore phase (almost never used)
    data[12] = 0.0; // Not in encore phase
    data[13] = 0.0; // Not in second encore

    // Feature 14: Pass would end phase
    // In normal play, pass doesn't end the phase
    data[14] = 0.0;

    // Feature 15: Komi parity (scaled by board area)
    final bArea = (boardSize * boardSize).toDouble();
    data[15] = 0.20 * selfKomi / (bArea * 0.25 + 7.5);

    // Features 16-18: Reserved/unused
    data[16] = 0.0;
    data[17] = 0.0;
    data[18] = 0.0;

    debugPrint('$_tag Global features: komi=${data[5]}, pass_indicators=[${data[0]},${data[1]},${data[2]},${data[3]},${data[4]}]');

    return data;
  }


  /// Create move candidates from pre-computed probabilities and winrate.
  List<MoveCandidate> _createMoveCandidates(
      int boardSize, List<double> probs, double baseWinrate) {
    final numBoardPositions = boardSize * boardSize;
    final candidates = <MoveCandidate>[];

    // Find top probability among legal moves for scaling
    final legalProbs = <double>[];
    for (var i = 0; i < numBoardPositions; i++) {
      if (!_occupiedPositions.contains(i)) {
        legalProbs.add(probs[i]);
      }
    }
    legalProbs.sort((a, b) => b.compareTo(a));
    final topProb = legalProbs.isNotEmpty ? legalProbs[0] : 0.001;

    for (var i = 0; i < numBoardPositions; i++) {
      if (_occupiedPositions.contains(i)) continue;

      final prob = probs[i];
      final row = i ~/ boardSize;
      final col = i % boardSize;
      final gtp = _indexToGtp(row, col, boardSize);

      final relativeProb = prob / topProb;
      final moveWinrate = baseWinrate - (1.0 - relativeProb) * 0.15;

      candidates.add(MoveCandidate(
        move: gtp,
        winrate: moveWinrate.clamp(0.0, 1.0),
        scoreLead: 0.0,
        visits: 1,
      ));
    }

    candidates.sort((a, b) => b.winrate.compareTo(a.winrate));
    final topMoves = candidates.take(20).toList();

    debugPrint('$_tag Created ${candidates.length} candidates, returning top ${topMoves.length}');
    if (topMoves.length >= 3) {
      debugPrint('$_tag Top 3 moves:');
      for (var i = 0; i < 3; i++) {
        debugPrint(
            '$_tag   ${i + 1}. ${topMoves[i].move}: ${(topMoves[i].winrate * 100).toStringAsFixed(1)}%');
      }
    }

    return topMoves;
  }

  /// Apply symmetry transform to binary input spatial dimensions.
  /// Input shape: [kNumBinaryFeatures × boardSize × boardSize] (flattened).
  Float32List _transformSpatialInput(Float32List input, int boardSize, int symmetry) {
    final size = boardSize * boardSize;
    final result = Float32List(input.length);

    for (int c = 0; c < kNumBinaryFeatures; c++) {
      final offset = c * size;
      for (int r = 0; r < boardSize; r++) {
        for (int col = 0; col < boardSize; col++) {
          final (newR, newC) = _applySymmetry(r, col, boardSize, symmetry);
          result[offset + newR * boardSize + newC] =
              input[offset + r * boardSize + col];
        }
      }
    }
    return result;
  }

  /// Inverse-transform policy from symmetry-transformed space back to original.
  List<double> _inverseTransformPolicy(
      List<double> policy, int boardSize, int symmetry) {
    final size = boardSize * boardSize;
    final result = List<double>.filled(policy.length, 0.0);

    for (int r = 0; r < boardSize; r++) {
      for (int col = 0; col < boardSize; col++) {
        final (symR, symC) = _applySymmetry(r, col, boardSize, symmetry);
        result[r * boardSize + col] = policy[symR * boardSize + symC];
      }
    }

    // Pass move probability unchanged
    if (policy.length > size) {
      result[size] = policy[size];
    }
    return result;
  }

  /// Map board coordinates through one of 8 symmetry transforms.
  static (int, int) _applySymmetry(
      int row, int col, int boardSize, int symmetry) {
    final n = boardSize - 1;
    switch (symmetry) {
      case 0: return (row, col);         // identity
      case 1: return (col, n - row);     // rotate 90° CW
      case 2: return (n - row, n - col); // rotate 180°
      case 3: return (n - col, row);     // rotate 270° CW
      case 4: return (row, n - col);     // flip horizontal
      case 5: return (n - row, col);     // flip vertical
      case 6: return (col, row);         // flip main diagonal
      case 7: return (n - col, n - row); // flip anti-diagonal
      default: return (row, col);
    }
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
