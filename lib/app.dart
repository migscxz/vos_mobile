// lib/app.dart
import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";

import "core/network/api_client.dart";
import "core/auth/auth_storage.dart";
import "data/repositories/auth_repository.dart";
import "ui/auth/login_page.dart";
import "ui/shell/shell.dart";
import "core/theme/app_theme.dart";

// -------------------------
// Providers
// -------------------------

final apiClientProvider = Provider<ApiClient>((ref) {
  // ApiClient is tokenless at creation; AuthRepository.restoreSession/login injects token later.
  return ApiClient(baseUrl: "http://goatedcodoer:8056");
});

final authStorageProvider = Provider<AuthStorage>((ref) {
  return AuthStorage();
});

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  final api = ref.read(apiClientProvider);
  final storage = ref.read(authStorageProvider);
  return AuthRepository(api, storage);
});

// -------------------------
// App
// -------------------------

class VOSApp extends StatelessWidget {
  const VOSApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: "VOS Mobile",
      themeMode: ThemeMode.system,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      home: const _AuthGate(),
    );
  }
}

// app.dart (AuthGate part only)
class _AuthGate extends ConsumerWidget {
  const _AuthGate();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FutureBuilder<bool>(
      future: ref.read(authRepositoryProvider).restoreSession(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final ok = snap.data ?? false;
        return ok ? const Shell() : const LoginPage();
      },
    );
  }
}
