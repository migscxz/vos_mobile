import "../../core/network/api_client.dart";
import "../../modules/approvals/dispatch_plan/dispatch_plan_models.dart";

// ==============================================================================
// MODELS
// ==============================================================================

/// A standardized wrapper for pagination.
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

/// Returned when a plan is successfully approved.
class ApproveResult {
  final int consolidatorId;
  final String? consolidatorNo;
  const ApproveResult({
    required this.consolidatorId,
    required this.consolidatorNo,
  });
}

// ==============================================================================
// REPOSITORY
// ==============================================================================

class DispatchPlanRepository {
  DispatchPlanRepository(this._api);

  final ApiClient _api;

  // --- Configuration ---
  static const String _dpCollection = "dispatch_plan";
  static const String _dpDetailsCollection = "dispatch_plan_details";
  static const String _branchCollection = "branches";
  static const String _userCollection = "user"; 
  
  // The ID of the row in `pick_list_no` that tracks our counters
  static const int _pickListPk = 15;
  static const String _consolidatorStatusPending = "Picking"; // Changed to Picking as per flow

  // Helper to format the generated CLDTST number
  static String _formatCldtst(int no) => "CLDTST-${no.toString().padLeft(6, "0")}";

  // =============================
  // FETCH FLOW (List View)
  // =============================

  Future<PagedResult<DispatchPlanHeader>> fetchDispatchPlansPaged({
    required int limit,
    required int offset,
    String? search,
    DispatchStatus? status,
  }) async {
    final query = <String, String>{
      "limit": limit.toString(),
      "offset": offset.toString(),
      "sort": "-created_at",
      "meta": "total_count",
    };

    // Apply Filters
    if (status != null) {
      query["filter[status][_eq]"] = status.label;
    }

    if (search != null && search.trim().isNotEmpty) {
      query["filter[dispatch_no][_icontains]"] = search.trim();
    }

    // Execute Request
    final res = await _api.getJson("/items/$_dpCollection", query: query);
    final List data = (res["data"] as List?) ?? [];

    // Calculate Meta
    int total = data.length;
    if (res["meta"] is Map) {
      total = _asInt(res["meta"]["total_count"]) ?? total;
    }

    // Optimization: Collect IDs for bulk lookup to avoid N+1 problem
    final branchIds = <int>{};
    final driverIds = <int>{};

    final rawItems = data.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList();

    for (final row in rawItems) {
      final bid = _asInt(row["branch_id"]);
      if (bid != null) branchIds.add(bid);

      final did = _asInt(row["driver_id"]);
      if (did != null) driverIds.add(did);
    }

    // Fetch Lookups (Parallel execution for speed)
    final results = await Future.wait([
      _fetchBranches(branchIds.toList()),
      _fetchDrivers(driverIds.toList()),
    ]);
    
    final branchMap = results[0];
    final driverMap = results[1];

    // Map to Domain Models
    final items = rawItems.map((row) {
      final bid = _asInt(row["branch_id"]) ?? 0;
      final did = _asInt(row["driver_id"]) ?? 0;

      return DispatchPlanHeader(
        dispatchId: _asInt(row["dispatch_id"]) ?? 0,
        dispatchNo: row["dispatch_no"]?.toString() ?? "",
        status: _parseStatus(row["status"]?.toString()),
        createdAt: DateTime.tryParse(row["created_at"]?.toString() ?? "") ?? DateTime.now(),
        dispatchDate: DateTime.tryParse(row["dispatch_date"]?.toString() ?? "") ?? DateTime.now(),
        totalAmount: double.tryParse(row["total_amount"]?.toString() ?? "0") ?? 0.0,
        remarks: row["remarks"]?.toString() ?? "",
        branchId: bid,
        driverId: did,
        branchName: branchMap[bid] ?? "Unknown Branch",
        driverName: driverMap[did] ?? "Unassigned",
      );
    }).toList();

    return PagedResult(items: items, total: total, limit: limit, offset: offset);
  }

  /// Dashboard Badge Count
  Future<int> fetchPendingDispatchCount() async {
    try {
      final res = await _api.getJson(
        "/items/$_dpCollection",
        query: {
          "aggregate[count]": "*",
          "filter[status][_eq]": "Pending",
        },
      );
      final data = res["data"] as List?;
      if (data != null && data.isNotEmpty) {
        return _asInt(data.first["count"]) ?? 0;
      }
    } catch (_) {
      // Fail silently for badge counts
    }
    return 0;
  }

  // =============================
  // DETAILS FLOW
  // =============================

