# TensorFlow Lite ProGuard rules
# Keep all TFLite classes
-keep class org.tensorflow.lite.** { *; }
-keep interface org.tensorflow.lite.** { *; }

# Keep GPU delegate
-keep class org.tensorflow.lite.gpu.** { *; }
-keep class org.tensorflow.lite.nnapi.** { *; }

# Suppress warnings for missing optional GPU classes
-dontwarn org.tensorflow.lite.gpu.GpuDelegateFactory$Options

# Keep method names for native methods
-keepclasseswithmembernames class * {
    native <methods>;
}
