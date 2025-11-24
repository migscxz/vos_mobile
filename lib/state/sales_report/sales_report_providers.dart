// lib/state/sales_report/sales_report_providers.dart
import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';

import 'package:vos_mobile/state/sales_report/sales_report_starte.dart';
import '../../data/local/app_db.dart';

/* ------------------------- Core ChangeNotifier ------------------------- */

final salesReportStateProvider = ChangeNotifierProvider<SalesReportState>((ref) {
  final state = SalesReportState();
  // Kick off async init without blocking provider creation
  scheduleMicrotask(() async {
    try {
      await state.init();
    } catch (_) {
      // state.error will be populated by the notifier if needed
    }
  });
  ref.onDispose(state.dispose);
  return state;
});

/* ------------------------------ Read Models ---------------------------- */

class SalesReportMetrics {
  final double totalSales;
  final double totalCollection;
  final double totalReturns;
  final double totalDiscounts;
  const SalesReportMetrics({
    required this.totalSales,
    required this.totalCollection,
    required this.totalReturns,
    required this.totalDiscounts,
  });
}

class SalesReportFiltersVM {
  final String period;
  final String branch;
  final String salesman;
  final String paymentStatus;
  final List<String> branchOptions;
  final List<String> salesmanOptions;
  final List<String> paymentStatusOptions;
  const SalesReportFiltersVM({
    required this.period,
    required this.branch,
    required this.salesman,
    required this.paymentStatus,
    required this.branchOptions,
    required this.salesmanOptions,
    required this.paymentStatusOptions,
  });
}

/* ----------------------------- Selectors ------------------------------- */

final salesReportRowsProvider = Provider<List<SalesReportRow>>(
      (ref) => ref.watch(salesReportStateProvider).rows,
);

final salesReportMetricsProvider = Provider<SalesReportMetrics>((ref) {
  final s = ref.watch(salesReportStateProvider);
  return SalesReportMetrics(
    totalSales: s.totalSales,
    totalCollection: s.totalCollection,
    totalReturns: s.totalReturns,
    totalDiscounts: s.totalDiscounts,
  );
});

final salesReportFiltersProvider = Provider<SalesReportFiltersVM>((ref) {
  final s = ref.watch(salesReportStateProvider);
  return SalesReportFiltersVM(
    period: s.selectedPeriod,
    branch: s.selectedBranch,
    salesman: s.selectedSalesman,
    paymentStatus: s.selectedPaymentStatus,
    branchOptions: s.branchOptions,
    salesmanOptions: s.salesmanOptions,
    paymentStatusOptions: s.paymentStatusOptions,
  );
});

// Optional but useful for UI
final salesReportLoadingProvider =
Provider<bool>((ref) => ref.watch(salesReportStateProvider).loading);

final salesReportErrorProvider =
Provider<String?>((ref) => ref.watch(salesReportStateProvider).error);

final salesReportHasMoreProvider =
Provider<bool>((ref) => ref.watch(salesReportStateProvider).hasMore);

/* ---------------------- Distinct option convenience -------------------- */

final salesReportBranchesProvider = Provider<List<String>>(
      (ref) => ref.watch(salesReportStateProvider).branchOptions,
);

final salesReportSalesmenProvider = Provider<List<String>>(
      (ref) => ref.watch(salesReportStateProvider).salesmanOptions,
);

final salesReportPaymentStatusesProvider = Provider<List<String>>(
      (ref) => ref.watch(salesReportStateProvider).paymentStatusOptions,
);

/* -------------------------- Directory tables --------------------------- */

Future<Database> _db() => AppDb.get();

bool _looksLikeNoSuchTable(DatabaseException e) {
  // Generic detection
  final msg = e.toString().toLowerCase();
  if (msg.contains('no such table')) return true;

  // Some sqflite versions expose an extension method; call defensively
  try {
    // ignore: invalid_use_of_visible_for_testing_member, invalid_use_of_protected_member
    return e.isNoSuchTableError();
  } catch (_) {
    return false;
  }
}

Future<List<Map<String, Object?>>> _safeQuery(
    String sql, {
      List<Object?> params = const [],
    }) async {
  try {
    final db = await _db();
    return await db.rawQuery(sql, params);
  } on DatabaseException catch (e) {
    if (_looksLikeNoSuchTable(e)) {
      // fail soft when table/view not created yet
      return <Map<String, Object?>>[];
    }
    rethrow;
  } catch (_) {
    return <Map<String, Object?>>[];
  }
}

final salesmanDirectoryProvider =
FutureProvider<List<Map<String, Object?>>>((ref) async {
  return _safeQuery('''
    SELECT
      id,
      salesman_code,
      salesman_name,
      truck_plate,
      division_id,
      branch_code,
      operation,
      price_type,
      isActive,
      isInventory,
      canCollect,
      modified_date
    FROM salesman
    ORDER BY salesman_name COLLATE NOCASE
  ''');
});

final paymentTermsDirectoryProvider =
FutureProvider<List<Map<String, Object?>>>((ref) async {
  return _safeQuery('''
    SELECT id, payment_name, payment_days
    FROM payment_terms
    ORDER BY payment_days IS NULL, payment_days, payment_name
  ''');
});

final operationDirectoryProvider =
FutureProvider<List<Map<String, Object?>>>((ref) async {
  return _safeQuery('''
    SELECT id, operation_code, operation_name, date_modified, definition
    FROM operation
    ORDER BY operation_name COLLATE NOCASE
  ''');
});

final invoiceTypeDirectoryProvider =
FutureProvider<List<Map<String, Object?>>>((ref) async {
  return _safeQuery('''
    SELECT id, type, shortcut, max_length
    FROM sales_invoice_type
    ORDER BY type COLLATE NOCASE
  ''');
});

final salesReturnDirectoryProvider =
FutureProvider<List<Map<String, Object?>>>((ref) async {
  return _safeQuery('''
    SELECT
      return_id,
      return_number,
      customer_code,
      salesman_id,
      branch_id,
      return_date,
      total_amount,
      discount_amount,
      gross_amount,
      remarks,
      order_id,
      invoice_no,
      updated_at,
      received_at,
      isThirdParty,
      price_type,
      status,
      isPosted,
      isApplied,
      isReceived
    FROM sales_return
    ORDER BY date(substr(COALESCE(return_date,''),1,10)) DESC, return_id DESC
  ''');
});
