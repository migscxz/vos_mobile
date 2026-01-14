// lib/modules/approvals/disbursement/disbursement_models.dart
import "package:flutter/material.dart";

enum DisbursementStatus {
  all("All"),
  pending("Pending"),
  approved("Approved");

  final String label;
  const DisbursementStatus(this.label);
}

/// Filter shown in the UI menu
enum DisbursementFilter {
  all("All", DisbursementStatus.all),
  pending("Pending", DisbursementStatus.pending),
  approved("Approved", DisbursementStatus.approved);

  final String label;
  final DisbursementStatus status;
  const DisbursementFilter(this.label, this.status);
}

class DisbursementApproveOutcome {
  final int disbursementId;
  final String docNo;

  const DisbursementApproveOutcome({
    required this.disbursementId,
    required this.docNo,
  });
}

class DisbursementHeader {
  final int id;
  final String docNo;

  final double totalAmount;
  final double paidAmount;

  final int encoderId;
  final String encoderName;

  final int payeeId;
  final String payeeName;

  final DateTime transactionDate;

  final int? approverId;
  final DateTime? dateApproved;

  final String remarks;

  const DisbursementHeader({
    required this.id,
    required this.docNo,
    required this.totalAmount,
    required this.paidAmount,
    required this.encoderId,
    required this.encoderName,
    required this.payeeId,
    required this.payeeName,
    required this.transactionDate,
    required this.approverId,
    required this.dateApproved,
    required this.remarks,
  });

  bool get isApproved => (approverId != null) && (dateApproved != null);
  bool get isPending => !isApproved;
}

class DisbursementPayableRow {
  final int id;
  final DateTime payableDate;
  final int coaId;
  final String coaTitle;
  final double amount;
  final String remarks;
  final String referenceNo;

  const DisbursementPayableRow({
    required this.id,
    required this.payableDate,
    required this.coaId,
    required this.coaTitle,
    required this.amount,
    required this.remarks,
    required this.referenceNo,
  });
}

// -------------------------
// Small formatting helpers
// -------------------------

String fmtYmd(DateTime d) {
  String two(int v) => v.toString().padLeft(2, "0");
  return "${d.year}-${two(d.month)}-${two(d.day)}";
}

String fmtHm(DateTime d) {
  String two(int v) => v.toString().padLeft(2, "0");
  return "${two(d.hour)}:${two(d.minute)}";
}

String money(double n) {
  // Simple comma formatting without intl dependency
  final s = n.toStringAsFixed(2);
  final parts = s.split(".");
  final whole = parts[0];
  final dec = parts.length > 1 ? parts[1] : "00";

  final buf = StringBuffer();
  for (int i = 0; i < whole.length; i++) {
    final idxFromEnd = whole.length - i;
    buf.write(whole[i]);
    if (idxFromEnd > 1 && idxFromEnd % 3 == 1) {
      buf.write(",");
    }
  }
  return "${buf.toString()}.$dec";
}

Color disbursementStatusColor(DisbursementHeader h, ColorScheme cs) {
  if (h.isApproved) return cs.tertiary;
  return cs.primary;
}
