/// Local SQLite cache service for offline-first functionality.
/// Mirrors the Python backend cache structure.
library;

import 'dart:convert';
import 'dart:io' show Directory, File, Platform;
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter/services.dart' show rootBundle;
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import '../models/models.dart';

// Conditional import for FFI (desktop only, not web)
import 'cache_service_ffi_stub.dart'
    if (dart.library.io) 'cache_service_ffi.dart';

/// Local cache service using SQLite
class CacheService {
  static const String _dbName = 'analysis_cache.db';
  static const String _bundledDbAsset = 'assets/data/analysis.db';
  static const int _dbVersion = 1;

  Database? _database;
  bool _bundledDataLoaded = false;

  /// Check if bundled opening book data has been loaded
  bool get bundledDataLoaded => _bundledDataLoaded;

  /// Initialize the database
  Future<void> init() async {
    if (_database != null) return;

    // Web support: Disable generic SQFlite for now as it requires special setup
    if (kIsWeb) {
      debugPrint('[CacheService] Web platform: Disabling local SQFlite cache');
      return;
    }

    String dbPath;

    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      // Initialize FFI for desktop platforms
      initFfiDatabase();

      // For desktop, getApplicationSupportDirectory is more reliable
      final appDir = await getApplicationSupportDirectory();
      dbPath = appDir.path;
      
      // Ensure the directory exists (CRITICAL for FFI)
      final dir = Directory(dbPath);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
    } else {
      dbPath = await getDatabasesPath();
    }

    final path = join(dbPath, _dbName);
    
    // Check if we need to copy bundled opening book
    await _copyBundledDbIfNeeded(path);

    _database = await openDatabase(
      path,
      version: _dbVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
    
    // Mark bundled data as loaded if we have entries
    final count = await _database!.rawQuery('SELECT COUNT(*) as cnt FROM analysis_cache');
    _bundledDataLoaded = (count.first['cnt'] as int) > 0;
    debugPrint('[CacheService] Initialized with ${count.first['cnt']} entries');
  }
  
  /// Copy bundled opening book database if local DB doesn't exist or is empty
  Future<void> _copyBundledDbIfNeeded(String targetPath) async {
    final targetFile = File(targetPath);
    
    // If file exists and is not empty, skip
    if (await targetFile.exists()) {
      final size = await targetFile.length();
      if (size > 1024) {  // More than 1KB means it has data
        debugPrint('[CacheService] Local DB exists (${(size / 1024 / 1024).toStringAsFixed(1)} MB), skipping bundled copy');
        return;
      }
    }
    
    // Try to copy bundled database
    try {
      debugPrint('[CacheService] Copying bundled opening book database...');
      final data = await rootBundle.load(_bundledDbAsset);
      final bytes = data.buffer.asUint8List();
      
      // Write to target path
      await targetFile.writeAsBytes(bytes);
      debugPrint('[CacheService] Copied bundled DB (${(bytes.length / 1024 / 1024).toStringAsFixed(1)} MB)');
    } catch (e) {
      debugPrint('[CacheService] No bundled DB found or copy failed: $e');
      // Not an error - will create empty DB
    }
  }

