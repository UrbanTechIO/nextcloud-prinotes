import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import '../../../core/constants/app_constants.dart';

class AuthState {
  final bool isSetup;
  final bool isLocked;
  final bool isAuthenticated;
  final String? serverUrl;
  final String? username;

  const AuthState({
    this.isSetup = false,
    this.isLocked = true,
    this.isAuthenticated = false,
    this.serverUrl,
    this.username,
  });

  AuthState copyWith({
    bool? isSetup,
    bool? isLocked,
    bool? isAuthenticated,
    String? serverUrl,
    String? username,
  }) => AuthState(
    isSetup: isSetup ?? this.isSetup,
    isLocked: isLocked ?? this.isLocked,
    isAuthenticated: isAuthenticated ?? this.isAuthenticated,
    serverUrl: serverUrl ?? this.serverUrl,
    username: username ?? this.username,
  );
}

class AuthNotifier extends StateNotifier<AuthState> {
  final _storage = const FlutterSecureStorage();
  final _localAuth = LocalAuthentication();

  AuthNotifier() : super(const AuthState()) {
    _init();
  }

  Future<void> _init() async {
    final serverUrl = await _storage.read(key: AppConstants.serverUrlKey);
    final username  = await _storage.read(key: AppConstants.usernameKey);
    final lockEnabled = await _storage.read(key: AppConstants.appLockEnabledKey);

    final isSetup = serverUrl != null && serverUrl.isNotEmpty;
    final isLocked = lockEnabled == 'true';

    state = state.copyWith(
      isSetup: isSetup,
      isLocked: isLocked,
      isAuthenticated: !isLocked, // if no lock, auto-authenticated
      serverUrl: serverUrl,
      username: username,
    );
  }

  Future<void> setup({
    required String serverUrl,
    required String username,
    required String appPassword,
  }) async {
    await _storage.write(key: AppConstants.serverUrlKey, value: serverUrl);
    await _storage.write(key: AppConstants.usernameKey, value: username);
    await _storage.write(key: AppConstants.appPasswordKey, value: appPassword);
    state = state.copyWith(
      isSetup: true,
      isAuthenticated: true,
      isLocked: false,
      serverUrl: serverUrl,
      username: username,
    );
  }

  Future<bool> authenticateWithPin(String pin) async {
    final storedHash = await _storage.read(key: AppConstants.appPinHashKey);
    if (storedHash == null) return false;
    final inputHash = _hashPin(pin);
    if (inputHash == storedHash) {
      state = state.copyWith(isAuthenticated: true, isLocked: false);
      return true;
    }
    return false;
  }

  Future<bool> authenticateWithBiometric() async {
    try {
      final available = await _localAuth.canCheckBiometrics;
      if (!available) return false;
      final result = await _localAuth.authenticate(
        localizedReason: 'Unlock PriNotes',
        options: const AuthenticationOptions(
          biometricOnly: false,
          stickyAuth: true,
        ),
      );
      if (result) {
        state = state.copyWith(isAuthenticated: true, isLocked: false);
      }
      return result;
    } catch (_) {
      return false;
    }
  }

  Future<void> setPin(String pin) async {
    await _storage.write(key: AppConstants.appPinHashKey, value: _hashPin(pin));
    await _storage.write(key: AppConstants.appLockEnabledKey, value: 'true');
    await _storage.write(key: AppConstants.appLockTypeKey, value: 'pin');
    state = state.copyWith(isLocked: false);
  }

  Future<void> enableBiometric() async {
    await _storage.write(key: AppConstants.appLockEnabledKey, value: 'true');
    await _storage.write(key: AppConstants.appLockTypeKey, value: 'biometric');
  }

  Future<void> disableLock() async {
    await _storage.write(key: AppConstants.appLockEnabledKey, value: 'false');
    state = state.copyWith(isLocked: false, isAuthenticated: true);
  }

  Future<String?> getLockType() => _storage.read(key: AppConstants.appLockTypeKey);

  Future<bool> hasBiometrics() => _localAuth.canCheckBiometrics;

  void lock() {
    state = state.copyWith(isLocked: true, isAuthenticated: false);
  }

  Future<void> logout() async {
    await _storage.deleteAll();
    state = const AuthState();
  }

  String _hashPin(String pin) {
    final bytes = utf8.encode('$pin:prinotes-mobile-salt');
    return sha256.convert(bytes).toString();
  }
}

final authStateProvider = StateNotifierProvider<AuthNotifier, AuthState>(
  (ref) => AuthNotifier(),
);
