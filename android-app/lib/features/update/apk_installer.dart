import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'update_checker.dart';

/// Thrown when Android has not yet allowed PriNotes to install apps; the settings page has been opened.
class InstallNotAllowed implements Exception {
  @override
  String toString() => 'PriNotes is not allowed to install apps yet';
}

/// Downloads a release APK and hands it to Android's package installer.
abstract class ApkInstaller {
  Future<bool> canInstall();
  Future<void> openInstallSettings();
  Future<String> download(ReleaseInfo release, void Function(double fraction) onProgress);
  Future<void> install(String path);
}

class AndroidApkInstaller implements ApkInstaller {
  static const _channel = MethodChannel('prinotes/system');

  @override
  Future<bool> canInstall() async => (await _channel.invokeMethod<bool>('canInstallApks')) ?? false;

  @override
  Future<void> openInstallSettings() => _channel.invokeMethod('openInstallSettings');

  @override
  Future<String> download(ReleaseInfo release, void Function(double fraction) onProgress) async {
    final dir = Directory('${(await getTemporaryDirectory()).path}/updates');
    await dir.create(recursive: true);
    final file = File('${dir.path}/prinotes-update.apk');
    if (await file.exists()) await file.delete();
    await Dio(BaseOptions(connectTimeout: const Duration(seconds: 15), receiveTimeout: const Duration(minutes: 10)))
        .download(
      release.apkUrl,
      file.path,
      onReceiveProgress: (got, total) {
        final t = total > 0 ? total : release.apkSize;
        if (t > 0) onProgress((got / t).clamp(0.0, 1.0));
      },
    );
    // A short file is a broken download: installing it would only fail with "package is invalid".
    if (release.apkSize > 0 && await file.length() != release.apkSize) {
      await file.delete();
      throw const FileSystemException('Download incomplete');
    }
    return file.path;
  }

  @override
  Future<void> install(String path) => _channel.invokeMethod('installApk', {'path': path});
}

final apkInstallerProvider = Provider<ApkInstaller>((_) => AndroidApkInstaller());

/// Checks permission, downloads the APK and starts the install. Returns once Android's install screen is up.
Future<void> runUpdate(ReleaseInfo release, ApkInstaller installer, {void Function(double fraction)? onProgress}) async {
  if (!await installer.canInstall()) {
    await installer.openInstallSettings();
    throw InstallNotAllowed();
  }
  final path = await installer.download(release, onProgress ?? (_) {});
  await installer.install(path);
}
