// lib/state/disbursement/disbursement_providers.dart
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:intl/intl.dart";
import "package:sqflite/sqflite.dart";

import "../../data/local/app_db.dart";
import "disbursement_state.dart";

/// ------------------------------
/// Repository (SQLite read)
/// ------------------------------
class DisbursementRepository {
  Future<Database> get _db async => AppDb.get();

  static const String _view = "view_disbursement_itemized";

  Future<List<Map<String, Object?>>> _queryItemized({
    required DisbursementQuery query,
  }) async {
    final db = await _db;

    final where = <String>[];
    final args = <Object?>[];

    String iso(DateTime d) => DateFormat("yyyy-MM-dd").format(d);

    // Date range applies to transaction_date (header-level)
    if (query.from != null) {
      where.add("date(transaction_date) >= ?");
      args.add(iso(query.from!));
    }
    if (query.to != null) {
      where.add("date(transaction_date) <= ?");
      args.add(iso(query.to!));
    }

    final q = query.search.trim();
    if (q.isNotEmpty) {
      // Keep this broad but stable: doc_no, payee, reference_no, coa_title, remarks
      where.add("""
        (
          doc_no LIKE ?
          OR payee_name LIKE ?
          OR reference_no LIKE ?
          OR coa_title LIKE ?
          OR COALESCE(payable_remarks,'') LIKE ?
          OR COALESCE(disbursement_remarks,'') LIKE ?
        )
      """);
      final like = "%$q%";
      args.addAll([like, like, like, like, like, like]);
    }

    // Filter logic maps to your chips.
    switch (query.filter) {
      case DisbursementFilter.all:
        break;

      case DisbursementFilter.trade:
        where.add("transaction_type = 1");
        break;

      case DisbursementFilter.nonTrade:
        where.add("transaction_type = 2");
        break;

      case DisbursementFilter.posted:
        where.add("COALESCE(isPosted,0) = 1");
        break;

      case DisbursementFilter.unpaid:
      // Default unpaid rule: total_amount > paid_amount
        where.add("(COALESCE(total_amount,0) - COALESCE(paid_amount,0)) > 0");
        break;
    }

    final whereSql = where.isEmpty ? "" : "WHERE ${where.join(" AND ")}";

    // IMPORTANT: because this is itemized, ordering should keep DV rows together.
    final sql = """
      SELECT *
      FROM $_view
      $whereSql
      ORDER BY date(transaction_date) DESC, disbursement_id DESC, payable_id ASC
    """;

    return db.rawQuery(sql, args);
  }

  Future<List<DisbursementGroup>> getGrouped({
    required DisbursementQuery query,
  }) async {
    final rows = await _queryItemized(query: query);

    final map = <int, _GroupBuilder>{};

    for (final r in rows) {
      final disbId = _asInt(r["disbursement_id"]) ?? -1;
      if (disbId <= 0) continue;

      map.putIfAbsent(disbId, () => _GroupBuilder.fromRow(r));

      map[disbId]!.addItem(DisbursementItem(
        payableId: _asInt(r["payable_id"]) ?? 0,
        referenceNo: _asString(r["reference_no"]),
        payableDate: _asDate(r["payable_date"]),
        divisionId: _asInt(r["division_id"]),
        divisionName: _asString(r["division_name"]),
        coaId: _asInt(r["coa_id"]),
        coaTitle: _asString(r["coa_title"]),
        amount: _asDouble(r["amount"]),
        payableRemarks: _asString(r["payable_remarks"]),
        payableDateCreated: _asDate(r["payable_date_created"]),
      ));
    }

    // Convert to final immutable groups (already ordered due to SQL ordering).
    final groups = map.values.map((b) => b.build()).toList();

    // map.values preserves insertion order in Dart; insertion follows row iteration order,
    // which follows SQL order. So result should stay sorted as desired.
    return groups;
  }
}

/// Helper to build a group incrementally.
class _GroupBuilder {
  final int disbursementId;
  final String docNo;

  final int transactionType;
  final String transactionTypeName;

  final int? payeeId;
  final String? payeeName;

  final String? disbursementRemarks;

  final double totalAmount;
  final double paidAmount;

  final int? encoderId;
  final String? encoderName;

  final int? approverId;
  final String? approverName;

  final int? postedById;
  final String? postedByName;

  final int isPosted;
  final DateTime? transactionDate;

  final DateTime? disbursementDateCreated;
  final DateTime? disbursementDateUpdated;

  int? divisionId;
  String? divisionName;

  final List<DisbursementItem> items = [];

  _GroupBuilder({
    required this.disbursementId,
    required this.docNo,
    required this.transactionType,
    required this.transactionTypeName,
    required this.payeeId,
    required this.payeeName,
    required this.disbursementRemarks,
    required this.totalAmount,
    required this.paidAmount,
    required this.encoderId,
    required this.encoderName,
    required this.approverId,
    required this.approverName,
    required this.postedById,
    required this.postedByName,
    required this.isPosted,
    required this.transactionDate,
    required this.disbursementDateCreated,
    required this.disbursementDateUpdated,
  });

