// lib/data/repositories/stock_transfer_repository.dart
import "../../core/network/api_client.dart";

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

/// Header-paged result (order_no based), but implemented safely on top of
/// line paging (because Directus does not provide DISTINCT order_no out-of-the-box).
class StockTransferHeaderPage {
  /// All line rows (raw maps) for the returned headers.
  final List<Map<String, dynamic>> lines;

  /// Returned header keys in stable order (order_no).
  final List<String> orderNos;

  /// Next cursor (line offset) to continue scanning.
  final int nextLineOffset;

  /// Whether more candidate lines exist server-side.
  final bool hasMore;

  const StockTransferHeaderPage({
    required this.lines,
    required this.orderNos,
    required this.nextLineOffset,
    required this.hasMore,
  });
}

class StockTransferRepository {
  StockTransferRepository(this._api);

  final ApiClient _api;

  // =============================
  // CONFIG
  // =============================

  static const String _stCollection = "stock_transfer";
  static const int _pickListPk = 15;

  static const String _stStatusForPicking = "For Picking";
  static const String _consolidatorStatusPending = "Picking";

  static String _formatCldtst(int no) => "CLDTST-${no.toString().padLeft(5, "0")}";

  static const String _userCollection = "user";
  static const String _productsCollection = "products";
  static const String _branchesCollection = "branches";

  static const String _stFields =
      "id,order_no,status,remarks,ordered_quantity,received_quantity,"
      "date_requested,date_encoded,encoder_id,product_id,source_branch,target_branch";

  // =============================
  // PUBLIC: LINE-PAGED (kept; used internally)
  // =============================

