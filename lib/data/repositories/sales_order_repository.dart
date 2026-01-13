// lib/data/repositories/sales_order_repository.dart
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

/// Aggregated payment totals across multiple sales orders (customer group / PO group).
class SalesOrderGroupPaymentSummary {
  final int orderCount;
  final double ordersNetTotal;

  final int invoiceCount;
  final int paymentCount;
  final double invoiceTotal;
  final double paidTotal;
  final double unpaidTotal;

  const SalesOrderGroupPaymentSummary({
    required this.orderCount,
    required this.ordersNetTotal,
    required this.invoiceCount,
    required this.paymentCount,
    required this.invoiceTotal,
    required this.paidTotal,
    required this.unpaidTotal,
  });
}

/// Compact card model: one row per Customer, containing multiple orders.
class SalesOrderCustomerGroup {
  final String customerCode;
  final List<SalesOrderHeader> orders;

  const SalesOrderCustomerGroup({
    required this.customerCode,
    required this.orders,
  });

  String get primaryOrderStatus {
    // Typically uniform in a queue; fallback to first.
    return orders.isEmpty ? "" : orders.first.orderStatus;
  }

  double get totalNet => orders.fold<double>(0.0, (s, o) => s + o.netAmount);
  double get totalGross => orders.fold<double>(0.0, (s, o) => s + o.totalAmount);

  int get orderCount => orders.length;

  String? get poNo {
    // If you still want to show PO, choose the most common non-empty.
    final map = <String, int>{};
    for (final o in orders) {
      final po = (o.poNo ?? "").trim();
      if (po.isEmpty) continue;
      map[po] = (map[po] ?? 0) + 1;
    }
    if (map.isEmpty) return null;
    final entries = map.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return entries.first.key;
  }
}

class SalesOrderRepository {
  SalesOrderRepository(this._api);

  final ApiClient _api;

  // =============================
  // CONFIG (ONLINE ONLY)
  // =============================

  static const String _soCollection = "sales_order";
  static const String _customerCollection = "customer";
  static const String _invoiceCollection = "sales_invoice";
  static const String _paymentCollection = "sales_invoice_payments";
  static const String _userCollection = "user";

  // =============================
  // ORDER STATUS ENUMS (Directus)
  // =============================

  static const String soStatusForApproval = "For Approval";
  static const String soStatusForConsolidation = "For Consolidation";
  static const String soStatusForPicking = "For Picking";
  static const String soStatusForInvoicing = "For Invoicing";
  static const String soStatusForLoading = "For Loading";
  static const String soStatusForShipping = "For Shipping";
  static const String soStatusEnRoute = "En Route";
  static const String soStatusDelivered = "Delivered";
  static const String soStatusOnHold = "On Hold";
  static const String soStatusCancelled = "Cancelled";
  static const String soStatusNotFulfilled = "Not Fulfilled";

  /// Approve action sets the SO to this status.
  static const String soStatusAfterApprove = soStatusForConsolidation;

  // NOTE: can't be const because join() is not const-evaluable
static const List<String> _defaultFieldsList = [
  "order_id",
  "order_no",
  "po_no",
  "customer_code",
  "salesman_id",
  "supplier_id",
  "order_date",
  "total_amount",
  "net_amount",
  "order_status",
  "created_by",
  "created_date",
  "for_approval_at",

  // timelines
  "for_consolidation_at",
  "for_picking_at",

  "modified_date",
  "modified_by",
];

  static final String _defaultFields = _defaultFieldsList.join(",");

  // =============================
  // PUBLIC: Paged fetch (for list screens)
  // =============================

  /// Fetch paged sales orders by status.
  /// - status null => all statuses
  /// - Uses limit/offset for pagination
Future<List<SalesOrderHeader>> fetchSalesOrders({
  String? status,
  String? search, // NEW
  required int limit,
  required int offset,
}) async {
  final query = <String, String>{
    "limit": limit.toString(),
    "offset": offset.toString(),
    "sort": "-for_approval_at,-for_picking_at,-modified_date,-order_id",
    "fields": _defaultFields,
  };

  if (status != null && status.trim().isNotEmpty) {
    query["filter[order_status][_eq]"] = status.trim();
  }

  final q = (search ?? "").trim();
  if (q.isNotEmpty) {
    final qNorm = _normalizeCustomerCode(q);

    // Search across key fields (raw + normalized)
    // Directus OR: filter[_or][i][field][_icontains]=value
    int i = 0;

    void addOr(String field, String value) {
      query["filter[_or][$i][$field][_icontains]"] = value;
      i++;
    }

    addOr("order_no", q);
    addOr("po_no", q);
    addOr("customer_code", q);

    if (qNorm != q) {
      addOr("customer_code", qNorm);
      addOr("po_no", qNorm);
      addOr("order_no", qNorm);
    }
  }

  final json = await _api.getJson("/items/$_soCollection", query: query);
  final data = _readDataList(json);
  return data.map(SalesOrderHeader.fromJson).toList();
}

