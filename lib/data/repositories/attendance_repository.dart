// lib/data/repositories/attendance_repository.dart
import "package:flutter/material.dart";

import "../../core/network/api_client.dart";
import "../../modules/approvals/attendance/attendance_model.dart";

/// Simple paged result wrapper for list screens.
class PagedResult<T> {
  final List<T> items;
  final int total;
  final int limit;
  final int offset;

  const PagedResult({
    required this.items,
    required this.total,
    required this.limit,
    required this.offset,
  });

  bool get hasMore => (offset + items.length) < total;
}

class AttendanceRepository {
  AttendanceRepository(this._api);

  final ApiClient _api;

  static const String _approvalCollection = "attendance_approval";
  static const String _logCollection = "attendance_log";
  static const String _scheduleCollection = "department_schedule";
  static const String _userCollection = "user";
  static const String _deptCollection = "department";
  static const String _overtimeCollection = "overtime_request";

  static const List<String> _logFieldsList = [
    "log_id",
    "user_id",
    "department_id",
    "log_date",
    "time_in",
    "time_out",
    "lunch_start",
    "lunch_end",
    "approval_status",
    "status",
    "created_at",
    "updated_at",
  ];

  static final String _logFields = _logFieldsList.join(",");

  // ============================================================
  // PUBLIC: PAGED LIST (ENRICHED FOR UI)
  // ============================================================

  /// Main attendance approvals fetch (paged + enriched).
  Future<PagedResult<AttendanceApprovalHeader>> fetchAttendanceApprovalsPaged({
    String? status, // "pending" | "approved" | "rejected" | null
    String? search,
    required int limit,
    required int offset,
    int? departmentFilter, // Filter by specific department (for permission-based access)
    bool allowAllDepartments = false, // Allow access to all departments (for super admin)
    List<int>? allowedDepartmentIds, // List of department IDs user can access
  }) async {
    final q = (search ?? "").trim();

    final query = <String, String>{
      "limit": limit.toString(),
      "offset": offset.toString(),
      "sort": "-log_date,-log_id",
      "fields": _logFields,
      "meta": "total_count",
    };

    final st = (status ?? "").trim().toLowerCase();
    if (st.isNotEmpty) {
      query["filter[approval_status][_eq]"] = st;
    }

    // Apply department-based permissions filtering
    if (allowedDepartmentIds != null && allowedDepartmentIds.isNotEmpty) {
      query["filter[department_id][_in]"] = allowedDepartmentIds.join(",");
    }

    if (q.isNotEmpty) {
      await _applySearchFilters(query, q);
    }

    final json = await _api.getJson("/items/$_logCollection", query: query);
    final dtos = _readDataList(json).map(AttendanceLogLite.fromJson).toList();

    int total = dtos.length;
    final meta = json["meta"];
    if (meta is Map) {
      final tc = _asInt(meta["total_count"]);
      if (tc != null) total = tc;
    }

    // Enrich: users + departments + schedule/actual times
    final userIds = dtos.map((e) => e.userId).where((id) => id > 0).toSet().toList()..sort();
    final deptIds = dtos.map((e) => e.departmentId ?? 0).where((id) => id > 0).toSet().toList()
      ..sort();

    final userMap = await fetchUsersByIds(userIds);
    final deptMap = await fetchDepartmentsByIds(deptIds);

    // Fetch schedule for each
    final scheduleMap = await _fetchSchedulesForLogs(dtos);

    // We need to compute discrepancies for each log, which is async.
    final itemsFutures = dtos.map((dto) async {
      final employee = userMap[dto.userId];
      final dept = deptMap[dto.departmentId ?? 0];

      final employeeName = employee?.displayName ?? "Unknown Employee";
      final deptName = dept?.departmentName ?? "Unknown Department";

      final schedule = scheduleMap[dto.departmentId ?? 0];

      // Compute discrepancies for UI display
      final computed = await _computeApprovalFields(dto, schedule, dto.userId, dto.logDate ?? "");

      return AttendanceApprovalHeader(
        approvalId: dto.logId,
        employeeId: dto.userId,
        employeeName: employeeName,
        departmentId: dto.departmentId ?? 0,
        departmentName: deptName,
        dateSchedule: parseDate(dto.logDate),
        lateMinutes: computed.lateMinutes,
        overtimeMinutes: computed.overtimeMinutes,
        undertimeMinutes: computed.undertimeMinutes,
        workMinutes: computed.workMinutes,
        status: AttendanceStatus.fromApi(dto.approvalStatus),
        attendanceLogStatus: AttendanceLogStatus.fromApi(dto.status),
        remarks: "", // Remarks are added on approval, so empty for pending.
        approvedBy: null,
        approvedAt: null,
        scheduleStart: schedule?.workStart,
        scheduleEnd: schedule?.workEnd,
        actualStart: dto.timeIn,
        actualEnd: dto.timeOut,
        lunchStart: dto.lunchStart,
        lunchEnd: dto.lunchEnd,
      );
    }).toList();

    final items = await Future.wait(itemsFutures);

    return PagedResult<AttendanceApprovalHeader>(
      items: items,
      total: total,
      limit: limit,
      offset: offset,
    );
  }

