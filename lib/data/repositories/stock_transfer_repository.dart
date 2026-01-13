// lib/data/repositories/stock_transfer_repository.dart
// import "dart:math";
import "../../core/network/api_client.dart";

class StockTransferRepository {
  StockTransferRepository(this._api);

  final ApiClient _api;

  // =============================
  // CONFIG (ONLINE ONLY)
  // =============================

  static const String _stCollection = "stock_transfer";
  static const int _pickListPk = 15;

  static const String _stStatusForPicking = "For Picking";
  static const String _consolidatorStatusPending = "Picking";

  static String _formatCldtst(int no) =>
      "CLDTST-${no.toString().padLeft(5, "0")}";

  // =============================
  // PUBLIC: Fetch lines for UI
  // =============================

  Future<_FetchLinesResult> fetchAllStockTransferLines() async {
    final json = await _api.getJson(
      "/items/$_stCollection",
      query: {
        "limit": "-1",
        "sort": "-date_encoded",
        "fields":
            "id,order_no,status,remarks,ordered_quantity,received_quantity,date_requested,date_encoded,encoder_id,product_id,source_branch,target_branch",
      },
    );

    final List data = (json["data"] as List?) ?? const [];
    return _FetchLinesResult(
      collection: _stCollection,
      rows: data.cast<Map<String, dynamic>>(),
    );
  }

  Future<List<Map<String, dynamic>>> fetchUsersByIds(List<int> userIds) async {
    if (userIds.isEmpty) return const [];

    final ids = userIds.toSet().toList()..sort();
    final json = await _api.getJson(
      "/items/user",
      query: {
        "limit": "-1",
        "filter[user_id][_in]": ids.join(","),
        "fields": "user_id,user_fname,user_lname,is_deleted",
      },
    );

    final List data = (json["data"] as List?) ?? const [];
    return data.cast<Map<String, dynamic>>();
  }

  Future<List<Map<String, dynamic>>> fetchProductsByIds(
    List<int> productIds,
  ) async {
    if (productIds.isEmpty) return const [];

    final ids = productIds.toSet().toList()..sort();
    final json = await _api.getJson(
      "/items/products",
      query: {
        "limit": "-1",
        "filter[product_id][_in]": ids.join(","),
        "fields": "product_id,product_name",
      },
    );

    final List data = (json["data"] as List?) ?? const [];
    return data.cast<Map<String, dynamic>>();
  }

  Future<List<Map<String, dynamic>>> fetchBranchesByIds(
    List<int> branchIds,
  ) async {
    if (branchIds.isEmpty) return const [];

    final ids = branchIds.toSet().toList()..sort();
    final json = await _api.getJson(
      "/items/branches",
      query: {
        "limit": "-1",
        "filter[id][_in]": ids.join(","),
        "fields": "id,branch_name",
      },
    );

    final List data = (json["data"] as List?) ?? const [];
    return data.cast<Map<String, dynamic>>();
  }

  // =============================
  // PUBLIC: Approve flow (ONLINE)
  // =============================

