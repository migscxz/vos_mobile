import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";

import "../../app.dart"; // must expose apiClientProvider (if yours is app_providers.dart, change it)
import "../../data/repositories/stock_transfer_repository.dart";
import "../../data/repositories/sales_order_repository.dart";

import "stock_transfer/stock_transfer_view.dart";
import "sales_order/sales_order_view.dart"; // IMPORTANT: match your real file/class name

class ApprovalView extends ConsumerStatefulWidget {
  const ApprovalView({super.key});

  @override
  ConsumerState<ApprovalView> createState() => _ApprovalViewState();
}

class _ApprovalViewState extends ConsumerState<ApprovalView> {
  // Stock Transfer badge
  bool _stLoading = true;
  String? _stError;
  int _requestedCount = 0;

  // Sales Order badge
  bool _soLoading = true;
  String? _soError;
  int _soForApprovalCount = 0;

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
    });

    final api = ref.read(apiClientProvider);

    final stRepo = StockTransferRepository(api);
    final soRepo = SalesOrderRepository(api);

    // Run in parallel, but isolate failures cleanly.
    final stFuture = stRepo.fetchRequestedHeaderCount();
    final soFuture = soRepo.fetchSalesOrderCount(
      status: SalesOrderRepository.soStatusForApproval,
    );

    final results = await Future.wait([
      stFuture.then<Object?>((v) => v).catchError((e) => e),
      soFuture.then<Object?>((v) => v).catchError((e) => e),
    ]);

    if (!mounted) return;

    // Stock Transfer result
    final stRes = results[0];
    if (stRes is int) {
      _requestedCount = stRes;
      _stLoading = false;
      _stError = null;
    } else {
      _requestedCount = 0;
      _stLoading = false;
      _stError = stRes.toString();
    }

    // Sales Order result
    final soRes = results[1];
    if (soRes is int) {
      _soForApprovalCount = soRes;
      _soLoading = false;
      _soError = null;
    } else {
      _soForApprovalCount = 0;
      _soLoading = false;
      _soError = soRes.toString();
    }

    setState(() {});
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

              _ApprovalCardWithBadge(
                title: "Stock Transfer",
                subtitle: "Tap to review Requested stock transfers",
                icon: Icons.swap_horiz_rounded,
                loading: _stLoading,
                badgeCount: _requestedCount,
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
                          badgeCount == 0 ? "No pending requests." : "$badgeCount pending request(s).",
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
        color: loading ? cs.surfaceContainerHigh : (show ? cs.primary : cs.surfaceContainerHigh),
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
