// lib/state/accounts_payable_state.dart
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:vos_mobile/data/repository/sync_repository.dart';

// ⬇️ Bridge to your app-level SyncRepository provider (no override needed here)
import 'package:vos_mobile/state/data_providers.dart' show syncRepoProvider;

/* -----------------------------------------------------------------------------
  Money normalization helpers
  - Because UI shows 2 decimals, anything < 0.005 will display as 0.00.
  - We treat those tiny values as zero and filter them out from lists.
----------------------------------------------------------------------------- */

const double _kMoneyEpsilon = 0.005;

double _asDouble(dynamic v) {
  if (v == null) return 0.0;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString()) ?? 0.0;
}

double _normalizeMoney(dynamic v) {
  final d = _asDouble(v);
  if (d.abs() < _kMoneyEpsilon) return 0.0;
  return d;
}

bool _isEffectivelyZero(double v) => v.abs() < _kMoneyEpsilon;

/* -----------------------------------------------------------------------------
  Dependency injection
----------------------------------------------------------------------------- */

/// Expose the SyncRepository used by this feature from the app-level provider.
final syncRepositoryProvider = Provider<SyncRepository>(
      (ref) => ref.watch(syncRepoProvider),
);

/* -----------------------------------------------------------------------------
  Models mapped for the AP UI
----------------------------------------------------------------------------- */

class APVendorCard {
  final int payeeId;
  final String vendor; // supplier name
  final double total; // total outstanding balance
  final String? due; // next due date (yyyy-MM-dd) or null
  final String status; // Overdue | Due Soon | Not Due | Settled
  final String remarks; // sample / earliest remark

  const APVendorCard({
    required this.payeeId,
    required this.vendor,
    required this.total,
    required this.due,
    required this.status,
    required this.remarks,
  });

  factory APVendorCard.fromRow(Map<String, Object?> r) {
    final payeeId = (r['payee_id'] as num?)?.toInt() ?? 0;
    final vendor = (r['vendor'] ?? '').toString().trim();

    final rawTotal = _normalizeMoney(r['total']);
    // AP should not show negative "balances" as payables; clamp for UI safety.
    final total = rawTotal < 0 ? 0.0 : rawTotal;

    final rawDue = (r['due'] as String?)?.trim();
    final due = (rawDue == null || rawDue.isEmpty) ? null : rawDue;

    return APVendorCard(
      payeeId: payeeId,
      vendor: vendor,
      total: total,
      due: due,
      status: (r['status'] ?? '').toString(),
      remarks: (r['remarks'] ?? '').toString(),
    );
  }
}

class APBillItem {
  final String no; // doc_no
  final String? due; // ISO date
  final double amount; // balance for that bill
  final String remarks;
  final int? primaryCoaId;
  final String? primaryCoaGl;
  final String? primaryCoaTitle;
  final String? coaList; // "1000 - Cash | 2xxx - Payable | ..."

  const APBillItem({
    required this.no,
    required this.due,
    required this.amount,
    required this.remarks,
    required this.primaryCoaId,
    required this.primaryCoaGl,
    required this.primaryCoaTitle,
    required this.coaList,
  });

  factory APBillItem.fromRow(Map<String, Object?> r) {
    final rawAmount = _normalizeMoney(r['amount']);
    final amount = rawAmount < 0 ? 0.0 : rawAmount;

    final rawDue = (r['due'] as String?)?.trim();
    final due = (rawDue == null || rawDue.isEmpty) ? null : rawDue;

    return APBillItem(
      no: (r['no'] ?? '').toString(),
      due: due,
      amount: amount,
      remarks: (r['remarks'] ?? '').toString(),
      primaryCoaId: (r['primary_coa_id'] as num?)?.toInt(),
      primaryCoaGl: r['primary_coa_gl'] as String?,
      primaryCoaTitle: r['primary_coa_title'] as String?,
      coaList: r['coa_list'] as String?,
    );
  }
}

/* -----------------------------------------------------------------------------
  ViewState
----------------------------------------------------------------------------- */

class AccountsPayableViewState {
  final List<APVendorCard> vendors;
  final bool loading;
  final String? error;

  // filters
  final String search;
  final String? status; // Overdue | Due Soon | Not Due | Settled

