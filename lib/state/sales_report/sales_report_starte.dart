// lib/features/sales_report/sales_report_state.dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:sqflite/sqflite.dart';
import '../../data/local/app_db.dart';

/// UI-facing row model mapped from v_sales_report_itemized
class SalesReportRow {
  final String invoiceNo;
  final DateTime? invoiceDate;

  /// ✅ NEW: customer code (for export)
  final String customerCode;

  final String customerName;
  final String customerAddress;
  final String salesman;
  final String branch;
  final String paymentTerms;
  final String salesType;
  final String invoiceType;
  final String transactionStatus;
  final String paymentStatus;
  final double totalAmount;
  final double discountAmount;
  final double amount;
  final double returnAmount;
  final double collection;
  final bool isDispatched;
  final bool isPosted;

  // Itemized + enrichment
  final String? productName;
  final String? productBrand;
  final String? productCategory;
  final String? productSupplier; // normalized/aliased
  final double? productUnitPrice;
  final double? productQuantity;
  final String? productUnit;
  final double? productDiscountAmount;
  final String? salesmanDivision;
  final String? customerProvince;
  final String? customerCity;

  /// Forecast / demand **in cases** for this product family (for export)
  final double? inCases;

  SalesReportRow({
    required this.invoiceNo,
    required this.invoiceDate,

    /// ✅ NEW (safe default; avoids breaking call sites)
    this.customerCode = "",

    required this.customerName,
    required this.customerAddress,
    required this.salesman,
    required this.branch,
    required this.paymentTerms,
    required this.salesType,
    required this.invoiceType,
    required this.transactionStatus,
    required this.paymentStatus,
    required this.totalAmount,
    required this.discountAmount,
    required this.amount,
    required this.returnAmount,
    required this.collection,
    required this.isDispatched,
    required this.isPosted,
    this.productName,
    this.productBrand,
    this.productCategory,
    this.productSupplier,
    this.productUnitPrice,
    this.productQuantity,
    this.productUnit,
    this.productDiscountAmount,
    this.salesmanDivision,
    this.customerProvince,
    this.customerCity,
    this.inCases,
  });

  factory SalesReportRow.fromDb(Map<String, Object?> m) {
    DateTime? parseDate(String? s) {
      if (s == null || s.isEmpty) return null;
      try {
        final t = s.length >= 10 ? s.substring(0, 10) : s;
        return DateTime.tryParse(s) ?? DateTime.tryParse(t);
      } catch (_) {
        return null;
      }
    }

    double _num(obj) {
      if (obj == null) return 0.0;
      if (obj is num) return obj.toDouble();
      return double.tryParse(obj.toString()) ?? 0.0;
    }

    double? _numN(obj) {
      if (obj == null) return null;
      if (obj is num) return obj.toDouble();
      return double.tryParse(obj.toString());
    }

    bool _bool(obj) {
      if (obj == null) return false;
      if (obj is num) return obj != 0;
      if (obj is bool) return obj;
      final s = obj.toString().toLowerCase().trim();
      return s == '1' || s == 'true' || s == 'y' || s == 'yes';
    }

    String? _strN(Object? v) => v == null ? null : v.toString();

    final dispatchedRaw = m['isDispatched'] ?? m['is_dispatched'];
    final postedRaw = m['isPosted'] ?? m['is_posted'];

    return SalesReportRow(
      invoiceNo: (m['invoice_no'] ?? '').toString(),
      invoiceDate: parseDate(m['invoice_date']?.toString()),

      /// ✅ NEW: read from SQL alias
      customerCode: (m['customer_code'] ?? m['customerCode'] ?? '').toString(),

      customerName: (m['customer_name'] ?? '').toString(),
      customerAddress: (m['customer_address'] ?? '').toString(),
      salesman: (m['salesman'] ?? '').toString(),
      branch: (m['branch'] ?? '').toString(),
      paymentTerms: (m['payment_terms'] ?? '').toString(),
      salesType: (m['sales_type'] ?? '').toString(),
      invoiceType: (m['invoice_type'] ?? '').toString(),
      transactionStatus: (m['transaction_status'] ?? '').toString(),
      paymentStatus: (m['payment_status'] ?? '').toString(),
      totalAmount: _num(m['total_amount']),
      discountAmount: _num(m['discount_amount']),
      amount: _num(m['amount']),
      returnAmount: _num(m['return_amount_total'] ?? m['return_amount']),
      collection: _num(m['collection']),
      isDispatched: _bool(dispatchedRaw),
      isPosted: _bool(postedRaw),
      productName: _strN(m['product_name']),
      productBrand: _strN(m['product_brand']),
      productCategory: _strN(m['product_category']),
      productSupplier: _strN(m['product_supplier']),
      productUnitPrice: _numN(m['product_unit_price']),
      productQuantity: _numN(m['product_quantity']),
      productUnit: _strN(m['product_unit']),
      productDiscountAmount: _numN(m['product_discount_amount']),
      salesmanDivision: _strN(m['salesman_division']),
      customerProvince: _strN(m['customer_province']),
      customerCity: _strN(m['customer_city']),
      inCases: _numN(m['in_cases']),
    );
  }