  Future<int> fetchAttendancePendingCount() async {
    final json = await _api.getJson(
      "/items/$_logCollection",
      query: <String, String>{
        "limit": "1",
        "offset": "0",
        "fields": "log_id", // minimal field
        "filter[approval_status][_eq]": "pending",
        "meta": "filter_count", // IMPORTANT: filtered count, not total_count
      },
    );

    final meta = json["meta"];
    if (meta is Map) {
      final fc = _asInt(meta["filter_count"]);
      if (fc != null) return fc;
    }

    // Fallback: if meta is missing, use returned data length (still safe for limit=1)
    final data = _readDataList(json);
    return data.length;
  }

  // ============================================================
  // APPROVE
  // ============================================================

  Future<void> approveAttendance({
    required int logId,
    required int employeeId,
    required int approverId,
    required String approverName,
    required String dateScheduleIso, // "YYYY-MM-DD"
  }) async {
    if (logId <= 0) throw Exception("logId is invalid.");
    if (employeeId <= 0) throw Exception("employeeId is invalid.");
    if (approverId <= 0) throw Exception("approverId is invalid.");

    // Fetch the attendance log details
    final logJson = await _api.getJson(
      "/items/$_logCollection/$logId",
      query: {
        "fields":
            "user_id,department_id,log_date,time_in,time_out,lunch_start,lunch_end,approval_status",
      },
    );
    final logData = logJson["data"];
    if (logData == null) throw Exception("Attendance log not found");

    final log = AttendanceLogLite.fromJson(logData as Map<String, dynamic>);

    // Fetch department schedule
    final scheduleJson = await _api.getJson(
      "/items/$_scheduleCollection",
      query: {
        "limit": "1",
        "filter[department_id][_eq]": log.departmentId.toString(),
        "fields": "work_start,work_end",
      },
    );
    final scheduleData = _readDataList(scheduleJson).firstOrNull;
    final schedule = scheduleData != null ? ScheduleLite.fromJson(scheduleData) : null;

    // Compute the required fields
    final computed = await _computeApprovalFields(log, schedule, employeeId, dateScheduleIso);

    final nowIso = DateTime.now().toUtc().toIso8601String();
    final remarks = "Approved by $approverName on $dateScheduleIso";

    // Update attendance_log approval_status
    await _api.patch("/items/$_logCollection/$logId", data: {"approval_status": "Approved"});

    // Create attendance_approval record
    final approvalData = <String, dynamic>{
      "log_id": logId,
      "employee_id": employeeId,
      "date_schedule": dateScheduleIso,
      "status": "approved",
      "approved_at": nowIso,
      "approved_by": approverId,
      "remarks": remarks,
      "late_minutes": computed.lateMinutes,
      "undertime_minutes": computed.undertimeMinutes,
      "work_minutes": computed.workMinutes,
      "overtime_minutes": computed.overtimeMinutes,
    };

    await _api.postJson("/items/$_approvalCollection", body: approvalData);
  }

