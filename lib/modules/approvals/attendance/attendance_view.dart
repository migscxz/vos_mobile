// lib/modules/approvals/attendance/attendance_view.dart
import "dart:async";

import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";

import "../../../app.dart"; // apiClientProvider
import "../../../core/auth/user_permissions.dart";
import "../../../data/repositories/attendance_repository.dart" hide formatTimeOfDay;
import "attendance_model.dart";
import 'attendance_sheet.dart';

class AttendanceApprovalView extends ConsumerStatefulWidget {
  const AttendanceApprovalView({super.key});

  @override
  ConsumerState<AttendanceApprovalView> createState() => _AttendanceApprovalViewState();
}

class _AttendanceApprovalViewState extends ConsumerState<AttendanceApprovalView> {
  final TextEditingController _searchCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  Timer? _debounce;

  String _query = "";
  bool _loading = true;
  String? _error;
  bool _loadingMore = false;
  bool _hasMore = true;

  late final AttendanceRepository _repo;

  AttendancePermission? _userPermission;

  final List<AttendanceApprovalGroup> _groups = [];
  final int _limit = 20;
  int _offset = 0;
  final int _initialLimit = -1; // Load all employees initially

  List<AttendanceApprovalGroup> get _filteredGroups {
    if (_query.trim().isEmpty) return _groups;

    final query = _query.trim().toLowerCase();
    return _groups.where((group) {
      return group.employeeName.toLowerCase().contains(query) ||
          group.departmentName.toLowerCase().contains(query);
    }).toList();
  }

  int get _totalPendingApprovals {
    final groups = _query.isNotEmpty ? _filteredGroups : _groups;
    return groups.fold(0, (sum, group) => sum + group.pendingCount);
  }

  @override
  void initState() {
    super.initState();
    _repo = AttendanceRepository(ref.read(apiClientProvider));
    _scrollCtrl.addListener(_onScroll);
    _loadUserPermissionAndData();
  }