  Future<ApproveResult> approveStockTransferAndCreateCldtst({
    required String stockTransferNo,
    required int createdBy,
  }) async {
    // 1) Idempotency check
    final existing = await _findExistingConsolidatorLink(stockTransferNo);
    if (existing != null) {
      await _setStockTransferStatus(stockTransferNo, _stStatusForPicking);
      return existing;
    }

    // 2) Load ST lines
    final stLinesJson = await _api.getJson(
      "/items/$_stCollection",
      query: {
        "limit": "-1",
        "filter[order_no][_eq]": stockTransferNo,
        "fields": "id,order_no,status,product_id,ordered_quantity",
      },
    );

    final List rawLines = (stLinesJson["data"] as List?) ?? const [];
    final lines = rawLines.cast<Map<String, dynamic>>();

    if (lines.isEmpty) {
      throw Exception(
        "No stock transfer lines found for order_no='$stockTransferNo'.",
      );
    }

    // Collect line ids (for Directus update multiple keys[])
    final stIds = <int>[];
    for (final r in lines) {
      final id = _asInt(r["id"]);
      if (id != null) stIds.add(id);
    }

    // 3) Group per product_id with summed ordered_quantity
    final grouped = <int, int>{};
    for (final r in lines) {
      final pid = _asInt(r["product_id"]);
      final qty = _asInt(r["ordered_quantity"]) ?? 0;
      if (pid == null) continue;
      grouped[pid] = (grouped[pid] ?? 0) + qty;
    }

    if (grouped.isEmpty) {
      throw Exception(
        "No valid product_id/ordered_quantity to consolidate for '$stockTransferNo'.",
      );
    }

    // 4) Allocate next numbers: ONLY increment these 2 fields on pick_list_no(15)
    final alloc = await _allocateNextPickListNumbers();
    final consolidatorNo = _formatCldtst(alloc.newStockTransferNo);

    // 5) Create consolidator header
    final consolidatorCreate = await _api.postJson(
      "/items/consolidator",
      body: {
        "consolidator_no": consolidatorNo,
        "status": _consolidatorStatusPending,
        "created_by": createdBy,
        "checked_by": null,
      },
    );

    final consolidator = (consolidatorCreate["data"] as Map?)
        ?.cast<String, dynamic>();
    if (consolidator == null) {
      throw Exception(
        "Failed to create consolidator header (no data returned).",
      );
    }

    final consolidatorId = _asInt(consolidator["id"]);
    if (consolidatorId == null) {
      throw Exception("Consolidator create returned no id.");
    }

    // 6) Create link row
    try {
      await _api.postJson(
        "/items/consolidator_stock_transfers",
        body: {
          "consolidator_id": consolidatorId,
          "stock_transfer_no": stockTransferNo,
        },
      );
    } catch (e) {
      await _safeCleanupOrphans(
        consolidatorId: consolidatorId,
        stockTransferNo: stockTransferNo,
      );
      final existing2 = await _findExistingConsolidatorLink(stockTransferNo);
      if (existing2 != null) return existing2;
      rethrow;
    }

    // 7) Create consolidator_details
    try {
      final detailsPayload = grouped.entries.map((e) {
        return {
          "consolidator_id": consolidatorId,
          "product_id": e.key,
          "ordered_quantity": e.value,
          "picked_quantity": 0,
          "picked_by": null,
          "picked_at": null,
          "applied_quantity": 0,
        };
      }).toList();

      await _api.postJson(
        "/items/consolidator_details",
        body: {"data": detailsPayload},
      );
    } catch (e) {
      // ignore: avoid_print
      print(
        "Bulk create consolidator_details failed. Falling back to per-row create. Error: $e",
      );

      try {
        for (final e2 in grouped.entries) {
          await _api.postJson(
            "/items/consolidator_details",
            body: {
              "consolidator_id": consolidatorId,
              "product_id": e2.key,
              "ordered_quantity": e2.value,
              "picked_quantity": 0,
              "picked_by": null,
              "picked_at": null,
              "applied_quantity": 0,
            },
          );
        }
      } catch (_) {
        await _safeCleanupOrphans(
          consolidatorId: consolidatorId,
          stockTransferNo: stockTransferNo,
        );
        rethrow;
      }
    }

    // 8) Update stock_transfer lines status
    if (stIds.isNotEmpty) {
      await _patchByKeys(_stCollection, stIds, {"status": _stStatusForPicking});
    }

    return ApproveResult(
      consolidatorId: consolidatorId,
      consolidatorNo: consolidatorNo,
    );
  }

  // =============================
  // INTERNALS
  // =============================

  Future<void> _patchByKeys(
    String collection,
    List<int> keys,
    Map<String, dynamic> fields,
  ) async {
    await _api.patch(
      "/items/$collection",
      data: {"keys": keys, "data": fields},
    );
  }

  Future<void> _setStockTransferStatus(String orderNo, String newStatus) async {
    final res = await _api.getJson(
      "/items/$_stCollection",
      query: {"limit": "-1", "filter[order_no][_eq]": orderNo, "fields": "id"},
    );

    final List data = (res["data"] as List?) ?? const [];
    final keys = <int>[];
    for (final row in data.cast<Map<String, dynamic>>()) {
      final id = _asInt(row["id"]);
      if (id != null) keys.add(id);
    }

    if (keys.isEmpty) return;
    await _patchByKeys(_stCollection, keys, {"status": newStatus});
  }

