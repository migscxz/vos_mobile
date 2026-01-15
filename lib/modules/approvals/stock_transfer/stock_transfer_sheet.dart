// lib/modules/approvals/stock_transfer/stock_transfer_sheet.dart

import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";

import "../../../app.dart";
import "../../../data/repositories/stock_transfer_repository.dart";
import "stock_transfer_models.dart";

class StockTransferApprovalSheet extends ConsumerStatefulWidget {
  const StockTransferApprovalSheet({super.key, required this.header});

  final StockTransferHeader header;

  @override
  ConsumerState<StockTransferApprovalSheet> createState() =>
      _StockTransferApprovalSheetState();
}

class _StockTransferApprovalSheetState
    extends ConsumerState<StockTransferApprovalSheet> {
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

      final createdBy = await ref
          .read(authRepositoryProvider)
          .getCurrentAppUserId();
      if (createdBy == null) {
        throw Exception(
          "No user session found (user_id missing). Please login again.",
        );
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
                topLeft: Radius.circular(24),
                topRight: Radius.circular(24),
              ),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black12,
                  blurRadius: 16,
                  offset: Offset(0, -4),
                ),
              ],
            ),
            child: Column(
              children: [
                // Improved drag handle
                Container(
                  margin: const EdgeInsets.only(top: 12, bottom: 4),
                  child: Container(
                    width: 48,
                    height: 4,
                    decoration: BoxDecoration(
                      color: cs.outlineVariant.withOpacity(0.4),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),

                // Header section
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 16, 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          "Approve Stock Transfer",
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.close_rounded, size: 24),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                ),

                Expanded(
                  child: ListView(
                    controller: scrollCtrl,
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                    children: [
                      if (_error != null) ...[
                        _ErrorBanner(message: _error!),
                        const SizedBox(height: 16),
                      ],

                      // Transfer details card
                      _Card(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    header.orderNo,
                                    style: theme.textTheme.titleLarge?.copyWith(
                                      fontWeight: FontWeight.w700,
                                      fontFamily: "RobotoMono",
                                    ),
                                  ),
                                ),
                                _Pill(
                                  text: header.statusEnum.label.toUpperCase(),
                                  bg: statusColor.withOpacity(0.12),
                                  fg: statusColor,
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            _KeyValueRow(
                              label: "Requested by",
                              value: header.requesterName,
                            ),
                            const SizedBox(height: 12),
                            _KeyValueRow(
                              label: "Requested at",
                              value:
                                  "${fmtYmd(header.requestedAt)} ${fmtHm(header.requestedAt)}",
                            ),
                            const SizedBox(height: 12),
                            _KeyValueRow(
                              label: "Route",
                              value: header.routeLabel,
                            ),
                            const SizedBox(height: 12),
                            _KeyValueRow(
                              label: "Total Qty",
                              value: "${header.totalOrderedQty}",
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 20),

                      // Items section header
                      Text(
                        "Items (${header.items.length})",
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Items list
                      ...header.items.map((item) {
                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          child: _Card(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.productName,
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  "Quantity: ${item.orderedQty}",
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: cs.onSurfaceVariant,
                                  ),
                                ),
                                if (item.remarks.trim().isNotEmpty) ...[
                                  const SizedBox(height: 12),
                                  Text(
                                    "Remarks",
                                    style: theme.textTheme.labelMedium
                                        ?.copyWith(
                                          fontWeight: FontWeight.w600,
                                          color: cs.onSurfaceVariant,
                                        ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    item.remarks,
                                    style: theme.textTheme.bodyMedium,
                                  ),
                                ],
                              ],
                            ),
                          ),
                        );
                      }),
                    ],
                  ),
                ),

                // Action button
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                  child: FilledButton(
                    onPressed: _approving ? null : _approve,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _approving
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2.5),
                          )
                        : Text(
                            "Approve Transfer",
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: cs.onPrimary,
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

// -------------------------
// Enhanced UI Components
// -------------------------

class _Card extends StatelessWidget {
  const _Card({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.5)),
        boxShadow: [
          BoxShadow(
            color: cs.shadow.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
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
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        message,
        style: TextStyle(
          color: cs.onErrorContainer,
          fontWeight: FontWeight.w500,
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: fg),
      ),
    );
  }
}

class _KeyValueRow extends StatelessWidget {
  final String label;
  final String value;

  const _KeyValueRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 120,
          child: Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}
