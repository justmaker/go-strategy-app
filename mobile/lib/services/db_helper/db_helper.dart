import 'db_helper_stub.dart'
    if (dart.library.io) 'db_helper_io.dart'
    if (dart.library.html) 'db_helper_web.dart';

abstract class DbHelper {
  /// Initialize the database factory (FFI for desktop/web)
  Future<void> init();

  /// Write raw bytes to a database file
  Future<void> writeDatabaseBytes(String path, List<int> bytes);

  /// Get the default databases directory path
  Future<String> getDatabasesPath();

  /// Check if a database exists
  Future<bool> databaseExists(String path);

  /// Get database size in bytes (returns 0 if not supported or not found)
  Future<int> getDatabaseSize(String path);

  /// Delete a database
  Future<void> deleteDatabase(String path);

  /// Read a text file (e.g. version file)
  Future<String?> readStringFile(String path);

  /// Write a text file
  Future<void> writeStringFile(String path, String content);
}

final DbHelper dbHelper = getDbHelper();