  Future<List<DispatchPlanItem>> fetchDispatchPlanItems(int dispatchId) async {
    // Fetches the items linked to this dispatch plan. 
    // Uses deep fetching (product_id.*) to get product names.
    final res = await _api.getJson(
      "/items/$_dpDetailsCollection",
      query: {
        "filter[dispatch_id][_eq]": dispatchId,
        "fields": "id,quantity,unit,product_id.product_id,product_id.product_name",
      },
    );

    final List data = (res["data"] as List?) ?? [];
    
    return data.map((row) {
      final map = row as Map;
      final prod = map["product_id"] as Map? ?? {};

      return DispatchPlanItem(
        id: _asInt(map["id"]) ?? 0,
        productId: _asInt(prod["product_id"]) ?? 0,
        productName: prod["product_name"]?.toString() ?? "Unknown Product",
        quantity: double.tryParse(map["quantity"]?.toString() ?? "0") ?? 0.0,
        unit: map["unit"]?.toString(),
      );
    }).toList();
  }

  // =============================
  // APPROVE FLOW (Atomic Transaction)
  // =============================

  Future<ApproveResult> approveDispatchPlan({
    required int dispatchId,
    required String dispatchNo,
    required int createdBy,
  }) async {
    // 1. Idempotency Check: Prevent duplicate approvals
    final existing = await _findExistingConsolidatorLink(dispatchNo);
    if (existing != null) {
      await _updateDispatchStatus(dispatchId, "Approved");
      return existing;
    }

    // 2. Increment Global Counter (pick_list_no)
    // This is critical logic; we must get the next number correctly.
    final nextDispatchNo = await _allocateNextDispatchNumber();
    final consolidatorNo = _formatCldtst(nextDispatchNo);

    // 3. Create Consolidator Header
    final consolidatorCreate = await _api.postJson(
      "/items/consolidator",
      body: {
        "consolidator_no": consolidatorNo,
        "status": _consolidatorStatusPending,
        "created_by": createdBy,
        "checked_by": null,
      },
    );

    final consolidatorId = _asInt(consolidatorCreate["data"]?["id"]);
    if (consolidatorId == null) {
      throw Exception("Failed to create consolidator header (no ID returned).");
    }

    try {
      // 4. Create Link (Bridge Table)
      await _api.postJson(
        "/items/consolidator_dispatches",
        body: {
          "consolidator_id": consolidatorId,
          "dispatch_no": dispatchNo
        },
      );

      // 5. Populate Consolidator Details
      // We fetch the items from the plan and move them to the consolidator
      // so the warehouse team sees them as "To Pick".
      final planItems = await fetchDispatchPlanItems(dispatchId);
      
      if (planItems.isNotEmpty) {
        final detailsPayload = planItems.map((item) {
          return {
            "consolidator_id": consolidatorId,
            "product_id": item.productId,
            "ordered_quantity": item.quantity,
            "picked_quantity": 0,
            "applied_quantity": 0,
            "picked_by": null,
            "picked_at": null,
          };
        }).toList();

        try {
          // Attempt Bulk Insert
          await _api.postJson("/items/consolidator_details", body: {"data": detailsPayload});
        } catch (e) {
          // Fallback: One-by-one insert if bulk fails
          print("Bulk insert failed. Retrying individually: $e");
          for (final payload in detailsPayload) {
             try {
               await _api.postJson("/items/consolidator_details", body: payload);
             } catch (_) {}
          }
        }
      }

      // 6. Finalize: Update Dispatch Status
      await _updateDispatchStatus(dispatchId, "Approved");
      
      return ApproveResult(
        consolidatorId: consolidatorId,
        consolidatorNo: consolidatorNo
      );

    } catch (e) {
      // ROLLBACK STRATEGY: 
      // If the linking or detail population fails, we must delete the 
      // 'consolidator' record we just made to prevent orphaned data.
      await _safeCleanupOrphans(
        consolidatorId: consolidatorId, 
        dispatchNo: dispatchNo
      );
      rethrow;
    }
  }

  // =============================
  // HELPERS
  // =============================

  DispatchStatus _parseStatus(String? s) {
    if (s == null) return DispatchStatus.pending;
    return DispatchStatus.values.firstWhere(
      (e) => e.label.toLowerCase() == s.toLowerCase(),
      orElse: () => DispatchStatus.pending,
    );
  }

  Future<Map<int, String>> _fetchBranches(List<int> ids) async {
    if (ids.isEmpty) return {};
    final res = await _api.getJson(
      "/items/$_branchCollection",
      query: {"filter[id][_in]": ids.join(","), "fields": "id,branch_name", "limit": "-1"},
    );
    final data = (res["data"] as List?) ?? [];
    final out = <int, String>{};
    for (final r in data) {
      if (r is Map) {
        final id = _asInt(r["id"]);
        if (id != null) out[id] = r["branch_name"]?.toString() ?? "";
      }
    }
    return out;
  }

