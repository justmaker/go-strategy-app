/// Cloud Storage Service
///
/// Abstract interface for cloud storage providers:
/// - Google Drive
/// - iCloud (Apple)
/// - OneDrive (Microsoft)
///
/// Game records are stored in the user's own cloud storage,
/// in an app-specific folder that they can access.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;

import '../models/game_record.dart';
import 'auth_service.dart';

/// Result of a cloud operation
class CloudResult<T> {
  final bool success;
  final T? data;
  final String? error;

  const CloudResult.success(this.data)
      : success = true,
        error = null;

  const CloudResult.failure(this.error)
      : success = false,
        data = null;
}

/// File info from cloud storage
class CloudFileInfo {
  final String id;
  final String name;
  final DateTime? modifiedTime;
  final String? etag;
  final int? size;

  const CloudFileInfo({
    required this.id,
    required this.name,
    this.modifiedTime,
    this.etag,
    this.size,
  });
}

/// Abstract cloud storage interface
abstract class CloudStorageProvider {
  CloudProvider get providerType;

  /// Check if the provider is available and authenticated
  Future<bool> isAvailable();

  /// List game records in cloud storage
  Future<CloudResult<List<CloudFileInfo>>> listGameRecords();

  /// Upload a game record
  Future<CloudResult<CloudFileInfo>> uploadGameRecord(
    GameRecord record, {
    required String format, // 'sgf' or 'json'
  });

  /// Download a game record
  Future<CloudResult<String>> downloadGameRecord(String fileId);

  /// Delete a game record
  Future<CloudResult<void>> deleteGameRecord(String fileId);

  /// Get file info
  Future<CloudResult<CloudFileInfo>> getFileInfo(String fileId);
}

/// Google Drive implementation
class GoogleDriveService extends CloudStorageProvider {
  static const String _appFolderName = 'Go Strategy';
  static const String _mimeTypeSgf = 'application/x-go-sgf';
  static const String _mimeTypeJson = 'application/json';

  final AuthService _authService;
  drive.DriveApi? _driveApi;
  String? _appFolderId;

  GoogleDriveService(this._authService);

  @override
  CloudProvider get providerType => CloudProvider.googleDrive;

  @override
  Future<bool> isAvailable() async {
    if (_authService.user?.provider != AuthProvider.google) {
      return false;
    }
    return await _initDriveApi();
  }

  Future<bool> _initDriveApi() async {
    try {
      final headers = await _authService.getGoogleAuthHeaders();
      if (headers == null) return false;

      final client = GoogleAuthClient(headers);
      _driveApi = drive.DriveApi(client);
      return true;
    } catch (e) {
      debugPrint('Failed to init Drive API: $e');
      return false;
    }
  }

  Future<String?> _getOrCreateAppFolder() async {
    if (_appFolderId != null) return _appFolderId;
    if (_driveApi == null) return null;

    try {
      // Search for existing folder
      final query =
          "name = '$_appFolderName' and mimeType = 'application/vnd.google-apps.folder' and trashed = false";
      final result = await _driveApi!.files.list(q: query, spaces: 'drive');

      if (result.files != null && result.files!.isNotEmpty) {
        _appFolderId = result.files!.first.id;
        return _appFolderId;
      }

      // Create folder
      final folder = drive.File()
        ..name = _appFolderName
        ..mimeType = 'application/vnd.google-apps.folder';

      final created = await _driveApi!.files.create(folder);
      _appFolderId = created.id;
      return _appFolderId;
    } catch (e) {
      debugPrint('Failed to get/create app folder: $e');
      return null;
    }
  }

  @override
  Future<CloudResult<List<CloudFileInfo>>> listGameRecords() async {
    if (!await isAvailable()) {
      return const CloudResult.failure('Google Drive not available');
    }

    try {
      final folderId = await _getOrCreateAppFolder();
      if (folderId == null) {
        return const CloudResult.failure('Cannot access app folder');
      }

      final query =
          "'$folderId' in parents and trashed = false and (name contains '.sgf' or name contains '.json')";
      final result = await _driveApi!.files.list(
        q: query,
        spaces: 'drive',
        $fields: 'files(id, name, modifiedTime, size)',
      );

      final files = (result.files ?? [])
          .map((f) => CloudFileInfo(
                id: f.id!,
                name: f.name ?? 'Unknown',
                modifiedTime: f.modifiedTime,
                size: int.tryParse(f.size ?? ''),
              ))
          .toList();

      return CloudResult.success(files);
    } catch (e) {
      debugPrint('Failed to list game records: $e');
      return CloudResult.failure('無法列出雲端檔案：$e');
    }
  }

