import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import '../../../../data/local/database.dart';

class NoteLockScreen extends StatefulWidget {
  final Note note;
  final VoidCallback onUnlocked;

  const NoteLockScreen({super.key, required this.note, required this.onUnlocked});

  @override
  State<NoteLockScreen> createState() => _NoteLockScreenState();
}

class _NoteLockScreenState extends State<NoteLockScreen> {
  final _pin = <String>[];
  String? _error;
  final _localAuth = LocalAuthentication();

  @override
  void initState() {
    super.initState();
    _tryBiometric();
  }

  Future<void> _tryBiometric() async {
    final canBio = await _localAuth.canCheckBiometrics;
    if (!canBio) return;
    final ok = await _localAuth.authenticate(
      localizedReason: 'Unlock note: ${widget.note.title}',
      options: const AuthenticationOptions(stickyAuth: true),
    );
    if (ok && mounted) widget.onUnlocked();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.lock_rounded, color: Color(0xFFF59E0B), size: 56),
            const SizedBox(height: 16),
            Text(
              widget.note.title.isEmpty ? 'Locked Note' : widget.note.title,
              style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            const Text('Enter PIN to unlock', style: TextStyle(color: Colors.white54, fontSize: 14)),
            const SizedBox(height: 48),

            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(6, (i) {
                final filled = i < _pin.length;
                return Container(
                  width: 16, height: 16,
                  margin: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: filled ? const Color(0xFFF59E0B) : Colors.white24,
                  ),
                );
              }),
            ),

            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(_error!, style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
            ],

            const SizedBox(height: 40),
            _buildNumpad(),
            const SizedBox(height: 24),

            TextButton.icon(
              onPressed: _tryBiometric,
              icon: const Icon(Icons.fingerprint, color: Colors.white70),
              label: const Text('Use biometric', style: TextStyle(color: Colors.white70)),
            ),

            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Go back', style: TextStyle(color: Colors.white38)),
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

  Widget _numKey(String digit) => _keyButton(
    child: Text(digit, style: const TextStyle(color: Colors.white, fontSize: 22)),
    onTap: () => _addDigit(digit),
  );

  Widget _iconKey(IconData icon, VoidCallback onTap, {Color? color}) => _keyButton(
    child: Icon(icon, color: color ?? Colors.white54, size: 26),
    onTap: onTap,
  );

  Widget _keyButton({required Widget child, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: () { HapticFeedback.selectionClick(); onTap(); },
      child: Container(
        margin: const EdgeInsets.all(6),
        decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withOpacity(0.08)),
        child: Center(child: child),
      ),
    );
  }

  void _addDigit(String digit) {
    if (_pin.length >= 8) return;
    setState(() { _pin.add(digit); _error = null; });
  }

  void _backspace() {
    if (_pin.isNotEmpty) setState(() => _pin.removeLast());
  }

  void _submit() {
    if (_pin.length < 4) {
      setState(() => _error = 'PIN must be at least 4 digits');
      return;
    }
    final inputHash = _hashPin(_pin.join());
    if (inputHash == widget.note.lockPinHash) {
      widget.onUnlocked();
    } else {
      setState(() { _pin.clear(); _error = 'Incorrect PIN'; });
      HapticFeedback.vibrate();
    }
  }

  String _hashPin(String pin) {
    final bytes = utf8.encode('$pin:prinotes-salt');
    return sha256.convert(bytes).toString();
  }
}
