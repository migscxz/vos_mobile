// lib/modules/profile/profile_view.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// Existing repos + states
import 'package:vos_mobile/state/data_providers.dart';
import 'package:vos_mobile/state/accounts_receivable_state/account_receivable_state.dart';
import 'package:vos_mobile/state/accounts_payable/accounts_payable_state.dart';
import 'package:vos_mobile/state/delivery_report/delivery_report_state.dart';

// NEW: Sales Report (Riverpod) providers.
// If your app doesn't have these exact files yet, either create them or remove these imports + invalidations below.
import 'package:vos_mobile/state/sales_report/sales_report_providers.dart';

class ProfileView extends ConsumerStatefulWidget {
  const ProfileView({super.key});

  @override
  ConsumerState<ProfileView> createState() => _ProfileViewState();
}

class _ProfileViewState extends ConsumerState<ProfileView> {
  bool _isSyncing = false;

  /// ONLY invalidates providers; never runs sync here.
  Future<void> _refreshReadModels() async {
    // ---------------- Delivery Report ----------------
    ref.invalidate(deliveryReportProvider);
    ref.invalidate(deliveryGroupedProvider);
    ref.invalidate(deliveryByPlanProvider);
    ref.invalidate(overallSupplierSummaryProvider);
    ref.invalidate(driversProvider);
    ref.invalidate(deliveryGrandTotalProvider);

    // ---------------- Accounts Payable ----------------
    ref.invalidate(accountsPayableProvider);

    // ---------------- Accounts Receivable -------------
    await ref.read(arNotifierProvider.notifier).refresh();

    // ---------------- Sales Report (NEW) --------------
    // These should cover: list rows, metrics, and filter option sources.
    // Remove any that you don't use yet.
    ref.invalidate(salesReportRowsProvider);          // paged/filtered v_sales_report rows
    ref.invalidate(salesReportMetricsProvider);       // totals (sales, collection, returns, discounts)
    ref.invalidate(salesReportFiltersProvider);       // current filter state/presets
    ref.invalidate(salesReportBranchesProvider);      // distinct branches (from v_sales_report)
    ref.invalidate(salesReportSalesmenProvider);      // distinct salesmen (from v_sales_report or salesman table)
    ref.invalidate(salesReportPaymentStatusesProvider); // distinct payment_status
    ref.invalidate(salesmanDirectoryProvider);        // full salesman table (new endpoint)
    ref.invalidate(paymentTermsDirectoryProvider);    // payment_terms endpoint
    ref.invalidate(operationDirectoryProvider);       // operation endpoint
    ref.invalidate(invoiceTypeDirectoryProvider);     // sales_invoice_type endpoint
    ref.invalidate(salesReturnDirectoryProvider);     // sales_return endpoint
  }

  Future<void> _syncNow({bool fullReset = false}) async {
    if (_isSyncing) return;
    setState(() => _isSyncing = true);
    try {
      final repo = ref.read(syncRepoProvider);

      if (fullReset) {
        // Hard wipe + reseed
        await repo.syncAllFullReset();
      } else {
        // Strict mirror to avoid mixing old data
        await repo.syncAll(purge: true);
      }

      // Now that data is fresh, rebuild read models
      await _refreshReadModels();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(fullReset ? 'Full reseed completed' : 'Sync completed')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Sync failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircleAvatar(radius: 36, child: Icon(Icons.person, size: 32)),
          const SizedBox(height: 10),
          Text('Your Profile', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(
            'Manage account settings and preferences',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          Tooltip(
            message: 'Tap: normal sync (purge) • Long-press: full reseed (wipe local cache)',
            child: GestureDetector(
              onLongPress: _isSyncing ? null : () => _syncNow(fullReset: true),
              child: FilledButton.icon(
                onPressed: _isSyncing ? null : () => _syncNow(),
                icon: _isSyncing
                    ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
                    : const Icon(Icons.sync),
                label: Text(_isSyncing ? 'Syncing…' : 'Sync Now'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
