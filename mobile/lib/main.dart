/// Go Strategy Analysis App
///
/// A cross-platform mobile app for Go (Weiqi/Baduk) strategy analysis
/// powered by KataGo AI.
///
/// Features:
/// - AI-powered move analysis
/// - Multi-provider authentication (Google, Apple, Microsoft)
/// - Cloud sync (Google Drive, iCloud, OneDrive)
/// - Offline-first with local cache
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'config.dart';
import 'providers/providers.dart';
import 'screens/screens.dart';
import 'services/services.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppConfig.init();
  runApp(const GoStrategyApp());
}

class GoStrategyApp extends StatelessWidget {
  const GoStrategyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Go Strategy',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF8B4513), // Saddle brown (wood color)
        ),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF8B4513),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const AppWrapper(),
    );
  }
}

/// Wrapper that initializes services and providers
class AppWrapper extends StatefulWidget {
  const AppWrapper({super.key});

  @override
  State<AppWrapper> createState() => _AppWrapperState();
}

class _AppWrapperState extends State<AppWrapper> {
  // Core services
  late final ApiService _apiService;
  late final CacheService _cacheService;
  late final OpeningBookService _openingBookService;
  late final KataGoService _kataGoService;
  late final GameProvider _gameProvider;

  // Auth & Cloud services
  late final AuthService _authService;
  late final CloudStorageManager _cloudStorage;
  late final GameRecordService _gameRecordService;

  bool _initialized = false;
  bool _showAuthScreen = false;
  String? _error;
  String _initStatus = 'Starting...';

  @override
  void initState() {
    super.initState();
    _initServices();
  }

  Future<void> _initServices() async {
    try {
      // Step 1: Initialize auth service
      setState(() => _initStatus = '初始化認證服務...');
      _authService = AuthService();
      await _authService.init();

      // Step 2: Initialize cloud storage
      setState(() => _initStatus = '準備雲端服務...');
      _cloudStorage = CloudStorageManager(_authService);

      // Step 3: Initialize game record service
      setState(() => _initStatus = '載入棋譜...');
      _gameRecordService = GameRecordService(_authService, _cloudStorage);
      await _gameRecordService.init();

      // Step 4: Initialize opening book service (for offline-first)
      setState(() => _initStatus = '載入定式庫...');
      _openingBookService = OpeningBookService();

      // Step 5: Configure API endpoint from config
      setState(() => _initStatus = '連接伺服器...');
      _apiService = ApiService(
        baseUrl: AppConfig.apiBaseUrl,
        timeout: AppConfig.connectionTimeout,
      );

      // Step 6: Initialize local cache
      setState(() => _initStatus = '初始化快取...');
      _cacheService = CacheService();

      // Step 7: Initialize local KataGo engine service
      setState(() => _initStatus = '準備分析引擎...');
      _kataGoService = KataGoService();

      // Step 8: Create game provider with all services
      _gameProvider = GameProvider(
        api: _apiService,
        cache: _cacheService,
        openingBook: _openingBookService,
        kataGo: _kataGoService,
        boardSize: AppConfig.defaultBoardSize,
        komi: AppConfig.defaultKomi,
        defaultLookupVisits: AppConfig.defaultLookupVisits,
        defaultComputeVisits: AppConfig.defaultComputeVisits,
        availableLookupVisits: AppConfig.availableLookupVisits,
        availableComputeVisits: AppConfig.availableComputeVisits,
      );

      await _gameProvider.init();

      setState(() {
        _initialized = true;
        // Show auth screen only if user has never signed in and hasn't dismissed it
        // For now, always go directly to the app
        _showAuthScreen = false;
      });
    } catch (e) {
      setState(() {
        _error = '初始化失敗: $e';
      });
    }
  }

  @override
  void dispose() {
    if (_initialized) {
      _gameProvider.dispose();
      _gameRecordService.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, size: 64, color: Colors.red),
                const SizedBox(height: 16),
                Text(_error!, textAlign: TextAlign.center),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      _error = null;
                      _initialized = false;
                    });
                    _initServices();
                  },
                  child: const Text('重試'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (!_initialized) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(_initStatus),
            ],
          ),
        ),
      );
    }

    // Provide all services to the widget tree
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: _authService),
        ChangeNotifierProvider.value(value: _cloudStorage),
        ChangeNotifierProvider.value(value: _gameRecordService),
        ChangeNotifierProvider.value(value: _gameProvider),
      ],
      child: _showAuthScreen
          ? AuthScreen(
              onComplete: () => setState(() => _showAuthScreen = false),
            )
          : const _MainApp(),
    );
  }
}

/// Main app with navigation
class _MainApp extends StatelessWidget {
  const _MainApp();

  @override
  Widget build(BuildContext context) {
    return const AnalysisScreen();
  }
}