  // ============================================================
  // COMPUTE APPROVAL FIELDS
  // ============================================================

  Future<_ComputedApprovalFields> _computeApprovalFields(
    AttendanceLogLite log,
    ScheduleLite? schedule,
    int employeeId,
    String dateScheduleIso,
  ) async {
    if (schedule == null) {
      return const _ComputedApprovalFields(
        lateMinutes: 0,
        undertimeMinutes: 0,
        workMinutes: 0,
        overtimeMinutes: 0,
      );
    }

    final timeIn = log.timeIn;
    final timeOut = log.timeOut;
    final workStart = schedule.workStart;
    final workEnd = schedule.workEnd;

    if (timeIn == null || workStart == null || workEnd == null) {
      return const _ComputedApprovalFields(
        lateMinutes: 0,
        undertimeMinutes: 0,
        workMinutes: 0,
        overtimeMinutes: 0,
      );
    }

    // Helper: convert TimeOfDay to minutes since midnight
    int toMinutes(TimeOfDay t) => t.hour * 60 + t.minute;
    // Helper: convert DateTime to minutes since midnight
    int toMinutesFromDateTime(DateTime dt) => dt.hour * 60 + dt.minute;

    final timeInMins = toMinutesFromDateTime(timeIn);
    final workStartMins = toMinutes(workStart);
    final workEndMins = toMinutes(workEnd);

    // Check if schedule date is today
    final todayIso = DateTime.now().toIso8601String().substring(0, 10);
    final isToday = dateScheduleIso == todayIso;

    // 1. late_minutes (calculate even if not timed out, unless today and no time out)
    final lateMinutes = (isToday && timeOut == null)
        ? 0
        : (timeInMins > workStartMins ? timeInMins - workStartMins : 0);

    int undertimeMinutes = 0;
    int workMinutes = 0;
    int overtimeMinutes = 0;

    if (timeOut == null) {
      if (isToday) {
        // If schedule date is today and not timed out, do not compute work_minutes yet
        workMinutes = 0;
      } else {
        // If not timed out within schedule day (past date), set work_minutes to 4 hours (240 minutes)
        workMinutes = 240;
      }
    } else {
      final timeOutMins = toMinutesFromDateTime(timeOut);

      // 2. undertime_minutes
      undertimeMinutes = timeOutMins < workEndMins ? workEndMins - timeOutMins : 0;

      // 3. work_minutes
      final effectiveStartMins = timeInMins > workStartMins ? timeInMins : workStartMins;
      final grossDurationMins = timeOutMins - effectiveStartMins;
      workMinutes = grossDurationMins > 0
          ? (grossDurationMins - 60).clamp(0, double.infinity).toInt()
          : 0;

      // 4. overtime_minutes
      // Check for approved overtime request (handle 403 gracefully)
      try {
        final otJson = await _api.getJson(
          "/items/$_overtimeCollection",
          query: {
            "limit": "1",
            "filter[user_id][_eq]": employeeId.toString(),
            "filter[request_date][_eq]": dateScheduleIso,
            "filter[status][_eq]": "approved",
            "fields": "ot_to",
          },
        );
        final otData = _readDataList(otJson).firstOrNull;

        if (otData != null) {
          final otToRaw = otData["ot_to"]?.toString();
          if (otToRaw != null) {
            final otTo = parseTimeOfDay(otToRaw);
            final otToMins = toMinutes(otTo);

            // Actual OT duration from work_end to time_out
            final actualOtMins = timeOutMins > workEndMins ? timeOutMins - workEndMins : 0;

            // Apply 90-minute minimum
            if (actualOtMins >= 90) {
              // Cap at approved amount: from work_end to min(time_out, ot_to)
              final approvedDuration = otToMins > workEndMins ? otToMins - workEndMins : 0;
              overtimeMinutes = (actualOtMins < approvedDuration) ? actualOtMins : approvedDuration;
            }
          }
        }
      } catch (e) {
        // If we can't access overtime_request (403), assume no overtime
        overtimeMinutes = 0;
      }
    }

    return _ComputedApprovalFields(
      lateMinutes: lateMinutes,
      undertimeMinutes: undertimeMinutes,
      workMinutes: workMinutes,
      overtimeMinutes: overtimeMinutes,
    );
  }

