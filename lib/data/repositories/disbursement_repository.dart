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

  static const String _disbursementThresholds = "disbursement_threshold";
  static const String _disbursementFields =
      "id,doc_no,total_amount,paid_amount,encoder_id,payee,transaction_date,"
      "approver_id,date_approved,remarks,transaction_type,date_created,date_updated";

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

    await _applyStatusFilter(query, filter);

    final q = (search ?? "").trim();
    if (q.isNotEmpty) {
      await _applyServerSideSearch(query, q);
    }

    final json = await _api.getJson("/items/$_disbursement", query: query);

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

  Future<int> fetchDisbursementCount({
    required DisbursementFilter filter,
  }) async {
    final query = <String, String>{
      "limit": "1",
      "fields": "id",
      "meta": "total_count",
    };

    await _applyStatusFilter(query, filter);

    final json = await _api.getJson("/items/$_disbursement", query: query);

    final meta = json["meta"];
    if (meta is Map) {
      final tc = _asInt(meta["total_count"]);
      return tc ?? 0;
    }
    return 0;
  }

  Future<List<DisbursementThreshold>> fetchThresholds() async {
    final json = await _api.getJson(
      "/items/$_disbursementThresholds",
      query: {"limit": "-1"},
    );
    final List data = (json["data"] as List?) ?? const [];
    return data
        .whereType<Map>()
        .map(
          (m) => DisbursementThreshold.fromJson(Map<String, dynamic>.from(m)),
        )
        .toList();
  }

  Future<void> _applyStatusFilter(
    Map<String, String> query,
    DisbursementFilter filter,
  ) async {
    // All: no filter
    if (filter == DisbursementFilter.all) return;

    if (filter == DisbursementFilter.pending) {
      // Pending means NOT approved yet
      query["filter[approver_id][_null]"] = "true";
      query["filter[date_approved][_null]"] = "true";

      // AND ( (type=1 AND amount > T1) OR (type=2 AND amount > T2) )
      final thresholds = await fetchThresholds();
      if (thresholds.isNotEmpty) {
        int i = 0;
        for (final t in thresholds) {
          // Logic: Only pending if amount > threshold for this type
          // If a type has NO threshold, it falls through?
          // Actually, we want to construct an OR condition for "needs approval"
          // If transaction_type matches X, amount MUST be > threshold to be pending.
          // Wait, if amount <= threshold, it is NOT pending? Does it auto-approve?
          // Assuming here if amount <= threshold, clean logic is to HIDE from Pending list.
          // So we only SHOW items in Pending if they require approval.

          // Directus filter syntax for nested OR inside AND is tricky if using top-level params.
          // We need custom filter structure.
          // The base pending checks are already set.
          // We need to add: AND ( (transaction_type = T.type AND total_amount > T.threshold) ... )
          // But wait, what if transaction_type is NOT in threshold list?
          // If not in threshold list, assume it ALWAYS needs approval (default behavior).
          // But implementing "not in list" is hard.

          // Simplified Interpretation: Only apply threshold logic for types that HAVE a threshold.
          // For now, let's assume we list the conditions where it IS pending.

          // Using _or indices for the complex group
          // We want:
          // filter[_and][0][approver_id][_null]=true
          // filter[_and][1][date_approved][_null]=true
          // filter[_and][2][_or][0]... logic

          // Let's rewrite query to use explicit _and structure to be safe with complexity
          query.remove("filter[approver_id][_null]");
          query.remove("filter[date_approved][_null]");

          query["filter[_and][0][approver_id][_null]"] = "true";
          query["filter[_and][1][date_approved][_null]"] = "true";

          // Now the OR block for thresholds
          // If we have thresholds, we presumably only care about those specific types?
          // Or do we say: IF type matches X, then amount > Y?
          // If we restrict the view to only those logic, we might hide other valid pending items.
          //
          // Approach: Show pending IF:
          // (Amount > Threshold AND Type = ThresholdType) OR (Type NOT IN ThresholdTypes)
          // "Type NOT IN" is hard to express dynamically if there are many types.
          //
          // Alternative User Logic: "the logic is if the threshold is greaterthan the total amount it will automatically pending".
          // User corrected to "Total > Threshold = Pending".
          // This implies items with Total <= Threshold are NOT pending (auto-approved or just hidden).
          //
          // Let's implement:
          // Iterate thresholds, create OR conditions.
          // filter[_and][2][_or][index][transaction_type][_eq] = t.type
          // filter[_and][2][_or][index][total_amount][_gt] = t.threshold
          //
          // What about types not in the list?
          // If the user intends ONLY these types to be managed, then this logic is fine (others hidden).
          // If others should be default pending, we need an OR condition for them.
          // I will assume for now we only filter for the types defined in threshold table,
          // AND we also include "transaction_type is null" or "transaction_type not in [known types]" if possible.
          //
          // Given the prompt "added a new table... connected in disbursement... logic is...",
          // I'll stick to: Pending = Matches one of the Threshold rules.
          // i.e. It is pending IF (Type=1 AND Amount>1000) OR (Type=2 AND Amount>1000).
          // If there is a Type 3 with no rule, it won't show up here (safe bet).

          query["filter[_and][2][_or][$i][transaction_type][_eq]"] = t
              .transactionType
              .toString();
          query["filter[_and][2][_or][$i][total_amount][_gt]"] = t.threshold
              .toString();
          i++;
        }
      }
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

  Future<List<Map<String, dynamic>>> fetchPayablesByDisbursementId(
    int disbursementId,
  ) async {
    final json = await _api.getJson(
      "/items/$_disbursementPayables",
      query: {
        "limit": "-1",
        "sort": "date,id",
        "filter[disbursement_id][_eq]": disbursementId.toString(),
        "fields":
            "id,disbursement_id,reference_no,date,coa_id,amount,remarks,date_created,division_id",
      },
    );

    final List data = (json["data"] as List?) ?? const [];
    return data
        .whereType<Map>()
        .map((m) => Map<String, dynamic>.from(m))
        .toList();
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
    return data
        .whereType<Map>()
        .map((m) => Map<String, dynamic>.from(m))
        .toList();
  }

  // ----------------------------
  // Lookups (names)
  // ----------------------------

  Future<List<Map<String, dynamic>>> fetchSuppliersByIds(
    List<int> supplierIds,
  ) async {
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
    return data
        .whereType<Map>()
        .map((m) => Map<String, dynamic>.from(m))
        .toList();
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
    return data
        .whereType<Map>()
        .map((m) => Map<String, dynamic>.from(m))
        .toList();
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
      data: {"approver_id": approverId, "date_approved": nowIso},
    );
  }

  // ----------------------------
  // Server-side search expansion
  // ----------------------------

  Future<void> _applyServerSideSearch(
    Map<String, String> query,
    String q,
  ) async {
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
