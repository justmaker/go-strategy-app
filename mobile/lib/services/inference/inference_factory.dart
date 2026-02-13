/// Factory for creating platform-specific inference engines
library;

import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'inference_engine.dart';
import 'tflite_engine.dart';
import 'katago_engine.dart';

/// Create the appropriate inference engine for the current platform
InferenceEngine createInferenceEngine() {
  if (kIsWeb) {
    throw UnsupportedError('Web platform not supported for local inference');
  }

  // Android: Use TFLite (avoids pthread crash on Android 16 + Qualcomm)
  if (Platform.isAndroid) {
    debugPrint('[InferenceFactory] Creating TFLite engine for Android');
    return TFLiteEngine();
  }

  // iOS, macOS, Windows, Linux: Use native KataGo
  debugPrint('[InferenceFactory] Creating KataGo native engine for ${Platform.operatingSystem}');
  return KataGoEngine();
}
