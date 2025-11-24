import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../data/repository/sync_repository.dart';
import '../data_providers.dart';

// --- FILTER PROVIDERS ---
final drFromProvider = StateProvider<DateTime?>((_) => null);
final drToProvider = StateProvider<DateTime?>((_) => null);
final drDriverProvider = StateProvider<String?>((_) => null);
final drSearchProvider = StateProvider<String>((_) => '');

// --- DATA ROW CLASS ---
class DeliveryRow {
  final String driver;
  final int seq;
  final String city;
  final String supplier;
  final String docNo;
  final String ccn;
  final String invoiceNo;
  final DateTime? invoiceDate;
  final String customer;
  final double total;
  final String vehicle;
  final String postStatus; // invoice status only
  final String remarks;
  final DateTime? timeOfDispatch;
  final DateTime? timeOfArrival;

  // Plan-level fields surfaced on every row
  final String helperName;
  final double totalBudget;

  DeliveryRow({
    required this.driver,
    required this.seq,
    required this.city,
    required this.supplier,
    required this.docNo,
    required this.ccn,
    required this.invoiceNo,
    required this.invoiceDate,
    required this.customer,
    required this.total,
    required this.vehicle,
    required this.postStatus,
    required this.remarks,
    required this.timeOfDispatch,
    required this.timeOfArrival,
    required this.helperName,
    required this.totalBudget,
  });

  factory DeliveryRow.fromMap(Map<String, Object?> m) {
    DateTime? parseDT(String? s) {
      if (s == null || s.isEmpty) return null;
      try {
        return DateTime.tryParse(s);
      } catch (_) {
        return null;
      }
    }

    double dbl(Object? v) {
      if (v is num) return v.toDouble();
      if (v is String) return double.tryParse(v) ?? 0;
      return 0;
    }

    final inv = (m['post_dispatch_invoices_status'] as String?)?.trim() ?? '';

    return DeliveryRow(
      driver: (m['driver_name'] as String? ?? '').trim(),
      seq: (m['Seq'] as int?) ?? 0,
      city: (m['city_town_name'] as String? ?? '').trim(),
      supplier: (m['supplier_code'] as String? ?? '').trim(),
      docNo: (m['doc_no'] as String? ?? '').trim(),
      ccn: (m['ccn'] as String? ?? '').trim(),
      invoiceNo: (m['invoice_no'] as String? ?? '').trim(),
      invoiceDate: parseDT(m['invoice_date'] as String?),
      customer: (m['customer_name'] as String? ?? '').trim(),
      total: dbl(m['total']),
      vehicle: (m['vehicle'] as String? ?? '').trim(),
      postStatus: inv,
      remarks: (m['remarks'] as String? ?? '').trim(),
      timeOfDispatch: parseDT(m['time_of_dispatch'] as String?),
      timeOfArrival: parseDT(m['time_of_arrival'] as String?),
      helperName: (m['helper_name'] as String? ?? '').trim(),
      totalBudget: dbl(m['total_budget']),
    );
  }
}

// --- SUBTOTALS BY CUSTOMER ---
class CustomerGroup {
  final List<DeliveryRow> rows;
  final double subtotal;
  CustomerGroup(this.rows) : subtotal = rows.fold(0.0, (prev, row) => prev + row.total);
}

// --- DRIVER GROUPING ---
class DriverGroup {
  final String driver;
  final List<DeliveryRow> rowsRaw;
  final double subtotal;
  final int trips; // unique customers
  final Map<String, double> supplierTotals;
  final Map<String, CustomerGroup> customerGroups;

  DriverGroup(this.driver, List<DeliveryRow> rows)
      : rowsRaw = rows,
        subtotal = rows.fold(0.0, (s, r) => s + r.total),
        trips = rows.map((r) => r.customer.isEmpty ? '— No Customer —' : r.customer).toSet().length,
        supplierTotals = _calculateSupplierTotals(rows),
        customerGroups = _groupRowsByCustomer(rows);