  /// Line-paged fetch with:
  /// - status filter (exact match: "Requested", "For Picking", ...)
  /// - server-side search (order_no, remarks + lookup by product/branch/user names)
  /// Uses meta.total_count for accurate hasMore/total (LINE total).
  Future<PagedResult<Map<String, dynamic>>> fetchStockTransferLinesPaged({
    required int limit,
    required int offset,
    String? search,
    String? status,
  }) async {
    final query = <String, String>{
      "limit": limit.toString(),
      "offset": offset.toString(),
      "sort": "-date_encoded,-id",
      "fields": _stFields,
      "meta": "total_count",
    };

    final st = (status ?? "").trim();
    if (st.isNotEmpty) {
      query["filter[status][_eq]"] = st;
    }

    final q = (search ?? "").trim();
    if (q.isNotEmpty) {
      await _applyServerSideSearch(query, q);
    }

    final json = await _api.getJson("/items/$_stCollection", query: query);

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

  // =============================
  // PUBLIC: HEADER-PAGED (order_no based) — FIXES “5 headers only” bug
  // =============================

  /// Fetch headers (order_no) in pages of [headerLimit] while still using Directus line paging.
  ///
  /// How it works:
  /// 1) Scan line pages until we collect enough DISTINCT order_no candidates
  /// 2) Fetch ALL lines for those order_no in one query (so header status is correct)
  /// 3) Apply header-level filtering rules:
  ///    - If status == "Requested": keep only headers where ALL lines are Requested
  ///    - Otherwise if status is a specific status: keep headers where ANY line matches that status
  ///    - If status is null/empty: keep all headers
  ///
  /// This eliminates the collapsed paging issue where 40 lines become only 5 headers.
  Future<StockTransferHeaderPage> fetchStockTransferHeadersPaged({
    required int headerLimit,
    required int lineOffsetCursor,
    String? search,
    String? status,
  }) async {
    final wantedStatus = (status ?? "").trim();
    final effectiveStatus = wantedStatus.isEmpty ? null : wantedStatus;

    // We scan using line pages. Larger scan chunk reduces round-trips.
    // Choose something that balances payload and latency.
    const int scanChunk = 160;

    final collectedOrderNos = <String>[];
    final collectedSet = <String>{};

    var cursor = lineOffsetCursor;
    var hasMoreLines = true;

    // We may need multiple scans to fill headerLimit with VALID headers
    // after applying header-level rules (especially for Requested).
    final validOrderNos = <String>[];
    final validSet = <String>{};
    final allLinesForValidHeaders = <Map<String, dynamic>>[];

    // Safety breaker to avoid infinite loops if data is pathological.
    int safetyIters = 0;

    while (validOrderNos.length < headerLimit && hasMoreLines && safetyIters < 25) {
      safetyIters++;

      // Step 1: scan candidate lines (use status filter for speed when not searching)
      // If searching, we do NOT force status filter so search behaves like Sales Order.
      final scanStatus = (search ?? "").trim().isNotEmpty ? null : effectiveStatus;

      final page = await fetchStockTransferLinesPaged(
        limit: scanChunk,
        offset: cursor,
        search: (search ?? "").trim().isNotEmpty ? search : null,
        status: scanStatus,
      );

      cursor += page.items.length;
      hasMoreLines = page.hasMore;

      if (page.items.isEmpty) break;

      // Collect distinct order_nos from scanned lines
      for (final row in page.items) {
        final orderNo = (row["order_no"]?.toString() ?? "").trim();
        if (orderNo.isEmpty) continue;
        if (collectedSet.add(orderNo)) {
          collectedOrderNos.add(orderNo);
        }
      }

      if (collectedOrderNos.isEmpty) continue;

      // Step 2: take a slice of candidates we haven't validated yet
      // We validate in small batches so we can continue scanning if many fail.
      final remainingNeeded = headerLimit - validOrderNos.length;
      final batch = <String>[];

      for (final o in collectedOrderNos) {
        if (validSet.contains(o)) continue;
        if (batch.length >= (remainingNeeded * 2).clamp(10, 80)) break;
        batch.add(o);
      }

      if (batch.isEmpty) continue;

      // Fetch ALL lines for these order_nos (no status filter here; we need full truth)
      final allLines = await _fetchLinesByOrderNos(batch);

      // Group by header
      final byOrder = <String, List<Map<String, dynamic>>>{};
      for (final r in allLines) {
        final on = (r["order_no"]?.toString() ?? "").trim();
        if (on.isEmpty) continue;
        (byOrder[on] ??= []).add(r);
      }

      // Step 3: header-level filter
      for (final orderNo in batch) {
        if (validOrderNos.length >= headerLimit) break;

        final items = byOrder[orderNo] ?? const <Map<String, dynamic>>[];
        if (items.isEmpty) continue;

        final include = _headerMatchesStatus(items, effectiveStatus);

        if (include && validSet.add(orderNo)) {
          validOrderNos.add(orderNo);
          allLinesForValidHeaders.addAll(items);
        }
      }
    }

    return StockTransferHeaderPage(
      lines: allLinesForValidHeaders,
      orderNos: validOrderNos,
      nextLineOffset: cursor,
      hasMore: hasMoreLines,
    );
  }

  bool _headerMatchesStatus(List<Map<String, dynamic>> lines, String? status) {
    final s = (status ?? "").trim();
    if (s.isEmpty) return true;

    String norm(String? v) => (v ?? "").trim().toLowerCase().replaceAll(" ", "");
    final wanted = norm(s);

    if (wanted == "requested") {
      // Strict: for approvals queue, Requested means ALL lines are requested.
      return lines.isNotEmpty && lines.every((r) => norm(r["status"]?.toString()) == "requested");
    }

    // For other statuses, show header if ANY line is in that status (keeps mixed headers visible).
    return lines.any((r) => norm(r["status"]?.toString()) == wanted);
  }

  Future<List<Map<String, dynamic>>> _fetchLinesByOrderNos(List<String> orderNos) async {
    final list = orderNos.map((e) => e.trim()).where((e) => e.isNotEmpty).toSet().toList();
    if (list.isEmpty) return const [];

    // Directus _in works with comma-separated values for string fields.
    final json = await _api.getJson(
      "/items/$_stCollection",
      query: {
        "limit": "-1",
        "sort": "-date_encoded,-id",
        "fields": _stFields,
        "filter[order_no][_in]": list.join(","),
      },
    );

    final List raw = (json["data"] as List?) ?? const [];
    return raw.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList();
  }

  // =============================
  // LOOKUPS (unchanged)
  // =============================

  Future<List<Map<String, dynamic>>> fetchUsersByIds(List<int> userIds) async {
    if (userIds.isEmpty) return const [];

    final ids = userIds.where((e) => e > 0).toSet().toList()..sort();
    final json = await _api.getJson(
      "/items/$_userCollection",
      query: {
        "limit": "-1",
        "filter[user_id][_in]": ids.join(","),
        "fields": "user_id,user_fname,user_lname,is_deleted",
      },
    );

    final List data = (json["data"] as List?) ?? const [];
    return data.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList();
  }

  Future<List<Map<String, dynamic>>> fetchProductsByIds(List<int> productIds) async {
    if (productIds.isEmpty) return const [];

    final ids = productIds.where((e) => e > 0).toSet().toList()..sort();
    final json = await _api.getJson(
      "/items/$_productsCollection",
      query: {
        "limit": "-1",
        "filter[product_id][_in]": ids.join(","),
        "fields": "product_id,product_name",
      },
    );

    final List data = (json["data"] as List?) ?? const [];
    return data.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList();
  }

  Future<List<Map<String, dynamic>>> fetchBranchesByIds(List<int> branchIds) async {
    if (branchIds.isEmpty) return const [];

    final ids = branchIds.where((e) => e > 0).toSet().toList()..sort();
    final json = await _api.getJson(
      "/items/$_branchesCollection",
      query: {
        "limit": "-1",
        "filter[id][_in]": ids.join(","),
        "fields": "id,branch_name",
      },
    );

    final List data = (json["data"] as List?) ?? const [];
    return data.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList();
  }

  // =============================
  // APPROVE FLOW (UNCHANGED)
  // =============================

  Future<ApproveResult> approveStockTransferAndCreateCldtst({
    required String stockTransferNo,
    required int createdBy,
  }) async {
    final existing = await _findExistingConsolidatorLink(stockTransferNo);
    if (existing != null) {
      await _setStockTransferStatus(stockTransferNo, _stStatusForPicking);
      return existing;
    }

    final stLinesJson = await _api.getJson(
      "/items/$_stCollection",
      query: {
        "limit": "-1",
        "filter[order_no][_eq]": stockTransferNo,
        "fields": "id,order_no,status,product_id,ordered_quantity",
      },
    );

    final List rawLines = (stLinesJson["data"] as List?) ?? const [];
    final lines = rawLines.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList();

    if (lines.isEmpty) {
      throw Exception("No stock transfer lines found for order_no='$stockTransferNo'.");
    }

    final stIds = <int>[];
    for (final r in lines) {
      final id = _asInt(r["id"]);
      if (id != null) stIds.add(id);
    }

    final grouped = <int, int>{};
    for (final r in lines) {
      final pid = _asInt(r["product_id"]);
      final qty = _asInt(r["ordered_quantity"]) ?? 0;
      if (pid == null) continue;
      grouped[pid] = (grouped[pid] ?? 0) + qty;
    }

    if (grouped.isEmpty) {
      throw Exception("No valid product_id/ordered_quantity to consolidate for '$stockTransferNo'.");
    }

    final alloc = await _allocateNextPickListNumbers();
    final consolidatorNo = _formatCldtst(alloc.newStockTransferNo);

    final consolidatorCreate = await _api.postJson(
      "/items/consolidator",
      body: {
        "consolidator_no": consolidatorNo,
        "status": _consolidatorStatusPending,
        "created_by": createdBy,
        "checked_by": null,
      },
    );

    final consolidator = (consolidatorCreate["data"] as Map?)?.cast<String, dynamic>();
    if (consolidator == null) {
      throw Exception("Failed to create consolidator header (no data returned).");
    }

    final consolidatorId = _asInt(consolidator["id"]);
    if (consolidatorId == null) {
      throw Exception("Consolidator create returned no id.");
    }

    try {
      await _api.postJson(
        "/items/consolidator_stock_transfers",
        body: {
          "consolidator_id": consolidatorId,
          "stock_transfer_no": stockTransferNo,
        },
      );
    } catch (e) {
      await _safeCleanupOrphans(consolidatorId: consolidatorId, stockTransferNo: stockTransferNo);
      final existing2 = await _findExistingConsolidatorLink(stockTransferNo);
      if (existing2 != null) return existing2;
      rethrow;
    }

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

      await _api.postJson("/items/consolidator_details", body: {"data": detailsPayload});
    } catch (e) {
      // ignore: avoid_print
      print("Bulk create consolidator_details failed. Fallback to per-row. Error: $e");
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
        await _safeCleanupOrphans(consolidatorId: consolidatorId, stockTransferNo: stockTransferNo);
        rethrow;
      }
    }