  @override
  Future<CloudResult<CloudFileInfo>> uploadGameRecord(
    GameRecord record, {
    required String format,
  }) async {
    if (!await isAvailable()) {
      return const CloudResult.failure('Google Drive not available');
    }

    try {
      final folderId = await _getOrCreateAppFolder();
      if (folderId == null) {
        return const CloudResult.failure('Cannot access app folder');
      }

      String content;
      String fileName;
      String mimeType;

      if (format == 'sgf') {
        content = record.toSgf();
        fileName = '${record.name}.sgf';
        mimeType = _mimeTypeSgf;
      } else {
        content = jsonEncode(record.toJson());
        fileName = '${record.name}.json';
        mimeType = _mimeTypeJson;
      }

      final file = drive.File()
        ..name = fileName
        ..parents = [folderId]
        ..mimeType = mimeType;

      final media = drive.Media(
        Stream.value(utf8.encode(content)),
        content.length,
      );

      drive.File created;

      // Check if file exists (update) or create new
      if (record.cloudFileId != null) {
        created = await _driveApi!.files.update(
          file,
          record.cloudFileId!,
          uploadMedia: media,
        );
      } else {
        created = await _driveApi!.files.create(
          file,
          uploadMedia: media,
        );
      }

      return CloudResult.success(CloudFileInfo(
        id: created.id!,
        name: created.name ?? fileName,
        modifiedTime: DateTime.now(),
      ));
    } catch (e) {
      debugPrint('Failed to upload game record: $e');
      return CloudResult.failure('無法上傳棋譜：$e');
    }
  }

  @override
  Future<CloudResult<String>> downloadGameRecord(String fileId) async {
    if (!await isAvailable()) {
      return const CloudResult.failure('Google Drive not available');
    }

    try {
      final response = await _driveApi!.files.get(
        fileId,
        downloadOptions: drive.DownloadOptions.fullMedia,
      ) as drive.Media;

      final bytes = <int>[];
      await for (final chunk in response.stream) {
        bytes.addAll(chunk);
      }

      return CloudResult.success(utf8.decode(bytes));
    } catch (e) {
      debugPrint('Failed to download game record: $e');
      return CloudResult.failure('無法下載棋譜：$e');
    }
  }

  @override
  Future<CloudResult<void>> deleteGameRecord(String fileId) async {
    if (!await isAvailable()) {
      return const CloudResult.failure('Google Drive not available');
    }

    try {
      await _driveApi!.files.delete(fileId);
      return const CloudResult.success(null);
    } catch (e) {
      debugPrint('Failed to delete game record: $e');
      return CloudResult.failure('無法刪除棋譜：$e');
    }
  }

  @override
  Future<CloudResult<CloudFileInfo>> getFileInfo(String fileId) async {
    if (!await isAvailable()) {
      return const CloudResult.failure('Google Drive not available');
    }

    try {
      final file = await _driveApi!.files.get(
        fileId,
        $fields: 'id, name, modifiedTime, size',
      ) as drive.File;

      return CloudResult.success(CloudFileInfo(
        id: file.id!,
        name: file.name ?? 'Unknown',
        modifiedTime: file.modifiedTime,
        size: int.tryParse(file.size ?? ''),
      ));
    } catch (e) {
      debugPrint('Failed to get file info: $e');
      return CloudResult.failure('無法取得檔案資訊：$e');
    }
  }
}

/// iCloud implementation (placeholder)
class ICloudService extends CloudStorageProvider {
  final AuthService _authService;

  ICloudService(this._authService);

  @override
  CloudProvider get providerType => CloudProvider.iCloud;

  @override
  Future<bool> isAvailable() async {
    // TODO: Implement iCloud availability check
    // Requires CloudKit setup in Xcode
    return false;
  }

  @override
  Future<CloudResult<List<CloudFileInfo>>> listGameRecords() async {
    return const CloudResult.failure('iCloud 支援即將推出');
  }

  @override
  Future<CloudResult<CloudFileInfo>> uploadGameRecord(
    GameRecord record, {
    required String format,
  }) async {
    return const CloudResult.failure('iCloud 支援即將推出');
  }

  @override
  Future<CloudResult<String>> downloadGameRecord(String fileId) async {
    return const CloudResult.failure('iCloud 支援即將推出');
  }

  @override
  Future<CloudResult<void>> deleteGameRecord(String fileId) async {
    return const CloudResult.failure('iCloud 支援即將推出');
  }

  @override
  Future<CloudResult<CloudFileInfo>> getFileInfo(String fileId) async {
    return const CloudResult.failure('iCloud 支援即將推出');
  }
}

