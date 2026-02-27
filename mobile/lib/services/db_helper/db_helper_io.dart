import 'dart:io';
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path_provider/path_provider.dart';
import 'db_helper.dart';

class DbHelperIo implements DbHelper {
  bool _initialized = false;

  @override
  Future<void> init() async {
    if (_initialized) return;

    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }
    _initialized = true;
  }

  @override
  Future<void> writeDatabaseBytes(String path, List<int> bytes) async {
    final file = File(path);
    final parent = file.parent;
    if (!await parent.exists()) {
      await parent.create(recursive: true);
    }
    await file.writeAsBytes(bytes, flush: true);
  }

  @override
  Future<String> getDatabasesPath() async {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
       final appDir = await getApplicationSupportDirectory();
       return appDir.path;
    }
    return await sqflite.getDatabasesPath();
  }

  @override
  Future<bool> databaseExists(String path) async {
    return File(path).exists();
  }

  @override
  Future<int> getDatabaseSize(String path) async {
    final file = File(path);
    if (await file.exists()) {
      return await file.length();
    }
    return 0;
  }

  @override
  Future<void> deleteDatabase(String path) async {
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
  }

  @override
  Future<String?> readStringFile(String path) async {
    final file = File(path);
    if (await file.exists()) {
      return await file.readAsString();
    }
    return null;
  }

  @override
  Future<void> writeStringFile(String path, String content) async {
    final file = File(path);
    await file.writeAsString(content, flush: true);
  }
}

DbHelper getDbHelper() => DbHelperIo();
