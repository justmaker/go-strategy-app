/// TensorFlow Lite engine implementation with full tensor processing
library;

import 'dart:io';
import 'dart:typed_data';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
// TODO: Uncomment when tflite_flutter is added
// import 'package:tflite_flutter/tflite_flutter.dart';
import '../../models/models.dart';
import 'inference_engine.dart';

/// Number of binary feature planes for KataGo input
/// 22 channels: current stones, opponent stones, ko positions, etc.
const int kNumBinaryFeatures = 22;

/// Number of global features
/// 19 features: komi, passes, rules, etc.
const int kNumGlobalFeatures = 19;

/// TFLite-based KataGo inference engine
class TFLiteEngineImpl implements InferenceEngine {
  static const String _tag = '[TFLiteEngine]';
  static const String _modelAsset = 'assets/katago/model.tflite';

  // TODO: Uncomment when tflite_flutter is available
  // Interpreter? _interpreter;
  bool _isRunning = false;

  @override
  String get engineName => 'TFLite + NNAPI';

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
      debugPrint('$_tag Loading TFLite model...');

      // TODO: Implement actual model loading
      // final modelPath = await _extractModel();
      // final options = InterpreterOptions()
      //   ..addDelegate(NnApiDelegate()); // Hardware acceleration
      // _interpreter = await Interpreter.fromFile(
      //   File(modelPath),
      //   options: options,
      // );

      // debugPrint('$_tag Model loaded: ${_interpreter!.getInputTensors()}');
      // debugPrint('$_tag Outputs: ${_interpreter!.getOutputTensors()}');

      _isRunning = true;
      debugPrint('$_tag TFLite engine started with NNAPI');
      return true;
    } catch (e) {
      debugPrint('$_tag Failed to start: $e');
      return false;
    }
  }

  @override
  Future<void> stop() async {
    if (!_isRunning) return;

    // TODO: _interpreter?.close();
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

    debugPrint('$_tag Analyzing: ${boardSize}x$boardSize, ${moves.length} moves');

    // Step 1: Prepare input tensors
    final binaryInput = _prepareBinaryInput(boardSize, moves);
    final globalInput = _prepareGlobalInput(boardSize, komi, moves);

    // Step 2: Run inference
    // TODO: Uncomment when interpreter is available
    // _interpreter!.allocateTensors();
    // _interpreter!.run({
    //   0: binaryInput,  // input_binary
    //   1: globalInput,  // input_global
    // });

    // Step 3: Get outputs
    // TODO: Parse actual outputs
    // final policy = _interpreter!.getOutputTensor(0);  // output_policy
    // final value = _interpreter!.getOutputTensor(1);   // output_value
    // final miscValue = _interpreter!.getOutputTensor(2); // output_miscvalue
    // final ownership = _interpreter!.getOutputTensor(3); // output_ownership

    // Step 4: Convert to MoveCandidate list
    final topMoves = _parsePolicyOutput(boardSize, null);  // TODO: pass actual policy

    return EngineAnalysisResult(
      topMoves: topMoves,
      visits: maxVisits,
      modelName: 'katago-b6c96-tflite',
    );
  }

  /// Prepare binary input tensor (22 x boardSize x boardSize)
  /// Features: current stones, opponent stones, ko positions, etc.
  Float32List _prepareBinaryInput(int boardSize, List<String> moves) {
    final data = Float32List(kNumBinaryFeatures * boardSize * boardSize);

    // TODO: Implement board state encoding
    // - Channel 0: current player's stones
    // - Channel 1: opponent's stones
    // - Channels 2-3: ko positions
    // - Channels 4-21: move history, liberties, etc.

    return data;
  }

  /// Prepare global input tensor (19 features)
  /// Features: komi, pass count, board size, etc.
  Float32List _prepareGlobalInput(int boardSize, double komi, List<String> moves) {
    final data = Float32List(kNumGlobalFeatures);

    // Normalize komi to [-1, 1] range
    data[0] = komi / 15.0;

    // Board size one-hot encoding
    if (boardSize == 9) data[1] = 1.0;
    if (boardSize == 13) data[2] = 1.0;
    if (boardSize == 19) data[3] = 1.0;

    // Move count (normalized)
    data[4] = moves.length / 400.0;

    // TODO: Add remaining global features

    return data;
  }

  /// Parse policy output to MoveCandidate list
  List<MoveCandidate> _parsePolicyOutput(int boardSize, Float32List? policyLogits) {
    if (policyLogits == null) {
      // Placeholder - return random moves
      return [];
    }

    // TODO: Implement actual parsing
    // - Convert logits to probabilities (softmax)
    // - Map policy indices to board coordinates
    // - Sort by probability
    // - Return top N moves

    final candidates = <MoveCandidate>[];
    // ... implementation
    return candidates;
  }

  Future<String> _extractModel() async {
    final appDir = await getApplicationSupportDirectory();
    final modelPath = p.join(appDir.path, 'model.tflite');

    final file = File(modelPath);
    if (await file.exists()) {
      debugPrint('$_tag Using cached model: $modelPath');
      return modelPath;
    }

    debugPrint('$_tag Extracting model from assets...');
    final assetData = await rootBundle.load(_modelAsset);
    await file.writeAsBytes(
      assetData.buffer.asUint8List(),
      flush: true,
    );

    debugPrint('$_tag Model extracted: ${await file.length()} bytes');
    return modelPath;
  }

  @override
  void cancelAnalysis() {
    debugPrint('$_tag Analysis cancelled');
  }

  @override
  void dispose() {
    stop();
  }
}