  // ============================================================
  // REJECT
  // ============================================================

  Future<void> rejectAttendance({
    required int logId,
    required int employeeId,
    required int approverId,
    required String approverName,
    required String dateScheduleIso, // "YYYY-MM-DD"
  }) async {
    if (logId <= 0) throw Exception("logId is invalid.");
    if (employeeId <= 0) throw Exception("employeeId is invalid.");
    if (approverId <= 0) throw Exception("approverId is invalid.");

    final nowIso = DateTime.now().toUtc().toIso8601String();
    final remarks = "Rejected by $approverName on $dateScheduleIso";

    // 1. Update the original log's status to 'Rejected'
    await _api.patch("/items/$_logCollection/$logId", data: {"approval_status": "Rejected"});

    // 2. Create a new record in the attendance_approval table
    final approvalData = <String, dynamic>{
      "employee_id": employeeId,
      "date_schedule": dateScheduleIso,
      "status": "rejected",
      "approved_at": nowIso,
      "approved_by": approverId,
      "remarks": remarks,
    };

    await _api.postJson("/items/$_approvalCollection", body: approvalData);
  }

  // ============================================================
  // APPROVE SELECTED ATTENDANCE
  // ============================================================

  Future<List<int>> approveSelectedAttendance({
    required List<int> logIds,
    required int employeeId,
    required int approverId,
    required String approverName,
  }) async {
    if (logIds.isEmpty) return [];
    if (employeeId <= 0) throw Exception("employeeId is invalid.");
    if (approverId <= 0) throw Exception("approverId is invalid.");

    final approvedLogIds = <int>[];

    // Process each selected log individually
    for (final logId in logIds) {
      try {
        // Fetch the log details to get dateScheduleIso
        final logJson = await _api.getJson(
          "/items/$_logCollection/$logId",
          query: {"fields": "log_date"},
        );
        final logData = logJson["data"];
        if (logData == null) continue;

        final dateScheduleIso = logData["log_date"]?.toString() ?? "";

        await approveAttendance(
          logId: logId,
          employeeId: employeeId,
          approverId: approverId,
          approverName: approverName,
          dateScheduleIso: dateScheduleIso,
        );
        approvedLogIds.add(logId);
      } catch (e) {
        // Continue with other logs even if one fails
        continue;
      }
    }

    return approvedLogIds;
  }

  // ============================================================
  // APPROVE ALL PENDING FOR EMPLOYEE
  // ============================================================

  Future<List<int>> approveAllPendingAttendanceForEmployee({
    required int employeeId,
    required int approverId,
    required String approverName,
  }) async {
    if (employeeId <= 0) throw Exception("employeeId is invalid.");
    if (approverId <= 0) throw Exception("approverId is invalid.");

    // Fetch all pending attendance logs for this employee
    final json = await _api.getJson(
      "/items/$_logCollection",
      query: {
        "limit": "1000", // Get up to 1000 pending records
        "filter[user_id][_eq]": employeeId.toString(),
        "filter[approval_status][_eq]": "pending",
        "fields": "log_id,user_id,department_id,log_date,time_in,time_out,lunch_start,lunch_end",
      },
    );

    final logs = _readDataList(json).map(AttendanceLogLite.fromJson).toList();

    if (logs.isEmpty) {
      return []; // No pending records to approve
    }

    final approvedLogIds = <int>[];

    // Process each log individually
    for (final log in logs) {
      try {
        await approveAttendance(
          logId: log.logId,
          employeeId: employeeId,
          approverId: approverId,
          approverName: approverName,
          dateScheduleIso: log.logDate ?? "",
        );
        approvedLogIds.add(log.logId);
      } catch (e) {
        // Continue with other logs even if one fails
        // You might want to collect errors and return them
        continue;
      }
    }

    return approvedLogIds;
  }

