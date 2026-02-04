/// FFI implementation for desktop platforms (Windows, Linux, macOS)
library;

import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite/sqflite.dart';

/// Initialize FFI for desktop platforms
void initFfiDatabase() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
}

/// Check if FFI is available
bool get isFfiAvailable => true;
