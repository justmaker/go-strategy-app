/// Settings Screen
///
/// App settings including:
/// - Account management (sign in/out)
/// - Cloud sync preferences
/// - Game record management
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/game_record.dart';
import '../services/auth_service.dart';
import '../services/cloud_storage_service.dart';
import '../services/game_record_service.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('設定'),
      ),
      body: Consumer3<AuthService, CloudStorageManager, GameRecordService>(
        builder: (context, auth, cloud, records, _) {
          return ListView(
            children: [
              // Account Section
              _SectionHeader(title: '帳號'),
              if (auth.isSignedIn && !auth.isAnonymous)
                _AccountTile(auth: auth)
              else
                _SignInTile(auth: auth),

              const Divider(height: 32),

              // Cloud Sync Section
              _SectionHeader(title: '雲端同步'),
              if (auth.canUseCloudFeatures) ...[
                _CloudSyncTile(auth: auth, cloud: cloud, records: records),
                if (auth.syncPrefs.enabled) ...[
                  _SyncSettingsTile(auth: auth),
                  _SyncNowTile(cloud: cloud, records: records),
                ],
              ] else ...[
                const ListTile(
                  leading: Icon(Icons.cloud_off),
                  title: Text('需要登入才能使用雲端同步'),
                  subtitle: Text('請先在上方「帳號」區塊登入'),
                ),
              ],

              const Divider(height: 32),

              // Game Records Section
              _SectionHeader(title: '棋譜管理'),
              ListTile(
                leading: const Icon(Icons.folder),
                title: const Text('本機棋譜'),
                subtitle: Text('${records.records.length} 個棋譜'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _showRecordsList(context, records),
              ),

              const Divider(height: 32),

              // About Section
              _SectionHeader(title: '關於'),
              const ListTile(
                leading: Icon(Icons.info_outline),
                title: Text('Go Strategy'),
                subtitle: Text('版本 1.0.0'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showSignInSheet(BuildContext context, AuthService auth) {
    showModalBottomSheet(
      context: context,
      builder: (context) => _SignInSheet(auth: auth),
    );
  }

  void _showRecordsList(BuildContext context, GameRecordService records) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => _RecordsListScreen(records: records),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;

  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.bold,
            ),
      ),
    );
  }
}

class _AccountTile extends StatelessWidget {
  final AuthService auth;

  const _AccountTile({required this.auth});

  @override
  Widget build(BuildContext context) {
    final user = auth.user!;
    final providerName = switch (user.provider) {
      AuthProvider.google => 'Google',
      AuthProvider.apple => 'Apple',
      AuthProvider.microsoft => 'Microsoft',
      AuthProvider.anonymous => '訪客',
    };

    return ListTile(
      leading: CircleAvatar(
        backgroundImage:
            user.photoUrl != null ? NetworkImage(user.photoUrl!) : null,
        child: user.photoUrl == null
            ? Text(user.displayName?.substring(0, 1).toUpperCase() ?? '?')
            : null,
      ),
      title: Text(user.displayName ?? user.email ?? '使用者'),
      subtitle: Text('已使用 $providerName 登入'),
      trailing: TextButton(
        onPressed: () => _confirmSignOut(context),
        child: const Text('登出'),
      ),
    );
  }

  void _confirmSignOut(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('確定要登出嗎？'),
        content: const Text('登出後，您的棋譜將不再同步到雲端。本機的棋譜不會被刪除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              auth.signOut();
            },
            child: const Text('登出'),
          ),
        ],
      ),
    );
  }
}

class _SignInTile extends StatelessWidget {
  final AuthService auth;

  const _SignInTile({required this.auth});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const CircleAvatar(
        child: Icon(Icons.person_outline),
      ),
      title: const Text('尚未登入'),
      subtitle: const Text('登入以啟用雲端同步'),
      trailing: ElevatedButton(
        onPressed: () => _showSignInSheet(context),
        child: const Text('登入'),
      ),
    );
  }

  void _showSignInSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (context) => _SignInSheet(auth: auth),
    );
  }
}

