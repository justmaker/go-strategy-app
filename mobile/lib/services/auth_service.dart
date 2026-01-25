/// Authentication Service
///
/// Provides a unified interface for multiple authentication providers:
/// - Google Sign-In + Google Drive
/// - Apple Sign-In + iCloud (iOS/macOS)
/// - Microsoft Sign-In + OneDrive
/// - Anonymous (local-only mode)
///
/// Users can use the app without signing in, but cloud sync requires auth.
library;

import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import '../models/game_record.dart';

/// Supported authentication providers
enum AuthProvider {
  anonymous,
  google,
  apple,
  microsoft,
}

/// User information from authentication
class AuthUser {
  final String id;
  final String? email;
  final String? displayName;
  final String? photoUrl;
  final AuthProvider provider;
  final DateTime signInTime;

  const AuthUser({
    required this.id,
    this.email,
    this.displayName,
    this.photoUrl,
    required this.provider,
    required this.signInTime,
  });

  bool get isAnonymous => provider == AuthProvider.anonymous;
  bool get canUseCloud => !isAnonymous;

  /// Get the corresponding cloud provider
  CloudProvider get cloudProvider {
    switch (provider) {
      case AuthProvider.google:
        return CloudProvider.googleDrive;
      case AuthProvider.apple:
        return CloudProvider.iCloud;
      case AuthProvider.microsoft:
        return CloudProvider.oneDrive;
      case AuthProvider.anonymous:
        return CloudProvider.none;
    }
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'email': email,
        'displayName': displayName,
        'photoUrl': photoUrl,
        'provider': provider.name,
        'signInTime': signInTime.toIso8601String(),
      };

  factory AuthUser.fromJson(Map<String, dynamic> json) => AuthUser(
        id: json['id'] as String,
        email: json['email'] as String?,
        displayName: json['displayName'] as String?,
        photoUrl: json['photoUrl'] as String?,
        provider: AuthProvider.values.byName(json['provider'] as String),
        signInTime: DateTime.parse(json['signInTime'] as String),
      );

  factory AuthUser.anonymous() => AuthUser(
        id: 'anonymous_${DateTime.now().millisecondsSinceEpoch}',
        provider: AuthProvider.anonymous,
        signInTime: DateTime.now(),
      );

  @override
  String toString() =>
      'AuthUser(id: $id, email: $email, provider: ${provider.name})';
}

/// Authentication state
enum AuthState {
  initializing,
  signedOut,
  signedIn,
  signingIn,
  error,
}

/// Authentication Service
class AuthService extends ChangeNotifier {
  static const String _userPrefKey = 'auth_user';
  static const String _syncPrefKey = 'cloud_sync_prefs';

  AuthState _state = AuthState.initializing;
  AuthUser? _user;
  String? _errorMessage;
  CloudSyncPreferences _syncPrefs = const CloudSyncPreferences();

  // Google Sign-In
  late final GoogleSignIn _googleSignIn;
  GoogleSignInAccount? _googleAccount;

  // Apple credentials (stored temporarily)
  AuthorizationCredentialAppleID? _appleCredential;

  // Microsoft token (placeholder)
  String? _microsoftAccessToken;

  // Getters
  AuthState get state => _state;
  AuthUser? get user => _user;
  String? get errorMessage => _errorMessage;
  bool get isSignedIn => _state == AuthState.signedIn && _user != null;
  bool get isAnonymous => _user?.isAnonymous ?? true;
  bool get canUseCloudFeatures => isSignedIn && !isAnonymous;
  CloudSyncPreferences get syncPrefs => _syncPrefs;
  GoogleSignInAccount? get googleAccount => _googleAccount;

  /// Check if a provider is available on this platform
  bool isProviderAvailable(AuthProvider provider) {
    switch (provider) {
      case AuthProvider.anonymous:
        return true;
      case AuthProvider.google:
        return true; // Available on all platforms
      case AuthProvider.apple:
        // Apple Sign-In available on iOS, macOS, and web
        if (kIsWeb) return true;
        return !kIsWeb && (Platform.isIOS || Platform.isMacOS);
      case AuthProvider.microsoft:
        return true; // Available via OAuth on all platforms
    }
  }

  /// Get available providers for current platform
  List<AuthProvider> get availableProviders {
    return AuthProvider.values
        .where((p) => p != AuthProvider.anonymous && isProviderAvailable(p))
        .toList();
  }

