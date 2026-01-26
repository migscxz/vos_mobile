import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:sqflite/sqflite.dart";

import "package:vos_mobile/data/local/app_db.dart";
import "inventory_report_state.dart";

/// In your project, AppDb.get() returns Future<Database>.
final databaseProvider = FutureProvider<Database>((ref) async {
  return AppDb.get();
});

final inventoryReportProvider =
StateNotifierProvider<InventoryReportController, InventoryReportState>((ref) {
  return InventoryReportController(ref);
});

class InventoryReportController extends StateNotifier<InventoryReportState> {
  final Ref ref;

  InventoryReportController(this.ref) : super(InventoryReportState.initial());

  Future<void> load() async {
    state = state.copyWith(loading: true, clearError: true);

    try {
      final Database db = await ref.read(databaseProvider.future);

      final rows = await db.rawQuery("""
        SELECT
          id,
          product_id,
          product_code,
          product_name,
          unit_name,
          unit_count,
          branch_id,
          branch_name,
          last_cutoff,
          last_count,
          movement_after,
          running_inventory,
          supplier_shortcut,
          supplier_id
        FROM v_running_inventory
        ORDER BY branch_name ASC, product_name ASC
      """);

      final parsed = rows.map((m) => RunningInventoryRow.fromDb(m)).toList();

      state = state.copyWith(
        loading: false,
        rows: parsed,
      );
    } catch (e) {
      state = state.copyWith(
        loading: false,
        error: e.toString(),
      );
    }
  }

  Future<void> refresh() => load();
}