  /// Fetch paged + total count. Recommended for infinite scroll / pagination UI.
  Future<PagedResult<SalesOrderHeader>> fetchSalesOrdersPaged({
    String? status,
    required int limit,
    required int offset,
  }) async {
    final query = <String, String>{
      "limit": limit.toString(),
      "offset": offset.toString(),
      "sort": "-for_approval_at,-modified_date,-order_id",
      "fields": _defaultFields,
      "meta": "total_count",
    };

    if (status != null && status.trim().isNotEmpty) {
      query["filter[order_status][_eq]"] = status.trim();
    }

    final json = await _api.getJson("/items/$_soCollection", query: query);

    final items = _readDataList(json).map(SalesOrderHeader.fromJson).toList();

    int total = items.length;
    final meta = json["meta"];
    if (meta is Map) {
      final tc = _asInt(meta["total_count"]);
      if (tc != null) total = tc;
    }

    return PagedResult<SalesOrderHeader>(
      items: items,
      total: total,
      limit: limit,
      offset: offset,
    );
  }

  /// Backward-compatible helper (first page only).
  Future<List<SalesOrderHeader>> fetchSalesOrdersForApproval() async {
    return fetchSalesOrders(status: soStatusForApproval, limit: 50, offset: 0);
  }

  /// Generic count per status.
  Future<int> fetchSalesOrderCount({String? status}) async {
    final query = <String, String>{
      "limit": "0",
      "meta": "total_count",
      "fields": "order_id",
    };

    if (status != null && status.trim().isNotEmpty) {
      query["filter[order_status][_eq]"] = status.trim();
    }

    final json = await _api.getJson("/items/$_soCollection", query: query);

    final meta = json["meta"];
    if (meta is Map) {
      final total = _asInt(meta["total_count"]);
      if (total != null) return total;
    }
    return _readDataList(json).length;
  }

  // =============================
  // GROUPING FOR COMPACT CARDS (Customer)
  // =============================

