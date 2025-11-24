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

  SalesReportRow({
    required this.invoiceNo,
    required this.invoiceDate,
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
      productSupplier: _strN(m['product_supplier']), // <- from SELECT alias
      productUnitPrice: _numN(m['product_unit_price']),
      productQuantity: _numN(m['product_quantity']),
      productUnit: _strN(m['product_unit']),
      productDiscountAmount: _numN(m['product_discount_amount']),
      salesmanDivision: _strN(m['salesman_division']),
      customerProvince: _strN(m['customer_province']),
      customerCity: _strN(m['customer_city']),
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
    'product_supplier', // present in your view
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
      final rows = await db.rawQuery("PRAGMA table_info('v_sales_report_itemized')");
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
    if (avail.contains('product_supplier')) return "COALESCE(product_supplier,'')";
    final co = avail.map((c) => "NULLIF(TRIM($c),'')").join(', ');
    return "COALESCE($co,'')";
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
    paymentStatusOptions = ['All Status', ...await _distinctExpr('payment_status')];

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
    if (!branchOptions.contains(selectedBranch)) selectedBranch = 'All Branches';
    if (!salesmanOptions.contains(selectedSalesman)) selectedSalesman = 'All Salesmen';
    if (!paymentStatusOptions.contains(selectedPaymentStatus)) selectedPaymentStatus = 'All Status';
    if (!supplierOptions.contains(selectedSupplier)) selectedSupplier = 'All Suppliers';

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
      final totalInvoices =
      (cntRow.isNotEmpty ? cntRow.first['cnt'] : 0);
      final totalInvoicesInt = (totalInvoices is num) ? totalInvoices.toInt() : 0;

      // Page query with normalized supplier alias
      final supplierExpr = _supplierExprForSelect();

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
          t.invoice_date,
          t.customer_name,
          t.customer_address,
          t.salesman,
          t.branch,
          t.payment_terms,
          t.sales_type,
          t.invoice_type,
          t.transaction_status,
          t.payment_status,
          t.total_amount,
          t.discount_amount,
          t.amount,
          COALESCE(t.return_amount_total, 0) AS return_amount_total,
          t.collection,
          COALESCE(t.isDispatched, t.is_dispatched) AS isDispatched,
          COALESCE(t.isPosted,     t.is_posted)     AS isPosted,
          COALESCE(t.product_name,'')         AS product_name,
          COALESCE(t.product_brand,'')        AS product_brand,
          COALESCE(t.product_category,'')     AS product_category,
          $supplierExpr                        AS product_supplier,
          t.product_unit_price,
          t.product_quantity,
          COALESCE(t.product_unit,'')         AS product_unit,
          t.product_discount_amount,
          COALESCE(t.salesman_division,'')    AS salesman_division,
          COALESCE(t.customer_province,'')    AS customer_province,
          COALESCE(t.customer_city,'')        AS customer_city
        FROM v_sales_report_itemized t
        JOIN inv i USING (invoice_no)
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

  Future<List<SalesReportRow>> getItemizedRowsForExport() async {
    final db = await AppDb.get();
    final built = await _buildWhere();
    final whereSql = built.$1;
    final args = built.$2;
    final supplierExpr = _supplierExprForSelect();

    final sql = '''
      SELECT
        invoice_no,
        invoice_date,
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
        COALESCE(customer_city,'')        AS customer_city
      FROM v_sales_report_itemized
      $whereSql
      ORDER BY date(substr(invoice_date,1,10)) DESC, invoice_no DESC
    ''';

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
    final last = DateTime(year, month + 1, 1).subtract(const Duration(days: 1));
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
          print('[SalesReport] No supplier columns found; supplier filter ignored.');
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
        final last = DateTime(now.year, now.month + 1, 1).subtract(const Duration(days: 1));
        return (first, last);
      case 'This Quarter':
        final q = ((now.month - 1) ~/ 3) + 1;
        final firstMonth = (q - 1) * 3 + 1;
        final first = DateTime(now.year, firstMonth, 1);
        final last = DateTime(now.year, firstMonth + 3, 1).subtract(const Duration(days: 1));
        return (first, last);
      case 'This Year':
        return (DateTime(now.year, 1, 1), DateTime(now.year, 12, 31));
      case 'Custom':
        if (customFrom != null && customTo != null) {
          return (startOfDay(customFrom!), endOfDay(customTo!));
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
