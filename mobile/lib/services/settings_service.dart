/// Settings Service
///
/// Manages persistent application settings.
library;

import 'package:shared_preferences/shared_preferences.dart';
import '../config.dart';

class SettingsService {
  static const String _apiBaseUrlKey = 'api_base_url';

  // Singleton pattern
  static final SettingsService _instance = SettingsService._internal();
  factory SettingsService() => _instance;
  SettingsService._internal();

  late SharedPreferences _prefs;

  /// Initialize the settings service
  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  /// Get the API base URL
  String get apiBaseUrl => _prefs.getString(_apiBaseUrlKey) ?? AppConfig.apiBaseUrl;

  /// Set the API base URL
  Future<void> setApiBaseUrl(String url) async {
    await _prefs.setString(_apiBaseUrlKey, url);
  }

  /// Reset API base URL to default
  Future<void> resetApiBaseUrl() async {
    await _prefs.remove(_apiBaseUrlKey);
  }
}
