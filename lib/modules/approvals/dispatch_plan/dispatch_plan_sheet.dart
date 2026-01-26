import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../app.dart';
import '../../../data/repositories/dispatch_plan_repository.dart';
import 'dispatch_plan_models.dart';

class DispatchPlanApprovalSheet extends ConsumerStatefulWidget {
  const DispatchPlanApprovalSheet({super.key, required this.header});

  final DispatchPlanHeader header;

  static Future<ApproveResult?> show(BuildContext context, DispatchPlanHeader header) {
    return showModalBottomSheet<ApproveResult?>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DispatchPlanApprovalSheet(header: header),
    );
  }

  @override
  ConsumerState<DispatchPlanApprovalSheet> createState() => _DispatchPlanApprovalSheetState();
}

class _DispatchPlanApprovalSheetState extends ConsumerState<DispatchPlanApprovalSheet> {
  // State
  bool _loadingDetails = true;
  bool _approving = false;
  String? _error;
  List<DispatchPlanItem> _items = [];

  // Controllers
  late final DispatchPlanRepository _repo;

  @override
  void initState() {
    super.initState();
    _repo = DispatchPlanRepository(ref.read(apiClientProvider));
    _fetchDetails();
  }

  Future<void> _fetchDetails() async {
    try {
      final data = await _repo.fetchDispatchPlanItems(widget.header.dispatchId);
      if (!mounted) return;
      setState(() {
        _items = data;
        _loadingDetails = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = "Failed to load items: $e";
        _loadingDetails = false;
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
      // Get current user ID (Ensure you have a provider for this, or pass it in)
      final createdBy = await ref.read(authRepositoryProvider).getCurrentAppUserId();

      if (createdBy == null) throw Exception("User session invalid.");

      final result = await _repo.approveDispatchPlan(
        dispatchId: widget.header.dispatchId,
        dispatchNo: widget.header.dispatchNo,
        createdBy: createdBy,
      );

      if (!mounted) return;
      Navigator.of(context).pop(result); // Return the result to the view
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
    final statusColor = getDispatchStatusColor(header.status, cs);
    final currencyFmt = NumberFormat.currency(symbol: "₱", decimalDigits: 2);

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (ctx, scrollCtrl) {
        return Container(
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 20,
                offset: const Offset(0, -5),
              ),
            ],
          ),
          child: Column(
            children: [
              // Drag Handle
              Container(
                margin: const EdgeInsets.only(top: 12, bottom: 4),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: cs.outlineVariant.withOpacity(0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              // Title Bar
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 16, 16),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        "Approve Dispatch",
                        style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),

              // Main Content
              Expanded(
                child: ListView(
                  controller: scrollCtrl,
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                  children: [
                    if (_error != null) ...[
                      _ErrorBanner(message: _error!),
                      const SizedBox(height: 16),
                    ],

                    // HEADER INFO CARD
                    _Card(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  header.dispatchNo,
                                  style: theme.textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              _Pill(
                                text: header.status.label.toUpperCase(),
                                bg: statusColor.withOpacity(0.12),
                                fg: statusColor,
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          _KeyValueRow(label: "Branch", value: header.branchName ?? "N/A"),
                          const SizedBox(height: 8),
                          _KeyValueRow(label: "Driver", value: header.driverName ?? "Unassigned"),
                          const SizedBox(height: 8),
                          _KeyValueRow(
                            label: "Total Amount",
                            value: currencyFmt.format(header.totalAmount),
                          ),
                          const SizedBox(height: 8),
                          _KeyValueRow(
                            label: "Date",
                            value: DateFormat("MMM dd, yyyy • hh:mm a").format(header.dispatchDate),
                          ),
                          if (header.remarks.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            Text(
                              "Remarks",
                              style: theme.textTheme.labelMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              header.remarks,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),

                    // ITEMS LIST
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          "Items to Dispatch",
                          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        if (!_loadingDetails)
                          Text(
                            "${_items.length} Entries",
                            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    if (_loadingDetails)
                      const Padding(
                        padding: EdgeInsets.all(32.0),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else if (_items.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(24),
                        alignment: Alignment.center,
                        child: Text(
                          "No items found in this plan.",
                          style: TextStyle(color: cs.onSurfaceVariant),
                        ),
                      )
                    else
                      ..._items.map((item) => _ItemRow(item: item)),
                  ],
                ),
              ),

              // ACTION BUTTON
              Padding(
                padding: const EdgeInsets.all(24),
                child: SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: FilledButton(
                    onPressed: _approving ? null : _approve,
                    style: FilledButton.styleFrom(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: _approving
                        ? SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(color: cs.onPrimary, strokeWidth: 2.5),
                          )
                        : const Text(
                            "Confirm Approval",
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ==============================================================================
// PRIVATE HELPER COMPONENTS (Ensures visual consistency)
// ==============================================================================

class _Card extends StatelessWidget {
  final Widget child;
  const _Card({required this.child});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.5)),
        boxShadow: [
          BoxShadow(color: cs.shadow.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: child,
    );
  }
}

class _ItemRow extends StatelessWidget {
  final DispatchPlanItem item;
  const _ItemRow({required this.item});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: cs.secondaryContainer.withOpacity(0.4),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(Icons.inventory_2_outlined, size: 20, color: cs.onSecondaryContainer),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.productName,
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  "Product ID: ${item.productId}",
                  style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                "${item.quantity}",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: cs.primary),
              ),
              Text(
                item.unit ?? "pcs",
                style: TextStyle(
                  fontSize: 11,
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _KeyValueRow extends StatelessWidget {
  final String label, value;
  const _KeyValueRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 100,
          child: Text(
            label,
            style: TextStyle(fontWeight: FontWeight.w500, color: cs.onSurfaceVariant, fontSize: 13),
          ),
        ),
        Expanded(
          child: Text(value, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        ),
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  final String text;
  final Color bg, fg;
  const _Pill({required this.text, required this.bg, required this.fg});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
      child: Text(
        text,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: fg),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: cs.errorContainer, borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: cs.error),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: cs.onErrorContainer, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}
