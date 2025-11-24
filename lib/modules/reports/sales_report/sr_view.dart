// lib/modules/reports/sales_report/sr_view.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:excel/excel.dart' as xl;
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

// ✅ Use the correct package path to your updated state file
// If your file is named differently, change this import accordingly.
import 'package:vos_mobile/state/sales_report/sales_report_starte.dart';

import 'package:sqflite/sqflite.dart';
import 'package:vos_mobile/data/local/app_db.dart';

class SalesReportView extends StatefulWidget {
  const SalesReportView({Key? key}) : super(key: key);

  @override
  State<SalesReportView> createState() => _SalesReportViewState();
}

class _SalesReportViewState extends State<SalesReportView> {
  final SalesReportState state = SalesReportState();
  late VoidCallback _sub;

  // ---------- Division name resolver (cached) ----------
  Map<int, String>? _divisionLookupCache;

  bool _isNumeric(String s) {
    final t = s.trim();
    if (t.isEmpty) return false;
    return int.tryParse(t) != null;
  }

  Future<Database> _db() => AppDb.get();

  Future<List<Map<String, Object?>>> _safeQuery(
      String sql, [
        List<Object?> params = const [],
      ]) async {
    try {
      final db = await _db();
      return await db.rawQuery(sql, params);
    } catch (_) {
      return <Map<String, Object?>>[];
    }
  }

  /// Split a quantity into Ties / Boxes / Pieces based on the productUnit string.
  ({double ties, double boxes, double pieces}) _splitQtyByUnit(num? qty, String? unitRaw) {
    final q = (qty ?? 0).toDouble();
    final u = (unitRaw ?? '').toLowerCase().trim();
    double ties = 0, boxes = 0, pieces = 0;

    if (u.contains('tie')) {
      ties = q;
    } else if (u.contains('box')) {
      boxes = q;
    } else if (u == 'pc' || u == 'pcs' || u.contains('piece')) {
      pieces = q;
    } else {
      pieces = q;
    }
    return (ties: ties, boxes: boxes, pieces: pieces);
  }

  /// Try several common schemas to build a {id -> name} map for divisions.
  Future<Map<int, String>> _loadDivisionLookup() async {
    if (_divisionLookupCache != null) return _divisionLookupCache!;

    final candidates = <({String table, String idCol, String nameCol})>[
      (table: 'division', idCol: 'id', nameCol: 'name'),
      (table: 'division', idCol: 'division_id', nameCol: 'division_name'),
      (table: 'division', idCol: 'id', nameCol: 'division_name'),
      (table: 'division', idCol: 'division_id', nameCol: 'name'),
      (table: 'divisions', idCol: 'id', nameCol: 'name'),
      (table: 'divisions', idCol: 'division_id', nameCol: 'division_name'),
      (table: 'divisions', idCol: 'id', nameCol: 'division_name'),
      (table: 'divisions', idCol: 'division_id', nameCol: 'name'),
      (table: 'salesman_division', idCol: 'id', nameCol: 'name'),
      (table: 'salesman_division', idCol: 'division_id', nameCol: 'division_name'),
    ];

    final Map<int, String> out = {};
    for (final c in candidates) {
      final rows = await _safeQuery('''
        SELECT ${c.idCol} AS id, ${c.nameCol} AS name
        FROM ${c.table}
        WHERE ${c.idCol} IS NOT NULL
      ''');
      if (rows.isNotEmpty) {
        for (final r in rows) {
          final id = (r['id'] as num?)?.toInt();
          final name = (r['name'] ?? '').toString().trim();
          if (id != null && name.isNotEmpty) {
            out[id] = name;
          }
        }
        if (out.isNotEmpty) break; // first found mapping wins
      }
    }

    _divisionLookupCache = out;
    return out;
  }

  /// Prefer textual names; if numeric, try to resolve via lookup; else keep as-is.
  Future<String?> _resolveDivisionName(String? raw) async {
    if (raw == null || raw.trim().isEmpty) return null;
    if (!_isNumeric(raw)) return raw.trim();
    final id = int.tryParse(raw.trim());
    if (id == null) return raw.trim();
    final map = await _loadDivisionLookup();
    return map[id] ?? raw.trim();
  }

  @override
  void initState() {
    super.initState();
    _sub = () {
      if (mounted) setState(() {});
    };
    state.addListener(_sub);
    state.init(); // load filters + data
  }

