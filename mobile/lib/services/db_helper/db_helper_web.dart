import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';
import 'package:sqflite/sqflite.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:typed_data';
import 'db_helper.dart';

class DbHelperWeb implements DbHelper {
  @override
  Future<void> init() async {
    // Initialize FFI for Web
    databaseFactory = databaseFactoryFfiWeb;
  }

  @override
  Future<void> writeDatabaseBytes(String path, List<int> bytes) async {
    // Convert to Uint8List as required by sqflite_common
    final uint8Bytes = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
    await databaseFactory.writeDatabaseBytes(path, uint8Bytes);
  }

  @override
  Future<String> getDatabasesPath() async {
    return '/';
  }

  @override
  Future<bool> databaseExists(String path) async {
    return await databaseFactory.databaseExists(path);
  }

  @override
  Future<int> getDatabaseSize(String path) async {
    if (await databaseExists(path)) {
      return 10000; // Dummy size
    }
    return 0;
  }

  @override
  Future<void> deleteDatabase(String path) async {
    await databaseFactory.deleteDatabase(path);
  }

  @override
  Future<String?> readStringFile(String path) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('file_content_$path');
  }

  @override
  Future<void> writeStringFile(String path, String content) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('file_content_$path', content);
  }
}

DbHelper getDbHelper() => DbHelperWeb();
