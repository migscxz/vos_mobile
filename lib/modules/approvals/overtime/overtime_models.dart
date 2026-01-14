// lib/modules/approvals/overtime/overtime_models.dart
import "package:flutter/material.dart";

/// Raw status coming from API (lowercase: "pending", "approved", "rejected", "cancelled")
enum OvertimeStatus {
  all("All"),
  pending("Pending"),
  approved("Approved"),
  rejected("Rejected"),
  cancelled("Cancelled");

  final String label;
  const OvertimeStatus(this.label);

  /// Convert to API value (null for All)
  String? get apiValue {
    switch (this) {
      case OvertimeStatus.all:
        return null;
      case OvertimeStatus.pending:
        return "pending";
      case OvertimeStatus.approved:
        return "approved";
      case OvertimeStatus.rejected:
        return "rejected";
      case OvertimeStatus.cancelled:
        return "cancelled";
    }
  }

  static OvertimeStatus fromApi(String? raw) {
    final s = (raw ?? "").trim().toLowerCase();
    switch (s) {
      case "approved":
        return OvertimeStatus.approved;
      case "rejected":
        return OvertimeStatus.rejected;
      case "cancelled":
        return OvertimeStatus.cancelled;
      case "pending":
      default:
        return OvertimeStatus.pending;
    }
  }
}

/// Filter shown in the UI menu.
enum OvertimeFilter {
  all("All", null),
  pending("Pending", "pending"),
  approved("Approved", "approved"),
  rejected("Rejected", "rejected"),
  cancelled("Cancelled", "cancelled");

  final String label;
  final String? statusValue; // null => all
  const OvertimeFilter(this.label, this.statusValue);
}

/// UI-facing row model for the approvals list (card/table).
class OvertimeApprovalHeader {
  final int overtimeId;

  final int userId;
  final String employeeName;

  final int departmentId;
  final String departmentName;

  final DateTime requestDate; // derived from "request_date"
  final DateTime filedAt; // derived from "filed_at"

  final TimeOfDay otFrom;
  final TimeOfDay otTo;
  final TimeOfDay schedTimeout;

  final int durationMinutes;

  final OvertimeStatus status;

  final String purpose;
  final String? remarks;

  final int? approverId;
  final DateTime? approvedAt;

  const OvertimeApprovalHeader({
    required this.overtimeId,
    required this.userId,
    required this.employeeName,
    required this.departmentId,
    required this.departmentName,
    required this.requestDate,
    required this.filedAt,
    required this.otFrom,
    required this.otTo,
    required this.schedTimeout,
    required this.durationMinutes,
    required this.status,
    required this.purpose,
    required this.remarks,
    required this.approverId,
    required this.approvedAt,
  });

  String get durationLabel => formatMinutes(durationMinutes);

  String get requestDateLabel => _fmtDate(requestDate);

  String get filedAtLabel => _fmtDateTime(filedAt);

  String get timeRangeLabel => "${formatTimeOfDay(otFrom)} - ${formatTimeOfDay(otTo)}";

  String get schedTimeoutLabel => formatTimeOfDay(schedTimeout);

  bool get isPending => status == OvertimeStatus.pending;

  /// If you want a more explicit guard for actions
  bool get isActionable => status == OvertimeStatus.pending;
}

/// Strongly-typed outcome for approval sheet.
class OvertimeApproveOutcome {
  final int overtimeId;
  final OvertimeStatus newStatus;

  const OvertimeApproveOutcome({
    required this.overtimeId,
    required this.newStatus,
  });
}

/// Helper: minutes -> "Hh Mm" (no leading zero in minutes)
String formatMinutes(int minutes) {
  if (minutes <= 0) return "0m";
  final h = minutes ~/ 60;
  final m = minutes % 60;
  if (h <= 0) return "${m}m";
  if (m <= 0) return "${h}h";
  return "${h}h ${m}m";
}

/// Helper: TimeOfDay -> "HH:mm" 24h format
String formatTimeOfDay(TimeOfDay t) {
  final hh = t.hour.toString().padLeft(2, "0");
  final mm = t.minute.toString().padLeft(2, "0");
  return "$hh:$mm";
}

/// Parse "HH:mm:ss" or "HH:mm" safely into TimeOfDay (fallback 00:00).
TimeOfDay parseTimeOfDay(String? raw) {
  final s = (raw ?? "").trim();
  if (s.isEmpty) return const TimeOfDay(hour: 0, minute: 0);

  final parts = s.split(":");
  if (parts.length < 2) return const TimeOfDay(hour: 0, minute: 0);

  final h = int.tryParse(parts[0]) ?? 0;
  final m = int.tryParse(parts[1]) ?? 0;

  return TimeOfDay(
    hour: h.clamp(0, 23),
    minute: m.clamp(0, 59),
  );
}

/// Parse ISO or "YYYY-MM-DD" into DateTime safely (local).
DateTime parseDate(String? raw) {
  final s = (raw ?? "").trim();
  if (s.isEmpty) return DateTime.fromMillisecondsSinceEpoch(0);

  // "YYYY-MM-DD" -> parse as local midnight
  if (RegExp(r"^\d{4}-\d{2}-\d{2}$").hasMatch(s)) {
    final parts = s.split("-");
    final y = int.tryParse(parts[0]) ?? 1970;
    final mo = int.tryParse(parts[1]) ?? 1;
    final d = int.tryParse(parts[2]) ?? 1;
    return DateTime(y, mo, d);
  }

  // ISO datetime
  final dt = DateTime.tryParse(s);
  return dt?.toLocal() ?? DateTime.fromMillisecondsSinceEpoch(0);
}

/// UI helpers
String _fmtDate(DateTime d) {
  final y = d.year.toString().padLeft(4, "0");
  final m = d.month.toString().padLeft(2, "0");
  final dd = d.day.toString().padLeft(2, "0");
  return "$y-$m-$dd";
}

String _fmtDateTime(DateTime d) {
  final date = _fmtDate(d);
  final hh = d.hour.toString().padLeft(2, "0");
  final mm = d.minute.toString().padLeft(2, "0");
  return "$date $hh:$mm";
}
