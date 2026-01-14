// lib/data/repositories/disbursement_repository.dart
import "../../core/network/api_client.dart";

/// Simple paged result wrapper for list screens (Sales-Order style).
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

  // =============================
  // CONFIG
  // =============================

  static const String _disbCollection = "disbursement";
  static const String _userCollection = "user";
  static const String _suppliersCollection = "suppliers";

  // Only what we need for approvals list + action gating.
  static const String _disbFields =
      "id,doc_no,total_amount,paid_amount,encoder_id,payee,transaction_date,"
      "approver_id,date_approved,date_created,date_updated";

  // =============================
  // PUBLIC: Paged list (server-side)
  // =============================

  /// status:
  /// - null => All
  /// - "pending" => approver_id IS NULL AND date_approved IS NULL
  /// - "approved" => approver_id IS NOT NULL AND date_approved IS NOT NULL
  ///
  /// NOTE: paging is row-based (disbursement rows). The view groups by doc_no.
  Future<PagedResult<Map<String, dynamic>>> fetchDisbursementsPaged({
    required int limit,
    required int offset,
    String? search,
    String? status,
  }) async {
    final query = <String, String>{
      "limit": limit.toString(),
      "offset": offset.toString(),
      "sort": "-transaction_date,-id",
      "fields": _disbFields,
      "meta": "total_count",
    };

    final st = (status ?? "").trim().toLowerCase();
    if (st == "pending") {
      query["filter[_and][0][approver_id][_null]"] = "true";
      query["filter[_and][1][date_approved][_null]"] = "true";
    } else if (st == "approved") {
      query["filter[_and][0][approver_id][_nnull]"] = "true";
      query["filter[_and][1][date_approved][_nnull]"] = "true";
    }

    final q = (search ?? "").trim();
    if (q.isNotEmpty) {
      await _applyServerSideSearch(query, q);
    }

    final json = await _api.getJson("/items/$_disbCollection", query: query);

    final List raw = (json["data"] as List?) ?? const [];
    final items = raw
        .whereType<Map>()
        .map((m) => Map<String, dynamic>.from(m))
        .toList();

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

  // =============================
  // LOOKUPS
  // =============================

  Future<List<Map<String, dynamic>>> fetchUsersByIds(List<int> userIds) async {
    if (userIds.isEmpty) return const [];

    final ids = userIds.where((e) => e > 0).toSet().toList()..sort();
    final json = await _api.getJson(
      "/items/$_userCollection",
      query: {
        "limit": "-1",
        "filter[user_id][_in]": ids.join(","),
        "fields": "user_id,user_fname,user_mname,user_lname,is_deleted",
      },
    );

    final List data = (json["data"] as List?) ?? const [];
    return data
        .whereType<Map>()
        .map((m) => Map<String, dynamic>.from(m))
        .toList();
  }

  Future<List<Map<String, dynamic>>> fetchSuppliersByIds(List<int> supplierIds) async {
    if (supplierIds.isEmpty) return const [];

    final ids = supplierIds.where((e) => e > 0).toSet().toList()..sort();
    final json = await _api.getJson(
      "/items/$_suppliersCollection",
      query: {
        "limit": "-1",
        "filter[id][_in]": ids.join(","),
        "fields": "id,supplier_name",
      },
    );

    final List data = (json["data"] as List?) ?? const [];
    return data
        .whereType<Map>()
        .map((m) => Map<String, dynamic>.from(m))
        .toList();
  }

  // =============================
  // APPROVAL ACTION
  // =============================

  /// Approves ALL disbursement rows that share the same doc_no.
  ///
  /// Sets:
  /// - approver_id
  /// - date_approved (UTC ISO string)
  Future<void> approveByDocNo({
    required String docNo,
    required int approverId,
  }) async {
    final dn = docNo.trim();
    if (dn.isEmpty) throw Exception("doc_no is required.");

    // 1) Load all disbursement ids for this doc_no
    final json = await _api.getJson(
      "/items/$_disbCollection",
      query: {
        "limit": "-1",
        "filter[doc_no][_eq]": dn,
        "fields": "id,doc_no",
      },
    );

    final List data = (json["data"] as List?) ?? const [];
    final keys = <int>[];
    for (final row in data.whereType<Map>()) {
      final id = _asInt(row["id"]);
      if (id != null) keys.add(id);
    }

    if (keys.isEmpty) {
      throw Exception("No disbursement rows found for doc_no='$dn'.");
    }

    // 2) Patch all keys
    final nowIso = DateTime.now().toUtc().toIso8601String();
    await _api.patch(
      "/items/$_disbCollection",
      data: {
        "keys": keys,
        "data": {
          "approver_id": approverId,
          "date_approved": nowIso,
        },
      },
    );
  }

  // =============================
  // SERVER-SIDE SEARCH (Sales-Order style)
  // =============================

  Future<void> _applyServerSideSearch(Map<String, String> query, String q) async {
    int i = 0;

    void addOr(String field, String op, String value) {
      query["filter[_or][$i][$field][$op]"] = value;
      i++;
    }

    // Base searchable fields on disbursement
    addOr("doc_no", "_icontains", q);

    // Numeric quick hits
    final asInt = int.tryParse(q);
    if (asInt != null) {
      addOr("id", "_eq", q);
      addOr("encoder_id", "_eq", q);
      addOr("payee", "_eq", q);
      addOr("approver_id", "_eq", q);
    }

    // Expand by supplier/user lookups if there are letters
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
    }
  }

  Future<List<int>> _searchSupplierIdsByName(String q, {int limit = 60}) async {
    final s = q.trim();
    if (s.isEmpty) return const [];

    final json = await _api.getJson(
      "/items/$_suppliersCollection",
      query: {
        "limit": limit.toString(),
        "fields": "id",
        "filter[supplier_name][_icontains]": s,
      },
    );

    final List data = (json["data"] as List?) ?? const [];
    final ids = <int>[];
    for (final row in data.whereType<Map>()) {
      final id = _asInt(row["id"]) ?? 0;
      if (id > 0) ids.add(id);
    }
    return ids.toSet().toList()..sort();
  }

  Future<List<int>> _searchUserIdsByName(String q, {int limit = 60}) async {
    final s = q.trim();
    if (s.isEmpty) return const [];

    final json = await _api.getJson(
      "/items/$_userCollection",
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
    for (final row in data.whereType<Map>()) {
      final id = _asInt(row["user_id"]) ?? 0;
      if (id > 0) ids.add(id);
    }
    return ids.toSet().toList()..sort();
  }

  int? _asInt(Object? v) {
    if (v == null) return null;
    if (v is Map) {
      final m = v.cast<String, dynamic>();
      return _asInt(m["id"] ?? m["user_id"]);
    }
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString());
  }
}
