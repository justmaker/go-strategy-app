/// Stub implementation for web platform (no FFI support)
library;

/// Initialize FFI - no-op on web
void initFfiDatabase() {
  // No-op: FFI not supported on web
}

/// Check if FFI is available
bool get isFfiAvailable => false;
