import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/auth_provider.dart';

class LockScreen extends ConsumerStatefulWidget {
  const LockScreen({super.key});

  @override
  ConsumerState<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends ConsumerState<LockScreen> {
  final _pin = <String>[];
  String? _error;
  bool _biometricAvailable = false;
  String _lockType = 'pin';

  @override
  void initState() {
    super.initState();
    _checkBiometric();
  }

  Future<void> _checkBiometric() async {
    final auth = ref.read(authStateProvider.notifier);
    final lockType = await auth.getLockType() ?? 'pin';
    final hasBio = await auth.hasBiometrics();
    setState(() {
      _lockType = lockType;
      _biometricAvailable = hasBio && (lockType == 'biometric' || lockType == 'both');
    });
    if (_biometricAvailable) {
      _tryBiometric();
    }
  }

  Future<void> _tryBiometric() async {
    final ok = await ref.read(authStateProvider.notifier).authenticateWithBiometric();
    if (ok && mounted) context.go('/');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.lock_rounded, color: Color(0xFF2563EB), size: 60),
            const SizedBox(height: 16),
            const Text(
              'PriNotes',
              style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            const Text(
              'Enter PIN to unlock',
              style: TextStyle(color: Colors.white54, fontSize: 14),
            ),
            const SizedBox(height: 48),

            // PIN dots
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(6, (i) {
                final filled = i < _pin.length;
                return Container(
                  width: 16,
                  height: 16,
                  margin: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: filled ? const Color(0xFF2563EB) : Colors.white24,
                  ),
                );
              }),
            ),

            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(_error!, style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
            ],

            const SizedBox(height: 40),

            // Numpad
            _buildNumpad(),

            const SizedBox(height: 24),

            if (_biometricAvailable)
              TextButton.icon(
                onPressed: _tryBiometric,
                icon: const Icon(Icons.fingerprint, color: Colors.white70),
                label: const Text('Use biometric', style: TextStyle(color: Colors.white70)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildNumpad() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 60),
      child: GridView.count(
        crossAxisCount: 3,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        childAspectRatio: 1.4,
        children: [
          ...['1','2','3','4','5','6','7','8','9'].map(_numKey),
          _iconKey(Icons.backspace_outlined, _backspace),
          _numKey('0'),
          _iconKey(Icons.check_circle_outline, _submit, color: const Color(0xFF22C55E)),
        ],
      ),
    );
  }

  Widget _numKey(String digit) {
    return _keyButton(
      child: Text(digit, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w400)),
      onTap: () => _addDigit(digit),
    );
  }

  Widget _iconKey(IconData icon, VoidCallback onTap, {Color? color}) {
    return _keyButton(
      child: Icon(icon, color: color ?? Colors.white54, size: 28),
      onTap: onTap,
    );
  }

  Widget _keyButton({required Widget child, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: Container(
        margin: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withOpacity(0.08),
        ),
        child: Center(child: child),
      ),
    );
  }

  void _addDigit(String digit) {
    if (_pin.length >= 8) return;
    setState(() {
      _pin.add(digit);
      _error = null;
    });
    if (_pin.length >= 4) {
      // Auto-submit at 4-8 digits when user taps submit
    }
  }

  void _backspace() {
    if (_pin.isNotEmpty) {
      setState(() => _pin.removeLast());
    }
  }

  Future<void> _submit() async {
    if (_pin.length < 4) {
      setState(() => _error = 'PIN must be at least 4 digits');
      return;
    }

    final pin = _pin.join();
    final ok = await ref.read(authStateProvider.notifier).authenticateWithPin(pin);

    if (ok && mounted) {
      context.go('/');
    } else {
      setState(() {
        _pin.clear();
        _error = 'Incorrect PIN. Try again.';
      });
      HapticFeedback.vibrate();
    }
  }
}