  SalesReportRow copyWith({
    String? customerCode,
    double? inCases,
  }) {
    return SalesReportRow(
      invoiceNo: invoiceNo,
      invoiceDate: invoiceDate,
      customerCode: customerCode ?? this.customerCode,
      customerName: customerName,
      customerAddress: customerAddress,
      salesman: salesman,
      branch: branch,
      paymentTerms: paymentTerms,
      salesType: salesType,
      invoiceType: invoiceType,
      transactionStatus: transactionStatus,
      paymentStatus: paymentStatus,
      totalAmount: totalAmount,
      discountAmount: discountAmount,
      amount: amount,
      returnAmount: returnAmount,
      collection: collection,
      isDispatched: isDispatched,
      isPosted: isPosted,
      productName: productName,
      productBrand: productBrand,
      productCategory: productCategory,
      productSupplier: productSupplier,
      productUnitPrice: productUnitPrice,
      productQuantity: productQuantity,
      productUnit: productUnit,
      productDiscountAmount: productDiscountAmount,
      salesmanDivision: salesmanDivision,
      customerProvince: customerProvince,
      customerCity: customerCity,
      inCases: inCases ?? this.inCases,
    );
  }
}

const kPeriods = <String>[
  'Today',
  'This Week',
  'This Month',
  'This Quarter',
  'This Year',
  'Custom',
];

class SalesReportState extends ChangeNotifier {
  // Filters
  String selectedPeriod = 'This Month';
  String selectedBranch = 'All Branches';
  String selectedSalesman = 'All Salesmen';
  String selectedPaymentStatus = 'All Status';
  String selectedSupplier = 'All Suppliers';

  DateTime? customFrom;
  DateTime? customTo;

  // Data
  List<SalesReportRow> rows = [];
  double totalSales = 0;
  double totalCollection = 0;
  double totalReturns = 0;
  double totalDiscounts = 0;

  // Options
  List<String> branchOptions = const ['All Branches'];
  List<String> salesmanOptions = const ['All Salesmen'];
  List<String> paymentStatusOptions = const ['All Status'];
  List<String> supplierOptions = const ['All Suppliers'];

  // UX
  bool loading = false;
  String? error;

  // Paging
  int limit = 500;
  int offset = 0;
  bool hasMore = false;

  // ---- Schema awareness (cache) ----
  Set<String>? _viewColumns; // lowercase set of available columns

  /// Order matters: prefer product_supplier if present
  final List<String> _supplierCandidates = const <String>[
    'product_supplier',
    'supplier_name',
    'supplier',
    'vendor_name',
    'vendor',
    'supplier_company',
  ];

