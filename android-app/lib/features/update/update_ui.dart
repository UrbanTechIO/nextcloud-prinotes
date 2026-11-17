import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'apk_installer.dart';
import 'update_checker.dart';

/// "70 MB", or an empty string when the size is unknown.
String formatMegabytes(int bytes) => bytes <= 0 ? '' : '${(bytes / (1024 * 1024)).round()} MB';

/// Asks whether to install [release]. Returns true when the install screen was started, false otherwise.
Future<bool?> showUpdateDialog(BuildContext context, ReleaseInfo release, {required String currentVersion}) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _UpdateDialog(release: release, currentVersion: currentVersion),
  );
}

class _UpdateDialog extends ConsumerStatefulWidget {
  final ReleaseInfo release;
  final String currentVersion;
  const _UpdateDialog({required this.release, required this.currentVersion});

  @override
  ConsumerState<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends ConsumerState<_UpdateDialog> {
  double? _progress; // null: not downloading
  String? _error;
  bool _needsPermission = false;

  Future<void> _start() async {
    setState(() {
      _progress = 0;
      _error = null;
      _needsPermission = false;
    });
    try {
      await runUpdate(widget.release, ref.read(apkInstallerProvider), onProgress: (f) {
        if (mounted) setState(() => _progress = f);
      });
      if (mounted) Navigator.pop(context, true);
    } on InstallNotAllowed {
      if (mounted) {
        setState(() {
          _progress = null;
          _needsPermission = true;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _progress = null;
          _error = 'Download failed. Check your connection and try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.release;
    final size = formatMegabytes(r.apkSize);
    final busy = _progress != null;
    return AlertDialog(
      title: Text('Update available: ${r.version}'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 360),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('You have ${widget.currentVersion}${size.isEmpty ? '' : ' · download $size'}',
                style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7))),
            if (r.notes.trim().isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(r.notes.trim().replaceAll(RegExp(r'^#+\s*', multiLine: true), '')),
            ],
            if (busy) ...[
              const SizedBox(height: 16),
              LinearProgressIndicator(value: _progress == 0 ? null : _progress),
              const SizedBox(height: 6),
              Text('Downloading ${((_progress ?? 0) * 100).round()}%', style: const TextStyle(fontSize: 12)),
            ],
            if (_needsPermission) ...[
              const SizedBox(height: 16),
              const Text(
                'Android needs your OK first. In the page that opened, turn on "Install unknown apps" for PriNotes, '
                'come back and tap Download and install again.',
                style: TextStyle(color: Colors.amber),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(_error!, style: const TextStyle(color: Colors.redAccent)),
            ],
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: busy ? null : () => Navigator.pop(context, false), child: const Text('Later')),
        ElevatedButton(onPressed: busy ? null : _start, child: const Text('Download and install')),
      ],
    );
  }
}

/// "Check for updates" in Settings: always answers, with the update dialog, "up to date", or an error.
Future<void> checkForUpdateManually(BuildContext context, WidgetRef ref) async {
  final messenger = ScaffoldMessenger.of(context);
  final version = (await PackageInfo.fromPlatform()).version;
  try {
    final r = await ref.read(updateCheckerProvider).latestIfNewer(version);
    if (!context.mounted) return;
    if (r == null) {
      messenger.showSnackBar(SnackBar(content: Text("You're up to date ($version)")));
      return;
    }
    ref.read(availableUpdateProvider.notifier).state = null;
    await showUpdateDialog(context, r, currentVersion: version);
  } on UpdateCheckFailed {
    messenger.showSnackBar(const SnackBar(content: Text("Couldn't check for updates. Check your connection")));
  }
}
