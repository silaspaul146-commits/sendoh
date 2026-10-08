import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import 'session_store.dart';

bool deviceAuthenticationActive = false;
Future<bool> authenticateDevice(String reason) async {
  if (deviceAuthenticationActive) return false;
  deviceAuthenticationActive = true;
  try {
    return await LocalAuthentication().authenticate(localizedReason: reason,
        options: const AuthenticationOptions(stickyAuth: true));
  } finally {
    deviceAuthenticationActive = false;
  }
}

/// Device authentication unlocks an existing session; it never creates an account.
class DeviceLock extends StatefulWidget {
  const DeviceLock({super.key, required this.child, required this.onSignIn});
  final Widget child;
  final VoidCallback onSignIn;
  @override
  State<DeviceLock> createState() => _DeviceLockState();
}

class _DeviceLockState extends State<DeviceLock> with WidgetsBindingObserver {
  bool locked = false, checking = false;
  String? error;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    if (state == AppLifecycleState.paused && !checking && !deviceAuthenticationActive) {
      final enabled = await SessionStore.locked();
      if (mounted && enabled) setState(() => locked = true);
    }
  }
  Future<void> unlock() async {
    setState(() { checking = true; error = null; });
    try {
      final ok = await authenticateDevice('Unlock your Sendoh account');
      if (mounted && ok) setState(() => locked = false);
    } catch (_) {
      if (mounted) setState(() => error = 'Could not unlock. Use your device PIN or sign in again.');
    } finally {
      if (mounted) setState(() => checking = false);
    }
  }
  @override
  Widget build(BuildContext context) => Stack(fit: StackFit.expand, children: [
      Offstage(offstage: locked, child: widget.child),
      if (locked) Positioned.fill(child: Scaffold(body: SafeArea(child: Center(child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.lock_outline, size: 48),
            const SizedBox(height: 16),
            const Text('Welcome back to Sendoh'),
            if (error != null) Text(error!),
            const SizedBox(height: 24),
            FilledButton(onPressed: checking ? null : unlock,
                child: const Text('Unlock')),
            TextButton(onPressed: checking ? null : () async {
              await SessionStore.clear();
              if (mounted) {
                setState(() => locked = false);
                widget.onSignIn();
              }
            }, child: const Text('Sign in with phone instead')),
          ])))))),
    ]);
}
