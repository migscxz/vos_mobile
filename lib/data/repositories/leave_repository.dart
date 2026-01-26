// lib/data/repositories/leave_repository.dart
import "../../core/network/api_client.dart";
import "../../modules/approvals/leave/leave_models.dart";

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

class LeaveRepository {
  LeaveRepository(this._api);

  final ApiClient _api;

  static const String _leaveCollection = "leave_request";
  static const String _userCollection = "user";
  static const String _deptCollection = "department";

  static const List<String> _leaveFieldsList = [
    "leave_id",
    "user_id",
    "department_id",
    "filed_at",
    "leave_start",
    "leave_end",
    "leave_type",
    "reason",
    "status",
    "total_days",
    "remarks",
    "approver_id",
    "approved_at",
  ];

  static final String _leaveFields = _leaveFieldsList.join(",");

  // ============================================================
  // PUBLIC: PAGED LIST (ENRICHED FOR UI)
  // ============================================================

  /// Main leave approvals fetch (paged + enriched).
  Future<PagedResult<LeaveApprovalHeader>> fetchLeaveApprovalsPaged({
    String? status, // "pending" | "approved" | "rejected" | null
    String? search,
    required int limit,
    required int offset,
  }) async {
    final q = (search ?? "").trim();

    final query = <String, String>{
      "limit": limit.toString(),
      "offset": offset.toString(),
      "sort": "-filed_at,-leave_id",
      "fields": _leaveFields,
      "meta": "total_count",
    };

    final st = (status ?? "").trim().toLowerCase();
    if (st.isNotEmpty) {
      query["filter[status][_eq]"] = st;
    }

    if (q.isNotEmpty) {
      await _applySearchFilters(query, q);
    }

    final json = await _api.getJson("/items/$_leaveCollection", query: query);
    final dtos = _readDataList(json).map(LeaveRequestLite.fromJson).toList();

    int total = dtos.length;
    final meta = json["meta"];
    if (meta is Map) {
      final tc = _asInt(meta["total_count"]);
      if (tc != null) total = tc;
    }

    // Enrich: users + departments
    final userIds = <int>{
      ...dtos.map((e) => e.userId).where((id) => id > 0),
      ...dtos.map((e) => e.approverId ?? 0).where((id) => id > 0),
    }.toList()..sort();

    final deptIds = dtos.map((e) => e.departmentId).where((id) => id > 0).toSet().toList()..sort();

    final userMap = await fetchUsersByIds(userIds);
    final deptMap = await fetchDepartmentsByIds(deptIds);

    final items = dtos.map((dto) {
      final employee = userMap[dto.userId];
      final dept = deptMap[dto.departmentId];

      final employeeName = employee?.displayName ?? "Unknown Employee";
      final deptName = dept?.departmentName ?? "Unknown Department";

      return LeaveApprovalHeader(
        leaveId: dto.leaveId,
        userId: dto.userId,
        employeeName: employeeName,
        departmentId: dto.departmentId,
        departmentName: deptName,
        requestDate: parseDate(dto.filedAt),
        filedAt: parseDate(dto.filedAt),
        leaveStart: parseDate(dto.leaveStart),
        leaveEnd: parseDate(dto.leaveEnd),
        leaveType: LeaveType.fromApi(dto.leaveType),
        totalDays: dto.totalDays,
        status: LeaveStatus.fromApi(dto.status),
        reason: dto.reason ?? "",
        remarks: dto.remarks,
        approverId: dto.approverId,
        approvedAt: dto.approvedAt == null ? null : parseDate(dto.approvedAt),
      );
    }).toList();

    return PagedResult<LeaveApprovalHeader>(
      items: items,
      total: total,
      limit: limit,
      offset: offset,
    );
  }

  /// COMPAT ALIAS
  Future<PagedResult<LeaveApprovalHeader>> fetchLeaveRequestsPaged({
    String? status,
    String? search,
    required int limit,
    required int offset,
  }) {
    return fetchLeaveApprovalsPaged(status: status, search: search, limit: limit, offset: offset);
  }

