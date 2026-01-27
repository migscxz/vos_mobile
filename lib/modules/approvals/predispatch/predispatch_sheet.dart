import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../app.dart';
import '../../../data/repositories/predispatch_repository.dart';
import '../approval_sheet_widgets.dart';
import 'predispatch_models.dart';

class PredispatchApprovalSheet extends ConsumerStatefulWidget {
  const PredispatchApprovalSheet({super.key, required this.header});

  final PredispatchHeader header;

  @override
  ConsumerState<PredispatchApprovalSheet> createState() => _PredispatchApprovalSheetState();
}

class _PredispatchApprovalSheetState extends ConsumerState<PredispatchApprovalSheet> {
  // State
  bool _approving = false;
  String? _error;
  String _remarks = "";

  // Lazy loaded data
  List<PredispatchSalesOrder> _salesOrders = [];
  bool _loadingOrders = true;

  // Controllers
  late final PredispatchRepository _repo;
  final TextEditingController _remarksCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _repo = PredispatchRepository(ref.read(apiClientProvider));
    _loadOrders();
  }

  Future<void> _loadOrders() async {
    try {
      final orders = await _repo.fetchSalesOrders(widget.header.dispatchId);
      if (mounted) {
        setState(() {
          _salesOrders = orders;
          _loadingOrders = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loadingOrders = false);
    }
  }

  @override
  void dispose() {
    _remarksCtrl.dispose();
    super.dispose();
  }

  Future<void> _approve() async {
    if (_approving) return;

    setState(() {
      _approving = true;
      _error = null;
    });

    try {
      final result = await _repo.approvePredispatchPlan(
        dispatchId: widget.header.dispatchId,
        remarks: _remarks.trim(),
        dispatchDate: widget.header.dispatchDate,
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
    final statusColor = getPredispatchStatusColor(header.status, cs);
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
                        "Predispatch Approval",
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
                      ApprovalErrorBanner(message: _error!),
                      const SizedBox(height: 16),
                    ],

                    // HEADER INFO CARD
                    ApprovalCard(
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
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: statusColor.withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  header.status.label.toUpperCase(),
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: statusColor,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          ApprovalMiniKV(label: "Branch", value: header.branchName ?? "N/A"),
                          const SizedBox(height: 8),
                          ApprovalMiniKV(label: "Driver", value: header.driverName ?? "Unassigned"),
                          const SizedBox(height: 8),
                          ApprovalMiniKV(
                            label: "Total Amount",
                            value: currencyFmt.format(header.totalAmount),
                          ),
                          const SizedBox(height: 8),
                          ApprovalMiniKV(
                            label: "Dispatch Date",
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

                    // SALES ORDERS LIST
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          "Sales Orders",
                          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        if (!_loadingOrders)
                          Text(
                            "${_salesOrders.length} Orders",
                            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    if (_loadingOrders)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24.0),
                          child: CircularProgressIndicator(),
                        ),
                      )
                    else if (_salesOrders.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(24),
                        alignment: Alignment.center,
                        child: Text(
                          "No sales orders found in this dispatch.",
                          style: TextStyle(color: cs.onSurfaceVariant),
                        ),
                      )
                    else
                      ..._salesOrders.map((order) => _SalesOrderRow(order: order)),

                    const SizedBox(height: 24),

                    // REMARKS INPUT
                    Text(
                      "Approval Remarks (Optional)",
                      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _remarksCtrl,
                      onChanged: (value) => _remarks = value,
                      maxLines: 3,
                      decoration: InputDecoration(
                        hintText: "Add any comments...",
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        contentPadding: const EdgeInsets.all(12),
                      ),
                    ),
                  ],
                ),
              ),

              // ACTION BUTTONS
              Padding(
                padding: const EdgeInsets.all(24),
                child: ApprovalActionButtons(
                  onApprove: _approve,
                  onReject: () => Navigator.of(context).pop(),
                  approveEnabled: !_approving,
                  rejectEnabled: !_approving,
                  approveText: "Approve Predispatch",
                  rejectText: "Cancel",
                  isProcessing: _approving,
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
// PRIVATE HELPER COMPONENTS
// ==============================================================================

class _SalesOrderRow extends StatelessWidget {
  final PredispatchSalesOrder order;
  const _SalesOrderRow({required this.order});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final currencyFmt = NumberFormat.currency(symbol: "₱", decimalDigits: 2);

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
              color: cs.primaryContainer.withOpacity(0.4),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(Icons.receipt_long, size: 20, color: cs.onPrimaryContainer),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  order.orderNo,
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  order.customerName,
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                currencyFmt.format(order.allocatedAmount),
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: cs.primary),
              ),
              Text(
                "Allocated",
                style: TextStyle(
                  fontSize: 10,
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