  factory _GroupBuilder.fromRow(Map<String, Object?> r) {
    return _GroupBuilder(
      disbursementId: _asInt(r["disbursement_id"]) ?? 0,
      docNo: _asString(r["doc_no"]) ?? "",
      transactionType: _asInt(r["transaction_type"]) ?? 0,
      transactionTypeName: _asString(r["transaction_type_name"]) ?? "Unknown",
      payeeId: _asInt(r["payee_id"]),
      payeeName: _asString(r["payee_name"]),
      disbursementRemarks: _asString(r["disbursement_remarks"]),
      totalAmount: _asDouble(r["total_amount"]),
      paidAmount: _asDouble(r["paid_amount"]),
      encoderId: _asInt(r["encoder_id"]),
      encoderName: _asString(r["encoder_name"]),
      approverId: _asInt(r["approver_id"]),
      approverName: _asString(r["approver_name"]),
      postedById: _asInt(r["posted_by_id"]),
      postedByName: _asString(r["posted_by_name"]),
      isPosted: _asBoolInt(r["isPosted"]),
      transactionDate: _asDate(r["transaction_date"]),
      disbursementDateCreated: _asDate(r["disbursement_date_created"]),
      disbursementDateUpdated: _asDate(r["disbursement_date_updated"]),
    );
  }

  void addItem(DisbursementItem item) {
    items.add(item);

    // Keep the first non-null division as a "primary" division label (optional).
    divisionId ??= item.divisionId;
    divisionName ??= item.divisionName;
  }

  DisbursementGroup build() {
    return DisbursementGroup(
      disbursementId: disbursementId,
      docNo: docNo,
      transactionType: transactionType,
      transactionTypeName: transactionTypeName,
      payeeId: payeeId,
      payeeName: payeeName,
      disbursementRemarks: disbursementRemarks,
      totalAmount: totalAmount,
      paidAmount: paidAmount,
      encoderId: encoderId,
      encoderName: encoderName,
      approverId: approverId,
      approverName: approverName,
      postedById: postedById,
      postedByName: postedByName,
      isPosted: isPosted,
      transactionDate: transactionDate,
      disbursementDateCreated: disbursementDateCreated,
      disbursementDateUpdated: disbursementDateUpdated,
      divisionId: divisionId,
      divisionName: divisionName,
      items: List.unmodifiable(items),
    );
  }
}

/// ------------------------------
/// Providers + Controller
/// ------------------------------

final disbursementRepositoryProvider = Provider<DisbursementRepository>((ref) {
  return DisbursementRepository();
});

/// Controller that loads & filters disbursement groups.
///
/// UI usage later:
/// - ref.watch(disbursementControllerProvider) -> AsyncValue<DisbursementState>
/// - ref.read(disbursementControllerProvider.notifier).setFilter(...)
final disbursementControllerProvider =
AsyncNotifierProvider<DisbursementController, DisbursementState>(
  DisbursementController.new,
);

class DisbursementController extends AsyncNotifier<DisbursementState> {
  DisbursementRepository get _repo => ref.read(disbursementRepositoryProvider);

  @override
  Future<DisbursementState> build() async {
    // initial load with default query
    final initial = DisbursementState.initial();
    return _loadWith(initial.query);
  }

  Future<DisbursementState> _loadWith(DisbursementQuery query) async {
    final groups = await _repo.getGrouped(query: query);

    final totalGroups = groups.length;
    final totalItems =
    groups.fold<int>(0, (sum, g) => sum + g.items.length);
    final totalDisbursement =
    groups.fold<double>(0.0, (sum, g) => sum + g.totalAmount);

    return DisbursementState(
      query: query,
      groups: groups,
      totalGroups: totalGroups,
      totalItems: totalItems,
      totalDisbursement: totalDisbursement,
    );
  }

  Future<void> refresh() async {
    final current = state.valueOrNull ?? DisbursementState.initial();
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _loadWith(current.query));
  }

  Future<void> setFilter(DisbursementFilter filter) async {
    final current = state.valueOrNull ?? DisbursementState.initial();
    final nextQuery = current.query.copyWith(filter: filter);
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _loadWith(nextQuery));
  }

  Future<void> setSearch(String search) async {
    final current = state.valueOrNull ?? DisbursementState.initial();
    final nextQuery = current.query.copyWith(search: search);
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _loadWith(nextQuery));
  }

  Future<void> setDateRange({DateTime? from, DateTime? to}) async {
    final current = state.valueOrNull ?? DisbursementState.initial();
    final nextQuery = current.query.copyWith(from: from, to: to);
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _loadWith(nextQuery));
  }

  Future<void> clearDates() async {
    final current = state.valueOrNull ?? DisbursementState.initial();
    final nextQuery = current.query.copyWith(clearFrom: true, clearTo: true);
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _loadWith(nextQuery));
  }
}

/// ------------------------------
/// Parsing helpers (SQLite-safe)
/// ------------------------------

int? _asInt(Object? v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString());
}

double _asDouble(Object? v) {
  if (v == null) return 0.0;
  if (v is double) return v;
  if (v is int) return v.toDouble();
  if (v is num) return v.toDouble();
  final s = v.toString().trim();
  if (s.isEmpty) return 0.0;
  return double.tryParse(s) ?? 0.0;
}

String? _asString(Object? v) {
  if (v == null) return null;
  final s = v.toString();
  final t = s.trim();
  return t.isEmpty ? null : t;
}

/// Handles ISO strings like "2026-01-14" or "2026-01-14T08:10:00"
DateTime? _asDate(Object? v) {
  final s = _asString(v);
  if (s == null) return null;
  try {
    return DateTime.parse(s);
  } catch (_) {
    // fallback: try date-only
    try {
      if (s.length >= 10) return DateTime.parse(s.substring(0, 10));
    } catch (_) {}
  }
  return null;
}

/// Convert payload to 0/1 safely (SQLite ints, strings, etc.)
int _asBoolInt(Object? v) {
  if (v == null) return 0;
  if (v is int) return v != 0 ? 1 : 0;
  if (v is num) return v != 0 ? 1 : 0;
  if (v is bool) return v ? 1 : 0;
  final s = v.toString().toLowerCase().trim();
  return (s == "1" || s == "true" || s == "t" || s == "yes" || s == "y")
      ? 1
      : 0;
}
