// lib/modules/approvals/approval_view.dart
import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";

import "../../app.dart"; // must expose apiClientProvider
import "../../core/network/api_client.dart";

import "../../data/repositories/sales_order_repository.dart";
import "../../data/repositories/overtime_repository.dart";

import "stock_transfer/stock_transfer_view.dart";
import "sales_order/sales_order_view.dart"; // IMPORTANT: match your real file/class name
import "overtime/overtime_view.dart";
import "disbursement/disbursement_view.dart";

class ApprovalView extends ConsumerStatefulWidget {
  const ApprovalView({super.key});

  @override
  ConsumerState<ApprovalView> createState() => _ApprovalViewState();
}

class _ApprovalViewState extends ConsumerState<ApprovalView> {
  // approval_view >>> mwa mwa I love you

  // Stock Transfer badge (Requested headers = unique order_no where all lines are Requested)
  bool _stLoading = true;
  String? _stError;
  int _stRequestedHeaders = 0;

  // Sales Order badge
  bool _soLoading = true;
  String? _soError;
  int _soForApprovalCount = 0;

  // Overtime badge
  bool _otLoading = true;
  String? _otError;
  int _otPendingCount = 0;

  // Disbursement badge (Pending doc_no groups)
  bool _dbLoading = true;
  String? _dbError;
  int _dbPendingDocCount = 0;

  @override
  void initState() {
    super.initState();
    _loadCounts();
  }

  Future<void> _loadCounts() async {
    setState(() {
      _stLoading = true;
      _stError = null;

      _soLoading = true;
      _soError = null;

      _otLoading = true;
      _otError = null;

      _dbLoading = true;
      _dbError = null;
    });

    final api = ref.read(apiClientProvider);

    final soRepo = SalesOrderRepository(api);
    final otRepo = OvertimeRepository(api);

    // Run in parallel, but isolate failures cleanly.
    final futures = <Future<Object?>>[
      _fetchStockTransferRequestedHeaderCount(api).then<Object?>((v) => v).catchError((e) => e),
      soRepo
          .fetchSalesOrderCount(status: SalesOrderRepository.soStatusForApproval)
          .then<Object?>((v) => v)
          .catchError((e) => e),
      otRepo.fetchOvertimePendingCount().then<Object?>((v) => v).catchError((e) => e),
      _fetchDisbursementPendingDocCount(api).then<Object?>((v) => v).catchError((e) => e),
    ];

    final results = await Future.wait(futures);
    if (!mounted) return;

    // Stock Transfer
    final stRes = results[0];
    if (stRes is int) {
      _stRequestedHeaders = stRes;
      _stError = null;
    } else {
      _stRequestedHeaders = 0;
      _stError = stRes.toString();
    }
    _stLoading = false;

    // Sales Order
    final soRes = results[1];
    if (soRes is int) {
      _soForApprovalCount = soRes;
      _soError = null;
    } else {
      _soForApprovalCount = 0;
      _soError = soRes.toString();
    }
    _soLoading = false;

    // Overtime
    final otRes = results[2];
    if (otRes is int) {
      _otPendingCount = otRes;
      _otError = null;
    } else {
      _otPendingCount = 0;
      _otError = otRes.toString();
    }
    _otLoading = false;

    // Disbursement
    final dbRes = results[3];
    if (dbRes is int) {
      _dbPendingDocCount = dbRes;
      _dbError = null;
    } else {
      _dbPendingDocCount = 0;
      _dbError = dbRes.toString();
    }
    _dbLoading = false;

    setState(() {});
  }

  /// Computes unique order_no headers where ALL lines are in Requested status.
  /// This avoids the common pitfall where a repository method compiles but is
  /// accidentally placed outside the class due to a bracket mismatch.
  Future<int> _fetchStockTransferRequestedHeaderCount(ApiClient api) async {
    const stCollection = "stock_transfer";

    final json = await api.getJson(
      "/items/$stCollection",
      query: {
        "limit": "-1",
        "fields": "id,order_no,status",
        "sort": "-date_encoded,-id",
      },
    );

    final List data = (json["data"] as List?) ?? const [];

    final Map<String, List<String>> statusesByOrder = {};
    for (final item in data) {
      if (item is! Map) continue;
      final m = item.cast<String, dynamic>();

      final orderNo = (m["order_no"]?.toString() ?? "").trim();
      if (orderNo.isEmpty) continue;

      final status = (m["status"]?.toString() ?? "").trim().toLowerCase();
      (statusesByOrder[orderNo] ??= []).add(status);
    }

    int count = 0;
    statusesByOrder.forEach((_, statuses) {
      if (statuses.isEmpty) return;
      final allRequested = statuses.every((s) => s.replaceAll(" ", "") == "requested");
      if (allRequested) count++;
    });

    return count;
  }