    if (stIds.isNotEmpty) {
      await _patchByKeys(_stCollection, stIds, {"status": _stStatusForPicking});
    }

    return ApproveResult(consolidatorId: consolidatorId, consolidatorNo: consolidatorNo);
  }

  // =============================
  // COUNT: Requested headers (used by Approval badge)
  // =============================

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
    statusesByOrder.forEach((_, statuses) {
      if (statuses.isEmpty) return;
      final allRequested = statuses.every((s) => s.replaceAll(" ", "") == "requested");
      if (allRequested) count++;
    });

    return count;
  }

  // =============================
  // SERVER-SIDE SEARCH (unchanged)
  // =============================

  Future<void> _applyServerSideSearch(Map<String, String> query, String q) async {
    int i = 0;

    void addOr(String field, String op, String value) {
      query["filter[_or][$i][$field][$op]"] = value;
      i++;
    }

    addOr("order_no", "_icontains", q);
    addOr("remarks", "_icontains", q);

    final asInt = int.tryParse(q);
    if (asInt != null) {
      addOr("id", "_eq", q);
      addOr("product_id", "_eq", q);
      addOr("encoder_id", "_eq", q);
      addOr("source_branch", "_eq", q);
      addOr("target_branch", "_eq", q);
    }

    final hasLetters = RegExp(r"[A-Za-z]").hasMatch(q);
    if (!hasLetters) return;

    final results = await Future.wait([
      _searchProductIdsByName(q, limit: 60),
      _searchBranchIdsByName(q, limit: 60),
      _searchUserIdsByName(q, limit: 60),
    ]);

    final productIds = results[0];
    final branchIds = results[1];
    final userIds = results[2];

    if (productIds.isNotEmpty) addOr("product_id", "_in", productIds.join(","));

    if (branchIds.isNotEmpty) {
      addOr("source_branch", "_in", branchIds.join(","));
      addOr("target_branch", "_in", branchIds.join(","));
    }

    if (userIds.isNotEmpty) {
      addOr("encoder_id", "_in", userIds.join(","));
    }
  }

  Future<List<int>> _searchProductIdsByName(String q, {int limit = 60}) async {
    final s = q.trim();
    if (s.isEmpty) return const [];

    final json = await _api.getJson(
      "/items/$_productsCollection",
      query: {
        "limit": limit.toString(),
        "fields": "product_id",
        "filter[product_name][_icontains]": s,
      },
    );

    final List data = (json["data"] as List?) ?? const [];
    final ids = <int>[];
    for (final row in data) {
      if (row is! Map) continue;
      final id = _asInt(row["product_id"]) ?? 0;
      if (id > 0) ids.add(id);
    }
    return ids.toSet().toList()..sort();
  }

  Future<List<int>> _searchBranchIdsByName(String q, {int limit = 60}) async {
    final s = q.trim();
    if (s.isEmpty) return const [];

    final json = await _api.getJson(
      "/items/$_branchesCollection",
      query: {
        "limit": limit.toString(),
        "fields": "id",
        "filter[branch_name][_icontains]": s,
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
    for (final row in data) {
      if (row is! Map) continue;
      final id = _asInt(row["user_id"]) ?? 0;
      if (id > 0) ids.add(id);
    }
    return ids.toSet().toList()..sort();
  }

  // =============================
  // INTERNALS (unchanged)
  // =============================

  Future<void> _patchByKeys(String collection, List<int> keys, Map<String, dynamic> fields) async {
    await _api.patch("/items/$collection", data: {"keys": keys, "data": fields});
  }

  Future<void> _setStockTransferStatus(String orderNo, String newStatus) async {
    final res = await _api.getJson(
      "/items/$_stCollection",
      query: {"limit": "-1", "filter[order_no][_eq]": orderNo, "fields": "id"},
    );

    final List data = (res["data"] as List?) ?? const [];
    final keys = <int>[];
    for (final row in data.whereType<Map>()) {
      final id = _asInt(row["id"]);
      if (id != null) keys.add(id);
    }

    if (keys.isEmpty) return;
    await _patchByKeys(_stCollection, keys, {"status": newStatus});
  }

  Future<ApproveResult?> _findExistingConsolidatorLink(String stockTransferNo) async {
    final res = await _api.getJson(
      "/items/consolidator_stock_transfers",
      query: {
        "limit": "1",
        "filter[stock_transfer_no][_eq]": stockTransferNo,
        "fields": "id,stock_transfer_no,consolidator_id,consolidator_id.id,consolidator_id.consolidator_no",
      },
    );

    final List data = (res["data"] as List?) ?? const [];
    if (data.isEmpty) return null;

    final row = Map<String, dynamic>.from(data.first as Map);
    final consObj = (row["consolidator_id"] as Map?)?.cast<String, dynamic>();

    final consId = _asInt(consObj?["id"] ?? row["consolidator_id"]);
    final consNo = (consObj?["consolidator_no"]?.toString() ?? "").trim();

    if (consId == null) return null;
    return ApproveResult(consolidatorId: consId, consolidatorNo: consNo.isEmpty ? null : consNo);
  }

  Future<_PickListAlloc> _allocateNextPickListNumbers() async {
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

  Future<Map<String, dynamic>> _getPickListRowWithFallbacks() async {
    try {
      final res = await _api.getJson(
        "/items/pick_list_no/$_pickListPk",
        query: {"fields": "pick_list_no,consolidation_no_stock_transfer,consolidation_no_dispatch"},
      );
      final data = (res["data"] as Map?)?.cast<String, dynamic>();
      if (data != null) return data;
    } catch (e) {
      // ignore: avoid_print
      print("pick_list_no read by id failed. Trying filtered list. Error: $e");
    }

    try {
      final res = await _api.getJson(
        "/items/pick_list_no",
        query: {
          "limit": "1",
          "filter[pick_list_no][_eq]": _pickListPk.toString(),
          "fields": "pick_list_no,consolidation_no_stock_transfer,consolidation_no_dispatch",
        },
      );
      final list = (res["data"] as List?) ?? const [];
      if (list.isNotEmpty) {
        return Map<String, dynamic>.from(list.first as Map);
      }
    } catch (e) {
      // ignore: avoid_print
      print("pick_list_no filtered list read failed. Trying limit=1. Error: $e");
    }

    try {
      final res = await _api.getJson(
        "/items/pick_list_no",
        query: {
          "limit": "1",
          "fields": "pick_list_no,consolidation_no_stock_transfer,consolidation_no_dispatch",
        },
      );
      final list = (res["data"] as List?) ?? const [];
      if (list.isNotEmpty) {
        final row = Map<String, dynamic>.from(list.first as Map);
        final pk = _asInt(row["pick_list_no"]);
        if (pk == _pickListPk) return row;
      }
    } catch (e) {
      // ignore: avoid_print
      print("pick_list_no limit=1 read failed. Error: $e");
    }

    throw Exception(
      "403 on pick_list_no. Your app cannot READ pick_list_no to increment counters. "
      "Fix Directus permissions for 'pick_list_no' (READ + UPDATE) for the role used by the app.",
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
    for (final row in data.whereType<Map>()) {
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
    for (final row in data.whereType<Map>()) {
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
      return _asInt(m["id"] ?? m["product_id"] ?? m["user_id"] ?? m["pick_list_no"]);
    }
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString());
  }
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
