part of "sr_view.dart";

/* ======================= EXPORT MIXIN ======================= */

mixin SalesReportExportMixin<T extends StatefulWidget>
on State<T>, DivisionLookupMixin<T> {
  SalesReportState get state;

  /* --------------------- Export Options --------------------- */

  void _showExportOptions(BuildContext sheetContext) {
    showModalBottomSheet(
      context: sheetContext,
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
                    "Export Report",
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                ListTile(
                  leading: const Icon(Icons.picture_as_pdf, color: Colors.red),
                  title: const Text("Export as PDF"),
                  subtitle: const Text("Professional format for printing"),
                  onTap: () {
                    Navigator.pop(context);
                    _exportPdf();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.table_chart, color: Colors.green),
                  title: const Text("Export as Excel (Itemized)"),
                  subtitle: const Text(
                      "Includes Product/Brand/Category/Supplier/Unit/In Cases"),
                  onTap: () async {
                    Navigator.pop(context);
                    await _exportExcel(itemized: true);
                  },
                ),
                ListTile(
                  leading:
                  const Icon(Icons.table_rows_outlined, color: Colors.teal),
                  title: const Text("Export as Excel (Invoice Header)"),
                  subtitle: const Text("One row per invoice"),
                  onTap: () async {
                    Navigator.pop(context);
                    await _exportExcel(itemized: false);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.text_snippet, color: Colors.blue),
                  title: const Text("Export as CSV"),
                  subtitle: const Text("Simple text format"),
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
      final currency = NumberFormat.currency(symbol: "₱", decimalDigits: 2);
      final dateFormat = DateFormat("MMM dd, yyyy");

      const pageFormat = PdfPageFormat.legal;

      // use deduped rows for PDF as well
      final rows = _dedupSalesRows(state.rows);

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
                  "SALES REPORT",
                  style: pw.TextStyle(
                    fontSize: 24,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 8),
                pw.Text(
                  "Generated: ${dateFormat.format(DateTime.now())}",
                  style: const pw.TextStyle(
                      fontSize: 10, color: PdfColors.grey600),
                ),
                pw.SizedBox(height: 4),
                pw.Text(
                  "Period: ${state.selectedPeriodLabel} | Branch: ${state.selectedBranch} | Salesman: ${state.selectedSalesman} | Supplier: ${state.selectedSupplier}",
                  style: const pw.TextStyle(
                      fontSize: 10, color: PdfColors.grey600),
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
                  _buildPdfSummaryItem(
                      "Total Sales", currency.format(state.totalSales)),
                  _buildPdfSummaryItem(
                      "Collection", currency.format(state.totalCollection)),
                  _buildPdfSummaryItem(
                      "Returns", currency.format(state.totalReturns)),
                  _buildPdfSummaryItem(
                      "Discounts", currency.format(state.totalDiscounts)),
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
                    _buildPdfTableHeader("Invoice No"),
                    _buildPdfTableHeader("Date"),
                    _buildPdfTableHeader("Customer"),
                    _buildPdfTableHeader("Salesman"),
                    _buildPdfTableHeader("Branch"),
                    _buildPdfTableHeader("Total"),
                    _buildPdfTableHeader("Collection"),
                    _buildPdfTableHeader("Status"),
                  ],
                ),
                ...rows.map((row) {
                  final dateStr = row.invoiceDate != null
                      ? dateFormat.format(row.invoiceDate!)
                      : "—";
                  return pw.TableRow(
                    children: [
                      _buildPdfTableCell(row.invoiceNo),
                      _buildPdfTableCell(dateStr),
                      _buildPdfTableCell(row.customerName),
                      _buildPdfTableCell(row.salesman),
                      _buildPdfTableCell(row.branch),
                      _buildPdfTableCell(currency.format(row.totalAmount),
                          align: pw.TextAlign.right),
                      _buildPdfTableCell(currency.format(row.collection),
                          align: pw.TextAlign.right),
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
                  "Total Records: ${rows.length}",
                  style: pw.TextStyle(
                      fontSize: 10, fontWeight: pw.FontWeight.bold),
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text(
                      "Grand Total: ${currency.format(state.totalCollection)}",
                      style: pw.TextStyle(
                          fontSize: 12, fontWeight: pw.FontWeight.bold),
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
                    "Sales Report - Generated by System",
                    style: const pw.TextStyle(
                        fontSize: 8, color: PdfColors.grey600),
                  ),
                  pw.Text(
                    "Page ${context.pageNumber} of ${context.pagesCount}",
                    style: const pw.TextStyle(
                        fontSize: 8, color: PdfColors.grey600),
                  ),
                ],
              ),
            ],
          ),
        ),
      );

      await Printing.layoutPdf(
        onLayout: (format) async => pdf.save(),
        name:
        "sales_report_${DateFormat("yyyyMMdd_HHmmss").format(DateTime.now())}.pdf",
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Error generating PDF: $e"),
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

  pw.Widget _buildPdfTableCell(String text,
      {pw.TextAlign align = pw.TextAlign.left}) {
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
  /// ✅ Updated: includes customer_code in the raw Excel export for BOTH
  /// header-only and itemized exports.
  ///
  /// NOTE: Your SalesReportRow must expose a `customerCode` field
  /// mapped from `customer_code` (SQLite/MySQL view).
  Future<void> _exportExcel({bool itemized = true}) async {
    try {
      List<SalesReportRow> rowsForExport;
      if (itemized) {
        // Uses SalesReportState.getItemizedRowsForExport()
        try {
          rowsForExport = await state.getItemizedRowsForExport();
        } catch (_) {
          // Fallback to header-only rows, already deduped by invoice
          rowsForExport = _dedupSalesRows(state.rows);
        }
        // Extra safety: kill any quad duplicates per invoice+product
        rowsForExport = _dedupItemizedRows(rowsForExport);
      } else {
        rowsForExport = _dedupSalesRows(state.rows);
      }

      final divisionLookup = await _loadDivisionLookup();

      final excel = xl.Excel.createExcel();
      final sheet = excel["Sales Report"];

      final dateFormat = DateFormat("MMM dd, yyyy");

      // Base column widths (✅ shifted due to Customer Code column)
      sheet.setColumnWidth(0, 15); // Invoice No
      sheet.setColumnWidth(1, 12); // Date
      sheet.setColumnWidth(2, 16); // Customer Code ✅
      sheet.setColumnWidth(3, 25); // Customer
      sheet.setColumnWidth(4, 20); // Salesman
      sheet.setColumnWidth(5, 15); // Branch
      sheet.setColumnWidth(6, 15); // Payment Terms
      sheet.setColumnWidth(7, 12); // Sales Type
      sheet.setColumnWidth(8, 15); // Total Amount (invoice)
      sheet.setColumnWidth(9, 15); // Discount (invoice)
      sheet.setColumnWidth(10, 15); // Returns (invoice)
      sheet.setColumnWidth(11, 15); // Collection (invoice)
      sheet.setColumnWidth(12, 12); // Status

      // Extra widths for itemized (✅ shifted start index from 12 -> 13)
      if (itemized) {
        sheet.setColumnWidth(13, 28); // Product
        sheet.setColumnWidth(14, 18); // Brand
        sheet.setColumnWidth(15, 18); // Category
        sheet.setColumnWidth(16, 24); // Supplier
        sheet.setColumnWidth(17, 16); // Unit Price
        sheet.setColumnWidth(18, 12); // Quantity
        sheet.setColumnWidth(19, 12); // Ties
        sheet.setColumnWidth(20, 12); // Boxes
        sheet.setColumnWidth(21, 12); // Pieces
        sheet.setColumnWidth(22, 16); // In Cases
        sheet.setColumnWidth(23, 16); // Division
        sheet.setColumnWidth(24, 16); // Customer Province
        sheet.setColumnWidth(25, 16); // Customer City
        sheet.setColumnWidth(26, 16); // Line Gross
        sheet.setColumnWidth(27, 16); // Line Discount
        sheet.setColumnWidth(28, 18); // Line Net
      }

      int row = 0;

      final headerInvoiceCols = [
        "Invoice No",
        "Date",
        "Customer Code", // ✅ ADDED
        "Customer",
        "Salesman",
        "Branch",
        "Payment Terms",
        "Sales Type",
        "Total Amount (Invoice)",
        "Discount (Invoice)",
        "Returns (Invoice)",
        "Collection (Invoice)",
        "Status",
      ];

      final headerItemizedCols = [
        "Product",
        "Brand",
        "Category",
        "Supplier",
        "Unit Price",
        "Quantity",
        "Ties",
        "Boxes",
        "Pieces",
        "In Cases",
        "Division",
        "Customer Province",
        "Customer City",
        "Line Gross",
        "Line Discount",
        "Line Net",
      ];

      final headers =
      itemized ? [...headerInvoiceCols, ...headerItemizedCols] : headerInvoiceCols;

      // Title
      sheet.merge(
        xl.CellIndex.indexByString("A1"),
        xl.CellIndex.indexByString("${_colLetter(headers.length - 1)}1"),
      );
      var titleCell = sheet.cell(xl.CellIndex.indexByString("A1"));
      titleCell.value = xl.TextCellValue("SALES REPORT");
      titleCell.cellStyle = xl.CellStyle(
        bold: true,
        fontSize: 16,
        horizontalAlign: xl.HorizontalAlign.Center,
      );
      row++;

      // Metadata
      row++;
      sheet
          .cell(xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row))
          .value = xl.TextCellValue("Generated: ${dateFormat.format(DateTime.now())}");
      row++;
      sheet
          .cell(xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row))
          .value = xl.TextCellValue("Period: ${state.selectedPeriodLabel} ");
      row++;
      sheet
          .cell(xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row))
          .value = xl.TextCellValue("Branch: ${state.selectedBranch}");
      row++;
      sheet
          .cell(xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row))
          .value = xl.TextCellValue("Salesman: ${state.selectedSalesman}");
      row++;
      sheet
          .cell(xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row))
          .value = xl.TextCellValue("Supplier: ${state.selectedSupplier}");
      row += 2;

      // Header row
      for (int i = 0; i < headers.length; i++) {
        var cell =
        sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: i, rowIndex: row));
        cell.value = xl.TextCellValue(headers[i]);
        cell.cellStyle = xl.CellStyle(
          bold: true,
          backgroundColorHex: xl.ExcelColor.fromHexString("#D3D3D3"),
          horizontalAlign: xl.HorizontalAlign.Center,
        );
      }
      row++;

      // Data rows
      for (var data in rowsForExport) {
        final dateStr =
        data.invoiceDate != null ? dateFormat.format(data.invoiceDate!) : null;

        // invoice-level (✅ shifted due to Customer Code)
        _writeTextOrNA(sheet, col: 0, row: row, text: data.invoiceNo);
        _writeTextOrNA(sheet, col: 1, row: row, text: dateStr);

        // ✅ Customer Code column (requires SalesReportRow.customerCode)
        _writeTextOrNA(sheet, col: 2, row: row, text: data.customerCode);

        _writeTextOrNA(sheet, col: 3, row: row, text: data.customerName);
        _writeTextOrNA(sheet, col: 4, row: row, text: data.salesman);
        _writeTextOrNA(sheet, col: 5, row: row, text: data.branch);
        _writeTextOrNA(sheet, col: 6, row: row, text: data.paymentTerms);
        _writeTextOrNA(sheet, col: 7, row: row, text: data.salesType);

        _writeNumOrNA(sheet, col: 8, row: row, value: data.totalAmount);
        _writeNumOrNA(sheet, col: 9, row: row, value: data.discountAmount);
        _writeNumOrNA(sheet, col: 10, row: row, value: data.returnAmount);
        _writeNumOrNA(sheet, col: 11, row: row, value: data.collection);
        _writeTextOrNA(sheet, col: 12, row: row, text: data.paymentStatus);

        if (itemized) {
          // ✅ shifted start index 12 -> 13
          _writeTextOrNA(sheet, col: 13, row: row, text: data.productName);
          _writeTextOrNA(sheet, col: 14, row: row, text: data.productBrand);
          _writeTextOrNA(sheet, col: 15, row: row, text: data.productCategory);
          _writeTextOrNA(sheet, col: 16, row: row, text: data.productSupplier);

          final unitPrice = (data.productUnitPrice ?? 0);
          final qty = (data.productQuantity ?? 0);
          final lineGross = unitPrice * qty;
          final lineDisc = (data.productDiscountAmount ?? 0);
          final lineNet = lineGross - lineDisc;

          // inCases comes from SQL via SalesReportRow.inCases
          final inCases = data.inCases;

          _writeNumOrNA(sheet, col: 17, row: row, value: unitPrice);
          _writeNumOrNA(sheet, col: 18, row: row, value: qty);

          final split = _splitQtyByUnit(data.productQuantity, data.productUnit);
          _writeNumOrNA(sheet, col: 19, row: row, value: split.ties);
          _writeNumOrNA(sheet, col: 20, row: row, value: split.boxes);
          _writeNumOrNA(sheet, col: 21, row: row, value: split.pieces);

          _writeNumOrNA(sheet, col: 22, row: row, value: inCases);

          String? divText = data.salesmanDivision;
          if (divText != null && divText.trim().isNotEmpty && _isNumeric(divText)) {
            final id = int.tryParse(divText.trim());
            if (id != null && divisionLookup.isNotEmpty) {
              divText = divisionLookup[id] ?? divText;
            }
          }
          _writeTextOrNA(sheet, col: 23, row: row, text: divText);

          _writeTextOrNA(sheet, col: 24, row: row, text: data.customerProvince);
          _writeTextOrNA(sheet, col: 25, row: row, text: data.customerCity);

          _writeNumOrNA(sheet, col: 26, row: row, value: lineGross);
          _writeNumOrNA(sheet, col: 27, row: row, value: lineDisc);
          _writeNumOrNA(sheet, col: 28, row: row, value: lineNet);
        }

        row++;
      }

      final bytes = excel.encode();
      if (bytes != null) {
        final dir = await getTemporaryDirectory();
        final filename =
            "sales_report_${DateFormat("yyyyMMdd_HHmmss").format(DateTime.now())}.xlsx";
        final file = File("${dir.path}/$filename");
        await file.writeAsBytes(bytes);

        await Share.shareXFiles(
          [XFile(file.path)],
          subject: "Sales Report",
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(itemized
                  ? "Excel (Itemized) file generated successfully"
                  : "Excel (Header) file generated successfully"),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Error generating Excel: $e"),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /* ------------------------ CSV Export ------------------------ */

  void _exportCsv() async {
    final divisionLookup = await _loadDivisionLookup();
    // Dedup for CSV as well so we don't export quad entries
    final csv =
    salesReportToCsv(_dedupSalesRows(state.rows), divisionLookup: divisionLookup);

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
                        "CSV Preview",
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
                        style: const TextStyle(
                            fontFamily: "monospace", fontSize: 12),
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