  /// Create database tables
  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS analysis_cache (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        board_hash TEXT NOT NULL,
        moves_sequence TEXT,
        board_size INTEGER NOT NULL,
        komi REAL NOT NULL,
        analysis_result TEXT NOT NULL,
        engine_visits INTEGER NOT NULL,
        model_name TEXT NOT NULL,
        created_at TEXT DEFAULT CURRENT_TIMESTAMP,
        calculation_duration REAL,
        stopped_by_limit INTEGER,
        limit_setting TEXT
      )
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_board_hash 
      ON analysis_cache(board_hash)
    ''');

    await db.execute('''
      CREATE UNIQUE INDEX IF NOT EXISTS idx_board_hash_visits_komi 
      ON analysis_cache(board_hash, engine_visits, komi)
    ''');
  }

  /// Handle database upgrades
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // Add migration logic here for future versions
  }

  /// Get database instance (safe)
  Database? get db => _database; // Changed to nullable getter


  /// Get cached analysis result
  Future<AnalysisResult?> get({
    required String boardHash,
    required double komi,
    int? requiredVisits,
  }) async {
    if (_database == null) return null; // Safe check

    String query;
    List<dynamic> params;

    if (requiredVisits != null) {
      query = '''
        SELECT board_hash, moves_sequence, board_size, komi,
               analysis_result, engine_visits, model_name, created_at,
               calculation_duration, stopped_by_limit, limit_setting
        FROM analysis_cache
        WHERE board_hash = ? AND komi = ? AND engine_visits = ?
      ''';
      params = [boardHash, komi, requiredVisits];
    } else {
      // Get the one with highest visits
      query = '''
        SELECT board_hash, moves_sequence, board_size, komi,
               analysis_result, engine_visits, model_name, created_at,
               calculation_duration, stopped_by_limit, limit_setting
        FROM analysis_cache
        WHERE board_hash = ? AND komi = ?
        ORDER BY engine_visits DESC
        LIMIT 1
      ''';
      params = [boardHash, komi];
    }

    final results = await _database!.rawQuery(query, params);
    if (results.isEmpty) return null;

    return _rowToAnalysisResult(results.first);
  }

  /// Store analysis result with intelligent merge logic
  Future<void> put(AnalysisResult result) async {
    if (_database == null) return; // Safe check

    // Check for existing entry
    final existing = await _database!.rawQuery('''
      SELECT calculation_duration, stopped_by_limit, limit_setting, created_at
      FROM analysis_cache
      WHERE board_hash = ? AND engine_visits = ? AND komi = ?
    ''', [result.boardHash, result.engineVisits, result.komi]);

    bool shouldUpdate = true;

    if (existing.isNotEmpty) {
      final row = existing.first;
      final existingStoppedRaw = row['stopped_by_limit'];
      final existingDuration = row['calculation_duration'] as double?;

      final existingStopped =
          existingStoppedRaw != null ? (existingStoppedRaw as int) == 1 : null;

      // Rule 1: Completeness - Complete always beats Partial
      if (existingStopped == false && result.stoppedByLimit == true) {
        // Existing is complete, new is partial - keep existing
        shouldUpdate = false;
      } else if (existingStopped == true && result.stoppedByLimit == false) {
        // Existing is partial, new is complete - update
        shouldUpdate = true;
      } else if (existingStopped == result.stoppedByLimit) {
        // Same completeness - Rule 2: Prefer longer duration (more effort)
        if (existingDuration != null && result.calculationDuration != null) {
          if (existingDuration > result.calculationDuration! * 1.1) {
            shouldUpdate = false;
          }
        }
        // Rule 3: If similar effort or unknown, prefer newer
      }
    }

    if (shouldUpdate) {
      // Serialize top_moves to JSON
      final resultJson = jsonEncode(
        result.topMoves.map((m) => m.toJson()).toList(),
      );

      await _database!.rawInsert('''
        INSERT OR REPLACE INTO analysis_cache 
        (board_hash, moves_sequence, board_size, komi, 
         analysis_result, engine_visits, model_name, created_at,
         calculation_duration, stopped_by_limit, limit_setting)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ''', [
        result.boardHash,
        result.movesSequence,
        result.boardSize,
        result.komi,
        resultJson,
        result.engineVisits,
        result.modelName,
        result.timestamp ?? DateTime.now().toIso8601String(),
        result.calculationDuration,
        result.stoppedByLimit == null ? null : (result.stoppedByLimit! ? 1 : 0),
        result.limitSetting,
      ]);
    }
  }

  /// Get cache statistics
  Future<Map<String, dynamic>> getStats() async {
    if (_database == null) {
      return {
        'total_entries': 0,
        'by_board_size': <int, int>{},
      };
    }
    
    final countResult = await _database!.rawQuery(
      'SELECT COUNT(*) as count FROM analysis_cache',
    );
    final totalEntries = countResult.first['count'] as int;

    final sizeResult = await _database!.rawQuery('''
      SELECT board_size, COUNT(*) as cnt 
      FROM analysis_cache 
      GROUP BY board_size
    ''');
    final byBoardSize = <int, int>{
      for (var row in sizeResult) row['board_size'] as int: row['cnt'] as int,
    };

    return {
      'total_entries': totalEntries,
      'by_board_size': byBoardSize,
    };
  }

  /// Count total cached entries
  Future<int> count() async {
    if (_database == null) return 0;
    final result = await _database!.rawQuery(
      'SELECT COUNT(*) as count FROM analysis_cache',
    );
    return result.first['count'] as int;
  }

  /// Clear all cached entries
  Future<int> clear() async {
    if (_database == null) return 0;
    return await _database!.delete('analysis_cache');
  }

  /// Import data from JSON (for syncing from server)
  Future<int> importFromJson(List<Map<String, dynamic>> data) async {
    int imported = 0;
    for (final item in data) {
      try {
        final result = AnalysisResult.fromJson(item);
        await put(result);
        imported++;
      } catch (e) {
        // Skip invalid entries
      }
    }
    return imported;
  }

  /// Export all data to JSON (for backup)
  Future<List<Map<String, dynamic>>> exportToJson() async {
    if (_database == null) return [];
    final results = await _database!.rawQuery('''
      SELECT board_hash, moves_sequence, board_size, komi,
             analysis_result, engine_visits, model_name, created_at,
             calculation_duration, stopped_by_limit, limit_setting
      FROM analysis_cache
    ''');

    return results.map((row) {
      final result = _rowToAnalysisResult(row);
      return result.toJson();
    }).toList();
  }

  /// Convert database row to AnalysisResult
  AnalysisResult _rowToAnalysisResult(Map<String, dynamic> row) {
    final topMovesJson = jsonDecode(row['analysis_result'] as String) as List;
    final topMoves = topMovesJson
        .map((m) => MoveCandidate.fromJson(m as Map<String, dynamic>))
        .toList();

    final stoppedByLimitRaw = row['stopped_by_limit'];
    final stoppedByLimit =
        stoppedByLimitRaw != null ? (stoppedByLimitRaw as int) == 1 : null;

    return AnalysisResult(
      boardHash: row['board_hash'] as String,
      boardSize: row['board_size'] as int,
      komi: (row['komi'] as num).toDouble(),
      movesSequence: row['moves_sequence'] as String? ?? '',
      topMoves: topMoves,
      engineVisits: row['engine_visits'] as int,
      modelName: row['model_name'] as String,
      fromCache: true,
      timestamp: row['created_at'] as String?,
      calculationDuration: row['calculation_duration'] as double?,
      stoppedByLimit: stoppedByLimit,
      limitSetting: row['limit_setting'] as String?,
    );
  }

  /// Close the database
  Future<void> close() async {
    await _database?.close();
    _database = null;
  }
}