  Future<ApproveResult?> _findExistingConsolidatorLink(
    String stockTransferNo,
  ) async {
    final res = await _api.getJson(
      "/items/consolidator_stock_transfers",
      query: {
        "limit": "1",
        "filter[stock_transfer_no][_eq]": stockTransferNo,
        "fields":
            "id,stock_transfer_no,consolidator_id,consolidator_id.id,consolidator_id.consolidator_no",
      },
    );

    final List data = (res["data"] as List?) ?? const [];
    if (data.isEmpty) return null;

    final row = (data.first as Map).cast<String, dynamic>();
    final consObj = (row["consolidator_id"] as Map?)?.cast<String, dynamic>();

    final consId = _asInt(consObj?["id"] ?? row["consolidator_id"]);
    final consNo = (consObj?["consolidator_no"]?.toString() ?? "").trim();

    if (consId == null) return null;
    return ApproveResult(
      consolidatorId: consId,
      consolidatorNo: consNo.isEmpty ? null : consNo,
    );
  }

  /// Reads pick_list_no row (PK=15) using multiple strategies.
  /// Then updates ONLY:
  /// - consolidation_no_stock_transfer
  /// - consolidation_no_dispatch
  ///
  /// It does NOT modify pick_list_no.
  Future<_PickListAlloc> _allocateNextPickListNumbers() async {
    // 1) Read the row (must know current values to increment)
    final row = await _getPickListRowWithFallbacks();

    final oldSt = _asInt(row["consolidation_no_stock_transfer"]);
    final oldDp = _asInt(row["consolidation_no_dispatch"]);

    if (oldSt == null || oldDp == null) {
      throw Exception(
        "pick_list_no row is missing numeric counters. "
        "consolidation_no_stock_transfer='$oldSt', consolidation_no_dispatch='$oldDp'",
      );
    }

    final newSt = oldSt + 1;
    final newDp = oldDp + 1;

    // 2) Update ONLY the two fields (keep pick_list_no = 15)
    await _api.patch(
      "/items/pick_list_no/$_pickListPk",
      data: {
        "consolidation_no_stock_transfer": newSt,
        "consolidation_no_dispatch": newDp,
      },
    );

    return _PickListAlloc(
      oldStockTransferNo: oldSt,
      newStockTransferNo: newSt,
      oldDispatchNo: oldDp,
      newDispatchNo: newDp,
    );
  }

  /// Tries:
  /// 1) GET /items/pick_list_no/15
  /// 2) GET /items/pick_list_no?filter[pick_list_no][_eq]=15&limit=1
  /// 3) GET /items/pick_list_no?limit=1 (if only one row)
  Future<Map<String, dynamic>> _getPickListRowWithFallbacks() async {
    // Attempt 1: by id
    try {
      final res = await _api.getJson(
        "/items/pick_list_no/$_pickListPk",
        query: {
          "fields":
              "pick_list_no,consolidation_no_stock_transfer,consolidation_no_dispatch",
        },
      );
      final data = (res["data"] as Map?)?.cast<String, dynamic>();
      if (data != null) return data;
    } catch (e) {
      // ignore: avoid_print
      print("pick_list_no read by id failed. Trying filtered list. Error: $e");
    }

    // Attempt 2: filtered list
    try {
      final res = await _api.getJson(
        "/items/pick_list_no",
        query: {
          "limit": "1",
          "filter[pick_list_no][_eq]": _pickListPk.toString(),
          "fields":
              "pick_list_no,consolidation_no_stock_transfer,consolidation_no_dispatch",
        },
      );
      final list = (res["data"] as List?) ?? const [];
      if (list.isNotEmpty) {
        return Map<String, dynamic>.from(list.first as Map);
      }
    } catch (e) {
      // ignore: avoid_print
      print(
        "pick_list_no filtered list read failed. Trying limit=1. Error: $e",
      );
    }

    // Attempt 3: limit=1 (only if table really has one row)
    try {
      final res = await _api.getJson(
        "/items/pick_list_no",
        query: {
          "limit": "1",
          "fields":
              "pick_list_no,consolidation_no_stock_transfer,consolidation_no_dispatch",
        },
      );
      final list = (res["data"] as List?) ?? const [];
      if (list.isNotEmpty) {
        final row = Map<String, dynamic>.from(list.first as Map);
        // Ensure it is our pick_list_no=15
        final pk = _asInt(row["pick_list_no"]);
        if (pk == _pickListPk) return row;
      }
    } catch (e) {
      // ignore: avoid_print
      print("pick_list_no limit=1 read failed. Error: $e");
    }

    // If we reach here, permissions are the real problem.
    throw Exception(
      "403 on pick_list_no. Your app (Public role / no token) cannot READ pick_list_no, "
      "so it cannot increment counters. Fix in Directus: grant READ (and UPDATE) permission "
      "to the role used by the app for collection 'pick_list_no' (or use a token).",
    );
  }

