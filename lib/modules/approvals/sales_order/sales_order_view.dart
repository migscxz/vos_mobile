// lib/modules/approvals/sales_order/sales_order_approval_view.dart
import "dart:async";
import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";

import "../../../app_providers.dart"; // apiClientProvider
import "../../../data/repositories/sales_order_repository.dart" as repo;
import "sales_order_approval_sheet.dart";
import "sales_order_models.dart"; // SalesOrderFilter enum + labels

class SalesOrderApprovalView extends ConsumerStatefulWidget {
  const SalesOrderApprovalView({super.key});

  @override
  ConsumerState<SalesOrderApprovalView> createState() => _SalesOrderApprovalViewState();
}

class _SalesOrderApprovalViewState extends ConsumerState<SalesOrderApprovalView> {
  static const int _pageSize = 40;

  final TextEditingController _searchCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  Timer? _debounce;

  // Default must be For Approval
  SalesOrderFilter _selectedStatus = SalesOrderFilter.forApproval;
  String _query = "";

  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  String? _error;

  int _offset = 0;

  // Source-of-truth list from API
  final List<repo.SalesOrderHeader> _dtos = [];

  // Compact cards (grouped by customer)
  final List<repo.SalesOrderCustomerGroup> _groups = [];

  // Lookups
  final Map<String, String> _customerNameByCode = {};

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
    _reload();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_loading || _loadingMore || !_hasMore) return;
    if (!_scrollCtrl.hasClients) return;

    final threshold = _scrollCtrl.position.maxScrollExtent - 260;
    if (_scrollCtrl.position.pixels >= threshold) {
      _loadMore();
    }
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 320), () async {
      if (!mounted) return;

      final next = value.trim();
      if (next == _query) return;

      setState(() => _query = next);
      await _reload(); // server-side search requires reload
    });
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
      _offset = 0;
      _hasMore = true;

      _dtos.clear();
      _groups.clear();

      // Keep cache across pagination, but refresh on a full reload for correctness
      _customerNameByCode.clear();
    });

    await _loadMore(initial: true);

    if (!mounted) return;
    setState(() => _loading = false);
  }

  Future<void> _loadMore({bool initial = false}) async {
    if (_loadingMore || !_hasMore) return;

    setState(() {
      _loadingMore = true;
      _error = null;
    });

    try {
      final api = ref.read(apiClientProvider);
      final r = repo.SalesOrderRepository(api);

      final status = _selectedStatus.statusValue; // null for All
      final q = _query.trim().isEmpty ? null : _query.trim();

      final fetched = await r.fetchSalesOrders(
        status: status,
        search: q,
        limit: _pageSize,
        offset: _offset,
      );

      if (fetched.isEmpty) {
        if (!mounted) return;
        setState(() {
          _hasMore = false;
          _loadingMore = false;
        });
        return;
      }

      // Collect missing customer codes (raw + normalized) for name lookup
      final missingCodes = <String>{};
      for (final so in fetched) {
        final code = (so.customerCode ?? "").trim();
        if (code.isNotEmpty) {
          missingCodes.add(code);
          missingCodes.add(_normalizeCustomerCode(code));
        }
      }

      if (missingCodes.isNotEmpty) {
        final customers = await r.fetchCustomersByCodes(missingCodes.toList());
        customers.forEach((k, v) {
          final name = v.customerName.trim().isEmpty ? "Unknown Customer" : v.customerName.trim();
          _customerNameByCode[k] = name;
          _customerNameByCode[_normalizeCustomerCode(k)] = name;
        });
      }

      // Append DTOs and rebuild groups across the entire loaded list
      _dtos.addAll(fetched);

      final rebuilt = repo.SalesOrderRepository.groupByCustomerCode(_dtos);

      if (!mounted) return;
      setState(() {
        _groups
          ..clear()
          ..addAll(rebuilt);

        _offset += fetched.length;
        _hasMore = fetched.length == _pageSize;
        _loadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loadingMore = false;
        if (initial) _hasMore = false;
      });
    }
  }

  Future<void> _showFilterMenu() async {
    final selected = await showModalBottomSheet<SalesOrderFilter>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        final visible = SalesOrderFilter.values.toList();
        return Material(
          color: cs.surface,
          child: ListView(
            shrinkWrap: true,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Text(
                  "Filter by Status",
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                ),
              ),
              ...visible.map((s) {
                final isSelected = s == _selectedStatus;
                return ListTile(
                  leading: Icon(
                    isSelected ? Icons.check_circle_rounded : Icons.circle_outlined,
                    color: isSelected ? cs.primary : cs.onSurfaceVariant,
                  ),
                  title: Text(
                    s.label,
                    style: TextStyle(fontWeight: isSelected ? FontWeight.w900 : FontWeight.w700),
                  ),
                  onTap: () => Navigator.pop(ctx, s),
                );
              }),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );

    if (selected == null) return;
    setState(() => _selectedStatus = selected);
    await _reload();
  }

  Future<void> _openGroupApproval(repo.SalesOrderCustomerGroup g) async {
    // Only actionable if at least one order is For Approval
    final actionable = g.orders
        .where((o) => o.orderStatus == repo.SalesOrderRepository.soStatusForApproval)
        .toList();

    if (actionable.isEmpty) return;

    final api = ref.read(apiClientProvider);
    final r = repo.SalesOrderRepository(api);

    final code = g.customerCode.trim();
    final customerName = _displayCustomerName(code);

    // Fetch full actionable set for this customer (server truth)
    final fetchedGroup = await r.fetchSalesOrdersByCustomerCode(
      customerCode: code,
      status: repo.SalesOrderRepository.soStatusForApproval,
      limit: 500,
    );

    final ordersToApprove = fetchedGroup.isEmpty ? actionable : fetchedGroup;

    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => SalesOrderApprovalSheet(
        customerName: customerName,
        customerCode: code.isEmpty ? "—" : code,
        orders: ordersToApprove,
      ),
    );

    if (changed == true) {
      await _reload();
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Approved ${ordersToApprove.length} order(s) for $customerName.")),
      );
    }
  }

  String _displayCustomerName(String customerCode) {
    final raw = customerCode.trim();
    if (raw.isEmpty) return "Unknown Customer";
    return _customerNameByCode[raw] ??
        _customerNameByCode[_normalizeCustomerCode(raw)] ??
        raw;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      backgroundColor: cs.surfaceContainerLowest,
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Sales Orders", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
            Text("Approval", style: TextStyle(fontSize: 12)),
          ],
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: SearchBar(
              controller: _searchCtrl,
              hintText: "Search customer code, SO #, PO # ...",
              onChanged: _onSearchChanged,
              leading: const Icon(Icons.search),
              elevation: WidgetStateProperty.all(0),
              backgroundColor: WidgetStateProperty.all(cs.surfaceContainerHigh),
              shape: WidgetStateProperty.all(
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Row(
              children: [
                InkWell(
                  onTap: _showFilterMenu,
                  borderRadius: BorderRadius.circular(999),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: cs.outlineVariant.withOpacity(0.5)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.filter_alt_rounded, size: 16, color: cs.onSurfaceVariant),
                        const SizedBox(width: 6),
                        Text(
                          _selectedStatus.label,
                          style: theme.textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.w900,
                            color: cs.onSurface,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Icon(Icons.expand_more_rounded, size: 18, color: cs.onSurfaceVariant),
                      ],
                    ),
                  ),
                ),
                const Spacer(),
                Text(
                  "${_groups.length} customer(s)",
                  style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : (_error != null)
                    ? _ErrorState(message: _error!, onRetry: _reload)
                    : RefreshIndicator(
                        onRefresh: _reload,
                        child: _groups.isEmpty
                            ? ListView(children: const [_EmptyState()])
                            : ListView.builder(
                                controller: _scrollCtrl,
                                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                                itemCount: _groups.length + 1,
                                itemBuilder: (context, i) {
                                  if (i == _groups.length) {
                                    return Padding(
                                      padding: const EdgeInsets.only(top: 8, bottom: 24),
                                      child: Center(
                                        child: _loadingMore
                                            ? const SizedBox(
                                                width: 22,
                                                height: 22,
                                                child: CircularProgressIndicator(strokeWidth: 2),
                                              )
                                            : (!_hasMore ? const Text("— end —") : const SizedBox.shrink()),
                                      ),
                                    );
                                  }

                                  final g = _groups[i];
                                  final title = _displayCustomerName(g.customerCode);

                                  // Actionable if group contains at least one "For Approval"
                                  final actionable = g.orders.any(
                                    (o) => o.orderStatus == repo.SalesOrderRepository.soStatusForApproval,
                                  );

                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 12),
                                    child: _CustomerGroupCard(
                                      customerTitle: title,
                                      customerCode: g.customerCode,
                                      orderCount: g.orderCount,
                                      totalNet: g.totalNet,
                                      status: g.primaryOrderStatus,
                                      enabled: actionable,
                                      onTap: () => _openGroupApproval(g),
                                    ),
                                  );
                                },
                              ),
                      ),
          ),
        ],
      ),
    );
  }
}