  Future<void> _loadUserPermissionAndData() async {
    final permission = await _getCurrentUserPermission();
    setState(() => _userPermission = permission);

    if (permission != AttendancePermission.none) {
      _reload();
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollCtrl.position.pixels >= _scrollCtrl.position.maxScrollExtent - 200 &&
        !_loadingMore &&
        _hasMore &&
        _query.isEmpty) {
      _loadMore();
    }
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 320), () {
      if (!mounted) return;

      final next = value.trim();
      if (next == _query) return;

      setState(() => _query = next);
    });
  }

  Future<List<int>?> _getAllowedDepartmentIds() async {
    try {
      final service = ref.read(userPermissionsServiceProvider);
      final user = await service.getCurrentUser();
      if (user == null) return null;

      final permission = user.getAttendancePermission();
      switch (permission) {
        case AttendancePermission.none:
          return [];
        case AttendancePermission.readOwnDepartment:
        case AttendancePermission.approveOwnDepartment:
          return user.departmentId != null ? [user.departmentId!] : [];
        case AttendancePermission.readAllDepartments:
        case AttendancePermission.approveAllDepartments:
          return null; // null means all departments
      }
    } catch (e) {
      debugPrint('Error getting user permissions: $e');
      return null;
    }
  }

  Future<AttendancePermission> _getCurrentUserPermission() async {
    try {
      final service = ref.read(userPermissionsServiceProvider);
      final user = await service.getCurrentUser();
      return user?.getAttendancePermission() ?? AttendancePermission.none;
    } catch (e) {
      debugPrint('Error getting user permission: $e');
      return AttendancePermission.none;
    }
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
      _groups.clear();
      _offset = 0;
      _hasMore = true;
    });

    try {
      final allowedDepartmentIds = await _getAllowedDepartmentIds();
      final page = await _repo.fetchAttendanceApprovalsPaged(
        status: "pending",
        search: null,
        limit: _initialLimit, // Load all employees initially
        offset: _offset,
        allowedDepartmentIds: allowedDepartmentIds,
      );

      if (!mounted) return;

      // Group by employee
      final Map<int, List<AttendanceApprovalHeader>> grouped = {};
      for (final item in page.items) {
        grouped.putIfAbsent(item.employeeId, () => []).add(item);
      }

      final groups = grouped.entries.map((entry) {
        final employeeId = entry.key;
        final approvals = entry.value;
        final first = approvals.first;
        return AttendanceApprovalGroup(
          employeeId: employeeId,
          employeeName: first.employeeName,
          departmentName: first.departmentName,
          pendingApprovals: approvals,
        );
      }).toList();

      // Sort groups alphabetically by employee name
      groups.sort((a, b) => a.employeeName.compareTo(b.employeeName));

      setState(() {
        _groups.addAll(groups);
        _offset += page.items.length;
        _hasMore = page.items.length == _limit;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;

    setState(() {
      _loadingMore = true;
    });

    try {
      final page = await _repo.fetchAttendanceApprovalsPaged(
        status: "pending",
        search: null,
        limit: _limit,
        offset: _offset,
      );

      if (!mounted) return;

      // Group by employee
      final Map<int, List<AttendanceApprovalHeader>> grouped = {};
      for (final item in page.items) {
        grouped.putIfAbsent(item.employeeId, () => []).add(item);
      }

      final groups = grouped.entries.map((entry) {
        final employeeId = entry.key;
        final approvals = entry.value;
        final first = approvals.first;
        return AttendanceApprovalGroup(
          employeeId: employeeId,
          employeeName: first.employeeName,
          departmentName: first.departmentName,
          pendingApprovals: approvals,
        );
      }).toList();

      setState(() {
        _groups.addAll(groups);
        _offset += page.items.length;
        _hasMore = page.items.length == _limit;
        _loadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loadingMore = false;
      });
    }
  }

  Future<void> _openApprovalModal(AttendanceApprovalGroup group) async {
    final outcome = await showModalBottomSheet<AttendanceApproveOutcome?>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AttendanceApprovalSheet(group: group),
    );

    if (outcome == null) return;

    await _reload();
    if (!mounted) return;

    final msg = outcome.newStatus == AttendanceStatus.approved
        ? "Approved selected attendance for ${group.employeeName}."
        : "Rejected selected attendance for ${group.employeeName}.";
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Widget _buildSearchHeader(ColorScheme cs, bool searching) {
    return Container(
      color: cs.surface,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      child: Column(
        children: [
          Container(
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(14),
            ),
            child: TextField(
              controller: _searchCtrl,
              onChanged: _onSearchChanged,
              decoration: InputDecoration(
                hintText: "Search employee, department...",
                prefixIcon: Icon(Icons.search_rounded, color: cs.primary, size: 20),
                suffixIcon: _searchCtrl.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.cancel, size: 18),
                        onPressed: () {
                          _searchCtrl.clear();
                          _onSearchChanged("");
                        },
                      )
                    : null,
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (!_loading)
            Text(
              "$_totalPendingApprovals pending approval${_totalPendingApprovals != 1 ? 's' : ''}",
              style: TextStyle(
                fontSize: 12,
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final searching = _query.trim().isNotEmpty;

    return Scaffold(
      backgroundColor: cs.surfaceContainerLowest,
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: cs.surface,
        centerTitle: false,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Attendance",
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 24,
                color: cs.onSurface,
                letterSpacing: -0.8,
              ),
            ),
            Text(
              "Manage and approve attendance discrepancies",
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _reload)],
      ),
      body: Column(
        children: [
          _buildSearchHeader(cs, searching),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : (_error != null)
                ? _ErrorState(message: _error!, onRetry: _reload)
                : RefreshIndicator(
                    onRefresh: _reload,
                    child: (_query.isNotEmpty ? _filteredGroups : _groups).isEmpty
                        ? ListView(children: [_EmptyState(query: _query)])
                        : ListView.builder(
                            controller: _scrollCtrl,
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                            itemCount:
                                (_query.isNotEmpty ? _filteredGroups : _groups).length +
                                (_loadingMore ? 1 : 0),
                            itemBuilder: (context, i) {
                              if (i == (_query.isNotEmpty ? _filteredGroups : _groups).length) {
                                // Loading indicator at the end
                                return const Padding(
                                  padding: EdgeInsets.all(16),
                                  child: Center(child: CircularProgressIndicator()),
                                );
                              }

                              final group = (_query.isNotEmpty ? _filteredGroups : _groups)[i];

                              return Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: _AttendanceGroupCard(
                                  group: group,
                                  onTap: () => _openApprovalModal(group),
                                ),
                              );
                            },
                          ),
                  ),
          ),
        ],
      ),
    );
  }
}

