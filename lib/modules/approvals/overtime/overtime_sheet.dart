// lib/modules/approvals/overtime/overtime_sheet.dart
import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";

import "../../../app.dart"; // apiClientProvider, authRepositoryProvider
import "../../../data/repositories/overtime_repository.dart";
import "../approval_sheet_widgets.dart";
import "overtime_models.dart";

class OvertimeApprovalSheet extends ConsumerStatefulWidget {
  const OvertimeApprovalSheet({super.key, required this.header});

  final OvertimeApprovalHeader header;

  @override
  ConsumerState<OvertimeApprovalSheet> createState() => _OvertimeApprovalSheetState();
}

class _OvertimeApprovalSheetState extends ConsumerState<OvertimeApprovalSheet> {
  bool _processing = false;
  String? _error;

  Future<_ApproverInfo> _loadApproverInfo(OvertimeRepository overtimeRepo) async {
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

    final Map<int, AppUserLite> approverMap = await overtimeRepo.fetchUsersByIds(<int>[approverId]);

    final String approverName = approverMap[approverId]?.displayName ?? "Unknown Approver";

    return _ApproverInfo(id: approverId, name: approverName);
  }

  Future<void> _approve() async {
    if (_processing) return;

    setState(() {
      _processing = true;
      _error = null;
    });

    try {
      final api = ref.read(apiClientProvider);
      final overtimeRepo = OvertimeRepository(api);

      final approver = await _loadApproverInfo(overtimeRepo);

      await overtimeRepo.approveOvertime(
        overtimeId: widget.header.overtimeId,
        approverId: approver.id,
        approverName: approver.name,
        requestDateIso: widget.header.requestDateLabel, // "YYYY-MM-DD"
      );

      if (!mounted) return;
      Navigator.of(context).pop(
        OvertimeApproveOutcome(
          overtimeId: widget.header.overtimeId,
          newStatus: OvertimeStatus.approved,
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

  Future<void> _reject() async {
    if (_processing) return;

    // Optional: confirm reject
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Reject Overtime?"),
        content: const Text("This will mark the request as rejected."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Reject")),
        ],
      ),
    );

    if (ok != true) return;

    setState(() {
      _processing = true;
      _error = null;
    });

    try {
      final api = ref.read(apiClientProvider);
      final overtimeRepo = OvertimeRepository(api);

      final approver = await _loadApproverInfo(overtimeRepo);

      await overtimeRepo.rejectOvertime(
        overtimeId: widget.header.overtimeId,
        approverId: approver.id,
        approverName: approver.name,
        requestDateIso: widget.header.requestDateLabel, // e.g., 2025-11-29
      );

      if (!mounted) return;
      Navigator.of(context).pop(
        OvertimeApproveOutcome(
          overtimeId: widget.header.overtimeId,
          newStatus: OvertimeStatus.rejected,
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
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final h = widget.header;

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
                // Drag handle
                Padding(
                  padding: const EdgeInsets.only(top: 10, bottom: 8),
                  child: Container(
                    width: 48,
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
                              "Overtime Action",
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w900,
                                letterSpacing: -0.2,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              "Review and approve overtime request",
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
                        ApprovalErrorBanner(message: _error!),
                        const SizedBox(height: 12),
                      ],
                      ApprovalCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              h.employeeName,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w900,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              h.departmentName,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: cs.onSurfaceVariant,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: _MiniKV(label: "Request Date", value: h.requestDateLabel),
                                ),
                                Expanded(
                                  child: _MiniKV(label: "Filed At", value: h.filedAtLabel),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  child: _MiniKV(label: "OT Time", value: h.timeRangeLabel),
                                ),
                                Expanded(
                                  child: _MiniKV(label: "Duration", value: h.durationLabel),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            _MiniKV(
                              label: "Purpose",
                              value: h.purpose.trim().isEmpty ? "—" : h.purpose,
                            ),
                            const SizedBox(height: 10),
                            _MiniKV(label: "Status", value: h.status.label),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // ACTION BUTTONS
                ApprovalActionButtons(
                  onReject: _reject,
                  onApprove: _approve,
                  isProcessing: _processing,
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
  const _Card({required this.child});

  final Widget child;
  final EdgeInsets padding = EdgeInsets.zero;

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
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w900,
            color: cs.onSurface,
          ),
        ),
      ],
    );
  }
}
