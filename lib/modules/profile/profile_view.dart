// lib/modules/profile/profile_view.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vos_mobile/app_providers.dart'; // authRepositoryProvider
import '../../ui/auth/auth_gate.dart'; // AuthGate
import 'package:vos_mobile/state/accounts_payable/accounts_payable_state.dart';
import 'package:vos_mobile/state/accounts_receivable_state/account_receivable_state.dart';
import 'package:vos_mobile/state/data_providers.dart';
import 'package:vos_mobile/state/delivery_report/delivery_report_state.dart';
// NEW: Sales Report (Riverpod) providers.
import 'package:vos_mobile/state/sales_report/sales_report_providers.dart';

class ProfileView extends ConsumerStatefulWidget {
  const ProfileView({super.key});

  @override
  ConsumerState<ProfileView> createState() => _ProfileViewState();
}

class _ProfileViewState extends ConsumerState<ProfileView> {
  bool _isSyncing = false;
  String? _progressLabel;
  double? _progressValue; // 0–1, null = indeterminate

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
    ref.invalidate(salesReportRowsProvider); // paged/filtered v_sales_report rows
    ref.invalidate(salesReportMetricsProvider); // totals (sales, collection, returns, discounts)
    ref.invalidate(salesReportFiltersProvider); // current filter state/presets
    ref.invalidate(salesReportBranchesProvider); // distinct branches
    ref.invalidate(salesReportSalesmenProvider); // distinct salesmen
    ref.invalidate(salesReportPaymentStatusesProvider); // distinct payment_status
    ref.invalidate(salesmanDirectoryProvider); // full salesman table
    ref.invalidate(paymentTermsDirectoryProvider); // payment_terms endpoint
    ref.invalidate(operationDirectoryProvider); // operation endpoint
    ref.invalidate(invoiceTypeDirectoryProvider); // sales_invoice_type endpoint
    ref.invalidate(salesReturnDirectoryProvider); // sales_return endpoint

    // ---------------- Assets & Equipment (OPTIONAL) ---
    // If you have Riverpod providers for your assets/equipment views,
    // invalidate them here so they refresh after sync.
    //
    // Example (adjust to your actual provider names):
    // ref.invalidate(assetsAndEquipmentProvider);
    // ref.invalidate(itemTypeDirectoryProvider);
    // ref.invalidate(itemsDirectoryProvider);
    // ref.invalidate(assetsDepartmentDirectoryProvider);
  }

  Future<void> _syncNow({bool fullReset = false}) async {
    if (_isSyncing) return;

    setState(() {
      _isSyncing = true;
      _progressLabel = 'Preparing sync…';
      _progressValue = 0.0;
    });

    try {
      final repo = ref.read(syncRepoProvider);

      if (fullReset) {
        // Hard wipe before progress sync
        await repo.wipeLocal();
      }

      // New: progress-aware sync
      final errors = await repo.syncAllWithProgress(
        purge: true,
        onProgress: (progress) {
          if (!mounted) return;
          setState(() {
            _progressLabel = '(${progress.step}/${progress.total}) ${progress.label}';
            _progressValue = progress.total == 0 ? null : progress.step / progress.total;
          });
        },
      );

      // Now that data is fresh, rebuild read models
      await _refreshReadModels();

      if (!mounted) return;

      final baseMsg = fullReset ? 'Full reseed completed.' : 'Sync completed.';
      final errorMsg = errors.isEmpty
          ? ''
          : ' (${errors.length} task${errors.length == 1 ? '' : 's'} had issues – see logs.)';

      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$baseMsg$errorMsg')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Sync failed: $e')));
    } finally {
      if (!mounted) return;
      setState(() {
        _isSyncing = false;
        _progressLabel = null;
        _progressValue = null;
      });
    }
  }

  Future<void> _logout() async {
    try {
      final authRepo = ref.read(authRepositoryProvider);
      await authRepo.logout();

      // Navigate to the auth gate, which will show login page since session is cleared
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const AuthGate()));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Logout failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircleAvatar(radius: 36, child: Icon(Icons.person, size: 32)),
          const SizedBox(height: 10),
          Text('Your Profile', style: theme.textTheme.titleLarge),
          const SizedBox(height: 4),
          Text('Manage account settings and preferences', style: theme.textTheme.bodySmall),
          const SizedBox(height: 16),
          Tooltip(
            message: 'Tap: normal sync (purge)\nLong-press: full reseed (wipe local cache)',
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
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _logout,
            icon: const Icon(Icons.logout),
            label: const Text('Logout'),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
          ),

          // Progress bar + label while syncing
          if (_isSyncing) ...[
            const SizedBox(height: 16),
            SizedBox(width: 260, child: LinearProgressIndicator(value: _progressValue)),
            const SizedBox(height: 8),
            Text(
              _progressLabel ?? 'Syncing…',
              style: theme.textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }
}
