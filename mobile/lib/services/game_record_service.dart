/// Game Record Service
///
/// Manages game records with local storage and cloud sync.
/// Records are stored locally first, then synced to cloud if enabled.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/game_record.dart';
import 'auth_service.dart';
import 'cloud_storage_service.dart';

/// Game Record Service
///
/// Handles:
/// - Local SQLite storage for game records
/// - Cloud sync with user's chosen provider
/// - Import/export SGF and JSON formats
/// - Conflict resolution
class GameRecordService extends ChangeNotifier {
  final AuthService _authService;
  final CloudStorageManager _cloudStorage;

  Database? _db;
  List<GameRecord> _records = [];
  bool _isLoading = false;
  String? _error;

  GameRecordService(this._authService, this._cloudStorage);

  // Getters
  List<GameRecord> get records => List.unmodifiable(_records);
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get canSync =>
      _authService.canUseCloudFeatures && _authService.syncPrefs.userConsented;

  /// Initialize the service
  Future<void> init() async {
    await _initDatabase();
    await loadRecords();
  }

  Future<void> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, 'game_records.db');

    _db = await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE game_records (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            board_size INTEGER NOT NULL,
            komi REAL NOT NULL,
            handicap INTEGER NOT NULL DEFAULT 0,
            moves TEXT NOT NULL,
            created_at TEXT NOT NULL,
            modified_at TEXT NOT NULL,
            status TEXT NOT NULL,
            cloud_provider TEXT NOT NULL,
            cloud_file_id TEXT,
            cloud_etag TEXT,
            black_player TEXT,
            white_player TEXT,
            result TEXT,
            event TEXT,
            notes TEXT
          )
        ''');
      },
    );
  }

  /// Load all records from local database
  Future<void> loadRecords() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final rows =
          await _db?.query('game_records', orderBy: 'modified_at DESC');
      _records = (rows ?? []).map((row) => _rowToRecord(row)).toList();
    } catch (e) {
      _error = '無法載入棋譜：$e';
      debugPrint('Failed to load records: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Save a new game record
  Future<GameRecord?> saveRecord(GameRecord record) async {
    try {
      final newRecord = record.copyWith(
        modifiedAt: DateTime.now(),
        status: GameRecordStatus.local,
      );

      await _db?.insert(
        'game_records',
        _recordToRow(newRecord),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      // Update local list
      final index = _records.indexWhere((r) => r.id == newRecord.id);
      if (index >= 0) {
        _records[index] = newRecord;
      } else {
        _records.insert(0, newRecord);
      }
      notifyListeners();

      // Auto-sync if enabled
      if (canSync && _authService.syncPrefs.autoSync) {
        await _syncRecordToCloud(newRecord);
      }

      return newRecord;
    } catch (e) {
      _error = '無法儲存棋譜：$e';
      debugPrint('Failed to save record: $e');
      notifyListeners();
      return null;
    }
  }

  /// Update an existing record
  Future<GameRecord?> updateRecord(GameRecord record) async {
    return await saveRecord(record);
  }

  /// Delete a record
  Future<bool> deleteRecord(String recordId) async {
    try {
      final record = _records.firstWhere(
        (r) => r.id == recordId,
        orElse: () => throw Exception('Record not found'),
      );

      // Delete from cloud if synced
      if (record.cloudFileId != null && canSync) {
        await _cloudStorage.deleteRecord(record.cloudFileId!);
      }

      // Delete from local database
      await _db?.delete('game_records', where: 'id = ?', whereArgs: [recordId]);

      _records.removeWhere((r) => r.id == recordId);
      notifyListeners();
      return true;
    } catch (e) {
      _error = '無法刪除棋譜：$e';
      debugPrint('Failed to delete record: $e');
      notifyListeners();
      return false;
    }
  }

  /// Get a single record by ID
  GameRecord? getRecord(String recordId) {
    try {
      return _records.firstWhere((r) => r.id == recordId);
    } catch (e) {
      return null;
    }
  }

  // ============================================================
  // Cloud Sync
  // ============================================================

  /// Sync a single record to cloud
  Future<bool> _syncRecordToCloud(GameRecord record) async {
    if (!canSync) return false;

    try {
      // Upload in user's preferred format (default SGF)
      final result = await _cloudStorage.uploadRecord(record, format: 'sgf');

      if (result.success && result.data != null) {
        // Update record with cloud info
        final syncedRecord = record.copyWith(
          status: GameRecordStatus.synced,
          cloudProvider: _authService.user!.cloudProvider,
          cloudFileId: result.data!.id,
        );

        await _db?.update(
          'game_records',
          _recordToRow(syncedRecord),
          where: 'id = ?',
          whereArgs: [record.id],
        );

        final index = _records.indexWhere((r) => r.id == record.id);
        if (index >= 0) {
          _records[index] = syncedRecord;
          notifyListeners();
        }

        return true;
      }
    } catch (e) {
      debugPrint('Failed to sync record to cloud: $e');
    }

    return false;
  }

  /// Sync all pending records to cloud
  Future<int> syncAllToCloud() async {
    if (!canSync) return 0;

    int synced = 0;
    final pendingRecords = _records.where((r) =>
        r.status == GameRecordStatus.local ||
        r.status == GameRecordStatus.pendingUpload);

    for (final record in pendingRecords) {
      if (await _syncRecordToCloud(record)) {
        synced++;
      }
    }

    return synced;
  }

  /// Download all records from cloud
  Future<int> syncFromCloud() async {
    if (!canSync) return 0;

    int downloaded = 0;

    try {
      final cloudResult = await _cloudStorage.listCloudRecords();
      if (!cloudResult.success || cloudResult.data == null) {
        return 0;
      }

      for (final cloudFile in cloudResult.data!) {
        // Check if we already have this file
        final existingRecord = _records.firstWhere(
          (r) => r.cloudFileId == cloudFile.id,
          orElse: () => GameRecord(name: '', boardSize: 19),
        );

        // Skip if local version is newer
        if (existingRecord.id.isNotEmpty &&
            existingRecord.modifiedAt
                .isAfter(cloudFile.modifiedTime ?? DateTime(1970))) {
          continue;
        }

        // Download and parse
        final contentResult = await _cloudStorage.downloadRecord(cloudFile.id);
        if (contentResult.success && contentResult.data != null) {
          final content = contentResult.data!;

          GameRecord? newRecord;
          if (cloudFile.name.endsWith('.sgf')) {
            newRecord = GameRecord.fromSgf(content,
                name: cloudFile.name.replaceAll('.sgf', ''));
          } else if (cloudFile.name.endsWith('.json')) {
            newRecord = GameRecord.fromJson(
                jsonDecode(content) as Map<String, dynamic>);
          }

          if (newRecord != null) {
            final recordToSave = newRecord.copyWith(
              status: GameRecordStatus.synced,
              cloudProvider: _authService.user!.cloudProvider,
              cloudFileId: cloudFile.id,
            );

            await _db?.insert(
              'game_records',
              _recordToRow(recordToSave),
              conflictAlgorithm: ConflictAlgorithm.replace,
            );

            downloaded++;
          }
        }
      }

      if (downloaded > 0) {
        await loadRecords();
      }
    } catch (e) {
      debugPrint('Failed to sync from cloud: $e');
    }

    return downloaded;
  }

  /// Full two-way sync
  Future<Map<String, int>> fullSync() async {
    final results = {'uploaded': 0, 'downloaded': 0};

    if (!canSync) return results;

    results['uploaded'] = await syncAllToCloud();
    results['downloaded'] = await syncFromCloud();

    return results;
  }

  // ============================================================
  // Import/Export
  // ============================================================

  /// Import from SGF content
  Future<GameRecord?> importSgf(String sgfContent, {String? name}) async {
    final record = GameRecord.fromSgf(sgfContent, name: name);
    if (record != null) {
      return await saveRecord(record);
    }
    return null;
  }

  /// Export record to SGF
  String exportSgf(GameRecord record) {
    return record.toSgf();
  }

  /// Export record to JSON
  String exportJson(GameRecord record) {
    return jsonEncode(record.toJson());
  }

  // ============================================================
  // Database Helpers
  // ============================================================

  Map<String, dynamic> _recordToRow(GameRecord record) {
    return {
      'id': record.id,
      'name': record.name,
      'board_size': record.boardSize,
      'komi': record.komi,
      'handicap': record.handicap,
      'moves': jsonEncode(record.moves.map((m) => m.toJson()).toList()),
      'created_at': record.createdAt.toIso8601String(),
      'modified_at': record.modifiedAt.toIso8601String(),
      'status': record.status.name,
      'cloud_provider': record.cloudProvider.name,
      'cloud_file_id': record.cloudFileId,
      'cloud_etag': record.cloudEtag,
      'black_player': record.blackPlayer,
      'white_player': record.whitePlayer,
      'result': record.result,
      'event': record.event,
      'notes': record.notes,
    };
  }

  GameRecord _rowToRecord(Map<String, dynamic> row) {
    final movesJson = jsonDecode(row['moves'] as String) as List<dynamic>;

    return GameRecord(
      id: row['id'] as String,
      name: row['name'] as String,
      boardSize: row['board_size'] as int,
      komi: row['komi'] as double,
      handicap: row['handicap'] as int? ?? 0,
      moves: movesJson
          .map((m) => GameMove.fromJson(m as Map<String, dynamic>))
          .toList(),
      createdAt: DateTime.parse(row['created_at'] as String),
      modifiedAt: DateTime.parse(row['modified_at'] as String),
      status: GameRecordStatus.values.byName(row['status'] as String),
      cloudProvider:
          CloudProvider.values.byName(row['cloud_provider'] as String),
      cloudFileId: row['cloud_file_id'] as String?,
      cloudEtag: row['cloud_etag'] as String?,
      blackPlayer: row['black_player'] as String?,
      whitePlayer: row['white_player'] as String?,
      result: row['result'] as String?,
      event: row['event'] as String?,
      notes: row['notes'] as String?,
    );
  }

  /// Close database
  @override
  Future<void> dispose() async {
    await _db?.close();
    super.dispose();
  }

  /// Clear error
  void clearError() {
    _error = null;
    notifyListeners();
  }
}