// ------------------------------
// UI: ATTENDANCE CARD
// ------------------------------
class _AttendanceCard extends StatelessWidget {
  final AttendanceApprovalHeader header;
  final bool enabled;
  final VoidCallback onTap;

  const _AttendanceCard({required this.header, required this.enabled, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final statusColor = _statusColor(header.status, cs);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: enabled ? cs.outlineVariant.withOpacity(0.5) : cs.outlineVariant.withOpacity(0.2),
        ),
        boxShadow: [
          BoxShadow(color: cs.shadow.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            header.employeeName,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: cs.onSurface,
                            ),
                          ),
                          Text(
                            header.departmentName,
                            style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                          ),
                          Text(
                            header.dateScheduleLabel,
                            style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                          ),
                          Row(
                            children: [
                              Text(
                                "Time In: ${formatDateTimeToTime(header.actualStart)}",
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(width: 16),
                              Text(
                                "Time Out: ${formatDateTimeToTime(header.actualEnd)}",
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    _StatusBadge(text: header.status.label.toUpperCase(), color: statusColor),
                  ],
                ),
                if (enabled) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Spacer(),
                      Text(
                        "Review",
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.blue,
                        ),
                      ),
                      const Icon(Icons.chevron_right, size: 16, color: Colors.blue),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  static Color _statusColor(AttendanceStatus s, ColorScheme cs) {
    switch (s) {
      case AttendanceStatus.pending:
        return cs.primary;
      case AttendanceStatus.approved:
        return Colors.green;
      case AttendanceStatus.rejected:
        return cs.error;
      case AttendanceStatus.all:
        return cs.outline;
    }
  }
}

class _Pill extends StatelessWidget {
  final String text;
  final Color bg;
  final Color fg;

  const _Pill({required this.text, required this.bg, required this.fg});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: fg.withOpacity(0.25)),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: fg),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String text;
  final Color color;
  const _StatusBadge({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w900,
          color: color,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String query;
  const _EmptyState({required this.query});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(Icons.inbox_rounded, size: 64, color: cs.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(
              query.trim().isEmpty ? "No attendance requests found." : "No results for '$query'.",
              style: TextStyle(fontWeight: FontWeight.w900, color: cs.onSurface),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              "Try adjusting search or filter.",
              style: TextStyle(color: cs.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline_rounded, size: 56, color: cs.error),
            const SizedBox(height: 10),
            Text(
              "Failed to load data",
              style: TextStyle(fontWeight: FontWeight.w900, color: cs.onSurface),
            ),
            const SizedBox(height: 10),
            SelectableText(
              message,
              style: TextStyle(color: cs.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 14),
            FilledButton(onPressed: onRetry, child: const Text("Retry")),
          ],
        ),
      ),
    );
  }
}

class _AttendanceGroupCard extends StatelessWidget {
  final AttendanceApprovalGroup group;
  final VoidCallback onTap;

  const _AttendanceGroupCard({required this.group, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.5), width: 1),
        boxShadow: [
          BoxShadow(color: cs.shadow.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            group.employeeName,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: cs.onSurface,
                            ),
                          ),
                          Text(
                            group.departmentName,
                            style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                          ),
                          Text(
                            "${group.pendingCount} pending approval${group.pendingCount > 1 ? 's' : ''}",
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: cs.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    _Pill(text: "PENDING", bg: cs.primaryContainer, fg: cs.primary),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Spacer(),
                    Text(
                      "Review",
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: cs.primary,
                      ),
                    ),
                    Icon(Icons.chevron_right, size: 16, color: cs.primary),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
