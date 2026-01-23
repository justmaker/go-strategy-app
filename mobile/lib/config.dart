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
  static const String apiBaseUrl = 'http://10.20.90.254:8000';
  
  /// Connection timeout for API requests
  static const Duration connectionTimeout = Duration(seconds: 30);
  
  /// Default board size
  static const int defaultBoardSize = 19;
  
  /// Default komi value
  static const double defaultKomi = 7.5;
  
  /// Default analysis visits
  static const int defaultVisits = 100;
  
  /// Available visit options for analysis
  static const List<int> availableVisits = [10, 50, 100, 200, 500, 1000, 2000, 5000];
}
