import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";

import "../../../app_providers.dart";
import "../../../data/repositories/sales_order_repository.dart" as repo;

class SalesOrderApprovalSheet extends ConsumerStatefulWidget {
  const SalesOrderApprovalSheet({
    super.key,
    required this.customerName,
    required this.customerCode,
    required this.orders, // actionable orders only (For Approval)
  });

  final String customerName;
  final String customerCode;
  final List<repo.SalesOrderHeader> orders;

  @override
  ConsumerState<SalesOrderApprovalSheet> createState() =>
      _SalesOrderApprovalSheetState();
}

class _SalesOrderApprovalSheetState
    extends ConsumerState<SalesOrderApprovalSheet> {
  bool _loading = true;
  bool _approving = false;
  String? _error;

  // Selection state (default empty per user request)
  final Set<int> _selected = {};

  repo.SalesOrderGroupPaymentSummary? _groupSummary;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _groupSummary = null;
      // Per user request, start with NO selection
      _selected.clear();
    });

    try {
      final api = ref.read(apiClientProvider);
      final r = repo.SalesOrderRepository(api);

      // Use repo-optimized group summary
      final group = await r.fetchGroupPaymentSummary(orders: widget.orders);

      if (!mounted) return;
      setState(() {
        _groupSummary = group;
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

  void _toggle(int orderId) {
    setState(() {
      if (_selected.contains(orderId)) {
        _selected.remove(orderId);
      } else {
        _selected.add(orderId);
      }
    });
  }

  void _selectAll(bool? v) {
    setState(() {
      if (v == true) {
        _selected.addAll(widget.orders.map((e) => e.orderId));
      } else {
        _selected.clear();
      }
    });
  }

  Future<void> _onApproveSelected() async {
    if (_approving || _loading) return;
    if (_selected.isEmpty) return;

    setState(() {
      _approving = true;
      _error = null;
    });

    try {
      final api = ref.read(apiClientProvider);
      final r = repo.SalesOrderRepository(api);
      final approverId = await ref
          .read(authRepositoryProvider)
          .getCurrentAppUserId();

      // Filter to only selected
      final targets = widget.orders
          .where((o) => _selected.contains(o.orderId))
          .toList();

      if (targets.isEmpty) {
        setState(() => _approving = false);
        return;
      }

      // Approve per PO group when possible
      final byPo = <String, List<repo.SalesOrderHeader>>{};
      final singles = <repo.SalesOrderHeader>[];

      for (final o in targets) {
        final po = (o.poNo ?? "").trim();
        if (po.isEmpty) {
          singles.add(o);
        } else {
          (byPo[po] ??= []).add(o);
        }
      }

      final errors = <String>[];

      // 1. Grouped by PO
      for (final entry in byPo.entries) {
        final po = entry.key;
        final list = entry.value;

        try {
          if (list.length > 1) {
            // If ALL orders in this PO group are selected, use bulk by PO
            // BUT: wait, if we only selected SOME of the PO's orders, we can't use `approveSalesOrdersByPoNo`
            // because that approves ALL for that PO.
            // Logic check: fetchSalesOrdersByPoNo fetches ALL.
            // Safest approach: just loop individual updates unless we verify we have ALL.
            // To be safe and simple: just loop individual updates for now OR check count.
            // Given the requirement "can only select a order that be approve", let's just do individual loop
            // to avoid accidentally approving unselected orders sharing the same PO.
            for (final o in list) {
              await r.approveSalesOrder(
                orderId: o.orderId,
                approvedByUserId: approverId,
                writeTimelineFields: true,
              );
            }
          } else {
            final only = list.first;
            await r.approveSalesOrder(
              orderId: only.orderId,
              approvedByUserId: approverId,
              writeTimelineFields: true,
            );
          }
        } catch (e) {
          errors.add("PO $po: $e");
        }
      }

      // 2. Singles
      for (final o in singles) {
        try {
          await r.approveSalesOrder(
            orderId: o.orderId,
            approvedByUserId: approverId,
            writeTimelineFields: true,
          );
        } catch (e) {
          errors.add("Order ${o.orderNo}: $e");
        }
      }

      if (!mounted) return;

      if (errors.isNotEmpty) {
        // Partial or full failure
        setState(() {
          _error = "Errors occurred:\n${errors.join('\n')}";
          _approving = false;
        });

        // Also show snackbar if user requested
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              "Failed to approve ${errors.length} order(s). Check details.",
            ),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      } else {
        Navigator.of(context).pop(true);
      }
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

    final group = _groupSummary;

    // Calc totals only for VISIBLE orders (all) or SELECTED?
    // Usually header stats show what's available.
    // Let's keep stats for ALL orders passed to the sheet, so user knows what they are dealing with.
    final ordersNetTotal = widget.orders.fold<double>(
      0.0,
      (s, o) => s + o.netAmount,
    );
    final ordersGrossTotal = widget.orders.fold<double>(
      0.0,
      (s, o) => s + o.totalAmount,
    );

    // Calc selected count
    final selCount = _selected.length;
    final allCount = widget.orders.length;
    final isAllSelected = selCount == allCount && allCount > 0;

    // Correct workflow: approve -> For Consolidation
    final nextStatus = repo.SalesOrderRepository.soStatusAfterApprove;

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
                              "Approve Sales Orders",
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w900,
                                letterSpacing: -0.2,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              "Customer grouped approval",
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: cs.onSurfaceVariant,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(false),
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

                      // Customer + totals summary (hero card)
                      _Card(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _AvatarMark(
                                  letter: _initial(widget.customerName),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        widget.customerName,
                                        style: theme.textTheme.titleMedium
                                            ?.copyWith(
                                              fontWeight: FontWeight.w900,
                                              letterSpacing: -0.2,
                                            ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        widget.customerCode.trim().isEmpty
                                            ? "Code: —"
                                            : "Code: ${widget.customerCode}",
                                        style: theme.textTheme.bodySmall
                                            ?.copyWith(
                                              color: cs.onSurfaceVariant,
                                              fontWeight: FontWeight.w700,
                                            ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                _Pill(
                                  text: nextStatus.toUpperCase(),
                                  bg: cs.primary.withOpacity(0.10),
                                  fg: cs.primary,
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            const Divider(height: 1),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: _MiniKV(
                                    label: "Orders",
                                    value: "${widget.orders.length}",
                                  ),
                                ),
                                Expanded(
                                  child: _MiniKV(
                                    label: "Net Total",
                                    value: _fmtMoney(ordersNetTotal),
                                  ),
                                ),
                                Expanded(
                                  child: _MiniKV(
                                    label: "Gross Total",
                                    value: _fmtMoney(ordersGrossTotal),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 14),

                      // Payment summary
                      _SectionHeader(
                        title: "Payment Summary",
                        subtitle: "Group-level invoices and payments",
                      ),
                      const SizedBox(height: 10),
                      _Card(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (_loading && group == null) ...[
                              _SkeletonLine(widthFactor: 0.55),
                              const SizedBox(height: 10),
                              _SkeletonLine(widthFactor: 0.85),
                              const SizedBox(height: 10),
                              _SkeletonLine(widthFactor: 0.70),
                            ] else ...[
                              Row(
                                children: [
                                  Expanded(
                                    child: _MiniKV(
                                      label: "Invoices",
                                      value: "${group?.invoiceCount ?? 0}",
                                    ),
                                  ),
                                  Expanded(
                                    child: _MiniKV(
                                      label: "Payments",
                                      value: "${group?.paymentCount ?? 0}",
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Expanded(
                                    child: _MiniKV(
                                      label: "Invoice Total",
                                      value: _fmtMoney(
                                        group?.invoiceTotal ?? 0,
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: _MiniKV(
                                      label: "Paid Total",
                                      value: _fmtMoney(group?.paidTotal ?? 0),
                                      valueTone: Colors.green,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              _MiniKV(
                                label: "Unpaid Total",
                                value: _fmtMoney(group?.unpaidTotal ?? 0),
                                valueTone: (group?.unpaidTotal ?? 0) > 0
                                    ? cs.error
                                    : cs.onSurface,
                              ),
                            ],
                          ],
                        ),
                      ),

                      const SizedBox(height: 14),

                      // Orders list
                      Row(
                        children: [
                          Expanded(
                            child: _SectionHeader(
                              title: "Orders Included",
                              subtitle:
                                  "${widget.orders.length} order(s) available",
                            ),
                          ),
                          // Select All toggle
                          TextButton(
                            onPressed: () => _selectAll(!isAllSelected),
                            child: Text(
                              isAllSelected ? "Deselect All" : "Select All",
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      _Card(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          children: [
                            ...widget.orders.map((o) {
                              final soNo = o.orderNo.trim().isEmpty
                                  ? "SO-${o.orderId}"
                                  : o.orderNo.trim();
                              final po = (o.poNo ?? "").trim();
                              final amount = (o.netAmount != 0)
                                  ? o.netAmount
                                  : o.totalAmount;

                              final isSel = _selected.contains(o.orderId);

                              return _OrderRow(
                                soNo: soNo,
                                poNo: po,
                                amount: _fmtMoney(amount),
                                selected: isSel,
                                onSelect: (v) => _toggle(o.orderId),
                              );
                            }),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // Bottom CTA (sticky)
                SafeArea(
                  top: false,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                    decoration: BoxDecoration(
                      color: cs.surface,
                      border: Border(
                        top: BorderSide(
                          color: cs.outlineVariant.withOpacity(0.45),
                        ),
                      ),
                    ),
                    child: FilledButton(
                      onPressed: (_approving || _loading || selCount == 0)
                          ? null
                          : _onApproveSelected,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(52),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: _approving
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.2,
                              ),
                            )
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.verified_rounded, size: 18),
                                const SizedBox(width: 8),
                                Text(
                                  selCount == 0
                                      ? "Select Orders to Approve"
                                      : "Approve Selected ($selCount)",
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ],
                            ),
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
          BoxShadow(
            color: cs.shadow.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  // final Widget? trailing; // Removed unused parameter

  const _SectionHeader({
    required this.title,
    required this.subtitle,
    // this.trailing,
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
        // if (trailing != null) trailing!,
      ],
    );
  }
}

class _AvatarMark extends StatelessWidget {
  final String letter;
  const _AvatarMark({required this.letter});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: cs.primaryContainer,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.primary.withOpacity(0.15)),
      ),
      child: Center(
        child: Text(
          letter,
          style: TextStyle(
            fontWeight: FontWeight.w900,
            color: cs.onPrimaryContainer,
          ),
        ),
      ),
    );
  }
}

class _OrderRow extends StatelessWidget {
  final String soNo;
  final String poNo;
  final String amount;
  final bool selected;
  final ValueChanged<bool?>? onSelect;

  const _OrderRow({
    required this.soNo,
    required this.poNo,
    required this.amount,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return InkWell(
      onTap: () => onSelect?.call(!selected),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: Checkbox(
                value: selected,
                onChanged: onSelect,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    soNo,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.2,
                      fontFamily: "RobotoMono",
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (poNo.trim().isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      "PO: $poNo",
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 10),
            Text(
              amount,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w900,
                color: cs.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SkeletonLine extends StatelessWidget {
  final double widthFactor;
  const _SkeletonLine({required this.widthFactor});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return FractionallySizedBox(
      widthFactor: widthFactor,
      child: Container(
        height: 12,
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(999),
        ),
      ),
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
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.errorContainer,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.error.withOpacity(0.20)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline_rounded, color: cs.onErrorContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: cs.onErrorContainer,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
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
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w900,
          color: fg,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

// =====================
// Small helpers
// =====================

String _initial(String name) {
  final s = name.trim();
  if (s.isEmpty) return "?";
  return s.characters.first.toUpperCase();
}

String _fmtMoney(double v) => "₱ ${v.toStringAsFixed(2)}";