  @override
  void dispose() {
    state.removeListener(_sub);
    state.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(symbol: '₱', decimalDigits: 2);
    final width = MediaQuery.sizeOf(context).width;
    final isTablet = width >= 900;

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        title: Text(
          'Sales Report',
          style: TextStyle(
            color: Colors.black87,
            fontSize: isTablet ? 22 : 20,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_list, color: Colors.black87, size: 22),
            onPressed: () => _showFilterDialog(context),
            tooltip: 'Filters',
          ),
          IconButton(
            icon: const Icon(Icons.download, color: Colors.black87, size: 22),
            onPressed: () => _showExportOptions(context),
            tooltip: 'Export',
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          // Summary Cards
          Container(
            color: Colors.white,
            padding: EdgeInsets.all(isTablet ? 18 : 16),
            child: LayoutBuilder(
              builder: (ctx, c) {
                final chipGap = isTablet ? 12.0 : 12.0;
                return Wrap(
                  spacing: chipGap,
                  runSpacing: chipGap,
                  children: [
                    SizedBox(
                      width: _metricWidth(c.maxWidth, isTablet),
                      child: _CompactMetricCard(
                        label: 'Total Sales',
                        value: currency.format(state.totalSales),
                        icon: Icons.trending_up,
                        color: Colors.blue,
                        isTablet: isTablet,
                      ),
                    ),
                    SizedBox(
                      width: _metricWidth(c.maxWidth, isTablet),
                      child: _CompactMetricCard(
                        label: 'Collection',
                        value: currency.format(state.totalCollection),
                        icon: Icons.account_balance_wallet,
                        color: Colors.green,
                        isTablet: isTablet,
                      ),
                    ),
                    SizedBox(
                      width: _metricWidth(c.maxWidth, isTablet),
                      child: _CompactMetricCard(
                        label: 'Returns',
                        value: currency.format(state.totalReturns),
                        icon: Icons.assignment_return,
                        color: Colors.orange,
                        isTablet: isTablet,
                      ),
                    ),
                    SizedBox(
                      width: _metricWidth(c.maxWidth, isTablet),
                      child: _CompactMetricCard(
                        label: 'Discounts',
                        value: currency.format(state.totalDiscounts),
                        icon: Icons.discount,
                        color: Colors.purple,
                        isTablet: isTablet,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),

          // Compact Filters Bar
          Container(
            color: Colors.white,
            padding: EdgeInsets.fromLTRB(16, 0, 16, isTablet ? 14 : 12),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _CompactFilterChip(
                    label: state.selectedPeriodLabel,
                    icon: Icons.calendar_today,
                    onTap: () => _showPeriodSheet(context),
                    isTablet: isTablet,
                  ),
                  const SizedBox(width: 8),
                  _CompactFilterChip(
                    label: state.selectedBranch,
                    icon: Icons.store,
                    onTap: () => _showBranchPicker(context),
                    isTablet: isTablet,
                  ),
                  const SizedBox(width: 8),
                  _CompactFilterChip(
                    label: state.selectedSalesman,
                    icon: Icons.person,
                    onTap: () => _showSalesmanPicker(context),
                    isTablet: isTablet,
                  ),
                  const SizedBox(width: 8),
                  _CompactFilterChip(
                    label: state.selectedPaymentStatus,
                    icon: Icons.payment,
                    onTap: () => _showPaymentStatusPicker(context),
                    isTablet: isTablet,
                  ),
                  const SizedBox(width: 8),
                  _CompactFilterChip(
                    label: state.selectedSupplier,
                    icon: Icons.inventory_2,
                    onTap: () => _showSupplierPicker(context),
                    isTablet: isTablet,
                  ),
                ],
              ),
            ),
          ),

          const Divider(height: 1),

          // Invoice List Header
          Container(
            color: Colors.white,
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: isTablet ? 14 : 12),
            child: Row(
              children: [
                Text(
                  'Invoice List',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: isTablet ? 16 : 15,
                    color: Colors.black87,
                  ),
                ),
                const Spacer(),
                if (state.loading)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      SizedBox(
                        height: 14,
                        width: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      SizedBox(width: 6),
                      Text('Loading...', style: TextStyle(color: Colors.grey, fontSize: 12)),
                    ],
                  )
                else
                  Text(
                    '${state.rows.length} records',
                    style: TextStyle(
                      fontSize: isTablet ? 14 : 13,
                      color: Colors.grey,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
              ],
            ),
          ),

          const Divider(height: 1),

          // Sales Table / Loading / Error
          Expanded(
            child: state.error != null
                ? _ErrorWidget(
              error: state.error!,
              onRetry: () => state.refresh(),
            )
                : state.rows.isEmpty && !state.loading
                ? const _EmptyWidget()
                : _InvoiceList(
              rows: state.rows,
              hasMore: state.hasMore,
              onNeedMore: state.loadMore,
              isTablet: isTablet,
            ),
          ),
        ],
      ),
    );
  }

  double _metricWidth(double maxWidth, bool isTablet) {
    if (!isTablet) return (maxWidth - 12) / 2; // two per row on phone
    if (maxWidth >= 1100) {
      final gaps = 12.0 * 3; // 4 items => 3 gaps
      return (maxWidth - gaps) / 4;
    } else {
      final gaps = 12.0 * 2; // 3 items => 2 gaps
      return (maxWidth - gaps) / 3;
    }
  }

  /* --------------------- Export Options --------------------- */

