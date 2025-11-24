import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/network/api_client.dart';
import '../data/local/app_db.dart';
import '../data/repository/sync_repository.dart';

final apiProvider = Provider<ApiClient>((_) => ApiClient());
final databaseProvider = FutureProvider((_) => AppDb.get());
final syncRepoProvider =
Provider<SyncRepository>((ref) => SyncRepository(ref.read(apiProvider)));

/// One-time initializer: wipe on first run OR when server base has changed.
final appSyncInitProvider = FutureProvider<void>((ref) async {
  // Ensure DB exists
  await ref.read(databaseProvider.future);

  final prefs = await SharedPreferences.getInstance();
  final repo = ref.read(syncRepoProvider);
  final api = ref.read(apiProvider);

  // Use the real base URL (we added baseUrl in ApiClient earlier)
  final serverSig = api.baseUrl;

  final alreadyInit = prefs.getBool('cache.initialized') ?? false;
  final lastSig = prefs.getString('cache.serverSig');
  final mustWipe = !alreadyInit || lastSig != serverSig;

  if (mustWipe) {
    // Hard reset then strict mirror
    await repo.wipeLocal();
    await repo.syncAll(purge: true);
    await prefs.setBool('cache.initialized', true);
    await prefs.setString('cache.serverSig', serverSig);
  } else {
    // Keep strict mirroring so old rows never come back
    await repo.syncAll(purge: true);
  }
});

/// Example data source that depends on the initializer above
final deliveryReportProvider =
FutureProvider.autoDispose<List<Map<String, Object?>>>((ref) async {
  await ref.watch(appSyncInitProvider.future); // wait for wipe/sync
  final repo = ref.read(syncRepoProvider);
  return repo.getDeliveryReport(limit: 100);
});
