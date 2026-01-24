import 'package:flutter/foundation.dart' show kIsWeb;

/// Application configuration
///
/// Change the API_BASE_URL before building the APK to point to your server.

class AppConfig {
  /// Base URL for the Go Strategy API server
  ///
  /// Examples:
  /// - Local development: 'http://10.0.2.2:8000' (Android emulator)
  /// - Local network: 'http://192.168.1.100:8000'
  /// - Production: 'https://api.your-domain.com'
  /// - Web (same origin): '' (empty for relative URLs)

  // Network IP for mobile devices
  static const String _mobileApiUrl = 'http://10.20.90.254:8000';

  // For web, use localhost or configure your deployment URL
  static const String _webApiUrl = 'http://localhost:8000';

  /// Get the appropriate API base URL based on platform
  static String get apiBaseUrl => kIsWeb ? _webApiUrl : _mobileApiUrl;

  /// Connection timeout for API requests
  static const Duration connectionTimeout = Duration(seconds: 30);

  /// Default board size
  static const int defaultBoardSize = 19;

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