  // ============================================================
  // LOOKUPS
  // ============================================================

  Future<Map<int, AppUserLite>> fetchUsersByIds(List<int> ids) async {
    final uniq = ids.where((e) => e > 0).toSet().toList()..sort();
    if (uniq.isEmpty) return const {};

    final json = await _api.getJson(
      "/items/$_userCollection",
      query: {
        "limit": "-1",
        "filter[user_id][_in]": uniq.join(","),
        "fields": "user_id,user_fname,user_lname,is_deleted",
      },
    );

    final data = _readDataList(json);
    final out = <int, AppUserLite>{};

    for (final row in data) {
      final u = AppUserLite.fromJson(row);
      if (u.userId > 0) out[u.userId] = u;
    }
    return out;
  }

  Future<Map<int, DepartmentLite>> fetchDepartmentsByIds(List<int> ids) async {
    final uniq = ids.where((e) => e > 0).toSet().toList()..sort();
    if (uniq.isEmpty) return const {};

    final json = await _api.getJson(
      "/items/$_deptCollection",
      query: {
        "limit": "-1",
        "filter[department_id][_in]": uniq.join(","),
        "fields": "department_id,department_name",
      },
    );

    final data = _readDataList(json);
    final out = <int, DepartmentLite>{};

    for (final row in data) {
      final d = DepartmentLite.fromJson(row);
      if (d.departmentId > 0) out[d.departmentId] = d;
    }
    return out;
  }

  Future<Map<int, ScheduleLite>> _fetchSchedulesForLogs(List<AttendanceLogLite> logs) async {
    final deptIds = logs.map((e) => e.departmentId ?? 0).where((id) => id > 0).toSet().toList();
    if (deptIds.isEmpty) return const {};

    final json = await _api.getJson(
      "/items/$_scheduleCollection",
      query: {
        "limit": "-1",
        "filter[department_id][_in]": deptIds.join(","),
        "fields": "department_id,work_start,work_end",
      },
    );

    final data = _readDataList(json);
    final out = <int, ScheduleLite>{};

    for (final row in data) {
      final s = ScheduleLite.fromJson(row);
      if (s.departmentId > 0) out[s.departmentId] = s;
    }
    return out;
  }

  Future<Map<int, ScheduleLite>> _fetchSchedulesForApprovals(
    List<AttendanceApprovalLite> approvals,
  ) async {
    final deptIds = approvals
        .map((e) => e.departmentId ?? 0)
        .where((id) => id > 0)
        .toSet()
        .toList();
    if (deptIds.isEmpty) return const {};

    final json = await _api.getJson(
      "/items/$_scheduleCollection",
      query: {
        "limit": "-1",
        "filter[department_id][_in]": deptIds.join(","),
        "fields": "department_id,work_start,work_end",
      },
    );

    final data = _readDataList(json);
    final out = <int, ScheduleLite>{};

    for (final row in data) {
      final s = ScheduleLite.fromJson(row);
      if (s.departmentId > 0) out[s.departmentId] = s;
    }
    return out;
  }

  Future<Map<int, LogLite>> _fetchLogsForApprovals(List<AttendanceApprovalLite> approvals) async {
    final userIds = approvals.map((e) => e.employeeId).where((id) => id > 0).toSet().toList();
    final dates = approvals.map((e) => e.dateSchedule).where((d) => d != null).toSet().toList();
    if (userIds.isEmpty || dates.isEmpty) return const {};

    final userFilter = userIds.join(",");
    final dateFilter = dates.join(",");

    final json = await _api.getJson(
      "/items/$_logCollection",
      query: {
        "limit": "-1",
        "filter[user_id][_in]": userFilter,
        "filter[log_date][_in]": dateFilter,
        "fields": "user_id,log_date,time_in,time_out,lunch_start,lunch_end,approval_status",
      },
    );

    final data = _readDataList(json);
    final out = <int, LogLite>{};

    for (final row in data) {
      final l = LogLite.fromJson(row);
      if (l.userId > 0) out[l.userId] = l; // Assuming one log per user per date
    }
    return out;
  }

