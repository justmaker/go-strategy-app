/// Authentication Screen
///
/// Allows users to sign in with Google, Apple, or Microsoft,
/// or continue as anonymous (local-only mode).
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/auth_service.dart';

class AuthScreen extends StatelessWidget {
  final VoidCallback onComplete;

  const AuthScreen({super.key, required this.onComplete});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Consumer<AuthService>(
          builder: (context, auth, _) {
            if (auth.state == AuthState.signingIn) {
              return const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('正在登入...'),
                  ],
                ),
              );
            }

            return Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                children: [
                  const Spacer(),
                  // App logo/title
                  const Icon(
                    Icons.grid_on,
                    size: 80,
                    color: Color(0xFF8B4513),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Go Strategy',
                    style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '圍棋策略分析',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: Colors.grey[600],
                        ),
                  ),
                  const SizedBox(height: 48),

                  // Sign in options
                  if (auth.errorMessage != null) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red[50],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline, color: Colors.red),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              auth.errorMessage!,
                              style: const TextStyle(color: Colors.red),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () => auth.clearError(),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Google Sign In
                  _SignInButton(
                    icon: 'G',
                    iconColor: Colors.red,
                    label: '使用 Google 登入',
                    sublabel: '棋譜將存放在您的 Google Drive',
                    onPressed: () async {
                      if (await auth.signInWithGoogle()) {
                        onComplete();
                      }
                    },
                  ),
                  const SizedBox(height: 12),

                  // Apple Sign In (if available)
                  if (auth.isProviderAvailable(AuthProvider.apple)) ...[
                    _SignInButton(
                      icon: '',
                      iconWidget: const Icon(Icons.apple, size: 24),
                      label: '使用 Apple 登入',
                      sublabel: '棋譜將存放在您的 iCloud',
                      onPressed: () async {
                        if (await auth.signInWithApple()) {
                          onComplete();
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                  ],

                  // Microsoft Sign In
                  _SignInButton(
                    icon: 'M',
                    iconColor: Colors.blue,
                    label: '使用 Microsoft 登入',
                    sublabel: '棋譜將存放在您的 OneDrive',
                    onPressed: () async {
                      if (await auth.signInWithMicrosoft()) {
                        onComplete();
                      }
                    },
                    enabled: false, // Coming soon
                  ),

                  const SizedBox(height: 32),

                  // Divider
                  Row(
                    children: [
                      const Expanded(child: Divider()),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Text(
                          '或',
                          style: TextStyle(color: Colors.grey[600]),
                        ),
                      ),
                      const Expanded(child: Divider()),
                    ],
                  ),

                  const SizedBox(height: 24),

                  // Continue without account
                  OutlinedButton(
                    onPressed: () {
                      auth.continueAsAnonymous();
                      onComplete();
                    },
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 48),
                    ),
                    child: const Text('不登入，直接使用'),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '棋譜將只儲存在本機，無法雲端同步',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.grey[600],
                        ),
                  ),

                  const Spacer(),

                  // Privacy note
                  Text(
                    '登入即表示您同意我們的服務條款和隱私政策',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.grey[500],
                        ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _SignInButton extends StatelessWidget {
  final String icon;
  final Widget? iconWidget;
  final Color? iconColor;
  final String label;
  final String sublabel;
  final VoidCallback onPressed;
  final bool enabled;

  const _SignInButton({
    required this.icon,
    this.iconWidget,
    this.iconColor,
    required this.label,
    required this.sublabel,
    required this.onPressed,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1.0 : 0.5,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: enabled ? onPressed : null,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey[300]!),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(
                    child: iconWidget ??
                        Text(
                          icon,
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: iconColor ?? Colors.black,
                          ),
                        ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        enabled ? sublabel : '即將推出',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  color: Colors.grey[400],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