  Future<void> _safeCleanupOrphans({
    required int consolidatorId,
    required String stockTransferNo,
  }) async {
    try {
      await _safeDeleteConsolidatorDetails(consolidatorId);
    } catch (_) {}
    try {
      await _safeDeleteConsolidatorLink(stockTransferNo);
    } catch (_) {}
    try {
      await _api.deleteJson("/items/consolidator/$consolidatorId");
    } catch (_) {}
  }


    /// Count "Requested" Stock Transfers by header (order_no).
  /// A header is counted only if ALL its line rows are in Requested status.
  Future<int> fetchRequestedHeaderCount() async {
    final json = await _api.getJson(
      "/items/$_stCollection",
      query: {
        "limit": "-1",
        "fields": "id,order_no,status",
        "sort": "-date_encoded",
      },
    );

    final List data = (json["data"] as List?) ?? const [];

    // order_no -> list of statuses
    final Map<String, List<String>> statusesByOrder = {};

    for (final item in data) {
      if (item is! Map) continue;
      final m = item.cast<String, dynamic>();

      final orderNo = (m["order_no"]?.toString() ?? "").trim();
      if (orderNo.isEmpty) continue;

      final status = (m["status"]?.toString() ?? "").trim().toLowerCase();
      (statusesByOrder[orderNo] ??= []).add(status);
    }

    int count = 0;
    statusesByOrder.forEach((orderNo, statuses) {
      if (statuses.isEmpty) return;
      final allRequested = statuses.every((s) => s.replaceAll(" ", "") == "requested");
      if (allRequested) count++;
    });

    return count;
  }


  Future<void> _safeDeleteConsolidatorDetails(int consolidatorId) async {
    final res = await _api.getJson(
      "/items/consolidator_details",
      query: {
        "limit": "-1",
        "filter[consolidator_id][_eq]": consolidatorId,
        "fields": "id",
      },
    );

    final List data = (res["data"] as List?) ?? const [];
    for (final row in data.cast<Map<String, dynamic>>()) {
      final id = _asInt(row["id"]);
      if (id == null) continue;
      try {
        await _api.deleteJson("/items/consolidator_details/$id");
      } catch (_) {}
    }
  }

  Future<void> _safeDeleteConsolidatorLink(String stockTransferNo) async {
    final res = await _api.getJson(
      "/items/consolidator_stock_transfers",
      query: {
        "limit": "-1",
        "filter[stock_transfer_no][_eq]": stockTransferNo,
        "fields": "id",
      },
    );

    final List data = (res["data"] as List?) ?? const [];
    for (final row in data.cast<Map<String, dynamic>>()) {
      final id = _asInt(row["id"]);
      if (id == null) continue;
      try {
        await _api.deleteJson("/items/consolidator_stock_transfers/$id");
      } catch (_) {}
    }
  }

  int? _asInt(Object? v) {
    if (v == null) return null;
    if (v is Map) {
      final m = v.cast<String, dynamic>();
      return _asInt(
        m["id"] ?? m["product_id"] ?? m["user_id"] ?? m["pick_list_no"],
      );
    }
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString());
  }
}

class _FetchLinesResult {
  final String collection;
  final List<Map<String, dynamic>> rows;
  const _FetchLinesResult({required this.collection, required this.rows});
}

class _PickListAlloc {
  final int oldStockTransferNo;
  final int newStockTransferNo;
  final int oldDispatchNo;
  final int newDispatchNo;

  const _PickListAlloc({
    required this.oldStockTransferNo,
    required this.newStockTransferNo,
    required this.oldDispatchNo,
    required this.newDispatchNo,
  });
}

class ApproveResult {
  final int consolidatorId;
  final String? consolidatorNo;
  const ApproveResult({
    required this.consolidatorId,
    required this.consolidatorNo,
  });
}