  String get selectedPeriodLabel {
    if (selectedPeriod == 'Custom' && customFrom != null && customTo != null) {
      final fmt = DateFormat('MMM d, yyyy');
      return '${fmt.format(customFrom!)} – ${fmt.format(customTo!)}';
    }
    return selectedPeriod;
  }

  Future<void> init() async {
    await _primeSchema();
    await refreshFilters();
    await refresh();
  }

  Future<void> _primeSchema() async {
    try {
      final db = await AppDb.get();
      final rows =
      await db.rawQuery("PRAGMA table_info('v_sales_report_itemized')");
      _viewColumns = rows
          .map((r) => (r['name'] ?? '').toString().toLowerCase())
          .where((s) => s.isNotEmpty)
          .toSet();
      if (kDebugMode) {
        // ignore: avoid_print
        print('[SalesReport] View columns: $_viewColumns');
      }
    } catch (_) {
      _viewColumns = {};
    }
  }

  List<String> _availableSupplierCols() {
    final cols = _viewColumns ?? {};
    return _supplierCandidates.where((c) => cols.contains(c)).toList();
  }

  /// SELECT expression to expose a single alias `product_supplier`.
  String _supplierExprForSelect() {
    final avail = _availableSupplierCols();
    if (avail.isEmpty) return "''";
    if (avail.contains('product_supplier')) {
      return "COALESCE(product_supplier,'')";
    }
    final co = avail.map((c) => "NULLIF(TRIM($c),'')").join(', ');
    return "COALESCE($co,'')";
  }

  /// ✅ NEW: schema-aware customer_code expression (avoids "no such column")
  String _customerCodeExprForSelect([String alias = '']) {
    final cols = _viewColumns ?? {};
    if (!cols.contains('customer_code')) return "''";
    final a = alias.isEmpty ? '' : (alias.endsWith('.') ? alias : '$alias.');
    return "COALESCE(${a}customer_code,'')";
  }

  /// WHERE expression for equality filtering against selectedSupplier.
  (String? sql, List<Object?> args) _supplierWhereEq(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return (null, const []);
    final avail = _availableSupplierCols();
    if (avail.isEmpty) return (null, const []);
    if (avail.contains('product_supplier')) {
      return ("TRIM(COALESCE(product_supplier,'')) = ?", [trimmed]);
    }
    final parts = <String>[];
    final args = <Object?>[];
    for (final c in avail) {
      parts.add("TRIM(COALESCE($c,'')) = ?");
      args.add(trimmed);
    }
    return ('(${parts.join(' OR ')})', args);
  }

  Future<void> refreshFilters() async {
    final db = await AppDb.get();

    Future<List<String>> _distinctExpr(String expr) async {
      final sql = '''
        SELECT DISTINCT $expr AS v
        FROM v_sales_report_itemized
        WHERE TRIM(COALESCE($expr,'')) <> ''
        ORDER BY v COLLATE NOCASE
      ''';
      try {
        final rs = await db.rawQuery(sql);
        return rs
            .map((e) => (e['v'] as String?)?.trim() ?? '')
            .where((s) => s.isNotEmpty)
            .toList();
      } catch (_) {
        return <String>[];
      }
    }

    // Basic filters
    branchOptions = ['All Branches', ...await _distinctExpr('branch')];
    salesmanOptions = ['All Salesmen', ...await _distinctExpr('salesman')];
    paymentStatusOptions = [
      'All Status',
      ...await _distinctExpr('payment_status')
    ];

    // Supplier options (schema-aware)
    final avail = _availableSupplierCols();
    List<String> suppliers;
    if (avail.contains('product_supplier')) {
      suppliers = await _distinctExpr('product_supplier');
    } else if (avail.isNotEmpty) {
      final set = <String>{};
      for (final c in avail) {
        set.addAll(await _distinctExpr(c));
      }
      suppliers = set.toList()
        ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    } else {
      suppliers = <String>[];
    }
    supplierOptions = ['All Suppliers', ...suppliers];

    // Guard selections
    if (!branchOptions.contains(selectedBranch)) {
      selectedBranch = 'All Branches';
    }
    if (!salesmanOptions.contains(selectedSalesman)) {
      selectedSalesman = 'All Salesmen';
    }
    if (!paymentStatusOptions.contains(selectedPaymentStatus)) {
      selectedPaymentStatus = 'All Status';
    }
    if (!supplierOptions.contains(selectedSupplier)) {
      selectedSupplier = 'All Suppliers';
    }

    notifyListeners();
  }