  // ============================================================
  // SEARCH FILTERS
  // ============================================================

  Future<void> _applySearchFilters(Map<String, String> query, String q) async {
    // Numeric: assume log_id
    final asInt = int.tryParse(q);
    if (asInt != null) {
      query["filter[log_id][_eq]"] = q;
      return;
    }

    // Date: exact match
    if (RegExp(r"^\d{4}-\d{2}-\d{2}$").hasMatch(q)) {
      query["filter[log_date][_eq]"] = q;
      return;
    }

    // Text: search remarks only (to avoid 403 on related tables)
    query["filter[remarks][_icontains]"] = q;
  }

  void addOrDateRange(String field, String startInclusive, String endExclusive) {
    // Note: This is simplified; in practice, you'd need to handle the index properly
    // For now, assuming single date range
  }

  Future<List<int>> _searchUserIdsByName(String q, {int limit = 80}) async {
    final s = q.trim();
    if (s.isEmpty) return const [];

    final query = <String, String>{
      "limit": limit.toString(),
      "fields": "user_id",
      "filter[_or][0][user_fname][_icontains]": s,
      "filter[_or][1][user_lname][_icontains]": s,
      "filter[_or][2][user_mname][_icontains]": s,
    };

    final json = await _api.getJson("/items/$_userCollection", query: query);
    final data = _readDataList(json);

    final ids = <int>[];
    for (final row in data) {
      final id = _asInt(row["user_id"]) ?? 0;
      if (id > 0) ids.add(id);
    }
    return ids.toSet().toList()..sort();
  }

  Future<List<int>> _searchDepartmentIdsByName(String q, {int limit = 50}) async {
    final s = q.trim();
    if (s.isEmpty) return const [];

    final query = <String, String>{
      "limit": limit.toString(),
      "fields": "department_id",
      "filter[department_name][_icontains]": s,
    };

    final json = await _api.getJson("/items/$_deptCollection", query: query);
    final data = _readDataList(json);

    final ids = <int>[];
    for (final row in data) {
      final id = _asInt(row["department_id"]) ?? 0;
      if (id > 0) ids.add(id);
    }
    return ids.toSet().toList()..sort();
  }

  // ============================================================
  // INTERNAL HELPERS
  // ============================================================

  List<Map<String, dynamic>> _readDataList(Map<String, dynamic> json) {
    final raw = json["data"];
    if (raw is List) {
      return raw.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList();
    }
    return const [];
  }

  int? _asInt(Object? v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString());
  }

  String _fmtDate(DateTime d) {
    final y = d.year.toString().padLeft(4, "0");
    final m = d.month.toString().padLeft(2, "0");
    final dd = d.day.toString().padLeft(2, "0");
    return "$y-$m-$dd";
  }
}

// =============================
// MODELS (Lite, repo-facing)
// =============================

class AttendanceApprovalLite {
  final int approvalId;
  final String? approvedAt;
  final int? approvedBy;
  final String? dateSchedule;
  final int employeeId;
  final int lateMinutes;
  final int overtimeMinutes;
  final String? remarks;
  final String? status;
  final int undertimeMinutes;
  final int workMinutes;
  final int? departmentId; // Need to fetch this from user or log

  const AttendanceApprovalLite({
    required this.approvalId,
    required this.approvedAt,
    required this.approvedBy,
    required this.dateSchedule,
    required this.employeeId,
    required this.lateMinutes,
    required this.overtimeMinutes,
    required this.remarks,
    required this.status,
    required this.undertimeMinutes,
    required this.workMinutes,
    this.departmentId,
  });