  /// Build "one card per customer_code" from a page of orders.
  ///
  /// UI behavior:
  /// - List view shows grouped cards (customer_code / customer_name / totals / count).
  /// - Modal opens with all orders for that customer_code (either from existing loaded list,
  ///   or by fetching again using [fetchSalesOrdersByCustomerCode]).
  static List<SalesOrderCustomerGroup> groupByCustomerCode(List<SalesOrderHeader> orders) {
    final map = <String, List<SalesOrderHeader>>{};

    for (final o in orders) {
      final code = (o.customerCode ?? "").trim();
      final key = code.isEmpty ? "__UNKNOWN__" : code;
      (map[key] ??= []).add(o);
    }

    final groups = <SalesOrderCustomerGroup>[];
    for (final entry in map.entries) {
      // Sort inside group: newest first (approval queue)
      final rows = entry.value.toList()
        ..sort((a, b) {
          final da = _tryParseDateTime(a.forApprovalAt) ?? _tryParseDateTime(a.createdDate) ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
          final db = _tryParseDateTime(b.forApprovalAt) ?? _tryParseDateTime(b.createdDate) ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
          return db.compareTo(da);
        });

      groups.add(SalesOrderCustomerGroup(customerCode: entry.key, orders: rows));
    }

    // Sort groups by latest created/for_approval date (desc)
    groups.sort((a, b) {
      final a0 = a.orders.isEmpty ? null : a.orders.first;
      final b0 = b.orders.isEmpty ? null : b.orders.first;
      final da = a0 == null ? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true) : (_tryParseDateTime(a0.forApprovalAt) ?? _tryParseDateTime(a0.createdDate) ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true));
      final db = b0 == null ? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true) : (_tryParseDateTime(b0.forApprovalAt) ?? _tryParseDateTime(b0.createdDate) ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true));
      return db.compareTo(da);
    });

    return groups;
  }

  // =============================
  // GROUP FETCH (Customer / PO) for modal "Approve All"
  // =============================

  Future<List<SalesOrderHeader>> fetchSalesOrdersByCustomerCode({
    required String customerCode,
    String? status,
    int limit = 500,
  }) async {
    final raw = customerCode.trim();
    if (raw.isEmpty) return const [];

    final norm = _normalizeCustomerCode(raw);

    final query = <String, String>{
      "limit": limit.toString(),
      "offset": "0",
      "sort": "-for_approval_at,-modified_date,-order_id",
      "fields": _defaultFields,
      "filter[customer_code][_in]": {raw, norm}.join(","),
    };

    if (status != null && status.trim().isNotEmpty) {
      query["filter[order_status][_eq]"] = status.trim();
    }

    final json = await _api.getJson("/items/$_soCollection", query: query);
    final data = _readDataList(json);
    return data.map(SalesOrderHeader.fromJson).toList();
  }

  Future<List<SalesOrderHeader>> fetchSalesOrdersByPoNo({
    required String poNo,
    String? status,
    int limit = 500,
  }) async {
    final po = poNo.trim();
    if (po.isEmpty) return const [];

    final query = <String, String>{
      "limit": limit.toString(),
      "offset": "0",
      "sort": "-for_approval_at,-modified_date,-order_id",
      "fields": _defaultFields,
      "filter[po_no][_eq]": po,
    };

    if (status != null && status.trim().isNotEmpty) {
      query["filter[order_status][_eq]"] = status.trim();
    }

    final json = await _api.getJson("/items/$_soCollection", query: query);
    final data = _readDataList(json);
    return data.map(SalesOrderHeader.fromJson).toList();
  }

  Future<int> approveSalesOrdersByCustomerCode({
    required String customerCode,
    int? approvedByUserId,
    bool writeTimelineFields = true,
  }) async {
    final targets = await fetchSalesOrdersByCustomerCode(
      customerCode: customerCode,
      status: soStatusForApproval,
      limit: 500,
    );

    if (targets.isEmpty) return 0;

    int approved = 0;
    for (final so in targets) {
      if (so.orderId <= 0) continue;
      await approveSalesOrder(
        orderId: so.orderId,
        approvedByUserId: approvedByUserId,
        writeTimelineFields: writeTimelineFields,
      );
      approved++;
    }
    return approved;
  }

  Future<int> approveSalesOrdersByPoNo({
    required String poNo,
    int? approvedByUserId,
    bool writeTimelineFields = true,
  }) async {
    final targets = await fetchSalesOrdersByPoNo(
      poNo: poNo,
      status: soStatusForApproval,
      limit: 500,
    );

    if (targets.isEmpty) return 0;

    int approved = 0;
    for (final so in targets) {
      if (so.orderId <= 0) continue;
      await approveSalesOrder(
        orderId: so.orderId,
        approvedByUserId: approvedByUserId,
        writeTimelineFields: writeTimelineFields,
      );
      approved++;
    }
    return approved;
  }

  // =============================
  // PAYMENT SUMMARY (Single + Group)
  // =============================

  Future<SalesOrderPaymentSummary> fetchSalesOrderPaymentSummary({
    required String salesOrderNo,
  }) async {
    final orderNo = salesOrderNo.trim();
    if (orderNo.isEmpty) throw Exception("salesOrderNo is required.");

    final invJson = await _api.getJson(
      "/items/$_invoiceCollection",
      query: {
        "limit": "-1",
        "filter[order_id][_eq]": orderNo,
        "fields": "invoice_id,order_id,invoice_no,total_amount,net_amount,customer_code,payment_status",
      },
    );

    final invRows = _readDataList(invJson);
    final invoices = invRows.map(SalesInvoiceLite.fromJson).toList();

    if (invoices.isEmpty) {
      return const SalesOrderPaymentSummary(
        invoiceCount: 0,
        paymentCount: 0,
        invoiceTotal: 0,
        paidTotal: 0,
        unpaidTotal: 0,
      );
    }

    final invoiceIds = <int>[];
    double invoiceTotal = 0;

    for (final inv in invoices) {
      if (inv.invoiceId != null) invoiceIds.add(inv.invoiceId!);
      invoiceTotal += (inv.totalAmount ?? inv.netAmount ?? 0);
    }

    double paidTotal = 0;
    int paymentCount = 0;

    if (invoiceIds.isNotEmpty) {
      final ids = invoiceIds.toSet().toList()..sort();

      final payJson = await _api.getJson(
        "/items/$_paymentCollection",
        query: {
          "limit": "-1",
          "filter[invoice_id][_in]": ids.join(","),
          "fields": "id,invoice_id,paid_amount",
        },
      );

      final payRows = _readDataList(payJson);
      final payments = payRows.map(SalesInvoicePaymentLite.fromJson).toList();

      paymentCount = payments.length;
      for (final p in payments) {
        paidTotal += (p.paidAmount ?? 0);
      }
    }

    final unpaidTotal = (invoiceTotal - paidTotal) <= 0 ? 0.0 : (invoiceTotal - paidTotal);

    return SalesOrderPaymentSummary(
      invoiceCount: invoices.length,
      paymentCount: paymentCount,
      invoiceTotal: invoiceTotal,
      paidTotal: paidTotal,
      unpaidTotal: unpaidTotal,
    );
  }

  /// Group totals (for modal):
  /// - Orders Net Total (sum net_amount across the group)
  /// - Invoice Total / Paid / Unpaid across all invoices linked to the group
  ///
  /// IMPORTANT: invoice linkage is schema-dependent.
  /// We try:
  /// 1) invoice.order_id IN (sales_order.order_id ints)  [preferred if supported]
  /// 2) fallback invoice.order_id IN (sales_order.order_no strings)
  Future<SalesOrderGroupPaymentSummary> fetchGroupPaymentSummary({
    required List<SalesOrderHeader> orders,
  }) async {
    final orderCount = orders.length;
    final ordersNetTotal = orders.fold<double>(0.0, (s, o) => s + o.netAmount);

    final orderIds = orders.map((e) => e.orderId).where((e) => e > 0).toSet().toList()..sort();
    final orderNos = orders.map((e) => e.orderNo.trim()).where((e) => e.isNotEmpty).toSet().toList()..sort();

    if (orderIds.isEmpty && orderNos.isEmpty) {
      return SalesOrderGroupPaymentSummary(
        orderCount: orderCount,
        ordersNetTotal: ordersNetTotal,
        invoiceCount: 0,
        paymentCount: 0,
        invoiceTotal: 0,
        paidTotal: 0,
        unpaidTotal: 0,
      );
    }

    List<SalesInvoiceLite> invoices = [];

    if (orderIds.isNotEmpty) {
      invoices = await _fetchInvoicesByOrderIdInInts(orderIds);
    }

    // fallback for schemas where invoice.order_id stores order_no
    if (invoices.isEmpty && orderNos.isNotEmpty) {
      invoices = await _fetchInvoicesByOrderIdInStrings(orderNos);
    }

    if (invoices.isEmpty) {
      return SalesOrderGroupPaymentSummary(
        orderCount: orderCount,
        ordersNetTotal: ordersNetTotal,
        invoiceCount: 0,
        paymentCount: 0,
        invoiceTotal: 0,
        paidTotal: 0,
        unpaidTotal: 0,
      );
    }

    final invoiceIds = <int>[];
    double invoiceTotal = 0.0;

    for (final inv in invoices) {
      if (inv.invoiceId != null) invoiceIds.add(inv.invoiceId!);
      invoiceTotal += (inv.totalAmount ?? inv.netAmount ?? 0.0);
    }

    double paidTotal = 0.0;
    int paymentCount = 0;

    if (invoiceIds.isNotEmpty) {
      final payments = await _fetchPaymentsByInvoiceIds(invoiceIds);
      paymentCount = payments.length;
      for (final p in payments) {
        paidTotal += (p.paidAmount ?? 0.0);
      }
    }

    final unpaidTotal = (invoiceTotal - paidTotal) <= 0 ? 0.0 : (invoiceTotal - paidTotal);

    return SalesOrderGroupPaymentSummary(
      orderCount: orderCount,
      ordersNetTotal: ordersNetTotal,
      invoiceCount: invoices.length,
      paymentCount: paymentCount,
      invoiceTotal: invoiceTotal,
      paidTotal: paidTotal,
      unpaidTotal: unpaidTotal,
    );
  }

  // =============================
  // APPROVE
  // =============================

  Future<void> approveSalesOrder({
  required int orderId,
  int? approvedByUserId,
  bool writeTimelineFields = true,
}) async {
  if (orderId <= 0) throw Exception("orderId is invalid.");

  final nowIso = DateTime.now().toUtc().toIso8601String();

  final data = <String, dynamic>{
    "order_status": soStatusAfterApprove, // For Consolidation
  };

  if (writeTimelineFields) {
    data["for_consolidation_at"] = nowIso; // ✅ correct timeline
    data["modified_date"] = nowIso;
    if (approvedByUserId != null) data["modified_by"] = approvedByUserId;
  }

  await _api.patch("/items/$_soCollection/$orderId", data: data);
}

  // =============================
  // LOOKUPS
  // =============================

  Future<Map<String, CustomerLite>> fetchCustomersByCodes(List<String> codes) async {
    final expanded = <String>{};
    for (final c in codes) {
      final raw = c.trim();
      if (raw.isEmpty) continue;
      expanded.add(raw);
      expanded.add(_normalizeCustomerCode(raw));
    }
    if (expanded.isEmpty) return const {};

    final list = expanded.toList()..sort();

    final json = await _api.getJson(
      "/items/$_customerCollection",
      query: {
        "limit": "-1",
        "filter[customer_code][_in]": list.join(","),
        "fields": [
          "id",
          "customer_code",
          "customer_name",
          "store_name",
          "brgy",
          "city",
          "province",
          "payment_term",
          "isActive",
          "price_type",
        ].join(","),
      },
    );

    final data = _readDataList(json);
    final out = <String, CustomerLite>{};

    for (final row in data) {
      final c = CustomerLite.fromJson(row);
      final k1 = c.customerCode.trim();
      if (k1.isNotEmpty) out[k1] = c;

      final k2 = _normalizeCustomerCode(k1);
      if (k2.isNotEmpty) out[k2] = c;
    }

    return out;
  }

  Future<Map<int, AppUserLite>> fetchUsersByIds(List<int> ids) async {
    final uniq = ids.where((e) => e > 0).toSet().toList()..sort();
    if (uniq.isEmpty) return const {};

    final json = await _api.getJson(
      "/items/$_userCollection",
      query: {
        "limit": "-1",
        "filter[user_id][_in]": uniq.join(","),
        "fields": "user_id,user_fname,user_lname,is_deleted",
      },
    );

    final data = _readDataList(json);
    final out = <int, AppUserLite>{};

    for (final row in data) {
      final u = AppUserLite.fromJson(row);
      if (u.userId > 0) out[u.userId] = u;
    }

    return out;
  }

  // =============================
  // INTERNAL: Invoices / Payments (chunk-safe)
  // =============================

  Future<List<SalesInvoiceLite>> _fetchInvoicesByOrderIdInInts(List<int> orderIds) async {
    final ids = orderIds.toSet().toList()..sort();
    if (ids.isEmpty) return const [];

    final chunks = _chunkInts(ids, 75);
    final out = <SalesInvoiceLite>[];

    for (final c in chunks) {
      final invJson = await _api.getJson(
        "/items/$_invoiceCollection",
        query: {
          "limit": "-1",
          "filter[order_id][_in]": c.join(","),
          "fields": "invoice_id,order_id,invoice_no,total_amount,net_amount,customer_code,payment_status",
        },
      );
      final invRows = _readDataList(invJson);
      out.addAll(invRows.map(SalesInvoiceLite.fromJson));
    }

    return out;
  }

  Future<List<SalesInvoiceLite>> _fetchInvoicesByOrderIdInStrings(List<String> orderNos) async {
    final vals = orderNos.map((e) => e.trim()).where((e) => e.isNotEmpty).toSet().toList()..sort();
    if (vals.isEmpty) return const [];

    final chunks = _chunkStrings(vals, 60);
    final out = <SalesInvoiceLite>[];

    for (final c in chunks) {
      final invJson = await _api.getJson(
        "/items/$_invoiceCollection",
        query: {
          "limit": "-1",
          "filter[order_id][_in]": c.join(","),
          "fields": "invoice_id,order_id,invoice_no,total_amount,net_amount,customer_code,payment_status",
        },
      );
      final invRows = _readDataList(invJson);
      out.addAll(invRows.map(SalesInvoiceLite.fromJson));
    }

    return out;
  }