  void _showExportOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20),
                  child: Text(
                    'Export Report',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                ListTile(
                  leading: const Icon(Icons.picture_as_pdf, color: Colors.red),
                  title: const Text('Export as PDF'),
                  subtitle: const Text('Professional format for printing'),
                  onTap: () {
                    Navigator.pop(context);
                    _exportPdf();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.table_chart, color: Colors.green),
                  title: const Text('Export as Excel (Itemized)'),
                  subtitle: const Text('Includes Product/Brand/Category/Supplier/Unit'),
                  onTap: () async {
                    Navigator.pop(context);
                    await _exportExcel(itemized: true);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.table_rows_outlined, color: Colors.teal),
                  title: const Text('Export as Excel (Invoice Header)'),
                  subtitle: const Text('One row per invoice'),
                  onTap: () async {
                    Navigator.pop(context);
                    await _exportExcel(itemized: false);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.text_snippet, color: Colors.blue),
                  title: const Text('Export as CSV'),
                  subtitle: const Text('Simple text format'),
                  onTap: () {
                    Navigator.pop(context);
                    _exportCsv();
                  },
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /* --------------------- PDF Export --------------------- */

  Future<void> _exportPdf() async {
    try {
      final pdf = pw.Document();
      final currency = NumberFormat.currency(symbol: '₱', decimalDigits: 2);
      final dateFormat = DateFormat('MMM dd, yyyy');

      const pageFormat = PdfPageFormat.legal;

      pdf.addPage(
        pw.MultiPage(
          pageFormat: pageFormat,
          margin: const pw.EdgeInsets.all(40),
          build: (context) => [
            // Header
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'SALES REPORT',
                  style: pw.TextStyle(
                    fontSize: 24,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 8),
                pw.Text(
                  'Generated: ${dateFormat.format(DateTime.now())}',
                  style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600),
                ),
                pw.SizedBox(height: 4),
                pw.Text(
                  'Period: ${state.selectedPeriodLabel} | Branch: ${state.selectedBranch} | Salesman: ${state.selectedSalesman} | Supplier: ${state.selectedSupplier}',
                  style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600),
                ),
                pw.SizedBox(height: 20),
              ],
            ),

            // Summary
            pw.Container(
              padding: const pw.EdgeInsets.all(16),
              decoration: pw.BoxDecoration(
                color: PdfColors.grey100,
                borderRadius: pw.BorderRadius.circular(8),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  _buildPdfSummaryItem('Total Sales', currency.format(state.totalSales)),
                  _buildPdfSummaryItem('Collection', currency.format(state.totalCollection)),
                  _buildPdfSummaryItem('Returns', currency.format(state.totalReturns)),
                  _buildPdfSummaryItem('Discounts', currency.format(state.totalDiscounts)),
                ],
              ),
            ),

            pw.SizedBox(height: 24),

            // Table
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey300),
              columnWidths: {
                0: const pw.FlexColumnWidth(1.2), // Invoice No
                1: const pw.FlexColumnWidth(1), // Date
                2: const pw.FlexColumnWidth(2), // Customer
                3: const pw.FlexColumnWidth(1.5), // Salesman
                4: const pw.FlexColumnWidth(1), // Branch
                5: const pw.FlexColumnWidth(1.2), // Total
                6: const pw.FlexColumnWidth(1.2), // Collection
                7: const pw.FlexColumnWidth(1), // Status
              },
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.grey800),
                  children: [
                    _buildPdfTableHeader('Invoice No'),
                    _buildPdfTableHeader('Date'),
                    _buildPdfTableHeader('Customer'),
                    _buildPdfTableHeader('Salesman'),
                    _buildPdfTableHeader('Branch'),
                    _buildPdfTableHeader('Total'),
                    _buildPdfTableHeader('Collection'),
                    _buildPdfTableHeader('Status'),
                  ],
                ),
                ...state.rows.map((row) {
                  final dateStr = row.invoiceDate != null ? dateFormat.format(row.invoiceDate!) : '—';
                  return pw.TableRow(
                    children: [
                      _buildPdfTableCell(row.invoiceNo),
                      _buildPdfTableCell(dateStr),
                      _buildPdfTableCell(row.customerName),
                      _buildPdfTableCell(row.salesman),
                      _buildPdfTableCell(row.branch),
                      _buildPdfTableCell(currency.format(row.totalAmount), align: pw.TextAlign.right),
                      _buildPdfTableCell(currency.format(row.collection), align: pw.TextAlign.right),
                      _buildPdfTableCell(row.paymentStatus),
                    ],
                  );
                }),
              ],
            ),

            pw.SizedBox(height: 24),

            // Footer
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  'Total Records: ${state.rows.length}',
                  style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text(
                      'Grand Total: ${currency.format(state.totalCollection)}',
                      style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
                    ),
                  ],
                ),
              ],
            ),
          ],
          footer: (context) => pw.Column(
            children: [
              pw.Divider(),
              pw.SizedBox(height: 8),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    'Sales Report - Generated by System',
                    style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
                  ),
                  pw.Text(
                    'Page ${context.pageNumber} of ${context.pagesCount}',
                    style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
                  ),
                ],
              ),
            ],
          ),
        ),
      );

      await Printing.layoutPdf(
        onLayout: (format) async => pdf.save(),
        name: 'sales_report_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.pdf',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error generating PDF: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  pw.Widget _buildPdfSummaryItem(String label, String value) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          label,
          style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          value,
          style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
        ),
      ],
    );
  }

  pw.Widget _buildPdfTableHeader(String text) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(6),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: 8,
          fontWeight: pw.FontWeight.bold,
          color: PdfColors.white,
        ),
      ),
    );
  }

  pw.Widget _buildPdfTableCell(String text, {pw.TextAlign align = pw.TextAlign.left}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(6),
      child: pw.Text(
        text,
        style: const pw.TextStyle(fontSize: 7),
        textAlign: align,
      ),
    );
  }

  /* --------------------- Excel Export (Itemized-aware) --------------------- */
  Future<void> _exportExcel({bool itemized = true}) async {
    try {
      List<SalesReportRow> rowsForExport;
      if (itemized) {
        try {
          rowsForExport = await state.getItemizedRowsForExport();
        } catch (_) {
          rowsForExport = state.rows;
        }
      } else {
        rowsForExport = state.rows;
      }

      final divisionLookup = await _loadDivisionLookup();

      final excel = xl.Excel.createExcel();
      final sheet = excel['Sales Report'];

      final currency = NumberFormat.currency(symbol: '₱', decimalDigits: 2);
      final dateFormat = DateFormat('MMM dd, yyyy');

      // Base column widths
      sheet.setColumnWidth(0, 15);  // Invoice No
      sheet.setColumnWidth(1, 12);  // Date
      sheet.setColumnWidth(2, 25);  // Customer
      sheet.setColumnWidth(3, 20);  // Salesman
      sheet.setColumnWidth(4, 15);  // Branch
      sheet.setColumnWidth(5, 15);  // Payment Terms
      sheet.setColumnWidth(6, 12);  // Sales Type
      sheet.setColumnWidth(7, 15);  // Total Amount (invoice)
      sheet.setColumnWidth(8, 15);  // Discount (invoice)
      sheet.setColumnWidth(9, 15);  // Returns (invoice)
      sheet.setColumnWidth(10, 15); // Collection (invoice)
      sheet.setColumnWidth(11, 12); // Status

      // Extra widths for itemized
      if (itemized) {
        sheet.setColumnWidth(12, 28); // Product
        sheet.setColumnWidth(13, 18); // Brand
        sheet.setColumnWidth(14, 18); // Category
        sheet.setColumnWidth(15, 24); // Supplier
        sheet.setColumnWidth(16, 16); // Unit Price
        sheet.setColumnWidth(17, 12); // Quantity
        sheet.setColumnWidth(18, 12); // Ties
        sheet.setColumnWidth(19, 12); // Boxes
        sheet.setColumnWidth(20, 12); // Pieces
        sheet.setColumnWidth(21, 16); // Division
        sheet.setColumnWidth(22, 16); // Customer Province
        sheet.setColumnWidth(23, 16); // Customer City
        sheet.setColumnWidth(24, 16); // Line Gross
        sheet.setColumnWidth(25, 16); // Line Discount
        sheet.setColumnWidth(26, 18); // Line Net
      }

      int row = 0;

      final headerInvoiceCols = [
        'Invoice No',
        'Date',
        'Customer',
        'Salesman',
        'Branch',
        'Payment Terms',
        'Sales Type',
        'Total Amount (Invoice)',
        'Discount (Invoice)',
        'Returns (Invoice)',
        'Collection (Invoice)',
        'Status',
      ];

      final headerItemizedCols = [
        'Product',
        'Brand',
        'Category',
        'Supplier',
        'Unit Price',
        'Quantity',
        'Ties',
        'Boxes',
        'Pieces',
        'Division',
        'Customer Province',
        'Customer City',
        // New, use these for supplier-filtered sums:
        'Line Gross',
        'Line Discount',
        'Line Net',
      ];

      final headers = itemized ? [...headerInvoiceCols, ...headerItemizedCols] : headerInvoiceCols;

      // Title
      sheet.merge(
        xl.CellIndex.indexByString('A1'),
        xl.CellIndex.indexByString('${_colLetter(headers.length - 1)}1'),
      );
      var titleCell = sheet.cell(xl.CellIndex.indexByString('A1'));
      titleCell.value = xl.TextCellValue('SALES REPORT');
      titleCell.cellStyle = xl.CellStyle(
        bold: true,
        fontSize: 16,
        horizontalAlign: xl.HorizontalAlign.Center,
      );
      row++;

      // Metadata
      row++;
      sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row)).value =
          xl.TextCellValue('Generated: ${dateFormat.format(DateTime.now())}');
      row++;
      sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row)).value =
          xl.TextCellValue('Period: ${state.selectedPeriodLabel} ');
      row++;
      sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row)).value =
          xl.TextCellValue('Branch: ${state.selectedBranch}');
      row++;
      sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row)).value =
          xl.TextCellValue('Salesman: ${state.selectedSalesman}');
      row++;
      sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row)).value =
          xl.TextCellValue('Supplier: ${state.selectedSupplier}');
      row += 2;

      // Header row
      for (int i = 0; i < headers.length; i++) {
        var cell = sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: i, rowIndex: row));
        cell.value = xl.TextCellValue(headers[i]);
        cell.cellStyle = xl.CellStyle(
          bold: true,
          backgroundColorHex: xl.ExcelColor.fromHexString('#D3D3D3'),
          horizontalAlign: xl.HorizontalAlign.Center,
        );
      }
      row++;

      // Data rows
      for (var data in rowsForExport) {
        final dateStr = data.invoiceDate != null ? dateFormat.format(data.invoiceDate!) : null;

        // Always write invoice-level values in their fixed columns
        _writeTextOrNA(sheet, col: 0, row: row, text: data.invoiceNo);
        _writeTextOrNA(sheet, col: 1, row: row, text: dateStr);
        _writeTextOrNA(sheet, col: 2, row: row, text: data.customerName);
        _writeTextOrNA(sheet, col: 3, row: row, text: data.salesman);
        _writeTextOrNA(sheet, col: 4, row: row, text: data.branch);
        _writeTextOrNA(sheet, col: 5, row: row, text: data.paymentTerms);
        _writeTextOrNA(sheet, col: 6, row: row, text: data.salesType);

        // These are invoice-level totals; keep for reference
        _writeNumOrNA(sheet, col: 7,  row: row, value: data.totalAmount);
        _writeNumOrNA(sheet, col: 8,  row: row, value: data.discountAmount);
        _writeNumOrNA(sheet, col: 9,  row: row, value: data.returnAmount);
        _writeNumOrNA(sheet, col: 10, row: row, value: data.collection);
        _writeTextOrNA(sheet, col: 11, row: row, text: data.paymentStatus);

        if (itemized) {
          _writeTextOrNA(sheet, col: 12, row: row, text: data.productName);
          _writeTextOrNA(sheet, col: 13, row: row, text: data.productBrand);
          _writeTextOrNA(sheet, col: 14, row: row, text: data.productCategory);
          _writeTextOrNA(sheet, col: 15, row: row, text: data.productSupplier);

          final unitPrice = (data.productUnitPrice ?? 0);
          final qty       = (data.productQuantity ?? 0);
          final lineGross = unitPrice * qty;
          final lineDisc  = (data.productDiscountAmount ?? 0);
          final lineNet   = lineGross - lineDisc;

          _writeNumOrNA(sheet, col: 16, row: row, value: unitPrice);
          _writeNumOrNA(sheet, col: 17, row: row, value: qty);

          final split = _splitQtyByUnit(data.productQuantity, data.productUnit);
          _writeNumOrNA(sheet, col: 18, row: row, value: split.ties);
          _writeNumOrNA(sheet, col: 19, row: row, value: split.boxes);
          _writeNumOrNA(sheet, col: 20, row: row, value: split.pieces);

          String? divText = data.salesmanDivision;
          if (divText != null && divText.trim().isNotEmpty && _isNumeric(divText)) {
            final id = int.tryParse(divText.trim());
            if (id != null && divisionLookup.isNotEmpty) {
              divText = divisionLookup[id] ?? divText;
            }
          }
          _writeTextOrNA(sheet, col: 21, row: row, text: divText);

          _writeTextOrNA(sheet, col: 22, row: row, text: data.customerProvince);
          _writeTextOrNA(sheet, col: 23, row: row, text: data.customerCity);

          // NEW: per-line financials — use these for sums after filtering by supplier
          _writeNumOrNA(sheet, col: 24, row: row, value: lineGross);
          _writeNumOrNA(sheet, col: 25, row: row, value: lineDisc);
          _writeNumOrNA(sheet, col: 26, row: row, value: lineNet);
        }

        row++;
      }

      final bytes = excel.encode();
      if (bytes != null) {
        final dir = await getTemporaryDirectory();
        final filename = 'sales_report_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.xlsx';
        final file = File('${dir.path}/$filename');
        await file.writeAsBytes(bytes);

        await Share.shareXFiles(
          [XFile(file.path)],
          subject: 'Sales Report',
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(itemized ? 'Excel (Itemized) file generated successfully' : 'Excel (Header) file generated successfully'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error generating Excel: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // Convert 0-based column index to Excel letter (0 -> A, 23 -> X, etc.)
  String _colLetter(int zeroBasedIndex) {
    int n = zeroBasedIndex + 1;
    String s = '';
    while (n > 0) {
      final rem = (n - 1) % 26;
      s = String.fromCharCode(65 + rem) + s;
      n = (n - 1) ~/ 26;
    }
    return s;
  }

  // Write a text cell, or 'N/A' when text is null/empty
  void _writeTextOrNA(xl.Sheet sheet, {required int col, required int row, String? text}) {
    final v = (text == null || text.trim().isEmpty) ? 'N/A' : text.trim();
    sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row)).value = xl.TextCellValue(v);
  }

  // Write numeric when non-null, else 'N/A'
  void _writeNumOrNA(xl.Sheet sheet, {required int col, required int row, num? value}) {
    final cell = sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row));
    if (value == null) {
      cell.value = xl.TextCellValue('N/A');
    } else {
      cell.value = xl.DoubleCellValue(value.toDouble());
    }
  }

  /* --------------------- Pickers / Filters --------------------- */

  void _showFilterDialog(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => _PickerSheet(
        title: 'Quick Filters',
        items: kPeriods,
        onSelected: (value) => _handlePeriodSelect(context, value),
      ),
    );
  }

  // New period picker with tabs
  void _showPeriodSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => _PeriodPickerSheet(
        onPresetSelected: (value) => _handlePeriodSelect(context, value),
        onPickMonth: (year, month) {
          state.setMonth(year, month);
          Navigator.pop(context);
        },
        onPickRange: (DateTimeRange range) {
          state.setCustomRange(range.start, range.end);
          Navigator.pop(context);
        },
      ),
    );
  }

  Future<void> _handlePeriodSelect(BuildContext context, String value) async {
    if (value == 'Custom') {
      final now = DateTime.now();
      final first = DateTime(now.year, now.month, 1);
      final picked = await showDateRangePicker(
        context: context,
        firstDate: DateTime(now.year - 3),
        lastDate: DateTime(now.year + 3),
        initialDateRange: DateTimeRange(start: first, end: now),
        helpText: 'Select custom period',
      );
      if (picked != null) {
        state.setCustomRange(picked.start, picked.end);
      }
    } else {
      state.setPeriod(value);
    }
    if (mounted) Navigator.pop(context);
  }

  void _showBranchPicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => _PickerSheet(
        title: 'Select Branch',
        items: state.branchOptions,
        onSelected: state.setBranch,
      ),
    );
  }

  void _showSalesmanPicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => _PickerSheet(
        title: 'Select Salesman',
        items: state.salesmanOptions,
        onSelected: state.setSalesman,
      ),
    );
  }

  void _showPaymentStatusPicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => _PickerSheet(
        title: 'Payment Status',
        items: state.paymentStatusOptions,
        onSelected: state.setPaymentStatus,
      ),
    );
  }

  // Supplier picker
  void _showSupplierPicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => _PickerSheet(
        title: 'Select Supplier',
        items: state.supplierOptions,
        onSelected: state.setSupplier,
      ),
    );
  }

  /* ------------------------ CSV Export ------------------------ */

  void _exportCsv() async {
    final divisionLookup = await _loadDivisionLookup();
    final csv = salesReportToCsv(state.rows, divisionLookup: divisionLookup);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: DraggableScrollableSheet(
            expand: false,
            minChildSize: 0.3,
            maxChildSize: 0.9,
            initialChildSize: 0.6,
            builder: (_, controller) => Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  Row(
                    children: [
                      const Text(
                        'CSV Preview',
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                      ),
                      const Spacer(),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: SingleChildScrollView(
                      controller: controller,
                      child: SelectableText(
                        csv,
                        style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/* ======================= PRESENTATION WIDGETS ======================= */

class _InvoiceList extends StatefulWidget {
  final List<SalesReportRow> rows;
  final bool hasMore;
  final VoidCallback onNeedMore;
  final bool isTablet;

  const _InvoiceList({
    required this.rows,
    required this.hasMore,
    required this.onNeedMore,
    required this.isTablet,
  });

  @override
  State<_InvoiceList> createState() => _InvoiceListState();
}

class _InvoiceListState extends State<_InvoiceList> {
  bool _askedMore = false;

  @override
  Widget build(BuildContext context) {
    final pad = widget.isTablet ? const EdgeInsets.all(18) : const EdgeInsets.all(16);

    if (!widget.isTablet) {
      // Phone: ListView
      return ListView.separated(
        padding: pad,
        itemCount: widget.rows.length + (widget.hasMore ? 1 : 0),
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          if (index >= widget.rows.length) {
            if (!_askedMore) {
              _askedMore = true;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                widget.onNeedMore();
                _askedMore = false;
              });
            }
            return const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
              ),
            );
          }
          final row = widget.rows[index];
          return _SalesInvoiceCard(row: row, isTablet: false);
        },
      );
    }

    // Tablet: Grid (2–3 columns based on width)
    final width = MediaQuery.sizeOf(context).width;
    final columns = width ~/ 520; // target ~520px per card
    final crossAxisCount = columns.clamp(2, 3);

    return GridView.builder(
      padding: pad,
      itemCount: widget.rows.length + (widget.hasMore ? 1 : 0),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
        mainAxisExtent: 220,
      ),
      itemBuilder: (context, index) {
        if (index >= widget.rows.length) {
          if (!_askedMore) {
            _askedMore = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              widget.onNeedMore();
              _askedMore = false;
            });
          }
          return const Center(
            child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)),
          );
        }
        final row = widget.rows[index];
        return _SalesInvoiceCard(row: row, isTablet: true);
      },
    );
  }
}

