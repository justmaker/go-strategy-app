/// ONNX Runtime inference engine for Android
///
/// Uses ONNX Runtime Mobile with NNAPI for hardware acceleration.
/// Avoids pthread crash by using pure Dart/Java inference (no native threads).
library;

import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:onnxruntime/onnxruntime.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../../models/models.dart';
import 'inference_engine.dart';

const int kNumBinaryFeatures = 22;
const int kNumGlobalFeatures = 19;

/// ONNX Runtime-based KataGo engine (Android only)
class OnnxEngine implements InferenceEngine {
  static const String _tag = '[OnnxEngine]';
  static const String _modelAsset = 'assets/katago/model.onnx';

  OrtSession? _session;
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

      debugPrint('$_tag Loading ONNX model...');
      final modelPath = await _extractModel();

      final sessionOptions = OrtSessionOptions()
        ..setInterOpNumThreads(4)
        ..setIntraOpNumThreads(4)
        ..setSessionGraphOptimizationLevel(
          GraphOptimizationLevel.ortEnableAll,
        );

      // Try to add NNAPI provider for hardware acceleration
      try {
        sessionOptions.appendProvider('nnapi');
        debugPrint('$_tag NNAPI provider enabled');
      } catch (e) {
        debugPrint('$_tag NNAPI not available, using CPU: $e');
      }

      _session = OrtSession.fromFile(modelPath, sessionOptions);

      debugPrint('$_tag Model loaded successfully');
      debugPrint('$_tag Inputs: ${_session!.inputNames}');
      debugPrint('$_tag Outputs: ${_session!.outputNames}');

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
    if (!_isRunning || _session == null) {
      throw StateError('Engine not running');
    }

    debugPrint('$_tag Analyzing: ${boardSize}x$boardSize, ${moves.length} moves');

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
    final outputs = _session!.run(
      runOptions,
      {
        'input_binary': inputBinary,
        'input_global': inputGlobal,
      },
    );

    // Parse outputs
    final policyOutput = outputs?['output_policy']?.value as List<List<double>>;
    final valueOutput = outputs?['output_value']?.value as List<List<double>>;

    // Convert policy to move candidates
    final topMoves = _parsePolicyOutput(boardSize, policyOutput?[0]);

    // Cleanup
    inputBinary.release();
    inputGlobal.release();
    runOptions.release();
    outputs?.forEach((_, value) => value?.release());

    debugPrint('$_tag Analysis complete: ${topMoves.length} moves');

    return EngineAnalysisResult(
      topMoves: topMoves,
      visits: maxVisits,
      modelName: 'katago-b6c96-onnx',
    );
  }

  Float32List _prepareBinaryInput(int boardSize, List<String> moves) {
    final data = Float32List(kNumBinaryFeatures * boardSize * boardSize);

    // TODO: Implement full board state encoding
    // For now, just zeros (placeholder)

    return data;
  }

  Float32List _prepareGlobalInput(int boardSize, double komi, List<String> moves) {
    final data = Float32List(kNumGlobalFeatures);

    // Normalize komi
    data[0] = komi / 15.0;

    // Board size one-hot
    if (boardSize == 9) data[1] = 1.0;
    if (boardSize == 13) data[2] = 1.0;
    if (boardSize == 19) data[3] = 1.0;

    // Move count
    data[4] = moves.length / 400.0;

    return data;
  }

  List<MoveCandidate> _parsePolicyOutput(int boardSize, List<double>? policy) {
    if (policy == null || policy.isEmpty) {
      return [];
    }

    // TODO: Implement full policy parsing
    // - Apply softmax to logits
    // - Map indices to board coordinates
    // - Sort by probability
    // - Return top N moves

    return [];
  }

  Future<String> _extractModel() async {
    final appDir = await getApplicationSupportDirectory();
    final modelPath = p.join(appDir.path, 'katago.onnx');

    final file = File(modelPath);
    if (await file.exists()) {
      debugPrint('$_tag Using cached model');
      return modelPath;
    }

    debugPrint('$_tag Extracting ONNX model from assets...');
    final assetData = await rootBundle.load(_modelAsset);
    await file.writeAsBytes(assetData.buffer.asUint8List(), flush: true);

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
