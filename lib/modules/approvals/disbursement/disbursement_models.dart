// lib/modules/approvals/disbursement/disbursement_models.dart
import "package:flutter/material.dart";

enum DisbursementStatus {
  all("All"),
  pending("Pending"),
  approved("Approved"),
  mixed("Mixed");

  final String label;
  const DisbursementStatus(this.label);
}

/// Filter shown in the UI menu. (Exclude Mixed; Mixed is derived.)
enum DisbursementFilter {
  all("All", null),
  pending("Pending", "pending"),
  approved("Approved", "approved");

  final String label;
  final String? statusValue; // null => all
  const DisbursementFilter(this.label, this.statusValue);
}

class DisbursementApprovalHeader {
  final String docNo;

  final DateTime transactionDate; // derived from "transaction_date" or latest
  final int payeeId;
  final String payeeName;

  final int encoderId;
  final String encoderName;

  final double totalAmount;
  final double paidAmount;

  final DisbursementStatus status;

  final List<DisbursementRow> rows;

  const DisbursementApprovalHeader({
    required this.docNo,
    required this.transactionDate,
    required this.payeeId,
    required this.payeeName,
    required this.encoderId,
    required this.encoderName,
    required this.totalAmount,
    required this.paidAmount,
    required this.status,
    required this.rows,
  });

  bool get isPending => status == DisbursementStatus.pending;
  bool get isActionable => status == DisbursementStatus.pending;
}

class DisbursementRow {
  final int disbursementId;
  final String docNo;

  final int payeeId;
  final int encoderId;

  final DateTime transactionDate;

  final double totalAmount;
  final double paidAmount;

  final int? approverId;
  final DateTime? dateApproved;

  const DisbursementRow({
    required this.disbursementId,
    required this.docNo,
    required this.payeeId,
    required this.encoderId,
    required this.transactionDate,
    required this.totalAmount,
    required this.paidAmount,
    required this.approverId,
    required this.dateApproved,
  });

  bool get isPending => approverId == null && dateApproved == null;
  bool get isApproved => approverId != null && dateApproved != null;
}

class DisbursementApproveOutcome {
  final String docNo;
  const DisbursementApproveOutcome({required this.docNo});
}

// -------------------------
// Helpers
// -------------------------

String fmtYmd(DateTime dt) {
  final d = dt.toLocal();
  String two(int n) => n.toString().padLeft(2, "0");
  return "${d.year}-${two(d.month)}-${two(d.day)}";
}

String formatMoney(num v) {
  // Keep it simple and stable without intl dependency.
  // If you already use intl in your project, replace with NumberFormat.
  final s = v.toStringAsFixed(2);
  final parts = s.split(".");
  final intPart = parts.first;
  final dec = parts.length > 1 ? parts[1] : "00";

  final buf = StringBuffer();
  for (int i = 0; i < intPart.length; i++) {
    final idxFromRight = intPart.length - i;
    buf.write(intPart[i]);
    if (idxFromRight > 1 && idxFromRight % 3 == 1) buf.write(",");
  }
  return "${buf.toString()}.$dec";
}

double asDouble(Object? v) {
  if (v == null) return 0.0;
  if (v is double) return v;
  if (v is int) return v.toDouble();
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString()) ?? 0.0;
}

int? asInt(Object? v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString());
}

DateTime parseDateOrIso(String? raw) {
  final s = (raw ?? "").trim();
  if (s.isEmpty) return DateTime.fromMillisecondsSinceEpoch(0);

  // "YYYY-MM-DD" -> local
  if (RegExp(r"^\d{4}-\d{2}-\d{2}$").hasMatch(s)) {
    final parts = s.split("-");
    final y = int.tryParse(parts[0]) ?? 1970;
    final m = int.tryParse(parts[1]) ?? 1;
    final d = int.tryParse(parts[2]) ?? 1;
    return DateTime(y, m, d);
  }

  // ISO
  final dt = DateTime.tryParse(s);
  return dt?.toLocal() ?? DateTime.fromMillisecondsSinceEpoch(0);
}

String normalizeQuery(String raw) {
  var s = raw.trim();
  if (s.isEmpty) return s;
  s = s.replaceAll(RegExp(r"\s*-\s*"), "-");
  s = s.replaceAll(RegExp(r"\s+"), " ").trim();
  return s;
}
