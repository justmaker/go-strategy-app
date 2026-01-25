import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:package_info_plus/package_info_plus.dart';

/// Application configuration
///
/// Change the API_BASE_URL before building the APK to point to your server.

class AppConfig {
  /// App version info (loaded at runtime)
  static PackageInfo? _packageInfo;

  /// Initialize app config (call once at startup)
  static Future<void> init() async {
    _packageInfo = await PackageInfo.fromPlatform();
  }

  /// App version (e.g., "1.0.0")
  static String get appVersion => _packageInfo?.version ?? 'unknown';

  /// Build number (e.g., "1")
  static String get buildNumber => _packageInfo?.buildNumber ?? '0';

  /// Full version string (e.g., "1.0.0+1")
  static String get fullVersion => '$appVersion+$buildNumber';

  /// Package name
  static String get packageName => _packageInfo?.packageName ?? 'unknown';

  /// Base URL for the Go Strategy API server
  ///
  /// Examples:
  /// - Local development: 'http://10.0.2.2:8000' (Android emulator)
  /// - Local network: 'http://192.168.1.100:8000'
  /// - Production: 'https://api.your-domain.com'
  /// - Web (same origin): '' (empty for relative URLs)

  // For iOS Simulator / Android Emulator testing on local machine
  static const String _mobileApiUrl = 'http://127.0.0.1:8001';

  // For web, use localhost or configure your deployment URL
  static const String _webApiUrl = 'http://localhost:8001';

  /// Get the appropriate API base URL based on platform
  static String get apiBaseUrl => kIsWeb ? _webApiUrl : _mobileApiUrl;

  /// Connection timeout for API requests
  static const Duration connectionTimeout = Duration(seconds: 30);

  /// Default board size
  static const int defaultBoardSize = 9;

  /// Default komi value
  static const double defaultKomi = 7.5;

  /// Default lookup visits (for opening book/cache queries)
  static const int defaultLookupVisits = 100;

  /// Default compute visits (for live KataGo analysis)
  static const int defaultComputeVisits = 50;

  /// Available visit options for lookup (DB/book queries)
  static const List<int> availableLookupVisits = [
    100,
    200,
    500,
    1000,
    2000,
    5000,
  ];

  /// Available visit options for compute (live analysis)
  static const List<int> availableComputeVisits = [10, 20, 50, 100, 200];
}
