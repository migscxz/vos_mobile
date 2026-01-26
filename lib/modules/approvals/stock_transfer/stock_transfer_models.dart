// lib/modules/approvals/stock_transfer/stock_transfer_models.dart

import "package:flutter/material.dart";

enum StockTransferStatus {
  all("All"),
  mixed("Mixed"),
  requested("Requested"),
  forPicking("For Picking"),
  picking("Picking"),
  picked("Picked"),
  forLoading("For Loading"),
  received("Received");

  final String label;
  const StockTransferStatus(this.label);
}

/// Filter shown in the UI menu (exclude Mixed; Mixed is derived).
enum StockTransferFilter {
  all("All", null),
  requested("Requested", "Requested"),
  forPicking("For Picking", "For Picking"),
  picking("Picking", "Picking"),
  picked("Picked", "Picked"),
  forLoading("For Loading", "For Loading"),
  received("Received", "Received");

  final String label;
  final String? statusValue;
  const StockTransferFilter(this.label, this.statusValue);
}

/// Returned by approval sheet so the view can display a meaningful snackbar.
class StockTransferApproveOutcome {
  final int consolidatorId;
  final String? consolidatorNo;

  const StockTransferApproveOutcome({
    required this.consolidatorId,
    required this.consolidatorNo,
  });
}

class StockTransferHeader {
  final String orderNo;
  final StockTransferStatus statusEnum;

  final DateTime requestedAt;
  final String requesterName;
  final String sourceBranchName;
  final String targetBranchName;

  final List<StockTransferRow> items;

  final int totalOrderedQty;
  final int totalReceivedQty;

  final String? bossActionBy;
  final DateTime? bossActionAt;

  final bool rejected;
  final String? rejectReason;

  const StockTransferHeader({
    required this.orderNo,
    required this.statusEnum,
    required this.requestedAt,
    required this.requesterName,
    required this.sourceBranchName,
    required this.targetBranchName,
    required this.items,
    required this.totalOrderedQty,
    required this.totalReceivedQty,
    this.bossActionBy,
    this.bossActionAt,
    this.rejected = false,
    this.rejectReason,
  });

  bool get allRequested =>
      items.isNotEmpty &&
      items.every((e) => e.statusEnum == StockTransferStatus.requested);

  String get routeLabel => "$sourceBranchName → $targetBranchName";

  String get qtyLabel => "$totalReceivedQty/$totalOrderedQty";
}

class StockTransferRow {
  final int id;
  final String orderNo;
  final StockTransferStatus statusEnum;

  final String productName;
  final String sourceBranchName;
  final String targetBranchName;

  final int orderedQty;
  final int receivedQty;

  final DateTime requestedAt;

  final String requesterName;
  final String remarks;

  final String? bossActionBy;
  final DateTime? bossActionAt;

  final bool rejected;
  final String? rejectReason;

  const StockTransferRow({
    required this.id,
    required this.orderNo,
    required this.statusEnum,
    required this.productName,
    required this.sourceBranchName,
    required this.targetBranchName,
    required this.orderedQty,
    required this.receivedQty,
    required this.requestedAt,
    required this.requesterName,
    required this.remarks,
    this.bossActionBy,
    this.bossActionAt,
    this.rejected = false,
    this.rejectReason,
  });
}

Color stockTransferStatusColor(StockTransferStatus s, ColorScheme cs) {
  switch (s) {
    case StockTransferStatus.all:
      return cs.outline;
    case StockTransferStatus.mixed:
      return cs.outline;
    case StockTransferStatus.requested:
      return cs.primary;
    case StockTransferStatus.forPicking:
      return Colors.deepPurple;
    case StockTransferStatus.picking:
      return Colors.orange;
    case StockTransferStatus.picked:
      return Colors.teal;
    case StockTransferStatus.forLoading:
      return Colors.blue;
    case StockTransferStatus.received:
      return Colors.green;
  }
}

String fmtYmd(DateTime dt) {
  final d = dt.toLocal();
  String two(int n) => n.toString().padLeft(2, "0");
  return "${d.year}-${two(d.month)}-${two(d.day)}";
}

String fmtHm(DateTime dt) {
  final d = dt.toLocal();
  String two(int n) => n.toString().padLeft(2, "0");
  return "${two(d.hour)}:${two(d.minute)}";
}

bool truthyDeleted(Object? v) {
  if (v == null) return false;
  if (v is bool) return v;
  if (v is num) return v != 0;

  // handle: { type: "Buffer", data: [1] }
  if (v is Map) {
    final data = v["data"];
    if (data is List && data.isNotEmpty) {
      final first = data.first;
      if (first is num) return first != 0;
      final parsed = int.tryParse(first.toString());
      if (parsed != null) return parsed != 0;
    }
  }

  final s = v.toString().trim().toLowerCase();
  return s == "1" || s == "true" || s == "yes";
}

String normalizeQuery(String raw) {
  var s = raw.trim();
  if (s.isEmpty) return s;
  s = s.replaceAll(RegExp(r"\s*-\s*"), "-");
  s = s.replaceAll(RegExp(r"\s+"), " ").trim();
  return s;
}
