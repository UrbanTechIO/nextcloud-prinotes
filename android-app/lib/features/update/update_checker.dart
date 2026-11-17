import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Where releases are published. The app looks for the newest one that carries an Android APK.
const kReleasesUrl = 'https://api.github.com/repos/UrbanTechIO/nextcloud-prinotes/releases?per_page=15';

class ReleaseInfo {
  final String tag;
  final String version;
  final String apkUrl;
  final int apkSize;
  final String notes;
  const ReleaseInfo({required this.tag, required this.version, required this.apkUrl, required this.apkSize, required this.notes});
}

class UpdateCheckFailed implements Exception {
  final Object cause;
  UpdateCheckFailed(this.cause);
  @override
  String toString() => 'Could not check for updates: $cause';
}

List<int>? _parts(String v) {
  final core = v.trim().replaceFirst(RegExp(r'^[vV]'), '').split('+').first.split('-').first;
  if (core.isEmpty) return null;
  final out = <int>[];
  for (final p in core.split('.')) {
    final n = int.tryParse(p);
    if (n == null) return null;
    out.add(n);
  }
  return out;
}

/// True when [latest] is a higher version than [current]. Numeric, ignores a leading "v" and any "+build".
/// Anything unreadable counts as "not newer", so a bad tag never triggers an update prompt.
bool isNewerVersion(String latest, String current) {
  final a = _parts(latest);
  final b = _parts(current);
  if (a == null || b == null) return false;
  final n = a.length > b.length ? a.length : b.length;
  for (var i = 0; i < n; i++) {
    final x = i < a.length ? a[i] : 0;
    final y = i < b.length ? b[i] : 0;
    if (x != y) return x > y;
  }
  return false;
}

/// The newest published release that has an Android APK. Web-only releases, drafts and pre-releases are skipped.
ReleaseInfo? pickAndroidRelease(dynamic releases) {
  if (releases is! List) return null;
  for (final r in releases) {
    if (r is! Map || r['draft'] == true || r['prerelease'] == true) continue;
    final tag = r['tag_name'];
    final assets = r['assets'];
    if (tag is! String || assets is! List) continue;
    for (final a in assets) {
      if (a is Map && a['name'] is String && (a['name'] as String).toLowerCase().endsWith('.apk')) {
        final url = a['browser_download_url'];
        if (url is! String) continue;
        return ReleaseInfo(
          tag: tag,
          version: tag.replaceFirst(RegExp(r'^[vV]'), ''),
          apkUrl: url,
          apkSize: (a['size'] is int) ? a['size'] as int : 0,
          notes: (r['body'] is String) ? r['body'] as String : '',
        );
      }
    }
  }
  return null;
}

Future<dynamic> _defaultFetch(String url) async {
  final res = await Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 15),
    headers: {'Accept': 'application/vnd.github+json'},
  )).get(url);
  return res.data;
}

class UpdateChecker {
  final Future<dynamic> Function(String url) _fetch;
  UpdateChecker({Future<dynamic> Function(String url)? fetch}) : _fetch = fetch ?? _defaultFetch;

  /// The newest release when it is newer than [currentVersion], else null. Throws [UpdateCheckFailed]
  /// when GitHub cannot be reached.
  Future<ReleaseInfo?> latestIfNewer(String currentVersion) async {
    final dynamic data;
    try {
      data = await _fetch(kReleasesUrl);
    } catch (e) {
      throw UpdateCheckFailed(e);
    }
    final r = pickAndroidRelease(data);
    if (r == null || !isNewerVersion(r.version, currentVersion)) return null;
    return r;
  }
}

/// The launch-time prompt is not repeated for a version the user already said "Later" to.
bool shouldAutoPrompt(ReleaseInfo r, String? dismissedVersion) => r.version != dismissedVersion;

const _store = FlutterSecureStorage();
const _kDismissed = 'update_dismissed_version';

Future<String?> loadDismissedUpdate() async {
  try {
    return await _store.read(key: _kDismissed);
  } catch (_) {
    return null;
  }
}

Future<void> saveDismissedUpdate(String version) async {
  try {
    await _store.write(key: _kDismissed, value: version);
  } catch (_) {}
}

/// Set by the check at app start when a newer release exists and the user has not dismissed it.
final availableUpdateProvider = StateProvider<ReleaseInfo?>((_) => null);

final updateCheckerProvider = Provider<UpdateChecker>((_) => UpdateChecker());

/// Runs at app start: looks for a newer release and, unless the user already said "Later" to that
/// version, publishes it so the notes screen can offer it. Never throws: no network just means no prompt.
Future<void> checkForUpdateAtStart(ProviderContainer c, String currentVersion) async {
  try {
    final r = await c.read(updateCheckerProvider).latestIfNewer(currentVersion);
    if (r != null && shouldAutoPrompt(r, await loadDismissedUpdate())) {
      c.read(availableUpdateProvider.notifier).state = r;
    }
  } catch (_) {}
}