  static Map<String, double> _calculateSupplierTotals(List<DeliveryRow> rows) {
    final map = <String, double>{};
    for (final r in rows) {
      map.update(r.supplier.isEmpty ? '—' : r.supplier, (v) => v + r.total, ifAbsent: () => r.total);
    }
    return map;
  }

  static Map<String, CustomerGroup> _groupRowsByCustomer(List<DeliveryRow> rows) {
    final map = <String, List<DeliveryRow>>{};
    for (final r in rows) {
      final key = r.customer.isEmpty ? '— No Customer —' : r.customer;
      (map[key] ??= []).add(r);
    }
    return map.map((key, value) => MapEntry(key, CustomerGroup(value)));
  }

  /// Sum totalBudget across unique plans (by docNo or invoiceNo)
  double get sumBudgetByPlans {
    final seen = <String>{};
    double total = 0;
    for (final r in rowsRaw) {
      final planKey = (r.docNo.isNotEmpty ? r.docNo : r.invoiceNo);
      if (planKey.isEmpty) continue;
      if (seen.add(planKey)) total += r.totalBudget;
    }
    return total;
  }
}

final deliveryGroupedProvider = FutureProvider.autoDispose<List<DriverGroup>>((ref) async {
  final repo = ref.read(syncRepoProvider);
  final from = ref.watch(drFromProvider);
  final to = ref.watch(drToProvider);
  final driver = ref.watch(drDriverProvider);
  final search = ref.watch(drSearchProvider);
  final raw = await repo.getDeliveryReportFiltered(
    from: from,
    to: to,
    driverName: driver,
    search: search.isEmpty ? null : search,
  );
  final rows = raw.map((m) => DeliveryRow.fromMap(m)).toList();

  final map = <String, List<DeliveryRow>>{};
  for (final r in rows) {
    map.putIfAbsent(r.driver.isEmpty ? '— No Driver —' : r.driver, () => []).add(r);
  }
  final groups = map.entries.map((e) => DriverGroup(e.key, e.value)).toList()
    ..sort((a, b) => a.driver.compareTo(b.driver));
  return groups;
});

// --- PLAN GROUPING ---
class PlanGroup {
  final String docNo;
  final String driver;
  final String vehicle;
  final String ccn;
  final int trips; // unique customers
  final double subtotal;
  final Map<String, double> supplierTotals;
  final DateTime? timeOfDispatch;
  final DateTime? timeOfArrival;
  final Map<String, CustomerGroup> customerGroups;

  final String helperName;
  final double totalBudget;

  // NEW
  final int fulfilledCount;
  final int notFulfilledCount;
  final Duration? turnover; // arrival - dispatch

  PlanGroup({
    required this.docNo,
    required this.driver,
    required this.vehicle,
    required this.ccn,
    required this.trips,
    required this.subtotal,
    required this.supplierTotals,
    required this.timeOfDispatch,
    required this.timeOfArrival,
    required this.customerGroups,
    required this.helperName,
    required this.totalBudget,
    required this.fulfilledCount,
    required this.notFulfilledCount,
    required this.turnover,
  });

  static bool _isFulfilled(String s) {
    final t = s.toLowerCase();
    // Adjust these keywords to your real status values if needed.
    return t.contains('fulfill') ||
        t.contains('deliver') ||
        t.contains('complete') ||
        t.contains('cleared') ||
        t == 'done';
  }