// =====================
// UI
// =====================

class _CustomerGroupCard extends StatelessWidget {
  final String customerTitle;
  final String customerCode;
  final int orderCount;
  final double totalNet;
  final String status;
  final bool enabled;
  final VoidCallback onTap;

  const _CustomerGroupCard({
    required this.customerTitle,
    required this.customerCode,
    required this.orderCount,
    required this.totalNet,
    required this.status,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final statusColor = enabled ? cs.primary : cs.onSurfaceVariant;

    return InkWell(
      onTap: enabled ? onTap : null,
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
              child: Icon(Icons.receipt_long_rounded, color: cs.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    customerTitle,
                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    customerCode.trim().isEmpty ? "—" : customerCode,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    "$orderCount order(s) • ₱ ${totalNet.toStringAsFixed(2)}",
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            _Pill(
              text: status.trim().isEmpty ? "—" : status.toUpperCase(),
              bg: statusColor.withOpacity(0.12),
              fg: statusColor,
            ),
            const SizedBox(width: 6),
            Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(Icons.inbox_rounded, size: 64, color: cs.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(
              "No sales orders found.",
              style: TextStyle(fontWeight: FontWeight.w900, color: cs.onSurface),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline_rounded, size: 56, color: cs.error),
            const SizedBox(height: 10),
            Text(
              "Failed to load data",
              style: TextStyle(fontWeight: FontWeight.w900, color: cs.onSurface),
            ),
            const SizedBox(height: 10),
            SelectableText(
              message,
              style: TextStyle(color: cs.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 14),
            FilledButton(onPressed: onRetry, child: const Text("Retry")),
          ],
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

// =====================
// Utils
// =====================

String _normalizeCustomerCode(String raw) {
  var s = raw.trim();
  if (s.isEmpty) return s;
  s = s.replaceAll(RegExp(r"\s*-\s*"), "-");
  s = s.replaceAll(RegExp(r"\s+"), " ").trim();
  return s;
}