  Future<void> refresh({int? newOffset}) async {
    loading = true;
    error = null;
    hasMore = false;
    if (newOffset != null) offset = newOffset;
    notifyListeners();

    try {
      final db = await AppDb.get();

      // WHERE + args
      final built = await _buildWhere();
      final whereSql = built.$1;
      final args = built.$2;

      // Count distinct invoices (guard empty result)
      final countSql = '''
        SELECT COUNT(DISTINCT invoice_no) AS cnt
        FROM v_sales_report_itemized
        $whereSql
      ''';
      final cntRow = await db.rawQuery(countSql, args);
      final totalInvoices = (cntRow.isNotEmpty ? cntRow.first['cnt'] : 0);
      final totalInvoicesInt =
      (totalInvoices is num) ? totalInvoices.toInt() : 0;

      // Page query with normalized supplier alias
      final supplierExpr = _supplierExprForSelect();

      // ✅ customer_code expression (schema-aware)
      final customerCodeAgg = "MAX(${_customerCodeExprForSelect('t')}) AS customer_code";

      // 🔁 Now we GROUP BY invoice_no so the GridView shows one row per invoice
      final pageSql = '''
        WITH inv AS (
          SELECT DISTINCT invoice_no, date(substr(invoice_date,1,10)) AS d
          FROM v_sales_report_itemized
          $whereSql
          ORDER BY d DESC, invoice_no DESC
          LIMIT ? OFFSET ?
        )
        SELECT
          t.invoice_no,
          MAX(t.invoice_date)                AS invoice_date,
          $customerCodeAgg,
          MAX(t.customer_name)               AS customer_name,
          MAX(t.customer_address)            AS customer_address,
          MAX(t.salesman)                    AS salesman,
          MAX(t.branch)                      AS branch,
          MAX(t.payment_terms)               AS payment_terms,
          MAX(t.sales_type)                  AS sales_type,
          MAX(t.invoice_type)                AS invoice_type,
          MAX(t.transaction_status)          AS transaction_status,
          MAX(t.payment_status)              AS payment_status,
          MAX(t.total_amount)                AS total_amount,
          MAX(t.discount_amount)             AS discount_amount,
          MAX(t.amount)                      AS amount,
          MAX(COALESCE(t.return_amount_total, 0)) AS return_amount_total,
          MAX(t.collection)                  AS collection,
          MAX(COALESCE(t.isDispatched, t.is_dispatched)) AS isDispatched,
          MAX(COALESCE(t.isPosted,     t.is_posted))     AS isPosted,
          -- For the grid we don't need full itemization, just a representative product
          MAX(COALESCE(t.product_name,''))   AS product_name,
          MAX(COALESCE(t.product_brand,''))  AS product_brand,
          MAX(COALESCE(t.product_category,'')) AS product_category,
          $supplierExpr                      AS product_supplier,
          MAX(t.product_unit_price)          AS product_unit_price,
          MAX(t.product_quantity)            AS product_quantity,
          MAX(COALESCE(t.product_unit,''))   AS product_unit,
          MAX(t.product_discount_amount)     AS product_discount_amount,
          MAX(COALESCE(t.salesman_division,''))    AS salesman_division,
          MAX(COALESCE(t.customer_province,''))    AS customer_province,
          MAX(COALESCE(t.customer_city,''))        AS customer_city,
          MAX(t.in_cases)                          AS in_cases
        FROM v_sales_report_itemized t
        JOIN inv i USING (invoice_no)
        GROUP BY t.invoice_no
        ORDER BY i.d DESC, t.invoice_no DESC
      ''';

      final pageArgs = [...args, limit, offset];
      final list = await db.rawQuery(pageSql, pageArgs);
      rows = list.map((e) => SalesReportRow.fromDb(e)).toList();

      await _refreshTotals(db, whereSql, args);
      hasMore = (offset + limit) < totalInvoicesInt;
    } catch (e) {
      error = e.toString();
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> loadMore() async {
    if (!hasMore || loading) return;
    offset += limit;
    await refresh();
  }

  /// Itemized rows for Excel export.
  /// Now computes `in_cases` using family BOX logic (root_map + box_pick),
  /// falling back to the simple view column if product_id is not available.
  Future<List<SalesReportRow>> getItemizedRowsForExport() async {
    final db = await AppDb.get();

    // Ensure schema info is primed so we know if product_id exists in the view
    if (_viewColumns == null) {
      await _primeSchema();
    }
    final hasProductId = _viewColumns?.contains('product_id') ?? false;

    final built = await _buildWhere();
    final whereSql = built.$1;
    final args = built.$2;
    final supplierExpr = _supplierExprForSelect();

    // ✅ customer_code exprs
    final customerCodeExprVsr = "${_customerCodeExprForSelect('vsr')} AS customer_code";
    final customerCodeExprPlain = "${_customerCodeExprForSelect()} AS customer_code";

    late final String sql;

    if (hasProductId) {
      // Advanced path: mirror Java "family, BOX, pieces_per_box" logic
      sql = '''
        WITH RECURSIVE root_map AS (
          SELECT p.product_id, p.parent_id, p.product_id AS root_id
          FROM products p
          WHERE p.parent_id IS NULL
          UNION ALL
          SELECT c.product_id, c.parent_id, r.root_id
          FROM products c
          JOIN root_map r ON c.parent_id = r.product_id
        ),
        box_rank AS (
          SELECT
            rm.root_id,
            p.product_id,
            u."order" AS unit_order,
            COALESCE(p.unit_of_measurement_count, 1) AS umc,
            ROW_NUMBER() OVER (
              PARTITION BY rm.root_id
              ORDER BY
                (CASE WHEN u."order" IS NULL THEN 0 ELSE 1 END) DESC,
                u."order" DESC,
                COALESCE(p.unit_of_measurement_count, 1) DESC,
                p.product_id ASC
            ) AS rn
          FROM root_map rm
          JOIN products p
            ON p.product_id = rm.product_id
           AND p.isActive = 1
          LEFT JOIN units u
            ON u.unit_id = p.unit_of_measurement
        ),
        box_pick AS (
          SELECT
            br.root_id,
            br.product_id AS box_product_id,
            br.umc       AS pieces_per_box
          FROM box_rank br
          WHERE br.rn = 1
        )
        SELECT
          vsr.invoice_no,
          vsr.invoice_date,
          $customerCodeExprVsr,
          vsr.customer_name,
          vsr.customer_address,
          vsr.salesman,
          vsr.branch,
          vsr.payment_terms,
          vsr.sales_type,
          vsr.invoice_type,
          vsr.transaction_status,
          vsr.payment_status,
          vsr.total_amount,
          vsr.discount_amount,
          vsr.amount,
          COALESCE(vsr.return_amount_total, 0) AS return_amount_total,
          vsr.collection,
          COALESCE(vsr.isDispatched, vsr.is_dispatched) AS isDispatched,
          COALESCE(vsr.isPosted,     vsr.is_posted)     AS isPosted,
          COALESCE(vsr.product_name,'')         AS product_name,
          COALESCE(vsr.product_brand,'')        AS product_brand,
          COALESCE(vsr.product_category,'')     AS product_category,
          $supplierExpr                          AS product_supplier,
          vsr.product_unit_price,
          vsr.product_quantity,
          COALESCE(vsr.product_unit,'')         AS product_unit,
          vsr.product_discount_amount,
          COALESCE(vsr.salesman_division,'')    AS salesman_division,
          COALESCE(vsr.customer_province,'')    AS customer_province,
          COALESCE(vsr.customer_city,'')        AS customer_city,
          CASE
            WHEN vsr.product_id IS NULL THEN NULL
            ELSE
              (
                COALESCE(vsr.product_quantity, 0.0)
                * COALESCE(p.unit_of_measurement_count, 1.0)
              )
              / NULLIF(bp.pieces_per_box, 0.0)
          END AS in_cases
        FROM v_sales_report_itemized vsr
        LEFT JOIN products p
          ON p.product_id = vsr.product_id
        LEFT JOIN root_map rm
          ON rm.product_id = p.product_id
        LEFT JOIN box_pick bp
          ON bp.root_id = rm.root_id
        $whereSql
        ORDER BY date(substr(vsr.invoice_date,1,10)) DESC, vsr.invoice_no DESC
      ''';
    } else {
      // Fallback: use whatever in_cases column the view has (or null)
      sql = '''
        SELECT
          invoice_no,
          invoice_date,
          $customerCodeExprPlain,
          customer_name,
          customer_address,
          salesman,
          branch,
          payment_terms,
          sales_type,
          invoice_type,
          transaction_status,
          payment_status,
          total_amount,
          discount_amount,
          amount,
          COALESCE(return_amount_total, 0) AS return_amount_total,
          collection,
          COALESCE(isDispatched, is_dispatched) AS isDispatched,
          COALESCE(isPosted,     is_posted)     AS isPosted,
          COALESCE(product_name,'')         AS product_name,
          COALESCE(product_brand,'')        AS product_brand,
          COALESCE(product_category,'')     AS product_category,
          $supplierExpr                      AS product_supplier,
          product_unit_price,
          product_quantity,
          COALESCE(product_unit,'')         AS product_unit,
          product_discount_amount,
          COALESCE(salesman_division,'')    AS salesman_division,
          COALESCE(customer_province,'')    AS customer_province,
          COALESCE(customer_city,'')        AS customer_city,
          in_cases
        FROM v_sales_report_itemized
        $whereSql
        ORDER BY date(substr(invoice_date,1,10)) DESC, invoice_no DESC
      ''';
    }

    final rs = await db.rawQuery(sql, args);
    return rs.map((e) => SalesReportRow.fromDb(e)).toList();
  }

  Future<void> _refreshTotals(
      Database db,
      String whereSql,
      List<Object?> args,
      ) async {
    final sql = '''
      SELECT
        IFNULL(SUM(amount),0)          AS total_sales,
        IFNULL(SUM(return_amount),0)   AS total_returns,
        IFNULL(SUM(collection),0)      AS total_collection,
        IFNULL(SUM(discount_amount),0) AS total_discounts
      FROM (
        SELECT invoice_no,
               MAX(amount)                              AS amount,
               MAX(COALESCE(return_amount_total,0))     AS return_amount,
               MAX(collection)                          AS collection,
               MAX(discount_amount)                     AS discount_amount
        FROM v_sales_report_itemized
        $whereSql
        GROUP BY invoice_no
      ) t
    ''';

    final rList = await db.rawQuery(sql, args);
    final r = rList.isNotEmpty ? rList.first : <String, Object?>{};
    totalSales = (r['total_sales'] as num?)?.toDouble() ?? 0;
    totalReturns = (r['total_returns'] as num?)?.toDouble() ?? 0;
    totalCollection = (r['total_collection'] as num?)?.toDouble() ?? 0;
    totalDiscounts = (r['total_discounts'] as num?)?.toDouble() ?? 0;
  }

  // -------- setters --------

  void setPeriod(String value) {
    selectedPeriod = value;
    if (value != 'Custom') {
      customFrom = null;
      customTo = null;
    }
    offset = 0;
    refresh();
  }

  void setMonth(int year, int month) {
    final first = DateTime(year, month, 1);
    final last =
    DateTime(year, month + 1, 1).subtract(const Duration(days: 1));
    selectedPeriod = 'Custom';
    customFrom = first;
    customTo = last;
    offset = 0;
    refresh();
  }

  void setCustomRange(DateTime from, DateTime to) {
    selectedPeriod = 'Custom';
    customFrom = DateTime(from.year, from.month, from.day);
    customTo = DateTime(to.year, to.month, to.day);
    offset = 0;
    refresh();
  }

  void setBranch(String branch) {
    selectedBranch = branch;
    offset = 0;
    refresh();
  }

  void setSalesman(String name) {
    selectedSalesman = name;
    offset = 0;
    refresh();
  }

  void setPaymentStatus(String status) {
    selectedPaymentStatus = status;
    offset = 0;
    refresh();
  }

  void setSupplier(String supplier) {
    selectedSupplier = supplier;
    offset = 0;
    refresh();
  }

  // -------- WHERE builder (schema-aware) --------
  Future<(String, List<Object?>)> _buildWhere() async {
    if (_viewColumns == null) {
      await _primeSchema();
    }

    final where = <String>[];
    final args = <Object?>[];

    final range = _periodRange();
    if (range != null) {
      where.add("substr(COALESCE(invoice_date,''),1,10) >= ?");
      where.add("substr(COALESCE(invoice_date,''),1,10) <= ?");
      final fmt = DateFormat('yyyy-MM-dd');
      args.add(fmt.format(range.$1));
      args.add(fmt.format(range.$2));
    }
    if (selectedBranch != 'All Branches') {
      where.add('branch = ?');
      args.add(selectedBranch);
    }
    if (selectedSalesman != 'All Salesmen') {
      where.add('salesman = ?');
      args.add(selectedSalesman);
    }
    if (selectedPaymentStatus != 'All Status') {
      where.add('payment_status = ?');
      args.add(selectedPaymentStatus);
    }

    if (selectedSupplier != 'All Suppliers') {
      final sw = _supplierWhereEq(selectedSupplier);
      if (sw.$1 != null) {
        where.add(sw.$1!);
        args.addAll(sw.$2);
      } else {
        if (kDebugMode) {
          // ignore: avoid_print
          print(
              '[SalesReport] No supplier columns found; supplier filter ignored.');
        }
      }
    }

    final whereSql = where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}';
    return (whereSql, args);
  }

  (DateTime, DateTime)? _periodRange() {
    final now = DateTime.now();
    DateTime startOfDay(DateTime d) => DateTime(d.year, d.month, d.day);
    DateTime endOfDay(DateTime d) => DateTime(d.year, d.month, d.day);

    switch (selectedPeriod) {
      case 'Today':
        final d = startOfDay(now);
        return (d, d);
      case 'This Week':
        final wd = now.weekday;
        final mon = startOfDay(now.subtract(Duration(days: wd - 1)));
        final sun = startOfDay(mon.add(const Duration(days: 6)));
        return (mon, sun);
      case 'This Month':
        final first = DateTime(now.year, now.month, 1);
        final last = DateTime(now.year, now.month + 1, 1)
            .subtract(const Duration(days: 1));
        return (first, last);
      case 'This Quarter':
        final q = ((now.month - 1) ~/ 3) + 1;
        final firstMonth = (q - 1) * 3 + 1;
        final first = DateTime(now.year, firstMonth, 1);
        final last = DateTime(now.year, firstMonth + 3, 1)
            .subtract(const Duration(days: 1));
        return (first, last);
      case 'This Year':
        return (DateTime(now.year, 1, 1), DateTime(now.year, 12, 31));
      case 'Custom':
        if (customFrom != null && customTo != null) {
          return (
          startOfDay(customFrom!),
          endOfDay(customTo!),
          );
        }
        return null;
      default:
        return null;
    }
  }
}

extension<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