  /// Pending = approver_id IS NULL AND date_approved IS NULL.
  /// Count is unique doc_no (group key), so badge matches the card grouping.
  Future<int> _fetchDisbursementPendingDocCount(ApiClient api) async {
    const disbCollection = "disbursement";

    final json = await api.getJson(
      "/items/$disbCollection",
      query: {
        "limit": "-1",
        "fields": "id,doc_no,approver_id,date_approved",
        "filter[_and][0][approver_id][_null]": "true",
        "filter[_and][1][date_approved][_null]": "true",
      },
    );

    final List data = (json["data"] as List?) ?? const [];
    final seen = <String>{};

    for (final item in data) {
      if (item is! Map) continue;
      final m = item.cast<String, dynamic>();
      final docNo = (m["doc_no"]?.toString() ?? "").trim();
      if (docNo.isNotEmpty) seen.add(docNo);
    }

    return seen.length;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.surfaceContainerLowest,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadCounts,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            children: [
              if (_stError != null) ...[
                _InlineError(message: "Stock Transfer: $_stError"),
                const SizedBox(height: 12),
              ],
              if (_soError != null) ...[
                _InlineError(message: "Sales Order: $_soError"),
                const SizedBox(height: 12),
              ],
              if (_otError != null) ...[
                _InlineError(message: "Overtime: $_otError"),
                const SizedBox(height: 12),
              ],
              if (_dbError != null) ...[
                _InlineError(message: "Disbursement: $_dbError"),
                const SizedBox(height: 12),
              ],

              _ApprovalCardWithBadge(
                title: "Stock Transfer",
                subtitle: "Tap to review Requested stock transfers",
                icon: Icons.swap_horiz_rounded,
                loading: _stLoading,
                badgeCount: _stRequestedHeaders,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const StockTransferView()),
                  );
                },
              ),

              const SizedBox(height: 12),

              _ApprovalCardWithBadge(
                title: "Sales Orders",
                subtitle: "Tap to review Sales Orders for approval",
                icon: Icons.receipt_long_rounded,
                loading: _soLoading,
                badgeCount: _soForApprovalCount,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const SalesOrderApprovalView()),
                  );
                },
              ),

              const SizedBox(height: 12),

              _ApprovalCardWithBadge(
                title: "Overtime",
                subtitle: "Tap to review Overtime requests (Pending)",
                icon: Icons.timer_rounded,
                loading: _otLoading,
                badgeCount: _otPendingCount,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const OvertimeApprovalView()),
                  );
                },
              ),

              const SizedBox(height: 12),

              _ApprovalCardWithBadge(
                title: "Disbursement",
                subtitle: "Tap to review Disbursement approvals (Pending)",
                icon: Icons.payments_rounded,
                loading: _dbLoading,
                badgeCount: _dbPendingDocCount,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const DisbursementView()),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InlineError extends StatelessWidget {
  final String message;
  const _InlineError({required this.message});

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
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _ApprovalCardWithBadge extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final bool loading;
  final int badgeCount;
  final VoidCallback onTap;

  const _ApprovalCardWithBadge({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.loading,
    required this.badgeCount,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: cs.outlineVariant.withOpacity(0.45)),
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: cs.outlineVariant.withOpacity(0.45)),
                  ),
                  child: Icon(icon, color: cs.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (loading)
                        Text(
                          "Loading count...",
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        )
                      else
                        Text(
                          badgeCount == 0
                              ? "No pending requests."
                              : "$badgeCount pending request(s).",
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: badgeCount == 0 ? cs.onSurfaceVariant : cs.primary,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
              ],
            ),
          ),
        ),
        Positioned(
          top: -8,
          right: -8,
          child: _TopBadge(count: badgeCount, loading: loading),
        ),
      ],
    );
  }
}

class _TopBadge extends StatelessWidget {
  final int count;
  final bool loading;

  const _TopBadge({required this.count, required this.loading});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final show = !loading && count > 0;
    final text = count > 99 ? "99+" : "$count";

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: loading
            ? cs.surfaceContainerHigh
            : (show ? cs.primary : cs.surfaceContainerHigh),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.5)),
        boxShadow: [
          BoxShadow(
            blurRadius: 10,
            color: Colors.black.withOpacity(0.08),
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: loading
          ? SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: cs.primary,
              ),
            )
          : Text(
              show ? text : "0",
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 12,
                color: show ? cs.onPrimary : cs.onSurfaceVariant,
              ),
            ),
    );
  }
}
