import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../data/remote/api_client.dart';
import '../providers/auth_provider.dart';

class SetupScreen extends ConsumerStatefulWidget {
  const SetupScreen({super.key});

  @override
  ConsumerState<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends ConsumerState<SetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _serverCtrl = TextEditingController(text: 'https://');
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 40),
                // Logo
                Center(
                  child: Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: const Color(0xFF2563EB),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Icon(Icons.note_alt_rounded, color: Colors.white, size: 44),
                  ),
                ),
                const SizedBox(height: 24),
                const Center(
                  child: Text(
                    'PriNotes',
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                  ),
                ),
                const Center(
                  child: Text(
                    'Connect to your Nextcloud server',
                    style: TextStyle(color: Colors.grey, fontSize: 15),
                  ),
                ),
                const SizedBox(height: 40),

                // Server URL
                TextFormField(
                  controller: _serverCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Nextcloud Server URL',
                    hintText: 'https://your-server.com',
                    prefixIcon: Icon(Icons.cloud_outlined),
                  ),
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Required';
                    if (!v.startsWith('http')) return 'Must start with http(s)://';
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // Username
                TextFormField(
                  controller: _userCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Username',
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                  autocorrect: false,
                  validator: (v) => v?.isEmpty == true ? 'Required' : null,
                ),
                const SizedBox(height: 16),

                // App password
                TextFormField(
                  controller: _passCtrl,
                  decoration: const InputDecoration(
                    labelText: 'App Password',
                    hintText: 'Generate in Nextcloud → Settings → Security',
                    prefixIcon: Icon(Icons.key_outlined),
                  ),
                  obscureText: true,
                  validator: (v) => v?.isEmpty == true ? 'Required' : null,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Use an App Password, not your Nextcloud login password. Go to Nextcloud → Settings → Security → App passwords.',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 24),

                if (_error != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red.shade200),
                    ),
                    child: Text(_error!, style: TextStyle(color: Colors.red.shade700)),
                  ),
                  const SizedBox(height: 16),
                ],

                ElevatedButton(
                  onPressed: _loading ? null : _connect,
                  child: _loading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                        )
                      : const Text('Connect & Continue'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _connect() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _loading = true; _error = null; });

    final serverUrl = _serverCtrl.text.trimRight().replaceAll(RegExp(r'/$'), '');
    final username  = _userCtrl.text.trim();
    final password  = _passCtrl.text;

    final apiClient = ref.read(apiClientProvider);
    final ok = await apiClient.testConnection(serverUrl, username, password);

    if (!ok) {
      setState(() {
        _loading = false;
        _error = 'Could not connect. Check the URL and app password.';
      });
      return;
    }

    await ref.read(authStateProvider.notifier).setup(
      serverUrl: serverUrl,
      username: username,
      appPassword: password,
    );
    apiClient.reset(); // force Dio to rebuild with the new user's credentials

    if (mounted) context.go('/');
  }

  @override
  void dispose() {
    _serverCtrl.dispose();
    _userCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }
}