Future<int> fetchForApprovalCount() async {
  return fetchSalesOrderCount(status: soStatusForApproval);
}




  Future<List<SalesInvoicePaymentLite>> _fetchPaymentsByInvoiceIds(List<int> invoiceIds) async {
    final ids = invoiceIds.toSet().toList()..sort();
    if (ids.isEmpty) return const [];

    final chunks = _chunkInts(ids, 90);
    final out = <SalesInvoicePaymentLite>[];

    for (final c in chunks) {
      final payJson = await _api.getJson(
        "/items/$_paymentCollection",
        query: {
          "limit": "-1",
          "filter[invoice_id][_in]": c.join(","),
          "fields": "id,invoice_id,paid_amount",
        },
      );
      final payRows = _readDataList(payJson);
      out.addAll(payRows.map(SalesInvoicePaymentLite.fromJson));
    }

    return out;
  }

  List<List<int>> _chunkInts(List<int> items, int size) {
    if (items.isEmpty) return const [];
    final out = <List<int>>[];
    for (var i = 0; i < items.length; i += size) {
      out.add(items.sublist(i, (i + size) > items.length ? items.length : (i + size)));
    }
    return out;
  }

  List<List<String>> _chunkStrings(List<String> items, int size) {
    if (items.isEmpty) return const [];
    final out = <List<String>>[];
    for (var i = 0; i < items.length; i += size) {
      out.add(items.sublist(i, (i + size) > items.length ? items.length : (i + size)));
    }
    return out;
  }

  // =============================
  // INTERNAL HELPERS
  // =============================

  List<Map<String, dynamic>> _readDataList(Map<String, dynamic> json) {
    final raw = json["data"];
    if (raw is List) {
      return raw.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList();
    }
    return const [];
  }

  String _normalizeCustomerCode(String raw) {
    var s = raw.trim();
    if (s.isEmpty) return s;
    s = s.replaceAll(RegExp(r"\s*-\s*"), "-");
    s = s.replaceAll(RegExp(r"\s+"), " ").trim();
    return s;
  }

  int? _asInt(Object? v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString());
  }

  static DateTime? _tryParseDateTime(String? s) {
    if (s == null) return null;
    final v = s.trim();
    if (v.isEmpty) return null;
    return DateTime.tryParse(v);
  }
}

