import "package:flutter/material.dart";

import "../../core/network/api_client.dart";
import "../../modules/approvals/predispatch/predispatch_models.dart";

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

// ==============================================================================
// REPOSITORY
// ==============================================================================

class PredispatchRepository {
  PredispatchRepository(this._api);

  final ApiClient _api;

  // --- Configuration ---
  static const String _dpCollection = "dispatch_plan";
  static const String _dpDetailsCollection = "dispatch_plan_details";
  static const String _salesOrderCollection = "sales_order";
  static const String _branchCollection = "branches";
  static const String _userCollection = "user";
  static const String _customerCollection = "customer";

  // =============================
  // FETCH FLOW (List View)
  // =============================

  Future<PagedResult<PredispatchHeader>> fetchPredispatchPlansPaged({
    required int limit,
    required int offset,
    String? search,
    PredispatchStatus? status,
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
    } else {
      // Default to Pending for approvals
      query["filter[status][_eq]"] = "Pending";
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
    final dispatchIds = <int>{};

    final rawItems = data.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList();

    for (final row in rawItems) {
      final bid = _asInt(row["branch_id"]);
      if (bid != null) branchIds.add(bid);

      final did = _asInt(row["driver_id"]);
      if (did != null) driverIds.add(did);

      final did2 = _asInt(row["dispatch_id"]);
      if (did2 != null) dispatchIds.add(did2);
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
      final dispatchId = _asInt(row["dispatch_id"]) ?? 0;

      return PredispatchHeader(
        dispatchId: dispatchId,
        dispatchNo: row["dispatch_no"]?.toString() ?? "",
        status: _parseStatus(row["status"]?.toString()),
        createdAt: DateTime.tryParse(row["created_at"]?.toString() ?? "") ?? DateTime.now(),
        dispatchDate: DateTime.tryParse(row["dispatch_date"]?.toString() ?? "") ?? DateTime.now(),
        totalAmount: double.tryParse(row["total_amount"]?.toString() ?? "0") ?? 0.0,
        remarks: row["remarks"]?.toString() ?? "",
        branchId: bid,
        driverId: did,
        branchName: branchMap[bid],
        driverName: driverMap[did],
        salesOrders: [], // Lazy load this in the sheet to avoid 403 errors on list view
      );
    }).toList();

    return PagedResult(items: items, total: total, limit: limit, offset: offset);
  }

