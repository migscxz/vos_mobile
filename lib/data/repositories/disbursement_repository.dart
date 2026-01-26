// lib/data/repositories/disbursement_repository.dart
import "../../core/network/api_client.dart";
import "../../modules/approvals/disbursement/disbursement_models.dart";

/// Simple paged result wrapper for list screens.
class PagedResult<T> {
  final List<T> items;
  final int total;
  final int limit;
  final int offset;

  const PagedResult({
    required this.items,
    required this.total,
    required this.limit,
    required this.offset,
  });

  bool get hasMore => (offset + items.length) < total;
}

class DisbursementRepository {
  DisbursementRepository(this._api);
  final ApiClient _api;

  static const String _disbursement = "disbursement";
  static const String _disbursementPayables = "disbursement_payables";
  static const String _suppliers = "suppliers";
  static const String _users = "user";
  static const String _coa = "chart_of_accounts";

  static const String _disbursementFields =
      "id,doc_no,total_amount,paid_amount,encoder_id,payee,transaction_date,"
      "approver_id,date_approved,remarks,date_created,date_updated";

  /// Paged fetch for disbursement headers with:
  /// - filter: All / Pending / Approved
  /// - server-side search (doc_no, remarks, plus supplier/user name lookups -> ID filters)
  /// Uses meta.total_count for correct pagination.
  Future<PagedResult<Map<String, dynamic>>> fetchDisbursementsPaged({
    required int limit,
    required int offset,
    String? search,
    DisbursementFilter filter = DisbursementFilter.pending,
  }) async {
    final query = <String, String>{
      "limit": limit.toString(),
      "offset": offset.toString(),
      "sort": "-date_created,-id",
      "fields": _disbursementFields,
      "meta": "total_count",
    };

    _applyStatusFilter(query, filter);

    final q = (search ?? "").trim();
    if (q.isNotEmpty) {
      await _applyServerSideSearch(query, q);
    }

    final json = await _api.getJson("/items/$_disbursement", query: query);

    final List raw = (json["data"] as List?) ?? const [];
    final items = raw.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList();

    int total = items.length;
    final meta = json["meta"];
    if (meta is Map) {
      final tc = _asInt(meta["total_count"]);
      if (tc != null) total = tc;
    }

    return PagedResult<Map<String, dynamic>>(
      items: items,
      total: total,
      limit: limit,
      offset: offset,
    );
  }

  Future<int> fetchDisbursementCount({required DisbursementFilter filter}) async {
    final query = <String, String>{
      "limit": "1",
      "fields": "id",
      "meta": "total_count",
    };

    _applyStatusFilter(query, filter);

    final json = await _api.getJson("/items/$_disbursement", query: query);

    final meta = json["meta"];
    if (meta is Map) {
      final tc = _asInt(meta["total_count"]);
      return tc ?? 0;
    }
    return 0;
  }

  void _applyStatusFilter(Map<String, String> query, DisbursementFilter filter) {
    // All: no filter
    if (filter == DisbursementFilter.all) return;

    if (filter == DisbursementFilter.pending) {
      query["filter[approver_id][_null]"] = "true";
      query["filter[date_approved][_null]"] = "true";
      return;
    }

    if (filter == DisbursementFilter.approved) {
      query["filter[approver_id][_nnull]"] = "true";
      query["filter[date_approved][_nnull]"] = "true";
      return;
    }
  }

  // ----------------------------
  // Payables for modal
  // ----------------------------

  Future<List<Map<String, dynamic>>> fetchPayablesByDisbursementId(int disbursementId) async {
    final json = await _api.getJson(
      "/items/$_disbursementPayables",
      query: {
        "limit": "-1",
        "sort": "date,id",
        "filter[disbursement_id][_eq]": disbursementId.toString(),
        "fields": "id,disbursement_id,reference_no,date,coa_id,amount,remarks,date_created,division_id",
      },
    );

    final List data = (json["data"] as List?) ?? const [];
    return data.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList();
  }

  Future<List<Map<String, dynamic>>> fetchCoaByIds(List<int> coaIds) async {
    if (coaIds.isEmpty) return const [];

    final ids = coaIds.where((e) => e > 0).toSet().toList()..sort();
    final json = await _api.getJson(
      "/items/$_coa",
      query: {
        "limit": "-1",
        "filter[coa_id][_in]": ids.join(","),
        "fields": "coa_id,account_title",
      },
    );

    final List data = (json["data"] as List?) ?? const [];
    return data.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList();
  }

  // ----------------------------
  // Lookups (names)
  // ----------------------------