  Future<int> fetchLeavePendingCount() async {
    final json = await _api.getJson(
      "/items/$_leaveCollection",
      query: <String, String>{
        "limit": "1",
        "offset": "0",
        "fields": "leave_id", // minimal field
        "filter[status][_eq]": "pending",
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

  Future<void> approveLeave({
    required int leaveId,
    required int approverId,
    required String approverName,
    required String requestDateIso, // "YYYY-MM-DD"
  }) async {
    if (leaveId <= 0) throw Exception("leaveId is invalid.");
    if (approverId <= 0) throw Exception("approverId is invalid.");

    final nowIso = DateTime.now().toUtc().toIso8601String();
    final remarks = "Leave approved by $approverName on $requestDateIso";

    final data = <String, dynamic>{
      "status": "approved",
      "approved_at": nowIso,
      "approver_id": approverId,
      "remarks": remarks,
    };

    await _api.patch("/items/$_leaveCollection/$leaveId", data: data);
  }

  // ============================================================
  // REJECT
  // ============================================================

  Future<void> rejectLeave({
    required int leaveId,
    required int approverId,
    required String approverName,
    required String requestDateIso, // "YYYY-MM-DD"
  }) async {
    if (leaveId <= 0) throw Exception("leaveId is invalid.");
    if (approverId <= 0) throw Exception("approverId is invalid.");

    final nowIso = DateTime.now().toUtc().toIso8601String();
    final remarks = "Leave rejected by $approverName on $requestDateIso";

    final data = <String, dynamic>{
      "status": "rejected",
      "approved_at": nowIso, // you only have approved_at column; using it as action timestamp
      "approver_id": approverId,
      "remarks": remarks,
    };

    await _api.patch("/items/$_leaveCollection/$leaveId", data: data);
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

  // ============================================================
  // SEARCH FILTERS (SAFE FOR DIRECTUS TYPES)
  // ============================================================

  Future<void> _applySearchFilters(Map<String, String> query, String q) async {
    int i = 0;

    void addOr(String field, String op, String value) {
      query["filter[_or][$i][$field][$op]"] = value;
      i++;
    }

    void addOrDateRange(String field, String startInclusive, String endExclusive) {
      // One OR branch containing AND constraints (gte + lt)
      query["filter[_or][$i][_and][0][$field][_gte]"] = startInclusive;
      query["filter[_or][$i][_and][1][$field][_lt]"] = endExclusive;
      i++;
    }

    // Text fields (safe)
    addOr("reason", "_icontains", q);
    addOr("remarks", "_icontains", q);

    // Numeric direct hits
    final asInt = int.tryParse(q);
    if (asInt != null) {
      addOr("user_id", "_eq", q);
      addOr("department_id", "_eq", q);
      addOr("leave_id", "_eq", q);
    }

    // Date field handling: filed_at is a Directus DATETIME
    // Support:
    // - YYYY-MM-DD => _eq
    // - YYYY-MM    => month range
    // - YYYY       => year range
    if (RegExp(r"^\d{4}-\d{2}-\d{2}$").hasMatch(q)) {
      addOr("filed_at", "_eq", q);
    } else if (RegExp(r"^\d{4}-\d{2}$").hasMatch(q)) {
      final parts = q.split("-");
      final y = int.tryParse(parts[0]) ?? 1970;
      final m = int.tryParse(parts[1]) ?? 1;
      final start = DateTime(y, m, 1);
      final end = DateTime(y, m + 1, 1);
      addOrDateRange("filed_at", _fmtDate(start), _fmtDate(end));
    } else if (RegExp(r"^\d{4}$").hasMatch(q)) {
      final y = int.tryParse(q) ?? 1970;
      final start = DateTime(y, 1, 1);
      final end = DateTime(y + 1, 1, 1);
      addOrDateRange("filed_at", _fmtDate(start), _fmtDate(end));
    }

    // Only do user/dept lookups if query likely contains letters (reduces API calls)
    final hasLetters = RegExp(r"[A-Za-z]").hasMatch(q);
    if (!hasLetters) return;

    final userIds = await _searchUserIdsByName(q, limit: 80);
    if (userIds.isNotEmpty) {
      addOr("user_id", "_in", userIds.join(","));
    }

    final deptIds = await _searchDepartmentIdsByName(q, limit: 80);
    if (deptIds.isNotEmpty) {
      addOr("department_id", "_in", deptIds.join(","));
    }
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

  Future<List<int>> _searchDepartmentIdsByName(String q, {int limit = 80}) async {
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

class LeaveRequestLite {
  final int leaveId;
  final int userId;
  final int departmentId;

  final String? filedAt; // ISO datetime

  final String? leaveStart; // "YYYY-MM-DD"
  final String? leaveEnd; // "YYYY-MM-DD"
  final String? leaveType; // "vacation" | "sick" | "emergency"

  final double totalDays;
  final String? status; // "pending" | "approved" | "rejected"

  final String? reason;
  final String? remarks;

  final int? approverId;
  final String? approvedAt;

  const LeaveRequestLite({
    required this.leaveId,
    required this.userId,
    required this.departmentId,
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

  factory LeaveRequestLite.fromJson(Map<String, dynamic> j) {
    int asInt(Object? v) => (v is num) ? v.toInt() : int.tryParse("$v") ?? 0;
    int? asIntN(Object? v) => (v is num) ? v.toInt() : int.tryParse("$v");
    double asDouble(Object? v) => (v is num) ? v.toDouble() : double.tryParse("$v") ?? 0.0;

    return LeaveRequestLite(
      leaveId: asInt(j["leave_id"]),
      userId: asInt(j["user_id"]),
      departmentId: asInt(j["department_id"]),
      filedAt: j["filed_at"]?.toString(),
      leaveStart: j["leave_start"]?.toString(),
      leaveEnd: j["leave_end"]?.toString(),
      leaveType: j["leave_type"]?.toString(),
      totalDays: asDouble(j["total_days"]),
      status: j["status"]?.toString(),
      reason: j["reason"]?.toString(),
      remarks: j["remarks"]?.toString(),
      approverId: asIntN(j["approver_id"]),
      approvedAt: j["approved_at"]?.toString(),
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