  Future<Map<int, String>> _fetchDrivers(List<int> ids) async {
    if (ids.isEmpty) return {};
    final res = await _api.getJson(
      "/items/$_userCollection",
      query: {
        "filter[user_id][_in]": ids.join(","),
        "fields": "user_id,user_fname,user_lname",
        "limit": "-1",
      },
    );
    final data = (res["data"] as List?) ?? [];
    final out = <int, String>{};
    for (final r in data) {
      if (r is Map) {
        final id = _asInt(r["user_id"]);
        if (id != null) {
          final f = r["user_fname"] ?? "";
          final l = r["user_lname"] ?? "";
          out[id] = "$f $l".trim();
        }
      }
    }
    return out;
  }

  Future<void> _updateDispatchStatus(int id, String status) async {
    await _api.patch("/items/$_dpCollection/$id", data: {"status": status});
  }

  Future<ApproveResult?> _findExistingConsolidatorLink(String dispatchNo) async {
    final res = await _api.getJson(
      "/items/consolidator_dispatches",
      query: {
        "limit": "1",
        "filter[dispatch_no][_eq]": dispatchNo,
        "fields": "id,dispatch_no,consolidator_id.id,consolidator_id.consolidator_no",
      },
    );

    final List data = (res["data"] as List?) ?? const [];
    if (data.isEmpty) return null;

    final row = Map<String, dynamic>.from(data.first as Map);
    final consObj = (row["consolidator_id"] as Map?)?.cast<String, dynamic>();

    final consId = _asInt(consObj?["id"] ?? row["consolidator_id"]);
    final consNo = (consObj?["consolidator_no"]?.toString() ?? "").trim();

    if (consId == null) return null;
    return ApproveResult(consolidatorId: consId, consolidatorNo: consNo);
  }

  Future<int> _allocateNextDispatchNumber() async {
    final row = await _getPickListRowWithFallbacks();
    final current = _asInt(row["consolidation_no_dispatch"]);
    
    if (current == null) {
      throw Exception("pick_list_no row is missing 'consolidation_no_dispatch'.");
    }

    final next = current + 1;
    await _api.patch(
      "/items/pick_list_no/$_pickListPk", 
      data: {"consolidation_no_dispatch": next}
    );

    return next;
  }

  Future<Map<String, dynamic>> _getPickListRowWithFallbacks() async {
    // Attempt 1: Get by ID
    try {
      final res = await _api.getJson(
        "/items/pick_list_no/$_pickListPk",
        query: {"fields": "pick_list_no,consolidation_no_dispatch"},
      );
      final data = (res["data"] as Map?)?.cast<String, dynamic>();
      if (data != null) return data;
    } catch (_) {}

    // Attempt 2: Get by Filter (Permission workaround)
    try {
      final res = await _api.getJson(
        "/items/pick_list_no",
        query: {
          "limit": "1",
          "filter[pick_list_no][_eq]": _pickListPk.toString(),
          "fields": "pick_list_no,consolidation_no_dispatch",
        },
      );
      final list = (res["data"] as List?) ?? const [];
      if (list.isNotEmpty) return Map<String, dynamic>.from(list.first as Map);
    } catch (_) {}

    throw Exception("Cannot read pick_list_no counters. Check API permissions.");
  }

  Future<void> _safeCleanupOrphans({
    required int consolidatorId,
    required String dispatchNo,
  }) async {
    // 1. Delete Link
    try {
      final res = await _api.getJson(
        "/items/consolidator_dispatches",
        query: {"filter[dispatch_no][_eq]": dispatchNo, "fields": "id"},
      );
      final list = (res["data"] as List?) ?? [];
      for (final item in list) {
        final id = _asInt(item["id"]);
        if (id != null) {
          await _api.deleteJson("/items/consolidator_dispatches/$id");
        }
      }
    } catch (_) {}

    // 2. Delete Details (If partial insert happened)
    try {
      final res = await _api.getJson(
         "/items/consolidator_details",
         query: {"filter[consolidator_id][_eq]": consolidatorId, "fields": "id"},
      );
      final list = (res["data"] as List?) ?? [];
      for (final item in list) {
        final id = _asInt(item["id"]);
         if (id != null) {
          await _api.deleteJson("/items/consolidator_details/$id");
        }
      }
    } catch(_) {}

    // 3. Delete Header
    try {
      await _api.deleteJson("/items/consolidator/$consolidatorId");
    } catch (_) {}
  }

  int? _asInt(Object? v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString());
  }
}