class _CompactMetricCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final bool isTablet;

  const _CompactMetricCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.isTablet = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: isTablet ? 14 : 12, vertical: isTablet ? 12 : 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: isTablet ? 20 : 18),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: isTablet ? 11 : 10,
                  color: Colors.grey[700],
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: TextStyle(
                  fontSize: isTablet ? 16 : 14,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CompactFilterChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool isTablet;

  const _CompactFilterChip({
    required this.label,
    required this.icon,
    required this.onTap,
    this.isTablet = false,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: isTablet ? 12 : 10, vertical: isTablet ? 9 : 8),
        decoration: BoxDecoration(
          color: Colors.grey[100],
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey[300]!),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: isTablet ? 16 : 14, color: Colors.grey[700]),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: isTablet ? 13 : 12,
                color: Colors.grey[800],
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.arrow_drop_down, size: isTablet ? 20 : 18, color: Colors.grey[700]),
          ],
        ),
      ),
    );
  }
}

class _ErrorWidget extends StatelessWidget {
  final String error;
  final VoidCallback onRetry;

  const _ErrorWidget({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, color: Colors.red[700], size: 48),
            const SizedBox(height: 16),
            Text(
              'Error Loading Data',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.grey[800],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              error,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyWidget extends StatelessWidget {
  const _EmptyWidget();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.inbox_outlined, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            'No Results Found',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.grey[700],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Try adjusting your filters',
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }
}

class _SalesInvoiceCard extends StatelessWidget {
  final SalesReportRow row;
  final bool isTablet;

  const _SalesInvoiceCard({required this.row, this.isTablet = false});

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('MMM dd, yyyy');
    final dateStr = row.invoiceDate != null ? dateFormat.format(row.invoiceDate!) : '—';
    final currency = NumberFormat.currency(symbol: '₱', decimalDigits: 2);

    final paid = row.paymentStatus.toLowerCase() == 'paid';

    return InkWell(
      onTap: () {
        // TODO: Navigate to invoice details if needed
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: EdgeInsets.all(isTablet ? 16 : 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey[300]!),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Row - Invoice & Amount
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        row.invoiceNo,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: isTablet ? 16 : 15,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        dateStr,
                        style: TextStyle(
                          fontSize: isTablet ? 13 : 12,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      currency.format(row.collection),
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: isTablet ? 18 : 16,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 4),
                    _StatusBadge(
                      label: row.paymentStatus,
                      color: paid ? Colors.green : Colors.orange,
                      isTablet: isTablet,
                    ),
                  ],
                ),
              ],
            ),