class _SignInSheet extends StatelessWidget {
  final AuthService auth;

  const _SignInSheet({required this.auth});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '選擇登入方式',
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            _buildSignInButton(
              context,
              icon: Icons.g_mobiledata,
              label: 'Google',
              subtitle: '同步到 Google Drive',
              onPressed: () async {
                Navigator.of(context).pop();
                await auth.signInWithGoogle();
              },
            ),
            const SizedBox(height: 12),
            if (auth.isProviderAvailable(AuthProvider.apple))
              _buildSignInButton(
                context,
                icon: Icons.apple,
                label: 'Apple',
                subtitle: '同步到 iCloud',
                onPressed: () async {
                  Navigator.of(context).pop();
                  await auth.signInWithApple();
                },
              ),
            const SizedBox(height: 12),
            _buildSignInButton(
              context,
              icon: Icons.window,
              label: 'Microsoft',
              subtitle: '同步到 OneDrive (即將推出)',
              onPressed: null,
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildSignInButton(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String subtitle,
    required VoidCallback? onPressed,
  }) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.all(16),
      ),
      child: Row(
        children: [
          Icon(icon, size: 28),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CloudSyncTile extends StatelessWidget {
  final AuthService auth;
  final CloudStorageManager cloud;
  final GameRecordService records;

  const _CloudSyncTile({
    required this.auth,
    required this.cloud,
    required this.records,
  });

  @override
  Widget build(BuildContext context) {
    final providerName = switch (auth.user?.cloudProvider) {
      CloudProvider.googleDrive => 'Google Drive',
      CloudProvider.iCloud => 'iCloud',
      CloudProvider.oneDrive => 'OneDrive',
      _ => '雲端',
    };

    return SwitchListTile(
      secondary: const Icon(Icons.cloud),
      title: const Text('雲端同步'),
      subtitle: Text(
        auth.syncPrefs.enabled
            ? '棋譜將自動同步到 $providerName'
            : '啟用後，棋譜將存放在您的 $providerName',
      ),
      value: auth.syncPrefs.enabled,
      onChanged: (value) async {
        if (value) {
          // Show consent dialog
          final consent = await _showConsentDialog(context, providerName);
          if (consent == true) {
            await auth.enableCloudSync(userConsented: true);
            // Trigger initial sync
            await records.syncAllToCloud();
          }
        } else {
          await auth.disableCloudSync();
        }
      },
    );
  }

  Future<bool?> _showConsentDialog(BuildContext context, String provider) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('啟用雲端同步'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('您的棋譜將儲存在您的 $provider 帳號中：'),
            const SizedBox(height: 16),
            const Row(
              children: [
                Icon(Icons.folder, size: 20),
                SizedBox(width: 8),
                Text('Go Strategy 資料夾'),
              ],
            ),
            const SizedBox(height: 8),
            const Row(
              children: [
                Icon(Icons.lock, size: 20),
                SizedBox(width: 8),
                Expanded(child: Text('只有您可以存取這些檔案')),
              ],
            ),
            const SizedBox(height: 8),
            const Row(
              children: [
                Icon(Icons.delete_outline, size: 20),
                SizedBox(width: 8),
                Expanded(child: Text('您可以隨時刪除或匯出')),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('同意並啟用'),
          ),
        ],
      ),
    );
  }
}

class _SyncSettingsTile extends StatelessWidget {
  final AuthService auth;

  const _SyncSettingsTile({required this.auth});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SwitchListTile(
          secondary: const SizedBox(width: 24),
          title: const Text('自動同步'),
          subtitle: const Text('儲存棋譜時自動上傳'),
          value: auth.syncPrefs.autoSync,
          onChanged: (value) async {
            await auth.updateSyncPrefs(
              auth.syncPrefs.copyWith(autoSync: value),
            );
          },
        ),
        SwitchListTile(
          secondary: const SizedBox(width: 24),
          title: const Text('僅 Wi-Fi 同步'),
          subtitle: const Text('使用行動數據時不同步'),
          value: auth.syncPrefs.syncOnWifiOnly,
          onChanged: (value) async {
            await auth.updateSyncPrefs(
              auth.syncPrefs.copyWith(syncOnWifiOnly: value),
            );
          },
        ),
      ],
    );
  }
}