  Future<List<Map<String, dynamic>>> fetchSuppliersByIds(List<int> supplierIds) async {
    if (supplierIds.isEmpty) return const [];

    final ids = supplierIds.where((e) => e > 0).toSet().toList()..sort();
    final json = await _api.getJson(
      "/items/$_suppliers",
      query: {
        "limit": "-1",
        "filter[id][_in]": ids.join(","),
        "fields": "id,supplier_name",
      },
    );

    final List data = (json["data"] as List?) ?? const [];
    return data.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList();
  }

  Future<List<Map<String, dynamic>>> fetchUsersByIds(List<int> userIds) async {
    if (userIds.isEmpty) return const [];

    final ids = userIds.where((e) => e > 0).toSet().toList()..sort();
    final json = await _api.getJson(
      "/items/$_users",
      query: {
        "limit": "-1",
        "filter[user_id][_in]": ids.join(","),
        "fields": "user_id,user_fname,user_mname,user_lname,is_deleted",
      },
    );

    final List data = (json["data"] as List?) ?? const [];
    return data.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList();
  }

  // ----------------------------
  // Approval action
  // ----------------------------

  Future<void> approveDisbursement({
    required int disbursementId,
    required int approverId,
  }) async {
    final nowIso = DateTime.now().toUtc().toIso8601String();

    await _api.patch(
      "/items/$_disbursement/$disbursementId",
      data: {
        "approver_id": approverId,
        "date_approved": nowIso,
      },
    );
  }

  // ----------------------------
  // Server-side search expansion
  // ----------------------------

  Future<void> _applyServerSideSearch(Map<String, String> query, String q) async {
    int i = 0;

    void addOr(String field, String op, String value) {
      query["filter[_or][$i][$field][$op]"] = value;
      i++;
    }

    // Base searchable fields on disbursement
    addOr("doc_no", "_icontains", q);
    addOr("remarks", "_icontains", q);

    // Numeric quick hits
    final asInt = int.tryParse(q);
    if (asInt != null) {
      addOr("id", "_eq", q);
      addOr("encoder_id", "_eq", q);
      addOr("payee", "_eq", q);
      addOr("approver_id", "_eq", q);
      addOr("transaction_type", "_eq", q);
    }

    // Expand only if query has letters
    final hasLetters = RegExp(r"[A-Za-z]").hasMatch(q);
    if (!hasLetters) return;

    final results = await Future.wait([
      _searchSupplierIdsByName(q, limit: 60),
      _searchUserIdsByName(q, limit: 60),
    ]);

    final supplierIds = results[0];
    final userIds = results[1];

    if (supplierIds.isNotEmpty) {
      addOr("payee", "_in", supplierIds.join(","));
    }
    if (userIds.isNotEmpty) {
      addOr("encoder_id", "_in", userIds.join(","));
      addOr("approver_id", "_in", userIds.join(","));
      addOr("posted_by", "_in", userIds.join(","));
    }
  }

  Future<List<int>> _searchSupplierIdsByName(String q, {int limit = 60}) async {
    final s = q.trim();
    if (s.isEmpty) return const [];

    final json = await _api.getJson(
      "/items/$_suppliers",
      query: {
        "limit": limit.toString(),
        "fields": "id",
        "filter[supplier_name][_icontains]": s,
      },
    );

    final List data = (json["data"] as List?) ?? const [];
    final ids = <int>[];
    for (final row in data) {
      if (row is! Map) continue;
      final id = _asInt(row["id"]) ?? 0;
      if (id > 0) ids.add(id);
    }
    return ids.toSet().toList()..sort();
  }

  Future<List<int>> _searchUserIdsByName(String q, {int limit = 60}) async {
    final s = q.trim();
    if (s.isEmpty) return const [];

    final json = await _api.getJson(
      "/items/$_users",
      query: {
        "limit": limit.toString(),
        "fields": "user_id",
        "filter[_or][0][user_fname][_icontains]": s,
        "filter[_or][1][user_lname][_icontains]": s,
        "filter[_or][2][user_mname][_icontains]": s,
      },
    );

    final List data = (json["data"] as List?) ?? const [];
    final ids = <int>[];
    for (final row in data) {
      if (row is! Map) continue;
      final id = _asInt(row["user_id"]) ?? 0;
      if (id > 0) ids.add(id);
    }
    return ids.toSet().toList()..sort();
  }

  int? _asInt(Object? v) {
    if (v == null) return null;
    if (v is Map) {
      final m = v.cast<String, dynamic>();
      return _asInt(m["id"] ?? m["user_id"] ?? m["coa_id"]);
    }
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString());
  }
}