  // computed metrics (for the header cards)
  final double totalAP;
  final double overdueAP;
  final int dueSoonCount;

  final DateTime lastUpdated;

  const AccountsPayableViewState({
    required this.vendors,
    required this.loading,
    required this.error,
    required this.search,
    required this.status,
    required this.totalAP,
    required this.overdueAP,
    required this.dueSoonCount,
    required this.lastUpdated,
  });

  AccountsPayableViewState copyWith({
    List<APVendorCard>? vendors,
    bool? loading,
    String? error,
    String? search,
    String? status,
    double? totalAP,
    double? overdueAP,
    int? dueSoonCount,
    DateTime? lastUpdated,
  }) {
    return AccountsPayableViewState(
      vendors: vendors ?? this.vendors,
      loading: loading ?? this.loading,
      error: error,
      search: search ?? this.search,
      status: status ?? this.status,
      totalAP: totalAP ?? this.totalAP,
      overdueAP: overdueAP ?? this.overdueAP,
      dueSoonCount: dueSoonCount ?? this.dueSoonCount,
      lastUpdated: lastUpdated ?? this.lastUpdated,
    );
  }

  static AccountsPayableViewState initial() => AccountsPayableViewState(
    vendors: const [],
    loading: true,
    error: null,
    search: '',
    status: null,
    totalAP: 0,
    overdueAP: 0,
    dueSoonCount: 0,
    lastUpdated: DateTime.now(),
  );
}

/* -----------------------------------------------------------------------------
  Notifier
----------------------------------------------------------------------------- */

final accountsPayableProvider =
NotifierProvider<AccountsPayableNotifier, AccountsPayableViewState>(
  AccountsPayableNotifier.new,
);

class AccountsPayableNotifier extends Notifier<AccountsPayableViewState> {
  SyncRepository get _repo => ref.read(syncRepositoryProvider);

  @override
  AccountsPayableViewState build() {
    // Trigger initial load after provider is mounted.
    Future.microtask(_load);
    return AccountsPayableViewState.initial();
  }

  Future<void> refresh() async {
    await _load();
  }

  void setSearch(String value) {
    state = state.copyWith(search: value);
    _load(); // live filtering
  }

  void setStatus(String? value) {
    state = state.copyWith(status: (value?.isEmpty ?? true) ? null : value);
    _load();
  }

  Future<void> _load() async {
    try {
      state = state.copyWith(loading: true, error: null);

      final rows = await _repo.getApVendorsSummary(
        search: state.search.isEmpty ? null : state.search,
        status: state.status,
        // add fromDue/toDue when you wire up date pickers
      );

      // Map + remove "0.00" vendors (including tiny floating residues)
      final vendors = rows
          .map(APVendorCard.fromRow)
          .where((v) => !_isEffectivelyZero(v.total))
          .toList();

      // Compute header metrics using the filtered list
      final totalAP = vendors.fold<double>(0.0, (sum, v) => sum + v.total);
      final overdueAP = vendors
          .where((v) => v.status == 'Overdue')
          .fold<double>(0.0, (sum, v) => sum + v.total);
      final dueSoonCount = vendors.where((v) => v.status == 'Due Soon').length;

      state = state.copyWith(
        vendors: vendors,
        totalAP: totalAP,
        overdueAP: overdueAP,
        dueSoonCount: dueSoonCount,
        loading: false,
        lastUpdated: DateTime.now(),
      );
    } catch (e, st) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('AP load failed: $e\n$st');
      }
      state = state.copyWith(
        loading: false,
        error: e.toString(),
        lastUpdated: DateTime.now(),
      );
    }
  }

  /// For the vendor detail bottom sheet in your APView.
  Future<List<APBillItem>> getVendorBillsForUI(int payeeId) async {
    final rows = await _repo.getVendorBillsForUI(payeeId);

    // Map + remove "0.00" bills (including tiny floating residues)
    final bills = rows
        .map(APBillItem.fromRow)
        .where((b) => !_isEffectivelyZero(b.amount))
        .toList();

    return bills;
  }
}

/* -----------------------------------------------------------------------------
  (Optional) Formatting helpers for the UI layer
----------------------------------------------------------------------------- */

final currencyFmtPHProvider = Provider<NumberFormat>(
      (_) => NumberFormat('#,##0.00', 'en_PH'),
);
