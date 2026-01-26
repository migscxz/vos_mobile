part of "sr_view.dart";

/* ======================= SMALL HELPERS ======================= */

bool _isNumeric(String s) {
  final t = s.trim();
  if (t.isEmpty) return false;
  return int.tryParse(t) != null;
}

/// Split a quantity into Ties / Boxes / Pieces based on the productUnit string.
({double ties, double boxes, double pieces}) _splitQtyByUnit(
    num? qty, String? unitRaw) {
  final q = (qty ?? 0).toDouble();
  final u = (unitRaw ?? "").toLowerCase().trim();
  double ties = 0, boxes = 0, pieces = 0;

  if (u.contains("tie")) {
    ties = q;
  } else if (u.contains("box")) {
    boxes = q;
  } else if (u == "pc" || u == "pcs" || u.contains("piece")) {
    pieces = q;
  } else {
    pieces = q;
  }
  return (ties: ties, boxes: boxes, pieces: pieces);
}

/* ======================= DIVISION LOOKUP MIXIN ======================= */

mixin DivisionLookupMixin<T extends StatefulWidget> on State<T> {
  Map<int, String>? _divisionLookupCache;

  // The host State must provide this (your _SalesReportViewState already has it)
  Future<List<Map<String, Object?>>> _safeQuery(
      String sql, [
        List<Object?> params = const [],
      ]);

  /// Try several common schemas to build a {id -> name} map for divisions.
  Future<Map<int, String>> _loadDivisionLookup() async {
    if (_divisionLookupCache != null) return _divisionLookupCache!;

    final candidates = <({String table, String idCol, String nameCol})>[
      (table: "division", idCol: "id", nameCol: "name"),
      (table: "division", idCol: "division_id", nameCol: "division_name"),
      (table: "division", idCol: "id", nameCol: "division_name"),
      (table: "division", idCol: "division_id", nameCol: "name"),
      (table: "divisions", idCol: "id", nameCol: "name"),
      (table: "divisions", idCol: "division_id", nameCol: "division_name"),
      (table: "divisions", idCol: "id", nameCol: "division_name"),
      (table: "divisions", idCol: "division_id", nameCol: "name"),
      (table: "salesman_division", idCol: "id", nameCol: "name"),
      (table: "salesman_division",
      idCol: "division_id",
      nameCol: "division_name"),
    ];

    final Map<int, String> out = {};
    for (final c in candidates) {
      final rows = await _safeQuery("""
        SELECT ${c.idCol} AS id, ${c.nameCol} AS name
        FROM ${c.table}
        WHERE ${c.idCol} IS NOT NULL
      """);
      if (rows.isNotEmpty) {
        for (final r in rows) {
          final id = (r["id"] as num?)?.toInt();
          final name = (r["name"] ?? "").toString().trim();
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
}

/* ======================= DEDUP HELPERS ======================= */

/// Keep only one row per (invoiceNo + invoiceDate) combination (header-level).
List<SalesReportRow> _dedupSalesRows(List<SalesReportRow> rows) {
  final seen = <String>{};
  final result = <SalesReportRow>[];

  for (final r in rows) {
    final key = "${r.invoiceNo}::${r.invoiceDate?.toIso8601String() ?? ""}";
    if (seen.add(key)) {
      result.add(r);
    }
  }

  return result;
}

/// Itemized-level dedup: collapse identical lines per invoice+product combo
/// to avoid quad entries from joins.
List<SalesReportRow> _dedupItemizedRows(List<SalesReportRow> rows) {
  final seen = <String>{};
  final result = <SalesReportRow>[];

  for (final r in rows) {
    final key = [
      r.invoiceNo,
      r.invoiceDate?.toIso8601String() ?? "",
      r.productName ?? "",
      r.productBrand ?? "",
      r.productCategory ?? "",
      (r.productUnitPrice ?? 0).toStringAsFixed(4),
      (r.productQuantity ?? 0).toString(),
      r.productUnit ?? "",
    ].join("::");

    if (seen.add(key)) {
      result.add(r);
    }
  }

  return result;
}

/* ======================= EXCEL HELPERS ======================= */

// Convert 0-based column index to Excel letter (0 -> A, 23 -> X, etc.)
String _colLetter(int zeroBasedIndex) {
  int n = zeroBasedIndex + 1;
  String s = "";
  while (n > 0) {
    final rem = (n - 1) % 26;
    s = String.fromCharCode(65 + rem) + s;
    n = (n - 1) ~/ 26;
  }
  return s;
}

// Write a text cell, or 'N/A' when text is null/empty
void _writeTextOrNA(
    xl.Sheet sheet, {
      required int col,
      required int row,
      String? text,
    }) {
  final v = (text == null || text.trim().isEmpty) ? "N/A" : text.trim();
  sheet
      .cell(xl.CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row))
      .value = xl.TextCellValue(v);
}

// Write numeric when non-null, else 'N/A'
void _writeNumOrNA(
    xl.Sheet sheet, {
      required int col,
      required int row,
      num? value,
    }) {
  final cell =
  sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row));
  if (value == null) {
    cell.value = xl.TextCellValue("N/A");
  } else {
    cell.value = xl.DoubleCellValue(value.toDouble());
  }
}

/* ======================= CSV FALLBACK (LOCAL) ======================= */

/// CSV generator updated to also map division ids to names via [divisionLookup]
String salesReportToCsv(
    List<SalesReportRow> rows, {
      Map<int, String> divisionLookup = const {},
    }) {
  final dateFormat = DateFormat("yyyy-MM-dd");
  final sb = StringBuffer();

  // Headers
  sb.writeln([
    "Invoice No",
    "Date",
    "Customer",
    "Address",
    "Salesman",
    "Branch",
    "Payment Terms",
    "Sales Type",
    "Total Amount",
    "Discount",
    "Returns",
    "Collection",
    "Status",
    // itemized
    "Product",
    "Brand",
    "Category",
    "Supplier",
    "Unit Price",
    "Quantity",
    "Unit",
    "Division",
    "Customer Province",
    "Customer City",
  ].map(_csvEscape).join(","));

  bool _isNumericLocal(String s) => int.tryParse(s.trim()) != null;

  // Rows
  for (final r in rows) {
    final dateStr = r.invoiceDate != null ? dateFormat.format(r.invoiceDate!) : "";
    String divisionText = (r.salesmanDivision ?? "").trim();
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
      r.productName ?? "",
      r.productBrand ?? "",
      r.productCategory ?? "",
      r.productSupplier ?? "",
      (r.productUnitPrice ?? 0).toString(),
      (r.productQuantity ?? 0).toString(),
      r.productUnit ?? "",
      divisionText,
      r.customerProvince ?? "",
      r.customerCity ?? "",
    ].map(_csvEscape).join(",");
    sb.writeln(line);
  }

  return sb.toString();
}

String _csvEscape(String v) {
  final needsQuotes = v.contains(",") || v.contains('"') || v.contains("\n");
  var out = v.replaceAll('"', '""');
  return needsQuotes ? '"$out"' : '"$out"';
}
