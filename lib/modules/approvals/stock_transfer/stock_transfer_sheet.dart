// lib/modules/approvals/stock_transfer/stock_transfer_sheet.dart

import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";

import "../../../app.dart"; // apiClientProvider, authRepositoryProvider
import "../../../data/repositories/stock_transfer_repository.dart";
import "stock_transfer_models.dart";

class StockTransferApprovalSheet extends ConsumerStatefulWidget {
  const StockTransferApprovalSheet({
    super.key,
    required this.header,
  });

  final StockTransferHeader header;

  @override
  ConsumerState<StockTransferApprovalSheet> createState() => _StockTransferApprovalSheetState();
}

class _StockTransferApprovalSheetState extends ConsumerState<StockTransferApprovalSheet> {
  bool _approving = false;
  String? _error;

  Future<void> _approve() async {
    if (_approving) return;

    setState(() {
      _approving = true;
      _error = null;
    });

    try {
      final api = ref.read(apiClientProvider);
      final repo = StockTransferRepository(api);

      final createdBy = await ref.read(authRepositoryProvider).getCurrentAppUserId();
      if (createdBy == null) {
        throw Exception("No user session found (user_id missing). Please login again.");
      }

      final approveRes = await repo.approveStockTransferAndCreateCldtst(
        stockTransferNo: widget.header.orderNo,
        createdBy: createdBy,
      );

      if (!mounted) return;

      Navigator.of(context).pop(
        StockTransferApproveOutcome(
          consolidatorId: approveRes.consolidatorId,
          consolidatorNo: approveRes.consolidatorNo,
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
    final statusColor = stockTransferStatusColor(header.statusEnum, cs);

    return Container(
      color: Colors.transparent,
      child: DraggableScrollableSheet(
        initialChildSize: 0.84,
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
                          "Approve Stock Transfer",
                          style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
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

                      _Card(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    header.orderNo,
                                    style: const TextStyle(
                                      fontFamily: "monospace",
                                      fontWeight: FontWeight.w900,
                                      fontSize: 16,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                _Pill(
                                  text: header.statusEnum.label.toUpperCase(),
                                  bg: statusColor.withOpacity(0.12),
                                  fg: statusColor,
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            _kv("Requested by", header.requesterName),
                            const SizedBox(height: 6),
                            _kv("Requested at", "${fmtYmd(header.requestedAt)} ${fmtHm(header.requestedAt)}"),
                            const SizedBox(height: 6),
                            _kv("Route", header.routeLabel),
                            const SizedBox(height: 6),
                            _kv("Total Qty", "${header.totalOrderedQty}"),
                          ],
                        ),
                      ),

                      const SizedBox(height: 14),

                      Text(
                        "Items (${header.items.length})",
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 10),

                      ...header.items.map((item) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _Card(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.productName,
                                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  "Qty: ${item.orderedQty}",
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: cs.onSurfaceVariant,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                if (item.remarks.trim().isNotEmpty) ...[
                                  const SizedBox(height: 10),
                                  Text(
                                    "Remarks",
                                    style: theme.textTheme.labelLarge?.copyWith(
                                      fontWeight: FontWeight.w900,
                                      color: cs.onSurfaceVariant,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(item.remarks),
                                ],
                              ],
                            ),
                          ),
                        );
                      }),
                    ],
                  ),
                ),

                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                  child: FilledButton(
                    onPressed: _approving ? null : _approve,
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                    child: _approving
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text("Approve", style: TextStyle(fontWeight: FontWeight.w900)),
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

// -------------------------
// Small UI helpers (same style as Sales Order sheet)
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
        style: TextStyle(color: cs.onErrorContainer, fontWeight: FontWeight.w800),
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
      child: Text(text, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: fg)),
    );
  }
}

Widget _kv(String k, String v) {
  return Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SizedBox(width: 110, child: Text(k, style: const TextStyle(fontWeight: FontWeight.w900))),
      Expanded(child: Text(v)),
    ],
  );
}
