import 'dart:collection';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';

import 'package:vos_mobile/data/local/app_db.dart';

/// =========================
/// Data Models
/// =========================

class InvoiceAR {
  final int invoiceId;
  final String invoiceNo;
  final String customerCode;
  final String customerName;
  final double netAmount;   // total_amount - discount_amount
  final double paidAmount;  // SUM(payments)
  final double balance;     // >= 0
  final DateTime? dueDate;  // from view (computed if null at source)
  final bool isPosted;      // NEW

  const InvoiceAR({
    required this.invoiceId,
    required this.invoiceNo,
    required this.customerCode,
    required this.customerName,
    required this.netAmount,
    required this.paidAmount,
    required this.balance,
    required this.dueDate,
    required this.isPosted,
  });

  bool get isOutstanding => balance > 0;

  int get daysOverdue {
    if (dueDate == null) return 0;
    final today = DateTime.now();
    final d0 = DateTime(dueDate!.year, dueDate!.month, dueDate!.day);
    final t0 = DateTime(today.year, today.month, today.day);
    return t0.difference(d0).inDays;
  }

  String get agingBucket {
    if (!isOutstanding) return 'current';
    if (dueDate == null) return 'current';
    final d = daysOverdue;
    if (d <= 0) return 'current';
    if (d <= 30) return '1-30';
    if (d <= 60) return '31-60';
    if (d <= 90) return '61-90';
    return '90+';
  }

  String get uiStatus => (!isOutstanding || daysOverdue <= 0) ? 'Current' : 'Overdue';
}

class ClientAR {
  final String client;       // customer_name (fallback to code)
  final String customerCode;
  final List<InvoiceAR> invoices;

  const ClientAR({
    required this.client,
    required this.customerCode,
    required this.invoices,
  });

  double get total => invoices.fold(0.0, (s, x) => s + x.balance);

  Map<String, double> get aging {
    final map = <String, double>{
      'current': 0,
      '1-30': 0,
      '31-60': 0,
      '61-90': 0,
      '90+': 0,
    };
    for (final inv in invoices) {
      map[inv.agingBucket] = (map[inv.agingBucket] ?? 0) + inv.balance;
    }
    return map;
  }

  double get overdue => aging.entries
      .where((e) => e.key != 'current')
      .fold(0.0, (s, e) => s + e.value);

  String get status {
    if (overdue > 0) return 'Overdue';
    final hasPartial = invoices.any((i) => i.paidAmount > 0 && i.balance > 0);
    if (hasPartial) return 'Partial';
    return 'Current';
  }

  // NEW: quick helpers for posted flags
  bool get anyPosted => invoices.any((i) => i.isPosted);
  bool get allPosted => invoices.isNotEmpty && invoices.every((i) => i.isPosted);
}

/// =========================
/// State
/// =========================

@immutable
class ARState {
  final bool isLoading;
  final DateTime lastUpdated;
  final String search;
  final UnmodifiableListView<ClientAR> clients;

  const ARState({
    required this.isLoading,
    required this.lastUpdated,
    required this.search,
    required this.clients,
  });

  factory ARState.initial() => ARState(
    isLoading: false,
    lastUpdated: DateTime.now(),
    search: '',
    clients: UnmodifiableListView<ClientAR>([]),
  );

  ARState copyWith({
    bool? isLoading,
    DateTime? lastUpdated,
    String? search,
    List<ClientAR>? clients,
  }) {
    return ARState(
      isLoading: isLoading ?? this.isLoading,
      lastUpdated: lastUpdated ?? this.lastUpdated,
      search: search ?? this.search,
      clients: clients != null ? UnmodifiableListView(clients) : this.clients,
    );
  }
}

/// =========================
/// Notifier
/// =========================

class ARNotifier extends AutoDisposeNotifier<ARState> {
  @override
  ARState build() {
    // Auto refresh when provider is first watched
    Future.microtask(refresh);
    return ARState.initial();
  }