// =============================
// MODELS (Lite, repo-facing)
// =============================

class SalesOrderHeader {
  final int orderId;
  final String orderNo;
  final String? poNo;
  final String? customerCode;
  final int? salesmanId;
  final int? supplierId;
  final String? orderDate;
  final double totalAmount;
  final double netAmount;
  final String orderStatus;
  final int? createdBy;
  final String? createdDate;
  final String? forApprovalAt;

  const SalesOrderHeader({
    required this.orderId,
    required this.orderNo,
    required this.poNo,
    required this.customerCode,
    required this.salesmanId,
    required this.supplierId,
    required this.orderDate,
    required this.totalAmount,
    required this.netAmount,
    required this.orderStatus,
    required this.createdBy,
    required this.createdDate,
    required this.forApprovalAt,
  });

  factory SalesOrderHeader.fromJson(Map<String, dynamic> j) {
    int asInt(Object? v) => (v is num) ? v.toInt() : int.tryParse("$v") ?? 0;
    int? asIntN(Object? v) => (v is num) ? v.toInt() : int.tryParse("$v");
    double asDouble(Object? v) => (v is num) ? v.toDouble() : double.tryParse("$v") ?? 0.0;

    return SalesOrderHeader(
      orderId: asInt(j["order_id"]),
      orderNo: (j["order_no"] ?? "").toString(),
      poNo: j["po_no"]?.toString(),
      customerCode: j["customer_code"]?.toString(),
      salesmanId: asIntN(j["salesman_id"]),
      supplierId: asIntN(j["supplier_id"]),
      orderDate: j["order_date"]?.toString(),
      totalAmount: asDouble(j["total_amount"]),
      netAmount: asDouble(j["net_amount"]),
      orderStatus: (j["order_status"] ?? "").toString(),
      createdBy: asIntN(j["created_by"]),
      createdDate: j["created_date"]?.toString(),
      forApprovalAt: j["for_approval_at"]?.toString(),
    );
  }
}