  /// Initialize the auth service
  Future<void> init() async {
    _state = AuthState.initializing;
    notifyListeners();

    // Initialize Google Sign-In with Drive scopes
    _googleSignIn = GoogleSignIn(
      scopes: [
        'email',
        'https://www.googleapis.com/auth/drive.file',
        'https://www.googleapis.com/auth/drive.appdata',
      ],
    );

    try {
      // Load sync preferences
      await _loadSyncPrefs();

      // Try to restore session
      final savedUser = await _loadUserFromPrefs();

      if (savedUser != null && !savedUser.isAnonymous) {
        // Try to restore the appropriate session
        bool restored = false;

        switch (savedUser.provider) {
          case AuthProvider.google:
            final googleUser = await _googleSignIn.signInSilently();
            if (googleUser != null) {
              _googleAccount = googleUser;
              _user = _createUserFromGoogle(googleUser);
              restored = true;
            }
            break;
          case AuthProvider.apple:
            // Apple doesn't support silent sign-in, use saved user
            _user = savedUser;
            restored = true;
            break;
          case AuthProvider.microsoft:
            // TODO: Implement Microsoft token refresh
            break;
          case AuthProvider.anonymous:
            break;
        }

        if (restored) {
          _state = AuthState.signedIn;
          debugPrint('Restored session: ${_user?.email}');
        } else {
          await _clearUserPrefs();
          _user = AuthUser.anonymous();
          _state = AuthState.signedOut;
        }
      } else {
        _user = AuthUser.anonymous();
        _state = AuthState.signedOut;
      }
    } catch (e) {
      debugPrint('Auth init error: $e');
      _user = AuthUser.anonymous();
      _state = AuthState.signedOut;
    }

    notifyListeners();
  }

  // ============================================================
  // Google Sign-In
  // ============================================================