  Future<void> refresh() async {
    state = state.copyWith(isLoading: true);
    try {
      final db = await AppDb.get();

      // NOTE: view_account_recievable now contains: is_posted, due_date, due_date_date
      final rows = await db.rawQuery('''
  SELECT
    invoice_id,
    invoice_number,      -- aliased invoice_no from the view
    order_id,
    customer_code,
    customer_name,
    net_amount,
    paid_amount,
    balance,
    due_date,
    due_date_date,
    is_posted
  FROM view_account_recievable
  WHERE is_posted = 0            -- ⬅️ only NOT YET PAID
''');

      // Map rows -> invoices
      final invoices = <InvoiceAR>[];
      for (final r in rows) {
        final bal = _asDouble(r['balance']);
        invoices.add(InvoiceAR(
          invoiceId: _asInt(r['invoice_id']),
          invoiceNo: (r['invoice_number'] ?? '').toString(),
          customerCode: (r['customer_code'] ?? '').toString(),
          customerName: _pickName(r['customer_name'], r['customer_code']),
          netAmount: _asDouble(r['net_amount']),
          paidAmount: _asDouble(r['paid_amount']),
          balance: bal < 0 ? 0 : bal,
          // prefer the ISO-only date the view provides (due_date_date) if present
          dueDate: _parseDate(r['due_date_date']) ?? _parseDate(r['due_date']),
          isPosted: _asBool(r['is_posted']),
        ));
      }

      // Group by client; keep only clients with any outstanding balance
      final byClient = <String, List<InvoiceAR>>{};
      final codeByClient = <String, String>{};
      for (final inv in invoices) {
        final key = inv.customerName.isNotEmpty ? inv.customerName : inv.customerCode;
        byClient.putIfAbsent(key, () => []).add(inv);
        codeByClient[key] = inv.customerCode;
      }

      final grouped = <ClientAR>[];
      byClient.forEach((client, list) {
        if (list.any((i) => i.balance > 0)) {
          grouped.add(ClientAR(
            client: client,
            customerCode: codeByClient[client] ?? '',
            invoices: list,
          ));
        }
      });

      grouped.sort((a, b) => a.client.toLowerCase().compareTo(b.client.toLowerCase()));

      state = state.copyWith(
        clients: grouped,
        lastUpdated: DateTime.now(),
        isLoading: false,
      );
    } catch (e, st) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('ARNotifier.refresh error: $e\n$st');
      }
      state = state.copyWith(isLoading: false);
    }
  }

  void setSearch(String v) {
    if (v == state.search) return;
    state = state.copyWith(search: v);
  }

  // ----- helpers -----
  int _asInt(dynamic v) {
    if (v == null) return 0;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString()) ?? 0;
  }

  double _asDouble(dynamic v) {
    if (v == null) return 0.0;
    if (v is num) return v.toDouble();
    final s = v.toString().trim();
    if (s.isEmpty) return 0.0;
    return double.tryParse(s) ?? 0.0;
  }

  bool _asBool(dynamic v) {
    if (v == null) return false;
    if (v is bool) return v;
    if (v is num) return v != 0;
    return v.toString() == '1' || v.toString().toLowerCase() == 'true';
  }

  DateTime? _parseDate(dynamic v) {
    if (v == null) return null;
    // Accept 'YYYY-MM-DD' or full ISO strings
    final s = v.toString();
    final parsed = DateTime.tryParse(s);
    return parsed;
  }

  String _pickName(dynamic name, dynamic code) {
    final n = (name ?? '').toString().trim();
    if (n.isNotEmpty) return n;
    final c = (code ?? '').toString().trim();
    return c.isNotEmpty ? c : '—';
  }
}

/// =========================
/// Providers
/// =========================

final arNotifierProvider =
AutoDisposeNotifierProvider<ARNotifier, ARState>(ARNotifier.new);

/// Filtered clients by search (case-insensitive)
final arFilteredClientsProvider = Provider.autoDispose<List<ClientAR>>((ref) {
  final s = ref.watch(arNotifierProvider);
  if (s.search.trim().isEmpty) return s.clients;
  final q = s.search.toLowerCase();
  return s.clients.where((c) => c.client.toLowerCase().contains(q)).toList();
});

/// Totals & aging for the header/analytics sections
final arTotalsProvider = Provider.autoDispose<({
double totalAR,
double totalOverdue,
int overdueClientCount,
Map<String, double> agingTotals,
})>((ref) {
  final clients = ref.watch(arNotifierProvider.select((s) => s.clients));

  double totalAR = 0, totalOverdue = 0;
  int overdueCount = 0;
  final aging = <String, double>{
    'current': 0,
    '1-30': 0,
    '31-60': 0,
    '61-90': 0,
    '90+': 0,
  };

  for (final c in clients) {
    totalAR += c.total;
    final od = c.overdue;
    totalOverdue += od;
    if (od > 0) overdueCount++;
    final a = c.aging;
    for (final k in aging.keys) {
      aging[k] = (aging[k] ?? 0) + (a[k] ?? 0);
    }
  }

  return (
  totalAR: totalAR,
  totalOverdue: totalOverdue,
  overdueClientCount: overdueCount,
  agingTotals: aging,
  );
});

final arLastUpdatedProvider =
Provider.autoDispose<DateTime>((ref) => ref.watch(arNotifierProvider).lastUpdated);

final arIsLoadingProvider =
Provider.autoDispose<bool>((ref) => ref.watch(arNotifierProvider).isLoading);

final arSearchProvider = Provider.autoDispose<String>((ref) {
  return ref.watch(arNotifierProvider.select((s) => s.search));
});