            const SizedBox(height: 10),
            Divider(height: 1, color: Colors.grey[200]),
            const SizedBox(height: 10),

            // Customer Info
            Row(
              children: [
                Icon(Icons.person, size: isTablet ? 15 : 14, color: Colors.grey[600]),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    row.customerName,
                    style: TextStyle(
                      fontSize: isTablet ? 14 : 13,
                      fontWeight: FontWeight.w500,
                      color: Colors.black87,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(Icons.location_on, size: isTablet ? 15 : 14, color: Colors.grey[600]),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    row.customerAddress,
                    style: TextStyle(
                      fontSize: isTablet ? 13 : 12,
                      color: Colors.grey[700],
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 10),
            Divider(height: 1, color: Colors.grey[200]),
            const SizedBox(height: 10),

            // Sales Details
            Row(
              children: [
                Expanded(
                  child: _CompactInfoItem(
                    icon: Icons.person_outline,
                    label: row.salesman,
                    isTablet: isTablet,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _CompactInfoItem(
                    icon: Icons.store,
                    label: row.branch,
                    isTablet: isTablet,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _CompactInfoItem(
                    icon: Icons.payment,
                    label: row.paymentTerms,
                    isTablet: isTablet,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _CompactInfoItem(
                    icon: Icons.category,
                    label: row.salesType,
                    isTablet: isTablet,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 10),
            Divider(height: 1, color: Colors.grey[200]),
            const SizedBox(height: 10),

            // Amount Breakdown - Compact
            _CompactAmountRow(label: 'Total', amount: row.totalAmount, isTablet: isTablet),
            if (row.discountAmount > 0) ...[
              const SizedBox(height: 4),
              _CompactAmountRow(label: 'Discount', amount: row.discountAmount, isNegative: true, isTablet: isTablet),
            ],
            if (row.returnAmount > 0) ...[
              const SizedBox(height: 4),
              _CompactAmountRow(label: 'Returns', amount: row.returnAmount, isNegative: true, isTablet: isTablet),
            ],
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.green[50],
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(Icons.check_circle, size: isTablet ? 15 : 14, color: Colors.green[700]),
                      const SizedBox(width: 6),
                      Text(
                        'Collection',
                        style: TextStyle(
                          fontSize: isTablet ? 13 : 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.green[700],
                        ),
                      ),
                    ],
                  ),
                  Text(
                    NumberFormat.currency(symbol: '₱', decimalDigits: 2).format(row.collection),
                    style: TextStyle(
                      fontSize: isTablet ? 14 : 13,
                      fontWeight: FontWeight.bold,
                      color: Colors.green[700],
                    ),
                  ),
                ],
              ),
            ),

            if (row.isPosted || row.isDispatched) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  if (row.isPosted) _TinyBadge(label: 'Posted', icon: Icons.check_circle, color: Colors.blue, isTablet: isTablet),
                  if (row.isDispatched) const SizedBox(width: 6),
                  if (row.isDispatched)
                    _TinyBadge(label: 'Dispatched', icon: Icons.local_shipping, color: Colors.purple, isTablet: isTablet),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CompactInfoItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isTablet;

  const _CompactInfoItem({
    required this.icon,
    required this.label,
    this.isTablet = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: isTablet ? 14 : 13, color: Colors.grey[600]),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: isTablet ? 13 : 12,
              color: Colors.grey[800],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _CompactAmountRow extends StatelessWidget {
  final String label;
  final double amount;
  final bool isNegative;
  final bool isTablet;

  const _CompactAmountRow({
    required this.label,
    required this.amount,
    this.isNegative = false,
    this.isTablet = false,
  });

  @override
  Widget build(BuildContext context) {
    final formatter = NumberFormat.currency(symbol: '₱', decimalDigits: 2);
    final displayAmount = isNegative ? '-${formatter.format(amount)}' : formatter.format(amount);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: isTablet ? 13 : 12, color: Colors.grey[700])),
          Text(
            displayAmount,
            style: TextStyle(
              fontSize: isTablet ? 13 : 12,
              color: isNegative ? Colors.red[700] : Colors.black87,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String label;
  final Color color;
  final bool isTablet;

  const _StatusBadge({
    required this.label,
    required this.color,
    this.isTablet = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: isTablet ? 10 : 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.3), width: 1),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: isTablet ? 11 : 10,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

class _TinyBadge extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final bool isTablet;

  const _TinyBadge({
    required this.label,
    required this.icon,
    required this.color,
    this.isTablet = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: isTablet ? 7 : 6, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: isTablet ? 11 : 10, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: isTablet ? 10 : 9,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

// --- NEW WIDGET ---
class _PeriodPickerSheet extends StatefulWidget {
  final void Function(String preset) onPresetSelected;
  final void Function(int year, int month) onPickMonth;
  final void Function(DateTimeRange range) onPickRange;

  const _PeriodPickerSheet({
    required this.onPresetSelected,
    required this.onPickMonth,
    required this.onPickRange,
  });

  @override
  State<_PeriodPickerSheet> createState() => _PeriodPickerSheetState();
}

class _PeriodPickerSheetState extends State<_PeriodPickerSheet> {
  late int _year;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _year = now.year;
  }

  @override
  Widget build(BuildContext context) {
    final months = const ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    final maxH = MediaQuery.of(context).size.height * 0.8;

    return DefaultTabController(
      length: 3,
      child: Container(
        constraints: BoxConstraints(maxHeight: maxH),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
              child: Row(
                children: [
                  const Text(
                    'Select Period',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, size: 20),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),
            const TabBar(
              labelColor: Colors.black87,
              tabs: [
                Tab(text: 'Presets'),
                Tab(text: 'Month'),
                Tab(text: 'Range'),
              ],
            ),
            const Divider(height: 1),

            // Content
            Expanded(
              child: TabBarView(
                children: [
                  // --- Presets ---
                  ListView(
                    shrinkWrap: true,
                    children: [
                      for (final p in kPeriods)
                        ListTile(
                          title: Text(p),
                          dense: true,
                          onTap: () => widget.onPresetSelected(p),
                        ),
                    ],
                  ),

                  // --- Month picker ---
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            IconButton(
                              tooltip: 'Previous Year',
                              onPressed: () => setState(() => _year--),
                              icon: const Icon(Icons.chevron_left),
                            ),
                            Expanded(
                              child: Center(
                                child: Text('$_year', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                              ),
                            ),
                            IconButton(
                              tooltip: 'Next Year',
                              onPressed: () => setState(() => _year++),
                              icon: const Icon(Icons.chevron_right),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Expanded(
                          child: GridView.builder(
                            padding: const EdgeInsets.only(bottom: 16),
                            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 4,
                              mainAxisSpacing: 10,
                              crossAxisSpacing: 10,
                              childAspectRatio: 1.7,
                            ),
                            itemCount: 12,
                            itemBuilder: (_, i) {
                              final monthIdx = i + 1;
                              return OutlinedButton(
                                onPressed: () => widget.onPickMonth(_year, monthIdx),
                                style: OutlinedButton.styleFrom(
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  padding: const EdgeInsets.symmetric(vertical: 10),
                                ),
                                child: Text(
                                  months[i],
                                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),

                  // --- Date range picker ---
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('Pick a custom date range', style: TextStyle(fontSize: 14, color: Colors.black54)),
                          const SizedBox(height: 12),
                          FilledButton.icon(
                            icon: const Icon(Icons.date_range),
                            label: const Text('Choose Date Range'),
                            onPressed: () async {
                              final now = DateTime.now();
                              final first = DateTime(now.year - 3, 1, 1);
                              final last = DateTime(now.year + 3, 12, 31);
                              final picked = await showDateRangePicker(
                                context: context,
                                firstDate: first,
                                lastDate: last,
                                helpText: 'Select custom period',
                              );
                              if (picked != null) {
                                widget.onPickRange(picked);
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
// --- END NEW WIDGET ---

class _PickerSheet extends StatelessWidget {
  final String title;
  final List<String> items;
  final Function(String) onSelected;

  const _PickerSheet({
    required this.title,
    required this.items,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.6,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close, size: 20),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final item = items[index];
                    return ListTile(
                      title: Text(item, style: const TextStyle(fontSize: 14)),
                      dense: true,
                      onTap: () {
                        onSelected(item);
                        Navigator.pop(context);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/* ======================= CSV FALLBACK (LOCAL) ======================= */

/// CSV generator updated to also map division ids to names via [divisionLookup]
String salesReportToCsv(
    List<SalesReportRow> rows, {
      Map<int, String> divisionLookup = const {},
    }) {
  final dateFormat = DateFormat('yyyy-MM-dd');
  final sb = StringBuffer();

  // Headers
  sb.writeln([
    'Invoice No',
    'Date',
    'Customer',
    'Address',
    'Salesman',
    'Branch',
    'Payment Terms',
    'Sales Type',
    'Total Amount',
    'Discount',
    'Returns',
    'Collection',
    'Status',
    // itemized
    'Product',
    'Brand',
    'Category',
    'Supplier',
    'Unit Price',
    'Quantity',
    'Unit',
    'Division',
    'Customer Province',
    'Customer City',
  ].map(_csvEscape).join(','));

  bool _isNumericLocal(String s) => int.tryParse(s.trim()) != null;

  // Rows
  for (final r in rows) {
    final dateStr = r.invoiceDate != null ? dateFormat.format(r.invoiceDate!) : '';
    String divisionText = (r.salesmanDivision ?? '').trim();
    if (divisionText.isNotEmpty && _isNumericLocal(divisionText)) {
      final id = int.tryParse(divisionText);
      if (id != null && divisionLookup.containsKey(id)) {
        divisionText = divisionLookup[id]!;
      }
    }

    final line = [
      r.invoiceNo,
      dateStr,
      r.customerName,
      r.customerAddress,
      r.salesman,
      r.branch,
      r.paymentTerms,
      r.salesType,
      r.totalAmount.toStringAsFixed(2),
      r.discountAmount.toStringAsFixed(2),
      r.returnAmount.toStringAsFixed(2),
      r.collection.toStringAsFixed(2),
      r.paymentStatus,
      // itemized
      r.productName ?? '',
      r.productBrand ?? '',
      r.productCategory ?? '',
      r.productSupplier ?? '',
      (r.productUnitPrice ?? 0).toString(),
      (r.productQuantity ?? 0).toString(),
      r.productUnit ?? '',
      divisionText,
      r.customerProvince ?? '',
      r.customerCity ?? '',
    ].map(_csvEscape).join(',');
    sb.writeln(line);
  }

  return sb.toString();
}

String _csvEscape(String v) {
  final needsQuotes = v.contains(',') || v.contains('"') || v.contains('\n');
  var out = v.replaceAll('"', '""');
  return needsQuotes ? '"$out"' : out;
}
