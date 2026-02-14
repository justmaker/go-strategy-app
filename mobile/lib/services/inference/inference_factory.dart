/// Factory for creating platform-specific inference engines
library;

import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'inference_engine.dart';
import 'katago_engine.dart';

/// Create the appropriate inference engine for the current platform
InferenceEngine createInferenceEngine() {
  if (kIsWeb) {
    throw UnsupportedError('Web platform not supported for local inference');
  }

  // All platforms now use KataGo native engine
  // Android: Uses ONNX Runtime C++ backend (single-threaded, no pthread)
  // iOS/macOS/Desktop: Uses Eigen backend (multi-threaded)
  debugPrint('[InferenceFactory] Creating KataGo native engine for ${Platform.operatingSystem}');
  return KataGoEngine();
}
