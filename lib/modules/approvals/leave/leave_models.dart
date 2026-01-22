// lib/modules/approvals/leave/leave_models.dart

/// Raw status coming from API (lowercase: "pending", "approved", "rejected", "cancelled")
enum LeaveStatus {
  all("All"),
  pending("Pending"),
  approved("Approved"),
  rejected("Rejected"),
  cancelled("Cancelled");

  final String label;
  const LeaveStatus(this.label);

  /// Convert to API value (null for All)
  String? get apiValue {
    switch (this) {
      case LeaveStatus.all:
        return null;
      case LeaveStatus.pending:
        return "pending";
      case LeaveStatus.approved:
        return "approved";
      case LeaveStatus.rejected:
        return "rejected";
      case LeaveStatus.cancelled:
        return "cancelled";
    }
  }

  static LeaveStatus fromApi(String? raw) {
    final s = (raw ?? "").trim().toLowerCase();
    switch (s) {
      case "approved":
        return LeaveStatus.approved;
      case "rejected":
        return LeaveStatus.rejected;
      case "cancelled":
        return LeaveStatus.cancelled;
      case "pending":
      default:
        return LeaveStatus.pending;
    }
  }
}

/// Filter shown in the UI menu.
enum LeaveFilter {
  all("All", null),
  pending("Pending", "pending"),
  approved("Approved", "approved"),
  rejected("Rejected", "rejected"),
  cancelled("Cancelled", "cancelled");

  final String label;
  final String? statusValue; // null => all
  const LeaveFilter(this.label, this.statusValue);
}

/// Leave types
enum LeaveType {
  vacation("Vacation"),
  sick("Sick Leave"),
  emergency("Emergency");

  final String label;
  const LeaveType(this.label);

  static LeaveType fromApi(String? raw) {
    final s = (raw ?? "").trim().toLowerCase();
    switch (s) {
      case "vacation":
        return LeaveType.vacation;
      case "sick":
        return LeaveType.sick;
      case "emergency":
        return LeaveType.emergency;
      default:
        return LeaveType.vacation;
    }
  }
}

/// UI-facing row model for the approvals list (card/table).
class LeaveApprovalHeader {
  final int leaveId;

  final int userId;
  final String employeeName;

  final int departmentId;
  final String departmentName;

  final DateTime requestDate; // derived from "filed_at"
  final DateTime filedAt; // derived from "filed_at"

  final DateTime leaveStart;
  final DateTime leaveEnd;
  final LeaveType leaveType;

  final double totalDays;

  final LeaveStatus status;

  final String reason;
  final String? remarks;

  final int? approverId;
  final DateTime? approvedAt;

  const LeaveApprovalHeader({
    required this.leaveId,
    required this.userId,
    required this.employeeName,
    required this.departmentId,
    required this.departmentName,
    required this.requestDate,
    required this.filedAt,
    required this.leaveStart,
    required this.leaveEnd,
    required this.leaveType,
    required this.totalDays,
    required this.status,
    required this.reason,
    required this.remarks,
    required this.approverId,
    required this.approvedAt,
  });

  String get requestDateLabel => _fmtDate(requestDate);

  String get filedAtLabel => _fmtDateTime(filedAt);

  String get leavePeriodLabel => "${_fmtDate(leaveStart)} - ${_fmtDate(leaveEnd)}";

  String get totalDaysLabel => totalDays == 1 ? "1 day" : "${totalDays.toStringAsFixed(1)} days";

  bool get isPending => status == LeaveStatus.pending;

  /// If you want a more explicit guard for actions
  bool get isActionable => status == LeaveStatus.pending;
}

/// Strongly-typed outcome for approval sheet.
class LeaveApproveOutcome {
  final int leaveId;
  final LeaveStatus newStatus;

  const LeaveApproveOutcome({required this.leaveId, required this.newStatus});
}

/// Helper: Parse ISO or "YYYY-MM-DD" into DateTime safely (local).
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