  factory AttendanceApprovalLite.fromJson(Map<String, dynamic> j) {
    int asInt(Object? v) => (v is num) ? v.toInt() : int.tryParse("$v") ?? 0;
    int? asIntN(Object? v) => (v is num) ? v.toInt() : int.tryParse("$v");

    return AttendanceApprovalLite(
      approvalId: asInt(j["approval_id"]),
      approvedAt: j["approved_at"]?.toString(),
      approvedBy: asIntN(j["approved_by"]),
      dateSchedule: j["date_schedule"]?.toString(),
      employeeId: asInt(j["employee_id"]),
      lateMinutes: asInt(j["late_minutes"]),
      overtimeMinutes: asInt(j["overtime_minutes"]),
      remarks: j["remarks"]?.toString(),
      status: j["status"]?.toString(),
      undertimeMinutes: asInt(j["undertime_minutes"]),
      workMinutes: asInt(j["work_minutes"]),
      departmentId: asIntN(j["department_id"]), // Assuming it's added to the API
    );
  }
}

class AttendanceLogLite {
  final int logId;
  final int userId;
  final int? departmentId;
  final String? logDate;
  final DateTime? timeIn;
  final DateTime? timeOut;
  final DateTime? lunchStart;
  final DateTime? lunchEnd;
  final String? approvalStatus;
  final String? status;
  final String? createdAt;
  final String? updatedAt;

  const AttendanceLogLite({
    required this.logId,
    required this.userId,
    this.departmentId,
    this.logDate,
    this.timeIn,
    this.timeOut,
    this.lunchStart,
    this.lunchEnd,
    this.approvalStatus,
    this.status,
    this.createdAt,
    this.updatedAt,
  });

  factory AttendanceLogLite.fromJson(Map<String, dynamic> j) {
    int asInt(Object? v) => (v is num) ? v.toInt() : int.tryParse("$v") ?? 0;
    int? asIntN(Object? v) => (v is num) ? v.toInt() : int.tryParse("$v");

    return AttendanceLogLite(
      logId: asInt(j["log_id"]),
      userId: asInt(j["user_id"]),
      departmentId: asIntN(j["department_id"]),
      logDate: j["log_date"]?.toString(),
      timeIn: j["time_in"] != null ? DateTime.tryParse(j["time_in"].toString())?.toLocal() : null,
      timeOut: j["time_out"] != null
          ? DateTime.tryParse(j["time_out"].toString())?.toLocal()
          : null,
      lunchStart: j["lunch_start"] != null
          ? DateTime.tryParse(j["lunch_start"].toString())?.toLocal()
          : null,
      lunchEnd: j["lunch_end"] != null
          ? DateTime.tryParse(j["lunch_end"].toString())?.toLocal()
          : null,
      approvalStatus: j["approval_status"]?.toString(),
      status: j["status"]?.toString(),
      createdAt: j["created_at"]?.toString(),
      updatedAt: j["updated_at"]?.toString(),
    );
  }
}

class ScheduleLite {
  final int departmentId;
  final TimeOfDay? workStart;
  final TimeOfDay? workEnd;

  const ScheduleLite({required this.departmentId, this.workStart, this.workEnd});

  factory ScheduleLite.fromJson(Map<String, dynamic> j) {
    return ScheduleLite(
      departmentId: (j["department_id"] is num)
          ? (j["department_id"] as num).toInt()
          : int.tryParse("${j["department_id"]}") ?? 0,
      workStart: j["work_start"] != null ? parseTimeOfDay(j["work_start"].toString()) : null,
      workEnd: j["work_end"] != null ? parseTimeOfDay(j["work_end"].toString()) : null,
    );
  }
}

class LogLite {
  final int userId;
  final TimeOfDay? timeIn;
  final TimeOfDay? timeOut;
  final TimeOfDay? lunchStart;
  final TimeOfDay? lunchEnd;
  final String? approvalStatus;

  const LogLite({
    required this.userId,
    this.timeIn,
    this.timeOut,
    this.lunchStart,
    this.lunchEnd,
    this.approvalStatus,
  });

