// lib/modules/approvals/attendance/attendance_sheet.dart
import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";

import "../../../app.dart"; // apiClientProvider, authRepositoryProvider
import "../../../core/auth/user_permissions.dart";
import "../../../data/repositories/attendance_repository.dart" hide formatTimeOfDay;
import "attendance_model.dart";

class AttendanceApprovalSheet extends ConsumerStatefulWidget {
  const AttendanceApprovalSheet({super.key, required this.group});

  final AttendanceApprovalGroup group;

  @override
  ConsumerState<AttendanceApprovalSheet> createState() => _AttendanceApprovalSheetState();
}

class _AttendanceApprovalSheetState extends ConsumerState<AttendanceApprovalSheet> {
  bool _processing = false;
  String? _error;
  final Set<int> _selectedLogIds = {};
  final bool _canApprove = false;

  Future<_ApproverInfo> _loadApproverInfo(AttendanceRepository attendanceRepo) async {
    final approverIdRaw = await ref.read(authRepositoryProvider).getCurrentAppUserId();

    if (approverIdRaw == null) {
      throw Exception("Invalid approverId from authRepositoryProvider: null");
    }

    final int approverId = (approverIdRaw is int)
        ? approverIdRaw
        : int.tryParse(approverIdRaw.toString()) ?? 0;

    if (approverId <= 0) {
      throw Exception("Invalid approverId from authRepositoryProvider: $approverIdRaw");
    }

    final Map<int, AppUserLite> approverMap = await attendanceRepo.fetchUsersByIds(<int>[
      approverId,
    ]);

    final String approverName = approverMap[approverId]?.displayName ?? "Unknown Approver";

    return _ApproverInfo(id: approverId, name: approverName);
  }

  void _toggleSelection(int logId) {
    setState(() {
      if (_selectedLogIds.contains(logId)) {
        _selectedLogIds.remove(logId);
      } else {
        _selectedLogIds.add(logId);
      }
    });
  }

  void _toggleSelectAll(bool selectAll) {
    setState(() {
      if (selectAll) {
        _selectedLogIds.addAll(
          widget.group.pendingApprovals.map((approval) => approval.approvalId),
        );
      } else {
        _selectedLogIds.clear();
      }
    });
  }