class _SyncNowTile extends StatefulWidget {
  final CloudStorageManager cloud;
  final GameRecordService records;

  const _SyncNowTile({required this.cloud, required this.records});

  @override
  State<_SyncNowTile> createState() => _SyncNowTileState();
}

class _SyncNowTileState extends State<_SyncNowTile> {
  bool _syncing = false;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const SizedBox(width: 24),
      title: const Text('立即同步'),
      subtitle: widget.cloud.lastSyncTime != null
          ? Text('上次同步：${_formatTime(widget.cloud.lastSyncTime!)}')
          : const Text('尚未同步'),
      trailing: _syncing
          ? const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.sync),
      onTap: _syncing ? null : _sync,
    );
  }

  Future<void> _sync() async {
    setState(() => _syncing = true);
    try {
      final results = await widget.records.fullSync();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '同步完成：上傳 ${results['uploaded']} 個，下載 ${results['downloaded']} 個',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('同步失敗：$e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _syncing = false);
      }
    }
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);

    if (diff.inMinutes < 1) return '剛剛';
    if (diff.inHours < 1) return '${diff.inMinutes} 分鐘前';
    if (diff.inDays < 1) return '${diff.inHours} 小時前';
    return '${diff.inDays} 天前';
  }
}

class _RecordsListScreen extends StatelessWidget {
  final GameRecordService records;

  const _RecordsListScreen({required this.records});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('棋譜列表'),
      ),
      body: records.records.isEmpty
          ? const Center(child: Text('尚無棋譜'))
          : ListView.builder(
              itemCount: records.records.length,
              itemBuilder: (context, index) {
                final record = records.records[index];
                return ListTile(
                  leading: _buildStatusIcon(record.status),
                  title: Text(record.name),
                  subtitle: Text(
                    '${record.boardSize}x${record.boardSize} · ${record.moves.length} 手 · ${_formatDate(record.modifiedAt)}',
                  ),
                  trailing: PopupMenuButton<String>(
                    onSelected: (action) =>
                        _handleAction(context, action, record),
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'export_sgf',
                        child: Text('匯出 SGF'),
                      ),
                      const PopupMenuItem(
                        value: 'export_json',
                        child: Text('匯出 JSON'),
                      ),
                      const PopupMenuItem(
                        value: 'delete',
                        child: Text('刪除', style: TextStyle(color: Colors.red)),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }

  Widget _buildStatusIcon(GameRecordStatus status) {
    switch (status) {
      case GameRecordStatus.synced:
        return const Icon(Icons.cloud_done, color: Colors.green);
      case GameRecordStatus.pendingUpload:
        return const Icon(Icons.cloud_upload, color: Colors.orange);
      case GameRecordStatus.pendingDownload:
        return const Icon(Icons.cloud_download, color: Colors.blue);
      case GameRecordStatus.conflict:
        return const Icon(Icons.warning, color: Colors.red);
      case GameRecordStatus.local:
      default:
        return const Icon(Icons.folder, color: Colors.grey);
    }
  }

  String _formatDate(DateTime date) {
    return '${date.year}/${date.month}/${date.day}';
  }

  void _handleAction(BuildContext context, String action, GameRecord record) {
    switch (action) {
      case 'export_sgf':
        final sgf = records.exportSgf(record);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('SGF 已複製 (${sgf.length} 字元)')),
        );
        break;
      case 'export_json':
        final json = records.exportJson(record);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('JSON 已複製 (${json.length} 字元)')),
        );
        break;
      case 'delete':
        _confirmDelete(context, record);
        break;
    }
  }

  void _confirmDelete(BuildContext context, GameRecord record) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('刪除棋譜'),
        content: Text('確定要刪除「${record.name}」嗎？此操作無法復原。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              records.deleteRecord(record.id);
            },
            child: const Text('刪除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}
