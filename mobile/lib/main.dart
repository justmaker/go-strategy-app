/// Go Strategy Analysis App
/// 
/// A cross-platform mobile app for Go (Weiqi/Baduk) strategy analysis
/// powered by KataGo AI.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'config.dart';
import 'providers/providers.dart';
import 'screens/screens.dart';
import 'services/services.dart';

void main() {
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
  late final ApiService _apiService;
  late final CacheService _cacheService;
  late final GameProvider _gameProvider;
  bool _initialized = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initServices();
  }

  Future<void> _initServices() async {
    try {
      // Configure API endpoint from config
      _apiService = ApiService(
        baseUrl: AppConfig.apiBaseUrl,
        timeout: AppConfig.connectionTimeout,
      );
      _cacheService = CacheService();
      
      _gameProvider = GameProvider(
        api: _apiService,
        cache: _cacheService,
        boardSize: AppConfig.defaultBoardSize,
        komi: AppConfig.defaultKomi,
        defaultVisits: AppConfig.defaultVisits,
        availableVisits: AppConfig.availableVisits,
      );

      await _gameProvider.init();

      setState(() {
        _initialized = true;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to initialize: $e';
      });
    }
  }

  @override
  void dispose() {
    if (_initialized) {
      _gameProvider.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Scaffold(
        body: Center(
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
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (!_initialized) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Initializing...'),
            ],
          ),
        ),
      );
    }

    return ChangeNotifierProvider.value(
      value: _gameProvider,
      child: const AnalysisScreen(),
    );
  }
}