  factory LogLite.fromJson(Map<String, dynamic> j) {
    return LogLite(
      userId: (j["user_id"] is num)
          ? (j["user_id"] as num).toInt()
          : int.tryParse("${j["user_id"]}") ?? 0,
      timeIn: j["time_in"] != null ? parseTimeOfDay(j["time_in"].toString()) : null,
      timeOut: j["time_out"] != null ? parseTimeOfDay(j["time_out"].toString()) : null,
      lunchStart: j["lunch_start"] != null ? parseTimeOfDay(j["lunch_start"].toString()) : null,
      lunchEnd: j["lunch_end"] != null ? parseTimeOfDay(j["lunch_end"].toString()) : null,
      approvalStatus: j["approval_status"]?.toString(),
    );
  }
}

class AppUserLite {
  final int userId;
  final String? fname;
  final String? lname;
  final Object? isDeleted;

  const AppUserLite({
    required this.userId,
    required this.fname,
    required this.lname,
    required this.isDeleted,
  });

  String get displayName {
    final f = (fname ?? "").trim();
    final l = (lname ?? "").trim();
    final name = "$f $l".trim();
    return name.isEmpty ? "Unknown" : name;
  }

  factory AppUserLite.fromJson(Map<String, dynamic> j) {
    int asInt(Object? v) => (v is num) ? v.toInt() : int.tryParse("$v") ?? 0;
    return AppUserLite(
      userId: asInt(j["user_id"]),
      fname: j["user_fname"]?.toString(),
      lname: j["user_lname"]?.toString(),
      isDeleted: j["is_deleted"],
    );
  }
}

class DepartmentLite {
  final int departmentId;
  final String departmentName;

  const DepartmentLite({required this.departmentId, required this.departmentName});

  factory DepartmentLite.fromJson(Map<String, dynamic> j) {
    int asInt(Object? v) => (v is num) ? v.toInt() : int.tryParse("$v") ?? 0;
    return DepartmentLite(
      departmentId: asInt(j["department_id"]),
      departmentName: (j["department_name"] ?? "").toString(),
    );
  }
}

// =============================
// INTERNAL MODELS
// =============================

class _ComputedApprovalFields {
  final int lateMinutes;
  final int undertimeMinutes;
  final int workMinutes;
  final int overtimeMinutes;

  const _ComputedApprovalFields({
    required this.lateMinutes,
    required this.undertimeMinutes,
    required this.workMinutes,
    required this.overtimeMinutes,
  });
}

// Helper functions (assuming from overtime_models)
String formatTimeOfDay(TimeOfDay t) {
  final hh = t.hour.toString().padLeft(2, "0");
  final mm = t.minute.toString().padLeft(2, "0");
  return "$hh:$mm";
}

TimeOfDay parseTimeOfDay(String? raw) {
  final s = (raw ?? "").trim();
  if (s.isEmpty) return const TimeOfDay(hour: 0, minute: 0);

  final parts = s.split(":");
  if (parts.length < 2) return const TimeOfDay(hour: 0, minute: 0);

  final h = int.tryParse(parts[0]) ?? 0;
  final m = int.tryParse(parts[1]) ?? 0;

  return TimeOfDay(hour: h.clamp(0, 23), minute: m.clamp(0, 59));
}

DateTime parseDate(String? raw) {
  final s = (raw ?? "").trim();
  if (s.isEmpty) return DateTime.fromMillisecondsSinceEpoch(0);

  if (RegExp(r"^\d{4}-\d{2}-\d{2}$").hasMatch(s)) {
    final parts = s.split("-");
    final y = int.tryParse(parts[0]) ?? 1970;
    final mo = int.tryParse(parts[1]) ?? 1;
    final d = int.tryParse(parts[2]) ?? 1;
    return DateTime(y, mo, d);
  }

  final dt = DateTime.tryParse(s);
  return dt?.toLocal() ?? DateTime.fromMillisecondsSinceEpoch(0);
}
