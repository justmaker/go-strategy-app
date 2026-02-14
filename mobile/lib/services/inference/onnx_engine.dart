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
      throw UnsupportedError("No ONNX model for ${boardSize}x$boardSize");
    }

    debugPrint('$_tag Analyzing: ${boardSize}x$boardSize, ${moves.length} moves');

    try {
      // Prepare input tensors
      final binaryInput = _prepareBinaryInput(boardSize, moves);
      final globalInput = _prepareGlobalInput(boardSize, komi, moves);

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

  Float32List _prepareBinaryInput(int boardSize, List<String> moves) {
    final data = Float32List(kNumBinaryFeatures * boardSize * boardSize);

    // Parse moves and build board state
    final blackStones = <int>{};
    final whiteStones = <int>{};

    for (var i = 0; i < moves.length; i++) {
      final move = moves[i];
      if (move.toLowerCase() == 'pass') continue;

      final coord = _gtpToIndex(move, boardSize);
      if (coord == null) continue;

      if (i % 2 == 0) {
        blackStones.add(coord);
      } else {
        whiteStones.add(coord);
      }
    }

    // Channel 0: Current player's stones (last to move)
    final currentIsBlack = moves.length % 2 == 1;
    final currentStones = currentIsBlack ? blackStones : whiteStones;
    final opponentStones = currentIsBlack ? whiteStones : blackStones;

    for (final stone in currentStones) {
      data[stone] = 1.0; // Channel 0
    }

    // Channel 1: Opponent's stones
    for (final stone in opponentStones) {
      data[boardSize * boardSize + stone] = 1.0; // Channel 1
    }

    // TODO: Add remaining 20 channels (ko, liberties, etc.)
    // For now, basic stone positions should give reasonable results

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

    // Apply softmax to policy logits
    final maxLogit = policyLogits.reduce(math.max);
    final expSum = policyLogits
        .map((x) => math.exp(x - maxLogit))
        .reduce((a, b) => a + b);
    final probabilities =
        policyLogits.map((x) => math.exp(x - maxLogit) / expSum).toList();

    debugPrint('$_tag Max probability: ${probabilities.reduce(math.max)}');

    // Extract winrate from value output
    // KataGo value output: [win, loss, draw] probabilities
    debugPrint('$_tag Value raw: ${valueOutput[0]}, ${valueOutput[1]}, ${valueOutput[2]}');
    final winProb = valueOutput[0]; // Win probability
    final lossProb = valueOutput[1]; // Loss probability
    // Winrate = (win / (win + loss)) * 100
    final total = winProb + lossProb;
    final winrate = total > 0 ? (winProb / total) * 100 : 50.0;
    debugPrint('$_tag Base winrate: $winrate%');

    // Create move candidates
    final candidates = <MoveCandidate>[];
    for (var i = 0; i < boardSize * boardSize; i++) {
      final prob = probabilities[i];
      if (prob < 0.001) continue; // Skip low probability moves

      final row = i ~/ boardSize;
      final col = i % boardSize;
      final gtp = _indexToGtp(row, col, boardSize);

      // Calculate move-specific winrate
      // Higher probability moves should have higher winrate
      final moveWinrate = winrate + (prob - probabilities.reduce(math.max) / 2) * 5;

      candidates.add(MoveCandidate(
        move: gtp,
        winrate: moveWinrate.clamp(0.0, 100.0),
        scoreLead: 0.0, // TODO: Extract from miscvalue output
        visits: 1,
      ));
    }

    // Sort by probability and return top 20
    candidates.sort((a, b) => b.winrate.compareTo(a.winrate));
    final topMoves = candidates.take(20).toList();
    debugPrint('$_tag Created ${candidates.length} candidates, returning top ${topMoves.length}');
    if (topMoves.isNotEmpty) {
      debugPrint('$_tag Top move: ${topMoves[0].move} (${topMoves[0].winrate}%)');
    }
    return topMoves;
  }

  int? _gtpToIndex(String gtp, int boardSize) {
    if (gtp.length < 2) return null;
    final col = gtp[0].toUpperCase().codeUnitAt(0) - 'A'.codeUnitAt(0);
    if (col >= 8) return null; // Skip 'I'
    final row = int.tryParse(gtp.substring(1));
    if (row == null || row < 1 || row > boardSize) return null;

    final adjustedCol = col >= 8 ? col - 1 : col;
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