  Future<bool> signInWithGoogle() async {
    _state = AuthState.signingIn;
    _errorMessage = null;
    notifyListeners();

    try {
      final googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        _state = _user?.isAnonymous ?? true
            ? AuthState.signedOut
            : AuthState.signedIn;
        notifyListeners();
        return false;
      }

      _googleAccount = googleUser;
      _user = _createUserFromGoogle(googleUser);
      _state = AuthState.signedIn;
      await _saveUserToPrefs();

      debugPrint('Signed in with Google: ${_user?.email}');
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('Google sign in error: $e');
      _errorMessage = '無法使用 Google 登入：$e';
      _state = AuthState.error;
      notifyListeners();
      return false;
    }
  }

  Future<Map<String, String>?> getGoogleAuthHeaders() async {
    if (_googleAccount == null) return null;
    try {
      return await _googleAccount!.authHeaders;
    } catch (e) {
      debugPrint('Failed to get Google auth headers: $e');
      return null;
    }
  }

  AuthUser _createUserFromGoogle(GoogleSignInAccount account) {
    return AuthUser(
      id: account.id,
      email: account.email,
      displayName: account.displayName,
      photoUrl: account.photoUrl,
      provider: AuthProvider.google,
      signInTime: DateTime.now(),
    );
  }

  // ============================================================
  // Apple Sign-In
  // ============================================================

  Future<bool> signInWithApple() async {
    if (!isProviderAvailable(AuthProvider.apple)) {
      _errorMessage = 'Apple 登入在此平台不可用';
      _state = AuthState.error;
      notifyListeners();
      return false;
    }

    _state = AuthState.signingIn;
    _errorMessage = null;
    notifyListeners();

    try {
      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
      );

      _appleCredential = credential;

      // Build display name from given/family name
      String? displayName;
      if (credential.givenName != null || credential.familyName != null) {
        displayName =
            '${credential.givenName ?? ''} ${credential.familyName ?? ''}'
                .trim();
      }

      _user = AuthUser(
        id: credential.userIdentifier ??
            'apple_${DateTime.now().millisecondsSinceEpoch}',
        email: credential.email,
        displayName: displayName,
        provider: AuthProvider.apple,
        signInTime: DateTime.now(),
      );

      _state = AuthState.signedIn;
      await _saveUserToPrefs();

      debugPrint('Signed in with Apple: ${_user?.email ?? _user?.id}');
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('Apple sign in error: $e');
      if (e is SignInWithAppleAuthorizationException) {
        if (e.code == AuthorizationErrorCode.canceled) {
          _state = _user?.isAnonymous ?? true
              ? AuthState.signedOut
              : AuthState.signedIn;
          notifyListeners();
          return false;
        }
      }
      _errorMessage = '無法使用 Apple 登入：$e';
      _state = AuthState.error;
      notifyListeners();
      return false;
    }
  }

  // ============================================================
  // Microsoft Sign-In (Placeholder)
  // ============================================================

  Future<bool> signInWithMicrosoft() async {
    _state = AuthState.signingIn;
    _errorMessage = null;
    notifyListeners();

    // TODO: Implement Microsoft OAuth using aad_oauth package
    // This requires Azure AD app registration
    _errorMessage = 'Microsoft 登入即將推出，敬請期待';
    _state = AuthState.error;
    notifyListeners();
    return false;
  }

  String? get microsoftAccessToken => _microsoftAccessToken;

  // ============================================================
  // Sign Out
  // ============================================================

  Future<void> signOut() async {
    try {
      switch (_user?.provider) {
        case AuthProvider.google:
          await _googleSignIn.signOut();
          _googleAccount = null;
          break;
        case AuthProvider.apple:
          _appleCredential = null;
          break;
        case AuthProvider.microsoft:
          _microsoftAccessToken = null;
          break;
        default:
          break;
      }
    } catch (e) {
      debugPrint('Sign out error: $e');
    }

    // Clear sync preferences when signing out
    _syncPrefs = const CloudSyncPreferences();
    await _saveSyncPrefs();

    await _clearUserPrefs();
    _user = AuthUser.anonymous();
    _state = AuthState.signedOut;
    _errorMessage = null;
    notifyListeners();
  }

  /// Continue as anonymous (local-only mode)
  void continueAsAnonymous() {
    _user = AuthUser.anonymous();
    _state = AuthState.signedOut;
    _errorMessage = null;
    notifyListeners();
  }

  /// Clear error state
  void clearError() {
    _errorMessage = null;
    if (_state == AuthState.error) {
      _state =
          _user?.isAnonymous ?? true ? AuthState.signedOut : AuthState.signedIn;
    }
    notifyListeners();
  }

  // ============================================================
  // Cloud Sync Preferences
  // ============================================================

  /// Enable cloud sync (requires user consent)
  Future<void> enableCloudSync({required bool userConsented}) async {
    if (!canUseCloudFeatures) return;

    _syncPrefs = _syncPrefs.copyWith(
      enabled: true,
      provider: _user!.cloudProvider,
      userConsented: userConsented,
      lastSyncTime: DateTime.now(),
    );
    await _saveSyncPrefs();
    notifyListeners();
  }

  /// Disable cloud sync
  Future<void> disableCloudSync() async {
    _syncPrefs = _syncPrefs.copyWith(
      enabled: false,
    );
    await _saveSyncPrefs();
    notifyListeners();
  }

  /// Update sync preferences
  Future<void> updateSyncPrefs(CloudSyncPreferences prefs) async {
    _syncPrefs = prefs;
    await _saveSyncPrefs();
    notifyListeners();
  }

  // ============================================================
  // Persistence
  // ============================================================

  Future<void> _saveUserToPrefs() async {
    if (_user == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_userPrefKey, jsonEncode(_user!.toJson()));
    } catch (e) {
      debugPrint('Failed to save user: $e');
    }
  }

  Future<AuthUser?> _loadUserFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userStr = prefs.getString(_userPrefKey);
      if (userStr != null) {
        return AuthUser.fromJson(jsonDecode(userStr) as Map<String, dynamic>);
      }
    } catch (e) {
      debugPrint('Failed to load user: $e');
    }
    return null;
  }

  Future<void> _clearUserPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_userPrefKey);
    } catch (e) {
      debugPrint('Failed to clear user: $e');
    }
  }

  Future<void> _saveSyncPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_syncPrefKey, jsonEncode(_syncPrefs.toJson()));
    } catch (e) {
      debugPrint('Failed to save sync prefs: $e');
    }
  }

  Future<void> _loadSyncPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final prefsStr = prefs.getString(_syncPrefKey);
      if (prefsStr != null) {
        _syncPrefs = CloudSyncPreferences.fromJson(
            jsonDecode(prefsStr) as Map<String, dynamic>);
      }
    } catch (e) {
      debugPrint('Failed to load sync prefs: $e');
    }
  }

  /// Refresh authentication token
  Future<bool> refreshAuth() async {
    switch (_user?.provider) {
      case AuthProvider.google:
        if (_googleAccount != null) {
          try {
            final auth = await _googleAccount!.authentication;
            if (auth.accessToken == null) {
              _googleAccount =
                  await _googleSignIn.signInSilently(reAuthenticate: true);
              return _googleAccount != null;
            }
            return true;
          } catch (e) {
            debugPrint('Google auth refresh error: $e');
            return false;
          }
        }
        break;
      case AuthProvider.microsoft:
        // TODO: Implement Microsoft token refresh
        break;
      default:
        break;
    }
    return false;
  }
}
