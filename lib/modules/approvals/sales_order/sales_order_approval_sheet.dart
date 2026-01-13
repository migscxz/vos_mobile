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
  ConsumerState<SalesOrderApprovalSheet> createState() => _SalesOrderApprovalSheetState();
}

class _SalesOrderApprovalSheetState extends ConsumerState<SalesOrderApprovalSheet> {
  bool _loading = true;
  bool _approving = false;
  String? _error;

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
    });

    try {
      final api = ref.read(apiClientProvider);
      final r = repo.SalesOrderRepository(api);

      // Use repo-optimized group summary (handles int/string order_id linkage)
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

  Future<void> _onApproveAll() async {
    if (_approving || _loading) return;

    setState(() {
      _approving = true;
      _error = null;
    });

    try {
      final api = ref.read(apiClientProvider);
      final r = repo.SalesOrderRepository(api);
      final approverId = await ref.read(authRepositoryProvider).getCurrentAppUserId();

      // Approve per PO group when possible
      final byPo = <String, List<repo.SalesOrderHeader>>{};
      final singles = <repo.SalesOrderHeader>[];

      for (final o in widget.orders) {
        final po = (o.poNo ?? "").trim();
        if (po.isEmpty) {
          singles.add(o);
        } else {
          (byPo[po] ??= []).add(o);
        }
      }

      for (final entry in byPo.entries) {
        final po = entry.key;
        final list = entry.value;

        if (list.length > 1) {
          await r.approveSalesOrdersByPoNo(
            poNo: po,
            approvedByUserId: approverId,
            writeTimelineFields: true,
          );
        } else {
          final only = list.first;
          await r.approveSalesOrder(
            orderId: only.orderId,
            approvedByUserId: approverId,
            writeTimelineFields: true,
          );
        }
      }

      for (final o in singles) {
        await r.approveSalesOrder(
          orderId: o.orderId,
          approvedByUserId: approverId,
          writeTimelineFields: true,
        );
      }

      if (!mounted) return;
      Navigator.of(context).pop(true);
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

    final ordersNetTotal = widget.orders.fold<double>(0.0, (s, o) => s + o.netAmount);
    final ordersGrossTotal = widget.orders.fold<double>(0.0, (s, o) => s + o.totalAmount);

    // Correct workflow: approve -> For Consolidation
    final nextStatus = repo.SalesOrderRepository.soStatusAfterApprove;

    return Container(
      color: Colors.transparent,
      child: DraggableScrollableSheet(
        initialChildSize: 0.86,
        minChildSize: 0.55,
        maxChildSize: 0.95,
        builder: (ctx, scrollCtrl) {
          return Container(
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(18),
                topRight: Radius.circular(18),
              ),
              border: Border.all(color: cs.outlineVariant.withOpacity(0.40)),
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
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          "Approve Sales Orders",
                          style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        icon: const Icon(Icons.close_rounded),
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

                      // Header summary
                      _Card(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.customerName,
                              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              "Code: ${widget.customerCode}",
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: cs.onSurfaceVariant,
                                fontWeight: FontWeight.w700,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(child: _MiniKV(label: "Orders", value: "${widget.orders.length}")),
                                Expanded(child: _MiniKV(label: "Next Status", value: nextStatus)),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(child: _MiniKV(label: "Net Total", value: _fmtMoney(ordersNetTotal))),
                                Expanded(child: _MiniKV(label: "Gross Total", value: _fmtMoney(ordersGrossTotal))),
                              ],
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 14),

                      // Payment summary
                      _Card(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "Payment Summary (Group)",
                              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                            ),
                            const SizedBox(height: 12),
                            if (_loading && group == null)
                              Text(
                                "Loading payment summary...",
                                style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                              )
                            else ...[
                              Row(
                                children: [
                                  Expanded(child: _MiniKV(label: "Invoices", value: "${group?.invoiceCount ?? 0}")),
                                  Expanded(child: _MiniKV(label: "Payments", value: "${group?.paymentCount ?? 0}")),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  Expanded(child: _MiniKV(label: "Invoice Total", value: _fmtMoney(group?.invoiceTotal ?? 0))),
                                  Expanded(
                                    child: _MiniKV(
                                      label: "Paid Total",
                                      value: _fmtMoney(group?.paidTotal ?? 0),
                                      valueTone: Colors.green,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              _MiniKV(
                                label: "Unpaid Total",
                                value: _fmtMoney(group?.unpaidTotal ?? 0),
                                valueTone: (group?.unpaidTotal ?? 0) > 0 ? cs.error : cs.onSurface,
                              ),
                            ],
                          ],
                        ),
                      ),

                      const SizedBox(height: 14),

                      // Orders list (compact)
                      _Card(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "Orders Included",
                              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                            ),
                            const SizedBox(height: 10),
                            ...widget.orders.map((o) {
                              final soNo = o.orderNo.trim().isEmpty ? "SO-${o.orderId}" : o.orderNo.trim();
                              final po = (o.poNo ?? "").trim();
                              final amount = (o.netAmount != 0) ? o.netAmount : o.totalAmount;

                              return Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            soNo,
                                            style: const TextStyle(
                                              fontFamily: "monospace",
                                              fontWeight: FontWeight.w900,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          if (po.isNotEmpty) ...[
                                            const SizedBox(height: 2),
                                            Text(
                                              "PO: $po",
                                              style: theme.textTheme.bodySmall?.copyWith(
                                                color: cs.onSurfaceVariant,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Text(
                                      _fmtMoney(amount),
                                      style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w900),
                                    ),
                                  ],
                                ),
                              );
                            }),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: FilledButton(
                          onPressed: (_approving || _loading) ? null : _onApproveAll,
                          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                          child: _approving
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : Text(
                                  "Approve All (${widget.orders.length})",
                                  style: const TextStyle(fontWeight: FontWeight.w900),
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
}

// =====================
// Small UI
// =====================

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
        style: TextStyle(color: cs.onErrorContainer, fontWeight: FontWeight.w800),
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
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w900,
            color: valueTone ?? cs.onSurface,
          ),
        ),
      ],
    );
  }
}

String _fmtMoney(double v) => "₱ ${v.toStringAsFixed(2)}";