  /// Dashboard Badge Count
  Future<int> fetchPendingPredispatchCount() async {
    try {
      final res = await _api.getJson(
        "/items/$_dpCollection",
        query: {"aggregate[count]": "*", "filter[status][_eq]": "Pending"},
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

  /// Fetch sales orders for a specific dispatch plan (Lazy Load)
  Future<List<PredispatchSalesOrder>> fetchSalesOrders(int dispatchId) async {
    final map = await _fetchSalesOrders([dispatchId]);
    return map[dispatchId] ?? [];
  }

  /// Fetch sales orders specifically linked to a dispatch plan via dispatch_plan_details
  Future<List<PredispatchSalesOrder>> fetchLinkedSalesOrders(int dispatchId) async {
    final map = await _fetchSalesOrders([dispatchId]);
    return map[dispatchId] ?? [];
  }

  /// Fetch all sales orders for the branch of the dispatch plan
  Future<List<PredispatchSalesOrder>> fetchAllOrdersForDispatchCustomers(int dispatchId) async {
    try {
      // First, get the dispatch plan to get the branch_id
      final res = await _api.getJson(
        "/items/$_dpCollection/$dispatchId",
        query: {"fields": "branch_id"},
      );

      final dispatchData = res["data"];
      if (dispatchData is! Map) {
        return [];
      }

      final branchId = _asInt(dispatchData["branch_id"]);
      if (branchId == null) {
        return [];
      }

      // Fetch all orders for this branch
      final ordersRes = await _api.getJson(
        "/items/$_salesOrderCollection",
        query: {
          "filter[branch_id][_eq]": branchId.toString(),
          "fields": "order_id,id,order_no,customer_code,branch_id,allocated_amount,total_amount",
          "limit": "-1",
        },
      );

      final data = (ordersRes["data"] as List?) ?? [];

      // Collect customer codes for lookup
      final customerCodes = <String>{};

      for (final row in data) {
        if (row is Map) {
          final cc = row["customer_code"]?.toString();
          if (cc != null && cc.isNotEmpty) customerCodes.add(cc);
        }
      }

      // Fetch lookups
      final customersMap = await _fetchCustomersByCodes(customerCodes.toList());
      final branchesMap = await _fetchBranches([branchId]);

      // Map to domain models
      final orders = <PredispatchSalesOrder>[];
      for (final row in data) {
        if (row is Map) {
          final cCode = row["customer_code"]?.toString() ?? "";
          final cName = customersMap[cCode] ?? "Unknown Customer";

          final bName = branchesMap[branchId] ?? "";

          orders.add(
            PredispatchSalesOrder(
              orderId: _asInt(row["order_id"]) ?? _asInt(row["id"]) ?? 0,
              orderNo: row["order_no"]?.toString() ?? "",
              customerName: cName,
              customerCode: cCode,
              branchId: branchId,
              branchName: bName,
              totalAmount: double.tryParse(row["total_amount"]?.toString() ?? "0") ?? 0.0,
              allocatedAmount: double.tryParse(row["allocated_amount"]?.toString() ?? "0") ?? 0.0,
            ),
          );
        }
      }

      return orders;
    } catch (e) {
      debugPrint('Error fetching all orders for dispatch branch: $e');
      return [];
    }
  }

  // =============================
  // APPROVE FLOW
  // =============================

  Future<PredispatchApproveOutcome> approvePredispatchPlan({
    required int dispatchId,
    required String remarks,
    required DateTime dispatchDate,
  }) async {
    try {
      // 1. Update dispatch_plan status to 'Picking'
      await _api.patch(
        "/items/$_dpCollection/$dispatchId",
        data: {"status": "Picking", "remarks": remarks},
      );

      // 2. Get linked sales orders
      final res = await _api.getJson(
        "/items/$_dpDetailsCollection",
        query: {"filter[dispatch_id][_eq]": dispatchId, "fields": "sales_order_id"},
        allow403: true,
      );

      // Check if API returned an error (e.g., 403 Forbidden)
      if (res.containsKey("error")) {
        return PredispatchApproveOutcome(
          success: false,
          error: "Permission denied: Cannot read dispatch_plan_details.",
        );
      }

      final List data = (res["data"] as List?) ?? [];
      final salesOrderIds = data
          .map((row) {
            final val = row["sales_order_id"];
            if (val == null) return null;
            // Handle case where API returns the full object instead of just ID
            if (val is Map) return _asInt(val["order_id"]) ?? _asInt(val["id"]);
            return _asInt(val);
          })
          .whereType<int>()
          .where((id) => id > 0)
          .toList();

      // 3. Update each sales order
      for (final orderId in salesOrderIds) {
        await _api.patch(
          "/items/$_salesOrderCollection/$orderId",
          data: {
            "order_status": "For Consolidation",
            "delivery_date": dispatchDate.toIso8601String(),
            "for_consolidation_at": DateTime.now().toIso8601String(),
          },
        );
      }

      return const PredispatchApproveOutcome(success: true);
    } catch (e) {
      return PredispatchApproveOutcome(success: false, error: e.toString());
    }
  }

  // =============================
  // HELPERS
  // =============================

  PredispatchStatus _parseStatus(String? s) {
    if (s == null) return PredispatchStatus.pending;
    return PredispatchStatus.values.firstWhere(
      (e) => e.label.toLowerCase() == s.toLowerCase(),
      orElse: () => PredispatchStatus.pending,
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

  Future<Map<String, String>> _fetchCustomersByCodes(List<String> codes) async {
    if (codes.isEmpty) return {};
    final uniqueCodes = codes.toSet().toList();

    final res = await _api.getJson(
      "/items/$_customerCollection",
      query: {
        "filter[customer_code][_in]": uniqueCodes.join(","),
        "fields": "customer_code,customer_name",
        "limit": "-1",
      },
    );

    final data = (res["data"] as List?) ?? [];
    final out = <String, String>{};
    for (final r in data) {
      if (r is Map) {
        final code = r["customer_code"]?.toString() ?? "";
        final name = r["customer_name"]?.toString() ?? "";
        if (code.isNotEmpty) out[code] = name;
      }
    }
    return out;
  }

  Future<Map<int, List<PredispatchSalesOrder>>> _fetchSalesOrders(List<int> dispatchIds) async {
    if (dispatchIds.isEmpty) return {};

    try {
      final res = await _api.getJson(
        "/items/$_dpDetailsCollection",
        query: {
          "filter[dispatch_id][_in]": dispatchIds.join(","),
          "fields":
              "dispatch_id,sales_order_id.order_id,sales_order_id.id,sales_order_id.order_no,sales_order_id.customer_code,sales_order_id.allocated_amount,sales_order_id.total_amount,sales_order_id.branch_id",
          "limit": "-1",
        },
        allow403: true,
      );

      // Check if API returned an error (e.g., 403 Forbidden)
      if (res.containsKey("error")) {
        debugPrint(
          "⚠️ PERMISSION ERROR: User cannot read 'dispatch_plan_details'. Please grant Read access in Directus.",
        );
        return {};
      }

      final data = (res["data"] as List?) ?? [];
      final out = <int, List<PredispatchSalesOrder>>{};

      // Collect IDs for manual lookup (safer than deep nesting)
      final customerCodes = <String>{};
      final branchIds = <int>{};

      for (final row in data) {
        if (row is Map) {
          final so = row["sales_order_id"] as Map?;
          if (so != null) {
            final cc = so["customer_code"]?.toString();
            if (cc != null && cc.isNotEmpty) customerCodes.add(cc);

            final bid = _asInt(so["branch_id"]);
            if (bid != null) branchIds.add(bid);
          }
        }
      }

      // Fetch Lookups
      final customersMap = await _fetchCustomersByCodes(customerCodes.toList());
      final branchesMap = await _fetchBranches(branchIds.toList());

      for (final row in data) {
        if (row is Map) {
          final dispatchId = _asInt(row["dispatch_id"]);
          if (dispatchId == null) continue;

          final so = row["sales_order_id"] as Map?;
          if (so == null) continue;

          // Resolve Customer
          String cCode = so["customer_code"]?.toString() ?? "";
          // If API returned object for customer_code, extract ID
          if (so["customer_code"] is Map) {
            cCode = so["customer_code"]["customer_code"]?.toString() ?? "";
          }
          final cName = customersMap[cCode] ?? "Unknown Customer";

          // Resolve Branch
          int bId = 0;
          final branchRaw = so["branch_id"];
          if (branchRaw is Map) {
            bId = _asInt(branchRaw["id"]) ?? 0;
          } else {
            bId = _asInt(branchRaw) ?? 0;
          }
          final bName = branchesMap[bId] ?? "";

          final order = PredispatchSalesOrder(
            orderId: _asInt(so["order_id"]) ?? _asInt(so["id"]) ?? 0,
            orderNo: so["order_no"]?.toString() ?? "",
            customerName: cName,
            customerCode: cCode,
            branchId: bId,
            branchName: bName,
            totalAmount: double.tryParse(so["total_amount"]?.toString() ?? "0") ?? 0.0,
            allocatedAmount: double.tryParse(so["allocated_amount"]?.toString() ?? "0") ?? 0.0,
          );

          out.putIfAbsent(dispatchId, () => []).add(order);
        }
      }

      return out;
    } catch (e) {
      // If permission denied or error, return empty map to allow the list to load without sales orders
      if (e.toString().contains("403")) {
        debugPrint(
          "⚠️ PERMISSION ERROR: User cannot read 'dispatch_plan_details'. Please grant Read access in Directus.",
        );
      } else {
        debugPrint('Error fetching sales orders: $e');
      }
      return {};
    }
  }

  int? _asInt(Object? v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString());
  }
}
