library sales_report_view;

// lib/modules/reports/sales_report/sr_view.dart

import "dart:io";

import "package:flutter/material.dart";
import "package:intl/intl.dart";
import "package:pdf/pdf.dart";
import "package:pdf/widgets.dart" as pw;
import "package:printing/printing.dart";
import "package:excel/excel.dart" as xl;
import "package:path_provider/path_provider.dart";
import "package:share_plus/share_plus.dart";

import "package:sqflite/sqflite.dart";
import "package:vos_mobile/data/local/app_db.dart";

// ✅ Correct path to your updated state file
import "package:vos_mobile/state/sales_report/sales_report_starte.dart";

part "sr_helpers.dart";
part "sr_sheets.dart";
part "sr_exporter.dart";
part "sr_widgets.dart";

class SalesReportView extends StatefulWidget {
  const SalesReportView({Key? key}) : super(key: key);

  @override
  State<SalesReportView> createState() => _SalesReportViewState();
}

class _SalesReportViewState extends State<SalesReportView>
    with
        DivisionLookupMixin<SalesReportView>,
        SalesReportSheetsMixin<SalesReportView>,
        SalesReportExportMixin<SalesReportView> {
  final SalesReportState state = SalesReportState();
  late VoidCallback _sub;

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
    final currency = NumberFormat.currency(symbol: "₱", decimalDigits: 2);
    final width = MediaQuery.sizeOf(context).width;
    final isTablet = width >= 900;

    // 🔑 Deduplicate rows by invoice (fix "quad entry" in UI)
    final visibleRows = _dedupSalesRows(state.rows);

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        title: Text(
          "Sales Report",
          style: TextStyle(
            color: Colors.black87,
            fontSize: isTablet ? 22 : 20,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          IconButton(
            icon:
            const Icon(Icons.filter_list, color: Colors.black87, size: 22),
            onPressed: () => _showFilterDialog(context),
            tooltip: "Filters",
          ),
          IconButton(
            icon: const Icon(Icons.download, color: Colors.black87, size: 22),
            onPressed: () => _showExportOptions(context),
            tooltip: "Export",
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
                        label: "Total Sales",
                        value: currency.format(state.totalSales),
                        icon: Icons.trending_up,
                        color: Colors.blue,
                        isTablet: isTablet,
                      ),
                    ),
                    SizedBox(
                      width: _metricWidth(c.maxWidth, isTablet),
                      child: _CompactMetricCard(
                        label: "Collection",
                        value: currency.format(state.totalCollection),
                        icon: Icons.account_balance_wallet,
                        color: Colors.green,
                        isTablet: isTablet,
                      ),
                    ),
                    SizedBox(
                      width: _metricWidth(c.maxWidth, isTablet),
                      child: _CompactMetricCard(
                        label: "Returns",
                        value: currency.format(state.totalReturns),
                        icon: Icons.assignment_return,
                        color: Colors.orange,
                        isTablet: isTablet,
                      ),
                    ),
                    SizedBox(
                      width: _metricWidth(c.maxWidth, isTablet),
                      child: _CompactMetricCard(
                        label: "Discounts",
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
            padding: EdgeInsets.symmetric(
                horizontal: 16, vertical: isTablet ? 14 : 12),
            child: Row(
              children: [
                Text(
                  "Invoice List",
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
                      Text("Loading...",
                          style: TextStyle(color: Colors.grey, fontSize: 12)),
                    ],
                  )
                else
                  Text(
                    "${visibleRows.length} records",
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
                : visibleRows.isEmpty && !state.loading
                ? const _EmptyWidget()
                : _InvoiceList(
              rows: visibleRows,
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
}