class CustomerLite {
  final int id;
  final String customerCode;
  final String customerName;
  final String? storeName;
  final String? brgy;
  final String? city;
  final String? province;
  final int? paymentTerm;
  final bool isActive;
  final String? priceType;

  const CustomerLite({
    required this.id,
    required this.customerCode,
    required this.customerName,
    required this.storeName,
    required this.brgy,
    required this.city,
    required this.province,
    required this.paymentTerm,
    required this.isActive,
    required this.priceType,
  });

  factory CustomerLite.fromJson(Map<String, dynamic> j) {
    int asInt(Object? v) => (v is num) ? v.toInt() : int.tryParse("$v") ?? 0;

    final isActiveRaw = j["isActive"];
    final isActive = (isActiveRaw is num)
        ? isActiveRaw.toInt() != 0
        : ("$isActiveRaw" == "1" || "$isActiveRaw".toLowerCase() == "true");

    return CustomerLite(
      id: asInt(j["id"]),
      customerCode: (j["customer_code"] ?? "").toString(),
      customerName: (j["customer_name"] ?? "").toString(),
      storeName: j["store_name"]?.toString(),
      brgy: j["brgy"]?.toString(),
      city: j["city"]?.toString(),
      province: j["province"]?.toString(),
      paymentTerm: (j["payment_term"] is num)
          ? (j["payment_term"] as num).toInt()
          : int.tryParse("${j["payment_term"]}"),
      isActive: isActive,
      priceType: j["price_type"]?.toString(),
    );
  }
}

