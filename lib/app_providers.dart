// lib/app_providers.dart
import "package:flutter_riverpod/flutter_riverpod.dart";

import "core/network/api_client.dart";
import "core/auth/auth_storage.dart";
import "data/repositories/auth_repository.dart";

/// Change this if needed (or make it configurable later)
const String kBaseUrl = "http://goatedcodoer:8056";

final authStorageProvider = Provider<AuthStorage>((ref) {
  return AuthStorage();
});

/// IMPORTANT: single shared ApiClient instance for the whole app
final apiClientProvider = Provider<ApiClient>((ref) {
  final api = ApiClient(baseUrl: kBaseUrl);
  return api;
});

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  final api = ref.read(apiClientProvider);
  final storage = ref.read(authStorageProvider);
  return AuthRepository(api, storage);
});

/// Used by the AuthGate to restore token + user_id on app start
final authInitProvider = FutureProvider<bool>((ref) async {
  final auth = ref.read(authRepositoryProvider);
  return auth.restoreSession();
});