  Future<void> _approveSelected() async {
    if (_processing || _selectedLogIds.isEmpty) return;

    setState(() {
      _processing = true;
      _error = null;
    });

    try {
      // Check user permissions before approving
      final service = ref.read(userPermissionsServiceProvider);
      final user = await service.getCurrentUser();
      final departmentId = widget.group.pendingApprovals.first.departmentId;
      if (user == null || !user.canApproveDepartment(departmentId)) {
        setState(() {
          _error =
              "You do not have permission to approve attendance for this department. Only admins can approve.";
          _processing = false;
        });
        return;
      }

      final api = ref.read(apiClientProvider);
      final attendanceRepo = AttendanceRepository(api);

      final approver = await _loadApproverInfo(attendanceRepo);

      final approvedLogIds = await attendanceRepo.approveSelectedAttendance(
        logIds: _selectedLogIds.toList(),
        employeeId: widget.group.employeeId,
        approverId: approver.id,
        approverName: approver.name,
      );

      if (!mounted) return;

      if (approvedLogIds.isEmpty) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("No attendance records were approved.")));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Approved ${approvedLogIds.length} attendance record(s).")),
        );
      }

      // Close the sheet and return success
      Navigator.of(context).pop(
        AttendanceApproveOutcome(
          approvalId: widget.group.pendingApprovals.first.approvalId, // Use first as representative
          newStatus: AttendanceStatus.approved,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _processing = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final userAsync = ref.watch(currentUserProvider);
    return userAsync.when(
      data: (user) => _buildContent(context, user),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, stack) => Center(child: Text('Error loading user: $err')),
    );
  }

  Widget _buildContent(BuildContext context, UserData? user) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final departmentId = widget.group.pendingApprovals.first.departmentId;
    final canApproveThisDepartment = user?.canApproveDepartment(departmentId) ?? false;
    if (!canApproveThisDepartment) _selectedLogIds.clear();
    return Container(
      color: Colors.transparent,
      child: DraggableScrollableSheet(
        initialChildSize: 0.75,
        minChildSize: 0.55,
        maxChildSize: 0.95,
        builder: (ctx, scrollCtrl) {
          return Container(
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(22),
                topRight: Radius.circular(22),
              ),
              border: Border.all(color: cs.outlineVariant.withOpacity(0.40)),
              boxShadow: [
                BoxShadow(
                  color: cs.shadow.withOpacity(0.08),
                  blurRadius: 18,
                  offset: const Offset(0, -6),
                ),
              ],
            ),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 10, bottom: 6),
                  child: Container(
                    width: 44,
                    height: 4,
                    decoration: BoxDecoration(
                      color: cs.onSurfaceVariant.withOpacity(0.35),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                // Header
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 2, 10, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "Approve Attendance",
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w900,
                                letterSpacing: -0.2,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              "Review and approve attendance log",
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: cs.onSurfaceVariant,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(null),
                        icon: const Icon(Icons.close_rounded),
                        tooltip: "Close",
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView(
                    controller: scrollCtrl,
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    children: [
                      if (_error != null) ...[
                        _ErrorBanner(message: _error!),
                        const SizedBox(height: 12),
                      ],
                      // Employee details
                      _SectionHeader(
                        title: "Employee Details",
                        subtitle: "Attendance log information",
                        trailing: _Pill(
                          text: "FOR APPROVAL",
                          bg: cs.secondary.withOpacity(0.10),
                          fg: cs.secondary,
                        ),
                      ),
                      const SizedBox(height: 10),
                      _Card(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.group.employeeName,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w900,
                                letterSpacing: -0.2,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              widget.group.departmentName,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: cs.onSurfaceVariant,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      // Pending Approvals
                      _SectionHeader(
                        title: "Pending Approvals",
                        subtitle: "Select the attendance records to approve",
                        trailing: canApproveThisDepartment
                            ? Checkbox(
                                value:
                                    _selectedLogIds.length == widget.group.pendingApprovals.length,
                                onChanged: (selected) => _toggleSelectAll(selected ?? false),
                              )
                            : null,
                      ),
                      const SizedBox(height: 10),
                      ...(() {
                        final sortedApprovals = List<AttendanceApprovalHeader>.from(
                          widget.group.pendingApprovals,
                        )..sort((a, b) => a.dateScheduleLabel.compareTo(b.dateScheduleLabel));
                        return sortedApprovals.map(
                          (approval) => Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _PendingApprovalCard(
                              approval: approval,
                              isSelected: _selectedLogIds.contains(approval.approvalId),
                              onToggle: canApproveThisDepartment
                                  ? () => _toggleSelection(approval.approvalId)
                                  : null,
                            ),
                          ),
                        );
                      })(),
                    ],
                  ),
                ),
                // Bottom CTA (sticky)
                if (canApproveThisDepartment)
                  SafeArea(
                    top: false,
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                      decoration: BoxDecoration(
                        color: cs.surface,
                        border: Border(top: BorderSide(color: cs.outlineVariant.withOpacity(0.45))),
                      ),
                      child: FilledButton.icon(
                        onPressed: _processing || _selectedLogIds.isEmpty ? null : _approveSelected,
                        icon: _processing
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.check_circle_outline),
                        label: const Text("Approve Selected"),
                        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ApproverInfo {
  final int id;
  final String name;
  const _ApproverInfo({required this.id, required this.name});
}

// =====================
// Small UI (Revised)
// =====================

class _Card extends StatelessWidget {
  const _Card({required this.child, this.padding = const EdgeInsets.all(12)});

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.42)),
        boxShadow: [
          BoxShadow(color: cs.shadow.withOpacity(0.04), blurRadius: 12, offset: const Offset(0, 6)),
        ],
      ),
      child: child,
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: cs.errorContainer, borderRadius: BorderRadius.circular(12)),
      child: Text(
        message,
        style: TextStyle(color: cs.onErrorContainer, fontWeight: FontWeight.w800),
      ),
    );
  }
}

class _MiniKV extends StatelessWidget {
  const _MiniKV({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: cs.onSurfaceVariant,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.2,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w900,
            color: cs.onSurface,
            letterSpacing: -0.1,
          ),
        ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget? trailing;

  const _SectionHeader({required this.title, required this.subtitle, this.trailing});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: fg.withOpacity(0.22)),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: fg, letterSpacing: 0.3),
      ),
    );
  }
}

class _PendingApprovalCard extends StatelessWidget {
  final AttendanceApprovalHeader approval;
  final bool isSelected;
  final VoidCallback? onToggle;

  const _PendingApprovalCard({required this.approval, required this.isSelected, this.onToggle});

  String _getWorkMinutesDisplay(AttendanceApprovalHeader approval) {
    final todayIso = DateTime.now().toIso8601String().substring(0, 10);
    final isToday = approval.dateSchedule.toIso8601String().substring(0, 10) == todayIso;

    if (isToday && approval.actualEnd == null && approval.workMinutes == 0) {
      return "Not computed yet";
    }

    return approval.workMinutesLabel;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return _Card(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Checkbox(value: isSelected, onChanged: onToggle != null ? (_) => onToggle!() : null),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  approval.dateScheduleLabel,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: cs.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                      child: _MiniKV(
                        label: "Time In",
                        value: formatDateTimeToTime(approval.actualStart),
                      ),
                    ),
                    Expanded(
                      child: _MiniKV(
                        label: "Time Out",
                        value: formatDateTimeToTime(approval.actualEnd),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _MiniKV(label: "Late Minutes", value: "${approval.lateMinutes}"),
                    ),
                    Expanded(
                      child: _MiniKV(
                        label: "Work Minutes",
                        value: _getWorkMinutesDisplay(approval),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _MiniKV(
                        label: "Undertime Minutes",
                        value: "${approval.undertimeMinutes}",
                      ),
                    ),
                    Expanded(
                      child: _MiniKV(
                        label: "Overtime Minutes",
                        value: "${approval.overtimeMinutes}",
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