/// OneDrive implementation (placeholder)
class OneDriveService extends CloudStorageProvider {
  final AuthService _authService;

  OneDriveService(this._authService);

  @override
  CloudProvider get providerType => CloudProvider.oneDrive;

  @override
  Future<bool> isAvailable() async {
    // TODO: Implement OneDrive availability check
    // Requires Microsoft Graph API
    return false;
  }

  @override
  Future<CloudResult<List<CloudFileInfo>>> listGameRecords() async {
    return const CloudResult.failure('OneDrive 支援即將推出');
  }

  @override
  Future<CloudResult<CloudFileInfo>> uploadGameRecord(
    GameRecord record, {
    required String format,
  }) async {
    return const CloudResult.failure('OneDrive 支援即將推出');
  }

  @override
  Future<CloudResult<String>> downloadGameRecord(String fileId) async {
    return const CloudResult.failure('OneDrive 支援即將推出');
  }

  @override
  Future<CloudResult<void>> deleteGameRecord(String fileId) async {
    return const CloudResult.failure('OneDrive 支援即將推出');
  }

  @override
  Future<CloudResult<CloudFileInfo>> getFileInfo(String fileId) async {
    return const CloudResult.failure('OneDrive 支援即將推出');
  }
}

/// HTTP client that adds Google auth headers
class GoogleAuthClient extends http.BaseClient {
  final Map<String, String> _headers;
  final http.Client _client = http.Client();

  GoogleAuthClient(this._headers);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    return _client.send(request..headers.addAll(_headers));
  }
}

/// Cloud Storage Manager
///
/// Manages multiple cloud storage providers and handles sync operations.
class CloudStorageManager extends ChangeNotifier {
  final AuthService _authService;

  late final GoogleDriveService _googleDrive;
  late final ICloudService _iCloud;
  late final OneDriveService _oneDrive;

  bool _isSyncing = false;
  String? _syncError;
  DateTime? _lastSyncTime;

  CloudStorageManager(this._authService) {
    _googleDrive = GoogleDriveService(_authService);
    _iCloud = ICloudService(_authService);
    _oneDrive = OneDriveService(_authService);
  }

  // Getters
  bool get isSyncing => _isSyncing;
  String? get syncError => _syncError;
  DateTime? get lastSyncTime => _lastSyncTime;

  /// Get the appropriate storage provider for current user
  CloudStorageProvider? get currentProvider {
    switch (_authService.user?.provider) {
      case AuthProvider.google:
        return _googleDrive;
      case AuthProvider.apple:
        return _iCloud;
      case AuthProvider.microsoft:
        return _oneDrive;
      default:
        return null;
    }
  }

  /// Check if cloud sync is available
  Future<bool> isCloudAvailable() async {
    final provider = currentProvider;
    if (provider == null) return false;
    return await provider.isAvailable();
  }

  /// List all game records from cloud
  Future<CloudResult<List<CloudFileInfo>>> listCloudRecords() async {
    final provider = currentProvider;
    if (provider == null) {
      return const CloudResult.failure('尚未登入雲端服務');
    }
    return await provider.listGameRecords();
  }

  /// Upload a game record to cloud
  Future<CloudResult<CloudFileInfo>> uploadRecord(
    GameRecord record, {
    String format = 'sgf',
  }) async {
    if (!_authService.syncPrefs.userConsented) {
      return const CloudResult.failure('需要用戶同意才能上傳至雲端');
    }

    final provider = currentProvider;
    if (provider == null) {
      return const CloudResult.failure('尚未登入雲端服務');
    }

    _isSyncing = true;
    _syncError = null;
    notifyListeners();

    try {
      final result = await provider.uploadGameRecord(record, format: format);
      _lastSyncTime = DateTime.now();
      return result;
    } finally {
      _isSyncing = false;
      notifyListeners();
    }
  }

  /// Download a game record from cloud
  Future<CloudResult<String>> downloadRecord(String fileId) async {
    final provider = currentProvider;
    if (provider == null) {
      return const CloudResult.failure('尚未登入雲端服務');
    }

    _isSyncing = true;
    _syncError = null;
    notifyListeners();

    try {
      return await provider.downloadGameRecord(fileId);
    } finally {
      _isSyncing = false;
      notifyListeners();
    }
  }

  /// Delete a game record from cloud
  Future<CloudResult<void>> deleteRecord(String fileId) async {
    final provider = currentProvider;
    if (provider == null) {
      return const CloudResult.failure('尚未登入雲端服務');
    }

    return await provider.deleteGameRecord(fileId);
  }

  /// Clear sync error
  void clearError() {
    _syncError = null;
    notifyListeners();
  }
}
