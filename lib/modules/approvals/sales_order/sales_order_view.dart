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
  ConsumerState<SalesOrderApprovalView> createState() =>
      _SalesOrderApprovalViewState();
}

class _SalesOrderApprovalViewState
    extends ConsumerState<SalesOrderApprovalView> {
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
      _reload(); // server-side search requires reload
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
          final name = v.customerName.trim().isEmpty
              ? "Unknown Customer"
              : v.customerName.trim();
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
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        final cs = theme.colorScheme;
        final visible = SalesOrderFilter.values.toList();

        return Container(
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            boxShadow: [
              BoxShadow(
                color: cs.shadow.withOpacity(0.08),
                blurRadius: 18,
                offset: const Offset(0, -6),
              ),
            ],
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 6, 20, 12),
                  child: Text(
                    "Filter by Status",
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.2,
                    ),
                  ),
                ),
                Expanded(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      ...visible.map((s) {
                        final isSelected = s == _selectedStatus;
                        return Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () => Navigator.pop(ctx, s),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 14,
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 22,
                                    height: 22,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: isSelected
                                          ? cs.primary
                                          : Colors.transparent,
                                      border: Border.all(
                                        color: isSelected
                                            ? cs.primary
                                            : cs.outlineVariant,
                                        width: 2,
                                      ),
                                    ),
                                    child: isSelected
                                        ? Icon(
                                            Icons.check,
                                            size: 14,
                                            color: cs.onPrimary,
                                          )
                                        : null,
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Text(
                                      s.label,
                                      style: theme.textTheme.bodyLarge?.copyWith(
                                        fontWeight: isSelected
                                            ? FontWeight.w700
                                            : FontWeight.w600,
                                        color: isSelected
                                            ? cs.onSurface
                                            : cs.onSurfaceVariant,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ));
                        }),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
              ],
            ),
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
        .where(
          (o) => o.orderStatus == repo.SalesOrderRepository.soStatusForApproval,
        )
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
        SnackBar(
          content: Text(
            "Approved ${ordersToApprove.length} order(s) for $customerName.",
          ),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
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

  Widget _buildSearchAndFilterHeader(ColorScheme cs, bool searching) {
    return Container(
      color: cs.surface,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      child: Column(
        children: [
          Container(
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(14),
            ),
            child: TextField(
              controller: _searchCtrl,
              onChanged: _onSearchChanged,
              decoration: InputDecoration(
                hintText: "Search customer code, SO #, PO # ...",
                prefixIcon: Icon(
                  Icons.search_rounded,
                  color: cs.primary,
                  size: 20,
                ),
                suffixIcon: _searchCtrl.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.cancel, size: 18),
                        onPressed: () {
                          _searchCtrl.clear();
                          _onSearchChanged("");
                        },
                      )
                    : null,
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              GestureDetector(
                onTap: _showFilterMenu,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    border: Border.all(color: cs.outlineVariant),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.tune_rounded, size: 16, color: cs.primary),
                      const SizedBox(width: 8),
                      Text(
                        searching ? "Search Results" : _selectedStatus.label,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Icon(Icons.arrow_drop_down),
                    ],
                  ),
                ),
              ),
              const Spacer(),
              if (!_loading)
                Text(
                  "${_groups.length} Items",
                  style: TextStyle(
                    fontSize: 12,
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final searching = _query.trim().isNotEmpty;

    return Scaffold(
      backgroundColor: cs.surfaceContainerLowest,
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: cs.surface,
        centerTitle: false,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Sales Order Approvals",
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 20,
                color: cs.onSurface,
                letterSpacing: -0.8,
              ),
            ),
            Text(
              "Grouped by customer for faster review",
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w500,
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          _buildSearchAndFilterHeader(cs, searching),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : (_error != null)
                ? _ErrorState(message: _error!, onRetry: _reload)
                : RefreshIndicator(
                    onRefresh: _reload,
                    child: _groups.isEmpty
                        ? ListView(
                            padding: const EdgeInsets.fromLTRB(16, 40, 16, 16),
                            children: [
                              _EmptyState(searching: searching, query: _query),
                            ],
                          )
                        : ListView.builder(
                            controller: _scrollCtrl,
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                            itemCount: _groups.length + 1,
                            itemBuilder: (context, i) {
                              if (i == _groups.length) {
                                return Padding(
                                  padding: const EdgeInsets.only(
                                    top: 12,
                                    bottom: 26,
                                  ),
                                  child: Center(
                                    child: _loadingMore
                                        ? const SizedBox(
                                            width: 24,
                                            height: 24,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2.2,
                                            ),
                                          )
                                        : (!_hasMore
                                              ? Text(
                                                  "— end —",
                                                  style: theme
                                                      .textTheme
                                                      .bodySmall
                                                      ?.copyWith(
                                                        color:
                                                            cs.onSurfaceVariant,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                      ),
                                                )
                                              : const SizedBox.shrink()),
                                  ),
                                );
                              }

                              final g = _groups[i];
                              final title = _displayCustomerName(
                                g.customerCode,
                              );

                              // Actionable if group contains at least one "For Approval"
                              final actionable = g.orders.any(
                                (o) =>
                                    o.orderStatus ==
                                    repo
                                        .SalesOrderRepository
                                        .soStatusForApproval,
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
// UI (Revised)
// =====================

class _SearchField extends StatelessWidget {
  final TextEditingController controller;
  final String hintText;
  final ValueChanged<String> onChanged;

  const _SearchField({
    required this.controller,
    required this.hintText,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.45)),
      ),
      child: ValueListenableBuilder<TextEditingValue>(
        valueListenable: controller,
        builder: (ctx, v, _) {
          final hasText = v.text.trim().isNotEmpty;
          return TextField(
            controller: controller,
            onChanged: onChanged,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: hintText,
              prefixIcon: Icon(
                Icons.search_rounded,
                color: cs.primary,
                size: 20,
              ),
              suffixIcon: hasText
                  ? IconButton(
                      tooltip: "Clear",
                      icon: Icon(
                        Icons.close_rounded,
                        color: cs.onSurfaceVariant,
                      ),
                      onPressed: () {
                        controller.clear();
                        onChanged("");
                      },
                    )
                  : null,
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 12,
              ),
            ),
          );
        },
      ),
    );
  }
}

class _FilterChipButton extends StatelessWidget {
  final String label;
  final String subtitle;
  final VoidCallback onTap;
  final IconData leadingIcon;

  const _FilterChipButton({
    required this.label,
    required this.subtitle,
    required this.onTap,
    required this.leadingIcon,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: cs.outlineVariant.withOpacity(0.45)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(leadingIcon, size: 18, color: cs.onSurfaceVariant),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: cs.onSurface,
                      height: 1.0,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                      height: 1.0,
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 8),
              Icon(Icons.expand_more_rounded, color: cs.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

class _MetaCount extends StatelessWidget {
  final String label;
  final int value;
  final bool subtle;

  const _MetaCount({
    required this.label,
    required this.value,
    required this.subtle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.35)),
      ),
      child: Row(
        children: [
          Text(
            "$value",
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w900,
              color: subtle ? cs.onSurfaceVariant : cs.onSurface,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

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
    final codeText = customerCode.trim().isEmpty ? "—" : customerCode.trim();

    return Opacity(
      opacity: enabled ? 1.0 : 0.72,
      child: Container(
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
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: enabled ? onTap : null,
            borderRadius: BorderRadius.circular(20),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  _LeadingIcon(enabled: enabled),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Top row: name + pill
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                customerTitle,
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: -0.2,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 10),
                            _Pill(
                              text: status.trim().isEmpty
                                  ? "—"
                                  : status.toUpperCase(),
                              bg: statusColor.withOpacity(0.12),
                              fg: statusColor,
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          codeText,
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
                            Text(
                              "$orderCount order(s)",
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: cs.onSurfaceVariant,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                              ),
                              child: Container(
                                width: 4,
                                height: 4,
                                decoration: BoxDecoration(
                                  color: cs.onSurfaceVariant.withOpacity(0.6),
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ),
                            Expanded(
                              child: Text(
                                "₱ ${_formatMoney(totalNet)}",
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: cs.onSurfaceVariant,
                                  fontWeight: FontWeight.w800,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        if (enabled) ...[
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Icon(
                                Icons.verified_rounded,
                                size: 16,
                                color: cs.primary,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                "Ready for approval",
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: cs.primary,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LeadingIcon extends StatelessWidget {
  final bool enabled;
  const _LeadingIcon({required this.enabled});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.45)),
      ),
      child: Icon(
        enabled ? Icons.receipt_long_rounded : Icons.receipt_rounded,
        color: enabled ? cs.primary : cs.onSurfaceVariant,
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final bool searching;
  final String query;

  const _EmptyState({required this.searching, required this.query});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          children: [
            Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                shape: BoxShape.circle,
                border: Border.all(color: cs.outlineVariant.withOpacity(0.45)),
              ),
              child: Icon(
                searching ? Icons.manage_search_rounded : Icons.inbox_rounded,
                size: 36,
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              searching
                  ? "No results for \"${query.trim()}\""
                  : "No sales orders found",
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w900,
                color: cs.onSurface,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              searching
                  ? "Try a different keyword (SO #, PO #, or customer code)."
                  : "Pull down to refresh or adjust the status filter.",
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
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
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: cs.outlineVariant.withOpacity(0.45)),
            boxShadow: [
              BoxShadow(
                color: cs.shadow.withOpacity(0.05),
                blurRadius: 14,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline_rounded, size: 54, color: cs.error),
              const SizedBox(height: 10),
              Text(
                "Failed to load data",
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: cs.onSurface,
                ),
              ),
              const SizedBox(height: 10),
              SelectableText(
                message,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text("Retry"),
              ),
            ],
          ),
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
// Utils
// =====================

String _normalizeCustomerCode(String raw) {
  var s = raw.trim();
  if (s.isEmpty) return s;
  s = s.replaceAll(RegExp(r"\s*-\s*"), "-");
  s = s.replaceAll(RegExp(r"\s+"), " ").trim();
  return s;
}

String _formatMoney(double n) {
  final v = n.isNaN || n.isInfinite ? 0.0 : n;
  final s = v.toStringAsFixed(2);
  final parts = s.split(".");
  final whole = parts[0];
  final frac = parts.length > 1 ? parts[1] : "00";
  final buf = StringBuffer();
  for (int i = 0; i < whole.length; i++) {
    final idxFromEnd = whole.length - i;
    buf.write(whole[i]);
    if (idxFromEnd > 1 && idxFromEnd % 3 == 1) buf.write(",");
  }
  return "${buf.toString()}.$frac";
}