  factory PlanGroup.build(String docNo, List<DeliveryRow> rows) {
    rows.sort((a, b) {
      final s = a.seq.compareTo(b.seq);
      if (s != 0) return s;
      return (a.invoiceDate ?? DateTime(1970)).compareTo(b.invoiceDate ?? DateTime(1970));
    });

    final supplierMap = <String, double>{};
    int fulfilled = 0, notFulfilled = 0;

    for (final r in rows) {
      supplierMap.update(r.supplier.isEmpty ? '—' : r.supplier, (v) => v + r.total, ifAbsent: () => r.total);
      if (_isFulfilled(r.postStatus)) {
        fulfilled++;
      } else {
        notFulfilled++;
      }
    }

    final customerRowMap = <String, List<DeliveryRow>>{};
    for (final r in rows) {
      final key = r.customer.isEmpty ? '— No Customer —' : r.customer;
      (customerRowMap[key] ??= []).add(r);
    }
    final customerGroups = customerRowMap.map((k, v) => MapEntry(k, CustomerGroup(v)));
    final uniqueTrips = customerRowMap.keys.length;

    final first = rows.isNotEmpty ? rows.first : null;

    Duration? turnover;
    if (first?.timeOfDispatch != null && first?.timeOfArrival != null) {
      turnover = first!.timeOfArrival!.difference(first.timeOfDispatch!);
    }

    return PlanGroup(
      docNo: docNo,
      driver: first?.driver ?? '',
      vehicle: first?.vehicle ?? '',
      ccn: first?.ccn ?? '',
      trips: uniqueTrips,
      subtotal: rows.fold<double>(0, (s, r) => s + r.total),
      supplierTotals: supplierMap,
      timeOfDispatch: first?.timeOfDispatch,
      timeOfArrival: first?.timeOfArrival,
      customerGroups: customerGroups,
      helperName: first?.helperName ?? '',
      totalBudget: first?.totalBudget ?? 0.0,
      fulfilledCount: fulfilled,
      notFulfilledCount: notFulfilled,
      turnover: turnover,
    );
  }
}

final deliveryByPlanProvider = FutureProvider.autoDispose<List<PlanGroup>>((ref) async {
  final repo = ref.read(syncRepoProvider);
  final from = ref.watch(drFromProvider);
  final to = ref.watch(drToProvider);
  final driver = ref.watch(drDriverProvider);
  final search = ref.watch(drSearchProvider);
  final raw = await repo.getDeliveryReportFiltered(
    from: from,
    to: to,
    driverName: driver,
    search: search.isEmpty ? null : search,
  );
  final rows = raw.map((m) => DeliveryRow.fromMap(m)).toList();

  final map = <String, List<DeliveryRow>>{};
  for (final r in rows) {
    final key = r.docNo.isEmpty ? '—' : r.docNo;
    (map[key] ??= []).add(r);
  }
  final groups = <PlanGroup>[];
  for (final e in map.entries) {
    groups.add(PlanGroup.build(e.key, e.value));
  }
  groups.sort((a, b) => a.docNo.compareTo(b.docNo));
  return groups;
});

// --- OTHER PROVIDERS ---
class SupplierTotal {
  final String supplier;
  final double total;
  SupplierTotal(this.supplier, this.total);
}

final overallSupplierSummaryProvider = FutureProvider.autoDispose<List<SupplierTotal>>((ref) async {
  final repo = ref.read(syncRepoProvider);
  final from = ref.watch(drFromProvider);
  final to = ref.watch(drToProvider);
  final driver = ref.watch(drDriverProvider);
  final search = ref.watch(drSearchProvider);
  final raw = await repo.getDeliveryReportFiltered(
    from: from,
    to: to,
    driverName: driver,
    search: search.isEmpty ? null : search,
  );
  final rows = raw.map((m) => DeliveryRow.fromMap(m)).toList();
  final m = <String, double>{};
  for (final r in rows) {
    m.update(r.supplier.isEmpty ? '—' : r.supplier, (v) => v + r.total, ifAbsent: () => r.total);
  }
  final list = m.entries.map((e) => SupplierTotal(e.key, e.value)).toList()
    ..sort((a, b) => b.total.compareTo(a.total));
  return list;
});

final driversProvider = FutureProvider<List<String>>((ref) async {
  final repo = ref.read(syncRepoProvider);
  return repo.getDistinctDrivers();
});

final deliveryGrandTotalProvider = Provider<double>((ref) {
  final asyncGroups = ref.watch(deliveryGroupedProvider);
  return asyncGroups.maybeWhen(
    data: (groups) => groups.fold(0.0, (s, g) => s + g.subtotal),
    orElse: () => 0.0,
  );
});

final currencyFmt = NumberFormat('#,##0.00');
final dateFmt = DateFormat('M/d');
final timeFmt = DateFormat('h:mm a');
