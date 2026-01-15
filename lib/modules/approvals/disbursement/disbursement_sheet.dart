// lib/modules/approvals/disbursement/disbursement_sheet.dart
import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";

import "../../../app.dart"; // apiClientProvider, authRepositoryProvider
import "../../../data/repositories/disbursement_repository.dart";
import "disbursement_models.dart";

class DisbursementApprovalSheet extends ConsumerStatefulWidget {
  const DisbursementApprovalSheet({super.key, required this.header});

  final DisbursementHeader header;

  @override
  ConsumerState<DisbursementApprovalSheet> createState() =>
      _DisbursementApprovalSheetState();
}

class _DisbursementApprovalSheetState
    extends ConsumerState<DisbursementApprovalSheet> {
  bool _loading = true;
  bool _approving = false;
  String? _error;

  List<DisbursementPayableRow> _payables = const [];

  @override
  void initState() {
    super.initState();
    _loadPayables();
  }

  Future<void> _loadPayables() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final api = ref.read(apiClientProvider);
      final repo = DisbursementRepository(api);

      final raw = await repo.fetchPayablesByDisbursementId(widget.header.id);

      final coaIds = <int>{};
      for (final r in raw) {
        final id = _asInt(r["coa_id"]);
        if (id != null && id > 0) coaIds.add(id);
      }

      final coaRows = await repo.fetchCoaByIds(coaIds.toList());
      final coaTitleById = <int, String>{};
      for (final c in coaRows) {
        final id = _asInt(c["coa_id"]);
        if (id == null) continue;
        coaTitleById[id] = (c["account_title"]?.toString() ?? "Unknown COA")
            .trim();
      }

      final items = <DisbursementPayableRow>[];
      for (final r in raw) {
        final id = _asInt(r["id"]) ?? 0;
        if (id <= 0) continue;

        final payableDate =
            DateTime.tryParse((r["date"]?.toString() ?? "").trim()) ??
            DateTime.fromMillisecondsSinceEpoch(0);

        final coaId = _asInt(r["coa_id"]) ?? 0;
        final coaTitle = coaId > 0
            ? (coaTitleById[coaId] ?? "Unknown COA")
            : "Unknown COA";

        final amount = _asDouble(r["amount"]) ?? 0;
        final remarks = (r["remarks"]?.toString() ?? "").trim();
        final refNo = (r["reference_no"]?.toString() ?? "").trim();

        items.add(
          DisbursementPayableRow(
            id: id,
            payableDate: payableDate.toLocal(),
            coaId: coaId,
            coaTitle: coaTitle,
            amount: amount,
            remarks: remarks,
            referenceNo: refNo,
          ),
        );
      }

      // stable sort
      items.sort((a, b) {
        final c = a.payableDate.compareTo(b.payableDate);
        if (c != 0) return c;
        return a.id.compareTo(b.id);
      });

      if (!mounted) return;
      setState(() {
        _payables = items;
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

  Future<void> _approve() async {
    if (_approving) return;

    setState(() {
      _approving = true;
      _error = null;
    });

    try {
      final api = ref.read(apiClientProvider);
      final repo = DisbursementRepository(api);

      final approverId = await ref
          .read(authRepositoryProvider)
          .getCurrentAppUserId();
      if (approverId == null) {
        throw Exception(
          "No user session found (user_id missing). Please login again.",
        );
      }

      await repo.approveDisbursement(
        disbursementId: widget.header.id,
        approverId: approverId,
      );

      if (!mounted) return;

      Navigator.of(context).pop(
        DisbursementApproveOutcome(
          disbursementId: widget.header.id,
          docNo: widget.header.docNo,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _approving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final header = widget.header;
    final statusColor = disbursementStatusColor(header, cs);

    final payablesTotal = _payables.fold<double>(0, (sum, r) => sum + r.amount);

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
                              "Disbursement Action",
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w900,
                                letterSpacing: -0.2,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              "Review and approve disbursement",
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
                      _Card(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              header.docNo,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w900,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              header.payeeName,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: cs.onSurfaceVariant,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: _MiniKV(
                                    label: "Transaction Date",
                                    value: fmtYmd(header.transactionDate),
                                  ),
                                ),
                                Expanded(
                                  child: _MiniKV(
                                    label: "Total Amount",
                                    value: money(header.totalAmount),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  child: _MiniKV(
                                    label: "Paid Amount",
                                    value: money(header.paidAmount),
                                  ),
                                ),
                                Expanded(
                                  child: _MiniKV(
                                    label: "Payables Total",
                                    value: money(payablesTotal),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            _MiniKV(
                              label: "Encoder",
                              value: header.encoderName,
                            ),
                            const SizedBox(height: 10),
                            _MiniKV(
                              label: "Status",
                              value: header.isApproved ? "Approved" : "Pending",
                            ),
                            if (header.remarks.trim().isNotEmpty) ...[
                              const SizedBox(height: 10),
                              _MiniKV(label: "Remarks", value: header.remarks),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      _SectionHeader(
                        title: "Payables",
                        subtitle: "${_payables.length} item(s)",
                        trailing: _loading
                            ? Text(
                                "Loading...",
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: cs.onSurfaceVariant,
                                ),
                              )
                            : null,
                      ),
                      const SizedBox(height: 10),
                      if (_loading)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 18),
                          child: Center(child: CircularProgressIndicator()),
                        )
                      else if (_payables.isEmpty)
                        _Card(
                          child: Text(
                            "No payable lines found.",
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        )
                      else
                        ..._payables.map((p) {
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _Card(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    p.coaTitle,
                                    style: theme.textTheme.titleSmall?.copyWith(
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    "COA #${p.coaId} • Date: ${fmtYmd(p.payableDate)}",
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: cs.onSurfaceVariant,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    "Amount: ${money(p.amount)}",
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  if (p.referenceNo.trim().isNotEmpty) ...[
                                    const SizedBox(height: 8),
                                    Text(
                                      "Reference No",
                                      style: theme.textTheme.labelLarge
                                          ?.copyWith(
                                            fontWeight: FontWeight.w900,
                                            color: cs.onSurfaceVariant,
                                          ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(p.referenceNo),
                                  ],
                                  if (p.remarks.trim().isNotEmpty) ...[
                                    const SizedBox(height: 8),
                                    Text(
                                      "Remarks",
                                      style: theme.textTheme.labelLarge
                                          ?.copyWith(
                                            fontWeight: FontWeight.w900,
                                            color: cs.onSurfaceVariant,
                                          ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(p.remarks),
                                  ],
                                ],
                              ),
                            ),
                          );
                        }),
                    ],
                  ),
                ),

                // ACTION BUTTONS
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _approving
                              ? null
                              : () => Navigator.of(context).pop(),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(48),
                            side: BorderSide(
                              color: cs.outlineVariant.withOpacity(0.6),
                            ),
                          ),
                          child: const Text(
                            "Cancel",
                            style: TextStyle(fontWeight: FontWeight.w900),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          onPressed: (widget.header.isApproved || _approving)
                              ? null
                              : _approve,
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(48),
                          ),
                          child: _approving
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text(
                                  "Approve",
                                  style: TextStyle(fontWeight: FontWeight.w900),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  int? _asInt(Object? v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString());
  }

  double? _asDouble(Object? v) {
    if (v == null) return null;
    if (v is double) return v;
    if (v is int) return v.toDouble();
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }
}

// -------------------------
// Small UI helpers
// -------------------------

class _Card extends StatelessWidget {
  const _Card({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.35)),
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
      decoration: BoxDecoration(
        color: cs.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        message,
        style: TextStyle(
          color: cs.onErrorContainer,
          fontWeight: FontWeight.w800,
        ),
      ),
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

class _SectionHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget? trailing;

  const _SectionHeader({
    required this.title,
    required this.subtitle,
    this.trailing,
  });

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

class _MiniKV extends StatelessWidget {
  const _MiniKV({required this.label, required this.value, this.valueTone});
  final String label;
  final String value;
  final Color? valueTone;

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
            color: valueTone ?? cs.onSurface,
            letterSpacing: -0.1,
          ),
        ),
      ],
    );
  }
}

Widget _kv(String k, String v) {
  return Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SizedBox(
        width: 120,
        child: Text(k, style: const TextStyle(fontWeight: FontWeight.w900)),
      ),
      Expanded(child: Text(v)),
    ],
  );
}
