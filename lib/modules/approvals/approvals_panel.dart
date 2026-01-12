// lib/modules/approvals/approvals_panel.dart
import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:sqflite/sqflite.dart";

import "../../state/app_state.dart";
import "../../data/models.dart";
import "../../data/local/app_db.dart";

// Stock Transfer screen
import "../approvals/stock_transfer/stock_transfer_view.dart";
import "../approvals/predispatch/predispatch_view.dart";
import "../approvals/sales_order/sales_order_view.dart";
import "../approvals/logistics/logistics_approval_view.dart";




/// Counts how many Stock Transfer *orders* (grouped by order_no) are still REQUESTED
/// and not yet acted-on/rejected by Boss (local SQLite).
///
/// IMPORTANT:
/// - If user has NOT synced yet (tables missing), returns 0.
/// - Uses the table that actually has rows: prefer stock_transfer_items, else stock_transfer_local.
/// - Badge auto-refresh is handled in ApprovalsPanel on return from StockTransferView.
final stockTransferRequestedOrdersCountProvider =
    FutureProvider.autoDispose<int>((ref) async {
  final db = await AppDb.get();

  Future<bool> tableExists(String name) async {
    final r = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name=? LIMIT 1",
      [name],
    );
    return r.isNotEmpty;
  }

  Future<void> ensureBossCols(String table) async {
    // Only safe to do PRAGMA if table exists
    final exists = await tableExists(table);
    if (!exists) return;

    final info = await db.rawQuery("PRAGMA table_info($table)");
    final cols = info.map((e) => (e["name"]?.toString() ?? "")).toSet();

    Future<void> addCol(String name, String type, {String? defaultSql}) async {
      if (cols.contains(name)) return;
      final def = (defaultSql != null && defaultSql.trim().isNotEmpty)
          ? " DEFAULT $defaultSql"
          : "";
      await db.execute("ALTER TABLE $table ADD COLUMN $name $type$def");
    }

    await addCol("boss_status_override", "TEXT");
    await addCol("boss_action_at", "TEXT");
    await addCol("boss_action_by", "TEXT");
    await addCol("boss_rejected", "INTEGER", defaultSql: "0");
    await addCol("boss_reject_reason", "TEXT");
  }

  Future<int> countRows(String table) async {
    final r = await db.rawQuery("SELECT COUNT(*) AS c FROM $table");
    return (r.first["c"] as int?) ?? 0;
  }

  Future<int> countRequestedOrders(String table) async {
    await ensureBossCols(table);

    const normRequested = "requested";

    final res = await db.rawQuery('''
      SELECT
        COUNT(DISTINCT
          CASE
            WHEN TRIM(COALESCE(order_no,'')) = '' THEN ('ST-' || id)
            ELSE TRIM(order_no)
          END
        ) AS c
      FROM $table
      WHERE
        LOWER(REPLACE(REPLACE(
          COALESCE(NULLIF(TRIM(boss_status_override), ''), status),
          '_',''
        ), ' ', '')) = ?
        AND COALESCE(boss_rejected, 0) = 0
        AND (boss_action_at IS NULL OR TRIM(boss_action_at) = '')
        AND (boss_action_by IS NULL OR TRIM(boss_action_by) = '')
    ''', [normRequested]);

    return (res.first["c"] as int?) ?? 0;
  }

  try {
    final hasItems = await tableExists("stock_transfer_items");
    final hasLocal = await tableExists("stock_transfer_local");

    // Not synced yet
    if (!hasItems && !hasLocal) return 0;

    // Prefer items if it has data, else local
    String baseTable;
    if (hasItems) {
      final c = await countRows("stock_transfer_items");
      baseTable = (c > 0)
          ? "stock_transfer_items"
          : (hasLocal ? "stock_transfer_local" : "stock_transfer_items");
    } else {
      baseTable = "stock_transfer_local";
    }

    return await countRequestedOrders(baseTable);
  } on DatabaseException catch (e) {
    final msg = e.toString().toLowerCase();
    // If device DB isn't initialized/synced yet, just show 0 instead of crashing
    if (msg.contains("no such table")) return 0;
    rethrow;
  }
});

class ApprovalsPanel extends ConsumerWidget {
  const ApprovalsPanel({super.key});

  IconData _iconFor(ApprovalQueue q) {
    switch (q.id) {
      case "so":
        return Icons.assignment_turned_in_outlined;
      case "predispatch":
        return Icons.outbox_outlined;
      case "logi":
        return Icons.local_shipping_outlined;
      case "transfer":
        return Icons.swap_horiz_rounded;
      case "audit":
        return Icons.verified_user_outlined;
      default:
        return Icons.check_circle_outline;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final queues = ref.watch(approvalQueuesProvider);
    final stRequestedOrdersAsync =
        ref.watch(stockTransferRequestedOrdersCountProvider);

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        for (final q in queues)
          Card(
            margin: const EdgeInsets.symmetric(vertical: 6),
            child: ListTile(
              leading: Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(_iconFor(q)),
                  Builder(
                    builder: (_) {
                      // Stock Transfer badge = exact requested-orders count (grouped by order_no)
                        


                      final badgeCount = (q.id == "transfer")
                          ? stRequestedOrdersAsync.maybeWhen(
                              data: (v) => v,
                              orElse: () => q.pendingCount, // fallback while loading/error
                            )
                          : q.pendingCount;

                      if (badgeCount <= 0) return const SizedBox.shrink();

                      return Positioned(
                        right: -2,
                        top: -2,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 1.5,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.redAccent,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            "$badgeCount",
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
              title: Text(
                q.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),

              // Optional: show a small subtitle for Stock Transfer only
              // (This is safe because it returns Widgets, not Strings.)
              // subtitle: (q.id == "transfer")
              //     ? stRequestedOrdersAsync.when(
              //         data: (v) => Text(
              //           v > 0
              //               ? "Requested orders awaiting approval: $v"
              //               : "No requested orders awaiting approval.",
              //         ),
              //         loading: () => const Text("Checking requested orders..."),
              //         error: (_, __) =>
              //             const Text("Unable to check requested orders."),
              //       )
              //     : null,

              trailing: const Icon(Icons.chevron_right),
           onTap: () {
  ref.read(selectedApprovalQueueProvider.notifier).state = q;

  // Close drawer/sheet if applicable
  if (Navigator.of(context).canPop()) {
    Navigator.of(context).pop();
  }

  // ✅ Stock Transfer
  if (q.id == "transfer") {
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) => const StockTransferView(),
          ),
        )
        .then((_) {
      // Refresh badge when user returns (after sync / approve / reject)
      ref.invalidate(stockTransferRequestedOrdersCountProvider);
    });
    return;
  }

  // ✅ Pre-Dispatch / Dispatch (static UI for now)
  if (q.id == "predispatch") {
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) => const PreDispatchView(),
          ),
        )
        .then((_) {
      // Optional: when you create a provider for predispatch counts, invalidate here.
      // ref.invalidate(preDispatchPendingCountProvider);
    });
    return;
  }
  if (q.id == "so") {
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => const SalesOrderApprovalView(),
    ),
  );
  return;
}

if (q.id == "logi") {
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => const LogisticsApprovalView(),
    ),
  );
  return;
}

  // Fallback: existing behavior
  ref.read(moduleProvider.notifier).state = Module.approvals;
},

            
            ),
          ),
      ],
    );
  }
}
