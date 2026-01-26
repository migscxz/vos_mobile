import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";

import "../../app.dart";
import "../shell/shell.dart";
import "login_page.dart";

class AuthGate extends ConsumerStatefulWidget {
  const AuthGate({super.key});

  @override
  ConsumerState<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends ConsumerState<AuthGate> {
  bool? _hasSession;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    try {
      final auth = ref.read(authRepositoryProvider);
      final ok = await auth.restoreSession();
      if (!mounted) return;
      setState(() => _hasSession = ok);
    } catch (_) {
      if (!mounted) return;
      setState(() => _hasSession = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final v = _hasSession;

    if (v == null) {
      return const Scaffold(
        body: Center(
          child: SizedBox(
            width: 26,
            height: 26,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    return v ? const Shell() : const LoginPage();
  }
}
