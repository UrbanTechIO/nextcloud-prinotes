import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/remote/api_client.dart';
import '../../auth/providers/auth_provider.dart';
import 'package:local_auth/local_auth.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _storage = const FlutterSecureStorage();
  final _localAuth = LocalAuthentication();
  bool _lockEnabled = false;
  String _lockType = 'pin';
  bool _biometricAvailable = false;
  String _serverUrl = '';
  String _username = '';
  ThemeMode _themeMode = ThemeMode.system;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final lockEnabled = await _storage.read(key: AppConstants.appLockEnabledKey);
    final lockType = await _storage.read(key: AppConstants.appLockTypeKey);
    final serverUrl = await _storage.read(key: AppConstants.serverUrlKey);
    final username = await _storage.read(key: AppConstants.usernameKey);
    final hasBio = await _localAuth.canCheckBiometrics || await _localAuth.isDeviceSupported();
    final themeMode = ref.read(themeModeProvider);

    setState(() {
      _lockEnabled = lockEnabled == 'true';
      _lockType = lockType ?? 'pin';
      _serverUrl = serverUrl ?? '';
      _username = username ?? '';
      _biometricAvailable = hasBio;
      _themeMode = themeMode;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          // Account section
          _sectionHeader('Account'),
          ListTile(
            leading: const Icon(Icons.cloud_outlined),
            title: const Text('Server'),
            subtitle: Text(_serverUrl),
          ),
          ListTile(
            leading: const Icon(Icons.person_outline),
            title: const Text('Username'),
            subtitle: Text(_username),
          ),
          ListTile(
            leading: const Icon(Icons.key_outlined),
            title: const Text('Update app password'),
            subtitle: const Text('Use after regenerating a Nextcloud app password'),
            onTap: _updateAppPassword,
          ),
          ListTile(
            leading: const Icon(Icons.logout),
            title: const Text('Sign out'),
            onTap: _signOut,
          ),

          // Security section
          _sectionHeader('Security'),
          SwitchListTile(
            secondary: const Icon(Icons.lock_outline),
            title: const Text('App lock'),
            subtitle: const Text('Require PIN or biometric to open PriNotes'),
            value: _lockEnabled,
            onChanged: _toggleLock,
          ),
          if (_lockEnabled) ...[
            ListTile(
              leading: const Icon(Icons.pin_outlined),
              title: const Text('Change PIN'),
              onTap: _changePIN,
            ),
            SwitchListTile(
              secondary: const Icon(Icons.fingerprint),
              title: const Text('Biometric unlock'),
              subtitle: _biometricAvailable
                  ? null
                  : const Text('Enroll a fingerprint or face in device settings first'),
              value: _lockType == 'biometric' || _lockType == 'both',
              onChanged: _toggleBiometric,
            ),
          ],

          // Appearance
          _sectionHeader('Appearance'),
          ListTile(
            leading: const Icon(Icons.palette_outlined),
            title: const Text('Theme'),
            trailing: DropdownButton<ThemeMode>(
              value: _themeMode,
              underline: const SizedBox(),
              items: const [
                DropdownMenuItem(value: ThemeMode.system, child: Text('System')),
                DropdownMenuItem(value: ThemeMode.light, child: Text('Light')),
                DropdownMenuItem(value: ThemeMode.dark, child: Text('Dark')),
              ],
              onChanged: (mode) {
                if (mode == null) return;
                setState(() => _themeMode = mode);
                ref.read(themeModeProvider.notifier).state = mode;
              },
            ),
          ),

          // About
          _sectionHeader('About'),
          const ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('Version'),
            subtitle: Text('1.0.0'),
          ),
          const ListTile(
            leading: Icon(Icons.code),
            title: Text('PriNotes'),
            subtitle: Text('Open source note-taking for Nextcloud'),
          ),

          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: Colors.grey.shade500,
          letterSpacing: 0.8,
        ),
      ),
    );
  }

  Future<void> _toggleLock(bool value) async {
    if (value) {
      // Set PIN first
      await _changePIN();
    } else {
      await ref.read(authStateProvider.notifier).disableLock();
      setState(() => _lockEnabled = false);
    }
  }

  Future<void> _changePIN() async {
    final pinCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    String? error;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Set App PIN'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Enter a PIN (4-8 digits) to protect the app.', style: TextStyle(fontSize: 13)),
              const SizedBox(height: 12),
              TextField(
                controller: pinCtrl,
                obscureText: true,
                keyboardType: TextInputType.number,
                maxLength: 8,
                decoration: const InputDecoration(labelText: 'New PIN'),
              ),
              TextField(
                controller: confirmCtrl,
                obscureText: true,
                keyboardType: TextInputType.number,
                maxLength: 8,
                decoration: const InputDecoration(labelText: 'Confirm PIN'),
              ),
              if (error != null)
                Text(error!, style: const TextStyle(color: Colors.red, fontSize: 12)),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                if (pinCtrl.text.length < 4) {
                  setDialogState(() => error = 'PIN must be at least 4 digits');
                  return;
                }
                if (pinCtrl.text != confirmCtrl.text) {
                  setDialogState(() => error = 'PINs do not match');
                  return;
                }
                await ref.read(authStateProvider.notifier).setPin(pinCtrl.text);
                setState(() { _lockEnabled = true; _lockType = 'pin'; });
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('Set PIN'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _toggleBiometric(bool value) async {
    if (value) {
      final ok = await _localAuth.authenticate(
        localizedReason: 'Enable biometric unlock for PriNotes',
      );
      if (ok) {
        await ref.read(authStateProvider.notifier).enableBiometric();
        setState(() => _lockType = 'biometric');
      }
    } else {
      setState(() => _lockType = 'pin');
      await _storage.write(key: AppConstants.appLockTypeKey, value: 'pin');
    }
  }

  Future<void> _updateAppPassword() async {
    final pwCtrl = TextEditingController();
    String? errorMsg;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Update App Password'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Generate a new app password in Nextcloud (Settings → Security → App passwords) then paste it here.',
                style: TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: pwCtrl,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'New app password'),
                onChanged: (_) { if (errorMsg != null) setDialogState(() => errorMsg = null); },
              ),
              if (errorMsg != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(errorMsg!, style: const TextStyle(color: Colors.red, fontSize: 12)),
                ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                final pw = pwCtrl.text.trim();
                if (pw.isEmpty) {
                  setDialogState(() => errorMsg = 'Password cannot be empty');
                  return;
                }
                // Test connection before saving
                final api = ref.read(apiClientProvider);
                final ok = await api.testConnection(_serverUrl, _username, pw);
                if (!ok) {
                  setDialogState(() => errorMsg = 'Connection failed — check the password and try again');
                  return;
                }
                await _storage.write(key: AppConstants.appPasswordKey, value: pw);
                api.reset(); // force Dio to re-read the new password
                if (ctx.mounted) Navigator.pop(ctx, true);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );

    if (confirmed == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('App password updated — sync will resume')),
      );
    }
  }

  Future<void> _signOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text('All local data will be cleared. Make sure everything is synced.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      ref.read(apiClientProvider).reset(); // clear cached credentials before logout
      await ref.read(authStateProvider.notifier).logout();
      if (mounted) context.go('/setup');
    }
  }
}