class AppUserLite {
  final int userId;
  final String? fname;
  final String? lname;
  final Object? isDeleted;

  const AppUserLite({
    required this.userId,
    required this.fname,
    required this.lname,
    required this.isDeleted,
  });

  String get displayName {
    final f = (fname ?? "").trim();
    final l = (lname ?? "").trim();
    final name = "$f $l".trim();
    return name.isEmpty ? "Unknown" : name;
  }

  factory AppUserLite.fromJson(Map<String, dynamic> j) {
    int asInt(Object? v) => (v is num) ? v.toInt() : int.tryParse("$v") ?? 0;
    return AppUserLite(
      userId: asInt(j["user_id"]),
      fname: j["user_fname"]?.toString(),
      lname: j["user_lname"]?.toString(),
      isDeleted: j["is_deleted"],
    );
  }
}

class SalesInvoiceLite {
  final int? invoiceId;
  final String? orderId;
  final String? invoiceNo;
  final double? totalAmount;
  final double? netAmount;
  final String? customerCode;
  final String? paymentStatus;

  const SalesInvoiceLite({
    required this.invoiceId,
    required this.orderId,
    required this.invoiceNo,
    required this.totalAmount,
    required this.netAmount,
    required this.customerCode,
    required this.paymentStatus,
  });

  factory SalesInvoiceLite.fromJson(Map<String, dynamic> j) {
    int? asIntN(Object? v) => (v is num) ? v.toInt() : int.tryParse("$v");
    double? asDoubleN(Object? v) => (v is num) ? v.toDouble() : double.tryParse("$v");

    return SalesInvoiceLite(
      invoiceId: asIntN(j["invoice_id"]),
      orderId: j["order_id"]?.toString(),
      invoiceNo: j["invoice_no"]?.toString(),
      totalAmount: asDoubleN(j["total_amount"]),
      netAmount: asDoubleN(j["net_amount"]),
      customerCode: j["customer_code"]?.toString(),
      paymentStatus: j["payment_status"]?.toString(),
    );
  }
}

class SalesInvoicePaymentLite {
  final int id;
  final int? invoiceId;
  final double? paidAmount;

  const SalesInvoicePaymentLite({
    required this.id,
    required this.invoiceId,
    required this.paidAmount,
  });

  factory SalesInvoicePaymentLite.fromJson(Map<String, dynamic> j) {
    int asInt(Object? v) => (v is num) ? v.toInt() : int.tryParse("$v") ?? 0;
    int? asIntN(Object? v) => (v is num) ? v.toInt() : int.tryParse("$v");
    double? asDoubleN(Object? v) => (v is num) ? v.toDouble() : double.tryParse("$v");

    return SalesInvoicePaymentLite(
      id: asInt(j["id"]),
      invoiceId: asIntN(j["invoice_id"]),
      paidAmount: asDoubleN(j["paid_amount"]),
    );
  }
}

class SalesOrderPaymentSummary {
  final int invoiceCount;
  final int paymentCount;
  final double invoiceTotal;
  final double paidTotal;
  final double unpaidTotal;

  const SalesOrderPaymentSummary({
    required this.invoiceCount,
    required this.paymentCount,
    required this.invoiceTotal,
    required this.paidTotal,
    required this.unpaidTotal,
  });
}
