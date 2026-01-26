// lib/modules/approvals/attendance/attendance_model.dart
import "package:flutter/material.dart";

/// Raw status coming from API (lowercase: "pending", "approved", "rejected")
enum AttendanceStatus {
  all("All"),
  pending("Pending"),
  approved("Approved"),
  rejected("Rejected");

  final String label;
  const AttendanceStatus(this.label);

  /// Convert to API value (null for All)
  String? get apiValue {
    switch (this) {
      case AttendanceStatus.all:
        return null;
      case AttendanceStatus.pending:
        return "pending";
      case AttendanceStatus.approved:
        return "approved";
      case AttendanceStatus.rejected:
        return "rejected";
    }
  }

  static AttendanceStatus fromApi(String? raw) {
    final s = (raw ?? "").trim().toLowerCase();
    switch (s) {
      case "approved":
        return AttendanceStatus.approved;
      case "rejected":
        return AttendanceStatus.rejected;
      case "pending":
      default:
        return AttendanceStatus.pending;
    }
  }
}

/// Attendance log status for display in card
enum AttendanceLogStatus {
  onTime("On Time"),
  late("Late"),
  absent("Absent"),
  halfDay("Half day"),
  incomplete("Incomplete"),
  leave("Leave"),
  holiday("Holiday");

  final String label;
  const AttendanceLogStatus(this.label);

  static AttendanceLogStatus fromApi(String? raw) {
    final s = (raw ?? "").trim().toLowerCase();
    switch (s) {
      case "late":
        return AttendanceLogStatus.late;
      case "absent":
        return AttendanceLogStatus.absent;
      case "half day":
        return AttendanceLogStatus.halfDay;
      case "incomplete":
        return AttendanceLogStatus.incomplete;
      case "leave":
        return AttendanceLogStatus.leave;
      case "holiday":
        return AttendanceLogStatus.holiday;
      case "on time":
      default:
        return AttendanceLogStatus.onTime;
    }
  }
}

/// Filter shown in the UI menu.
enum AttendanceFilter {
  all("All", null),
  pending("Pending", "pending"),
  approved("Approved", "approved"),
  rejected("Rejected", "rejected");

  final String label;
  final String? statusValue; // null => all
  const AttendanceFilter(this.label, this.statusValue);
}

/// UI-facing row model for the approvals list (card/table).
class AttendanceApprovalHeader {
  final int approvalId;

  final int employeeId;
  final String employeeName;

  final int departmentId;
  final String departmentName;

  final DateTime dateSchedule;

  final int lateMinutes;
  final int overtimeMinutes;
  final int undertimeMinutes;
  final int workMinutes;

  final AttendanceStatus status;

  final AttendanceLogStatus? attendanceLogStatus;

  final String remarks;

  final int? approvedBy;
  final DateTime? approvedAt;

  // Additional fields for UI: schedule and actual times
  final TimeOfDay? scheduleStart;
  final TimeOfDay? scheduleEnd;
  final DateTime? actualStart;
  final DateTime? actualEnd;
  final DateTime? lunchStart;
  final DateTime? lunchEnd;

  const AttendanceApprovalHeader({
    required this.approvalId,
    required this.employeeId,
    required this.employeeName,
    required this.departmentId,
    required this.departmentName,
    required this.dateSchedule,
    required this.lateMinutes,
    required this.overtimeMinutes,
    required this.undertimeMinutes,
    required this.workMinutes,
    required this.status,
    required this.remarks,
    required this.approvedBy,
    required this.approvedAt,
    this.attendanceLogStatus,
    this.scheduleStart,
    this.scheduleEnd,
    this.actualStart,
    this.actualEnd,
    this.lunchStart,
    this.lunchEnd,
  });

  String get dateScheduleLabel => _fmtDate(dateSchedule);

  String get scheduleLabel {
    if (scheduleStart == null || scheduleEnd == null) return "—";
    return "${formatTimeOfDay(scheduleStart!)} - ${formatTimeOfDay(scheduleEnd!)}";
  }

  String get actualLabel {
    if (actualStart == null || actualEnd == null) return "—";
    return "${formatDateTimeToTime(actualStart!)} - ${formatDateTimeToTime(actualEnd!)}";
  }

  String get workMinutesLabel => formatWorkMinutes(workMinutes);

  bool get isPending => status == AttendanceStatus.pending;

  /// If you want a more explicit guard for actions
  bool get isActionable => status == AttendanceStatus.pending;

  // Discrepancy badges
  List<String> get discrepancyBadges {
    final badges = <String>[];
    if (lateMinutes > 0) badges.add("LATE: $lateMinutes min");
    if (overtimeMinutes > 0) badges.add("OVERTIME: $overtimeMinutes min");
    if (undertimeMinutes > 0) badges.add("UNDERTIME: $undertimeMinutes min");
    return badges;
  }
}

/// Strongly-typed outcome for approval sheet.
class AttendanceApproveOutcome {
  final int approvalId;
  final AttendanceStatus newStatus;

  const AttendanceApproveOutcome({required this.approvalId, required this.newStatus});
}

/// Grouped model for displaying pending approvals by employee.
class AttendanceApprovalGroup {
  final int employeeId;
  final String employeeName;
  final String departmentName;
  final List<AttendanceApprovalHeader> pendingApprovals;

  const AttendanceApprovalGroup({
    required this.employeeId,
    required this.employeeName,
    required this.departmentName,
    required this.pendingApprovals,
  });

  int get pendingCount => pendingApprovals.length;

  bool get hasPending => pendingApprovals.isNotEmpty;
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

/// Helper: work minutes -> "Hh Mm" (show minutes if less than 8 hours, otherwise only hours)
String formatWorkMinutes(int minutes) {
  if (minutes <= 0) return "0h";
  final h = minutes ~/ 60;
  final m = minutes % 60;
  if (h < 8) {
    // Show minutes for work less than 8 hours
    if (h <= 0) return "${m}m";
    if (m <= 0) return "${h}h";
    return "${h}h ${m}m";
  } else {
    // Show only hours for 8+ hours
    return "${h}h";
  }
}

/// Helper: TimeOfDay -> "HH:mm" 24h format
String formatTimeOfDay(TimeOfDay t) {
  final hh = t.hour.toString().padLeft(2, "0");
  final mm = t.minute.toString().padLeft(2, "0");
  return "$hh:$mm";
}

/// Helper: DateTime -> "HH:mm" 24h format
String formatDateTimeToTime(DateTime? dt) {
  if (dt == null) return "—";
  final hh = dt.hour.toString().padLeft(2, "0");
  final mm = dt.minute.toString().padLeft(2, "0");
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

  return TimeOfDay(hour: h.clamp(0, 23), minute: m.clamp(0, 59));
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
