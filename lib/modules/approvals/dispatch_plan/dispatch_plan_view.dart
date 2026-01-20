// lib/modules/approvals/dispatch_plan/dispatch_plan_view.dart

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app.dart';
import '../../../core/network/api_client.dart';
import '../../../data/repositories/dispatch_plan_repository.dart';
import 'dispatch_plan_models.dart';
import 'dispatch_plan_sheet.dart';

class DispatchPlanView extends ConsumerStatefulWidget {
  const DispatchPlanView({super.key});

  @override
  ConsumerState<DispatchPlanView> createState() => _DispatchPlanViewState();
}

class _DispatchPlanViewState extends ConsumerState<DispatchPlanView> {
  static const int _pageSize = 20;

  // Controllers
  final TextEditingController _searchCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  Timer? _debounce;

  // State
  late final ApiClient _api;
  late final DispatchPlanRepository _repo;

  String _query = "";
  DispatchStatus? _selectedStatus = DispatchStatus.pending; // Default to Pending for approvals

  List<DispatchPlanHeader> _items = [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  String? _error;
  int _offset = 0;
  bool _autoFilling = false;

  @override
  void initState() {
    super.initState();
    _api = ref.read(apiClientProvider);
    _repo = DispatchPlanRepository(_api);
    _scrollCtrl.addListener(_onScroll);
    _fetchFirstPage();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  // ===========================================================================
  // DATA LOGIC
  // ===========================================================================

  void _onScroll() {
    if (_loading || _loadingMore || !_hasMore || !_scrollCtrl.hasClients) return;
    final maxScroll = _scrollCtrl.position.maxScrollExtent;
    final currentScroll = _scrollCtrl.position.pixels;
    if (currentScroll >= maxScroll - 240) {
      _fetchNextPage();
    }
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 320), () {
      if (!mounted) return;
      final next = value.trim();
      if (next == _query) return;
      setState(() => _query = next);
      _resetAndFetch();
    });
  }

  void _resetAndFetch() {
    setState(() {
      _loading = true;
      _loadingMore = false;
      _hasMore = true;
      _error = null;
      _offset = 0;
      _items.clear();
    });
    _fetchFirstPage();
  }

  Future<void> _fetchFirstPage() async {
    try {
      final page = await _repo.fetchDispatchPlansPaged(
        limit: _pageSize,
        offset: 0,
        search: _query.isNotEmpty ? _query : null,
        status: _selectedStatus,
      );

      if (!mounted) return;
      setState(() {
        _items = page.items;
        _offset = page.items.length;
        _hasMore = page.hasMore;
        _loading = false;
      });
      _scheduleViewportFill();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _fetchNextPage() async {
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);

    try {
      final page = await _repo.fetchDispatchPlansPaged(
        limit: _pageSize,
        offset: _offset,
        search: _query.isNotEmpty ? _query : null,
        status: _selectedStatus,
      );

      if (!mounted) return;
      setState(() {
        _items.addAll(page.items);
        _offset += page.items.length;
        _hasMore = page.hasMore;
        _loadingMore = false;
      });
      _scheduleViewportFill();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loadingMore = false;
      });
    }
  }

  void _scheduleViewportFill() {
    if (_autoFilling) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => _autoFillViewportIfNeeded());
  }

  Future<void> _autoFillViewportIfNeeded() async {
    if (!mounted ||
        _autoFilling ||
        !_hasMore ||
        _loading ||
        _loadingMore ||
        !_scrollCtrl.hasClients)
      return;

    final pos = _scrollCtrl.position;
    if (pos.maxScrollExtent > 0) return;

    _autoFilling = true;
    try {
      int safety = 0;
      while (mounted && _hasMore && !_loadingMore && _scrollCtrl.hasClients) {
        final p = _scrollCtrl.position;
        if (p.maxScrollExtent > 0) break;
        if (safety++ > 5) break;
        await _fetchNextPage();
      }
    } finally {
      _autoFilling = false;
    }
  }

  Future<void> _showFilterMenu() async {
    final previous = _selectedStatus;
    final selected = await showModalBottomSheet<DispatchStatus?>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                child: Text(
                  "Filter by Status",
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 20, color: cs.onSurface),
                ),
              ),
              _buildFilterOption(ctx, "All", null),
              ...DispatchStatus.values.map((s) => _buildFilterOption(ctx, s.label, s)),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );

    // If selected is not null, it means a specific status was chosen.
    // If selected is null but _selectedStatus changed (to null for "All"), refresh.
    // If selected is null and _selectedStatus unchanged, it was a dismissal.
    if (selected != null || _selectedStatus != previous) {
      _resetAndFetch();
    }
  }

  Widget _buildFilterOption(BuildContext ctx, String label, DispatchStatus? value) {
    final isSelected = value == _selectedStatus;
    final cs = Theme.of(ctx).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          // We need to trigger the update here
          setState(() => _selectedStatus = value);
          Navigator.pop(ctx); // Close modal
          _resetAndFetch(); // Fetch
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Row(
            children: [
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isSelected ? cs.primary : Colors.transparent,
                  border: Border.all(color: isSelected ? cs.primary : cs.outline, width: 2),
                ),
                child: isSelected ? Icon(Icons.check, size: 16, color: cs.onPrimary) : null,
              ),
              const SizedBox(width: 16),
              Text(
                label,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                  color: isSelected ? cs.onSurface : cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openApprovalModal(DispatchPlanHeader header) async {
    final result = await showModalBottomSheet<ApproveResult?>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DispatchPlanApprovalSheet(header: header),
    );

    if (result != null) {
      _resetAndFetch();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "Approved. Created ${result.consolidatorNo} (ID: ${result.consolidatorId})",
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  // ===========================================================================
  // UI BUILD
  // ===========================================================================

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final searching = _query.isNotEmpty;

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
              "Dispatch Plans",
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 24,
                color: cs.onSurface,
                letterSpacing: -0.8,
              ),
            ),
            Text(
              "Manage and approve outgoing dispatches",
              style: TextStyle(
                fontSize: 12,
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
                : _error != null
                ? _ErrorState(message: _error!, onRetry: _resetAndFetch)
                : RefreshIndicator(
                    onRefresh: () async => _resetAndFetch(),
                    child: _items.isEmpty
                        ? ListView(children: [_EmptyState(query: _query)])
                        : ListView.builder(
                            controller: _scrollCtrl,
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                            itemCount: _items.length + (_loadingMore ? 1 : 0),
                            itemBuilder: (context, i) {
                              if (_loadingMore && i == _items.length) {
                                return const _LoadingMoreIndicator();
                              }
                              final item = _items[i];
                              return _DispatchPlanCard(
                                header: item,
                                enabled: item.isApprovable,
                                onTap: () => _openApprovalModal(item),
                              );
                            },
                          ),
                  ),
          ),
        ],
      ),
    );
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
                hintText: "Search Dispatch No...",
                prefixIcon: Icon(Icons.search_rounded, color: cs.primary, size: 20),
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
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    border: Border.all(color: cs.outlineVariant),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.tune_rounded, size: 16, color: cs.primary),
                      const SizedBox(width: 8),
                      Text(
                        searching ? "Search Results" : (_selectedStatus?.label ?? "All Statuses"),
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                      ),
                      const Icon(Icons.arrow_drop_down),
                    ],
                  ),
                ),
              ),
              const Spacer(),
              if (!_loading)
                Text(
                  "${_items.length} Items",
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
}

// ==============================================================================
// PROFESSIONAL UI COMPONENTS (Mirrors StockTransferCard)
// ==============================================================================

class _DispatchPlanCard extends StatelessWidget {
  final DispatchPlanHeader header;
  final bool enabled;
  final VoidCallback onTap;

  const _DispatchPlanCard({required this.header, required this.enabled, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final statusColor = getDispatchStatusColor(header.status, cs);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: enabled ? cs.outlineVariant.withOpacity(0.5) : cs.outlineVariant.withOpacity(0.2),
        ),
        boxShadow: [
          BoxShadow(color: cs.shadow.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top Row: Dispatch No & Status
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          header.dispatchNo,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: cs.onSurface,
                          ),
                        ),
                        Text(
                          _formatSimpleDate(header.createdAt),
                          style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                        ),
                      ],
                    ),
                    _StatusBadge(text: header.status.label.toUpperCase(), color: statusColor),
                  ],
                ),

                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Divider(height: 1, thickness: 0.5),
                ),

                // Middle Row: Branch & Driver Info
                Row(
                  children: [
                    // Visual Connector Line
                    Column(
                      children: [
                        Icon(Icons.store, size: 12, color: cs.primary),
                        Container(width: 1, height: 20, color: cs.outlineVariant),
                        Icon(Icons.local_shipping, size: 12, color: cs.secondary),
                      ],
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _DetailRow(label: "BRANCH", value: header.branchName),
                          const SizedBox(height: 8),
                          _DetailRow(label: "DRIVER", value: header.driverName),
                        ],
                      ),
                    ),

                    // Amount Badge (Instead of item count)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            "₱${header.totalAmount.toStringAsFixed(2)}",
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: cs.primary,
                              fontSize: 13,
                            ),
                          ),
                          Text(
                            "AMOUNT",
                            style: TextStyle(
                              fontSize: 8,
                              fontWeight: FontWeight.w900,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // Bottom Row: Review Action
                Row(
                  children: [
                    CircleAvatar(
                      radius: 10,
                      backgroundColor: cs.primaryContainer,
                      child: Icon(Icons.calendar_today, size: 12, color: cs.onPrimaryContainer),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      "Dispatch: ${_formatSimpleDate(header.dispatchDate).split('•')[0]}",
                      style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const Spacer(),
                    if (enabled)
                      const Row(
                        children: [
                          Text(
                            "Review",
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.blue,
                            ),
                          ),
                          Icon(Icons.chevron_right, size: 16, color: Colors.blue),
                        ],
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatSimpleDate(DateTime date) {
    final months = [
      "Jan",
      "Feb",
      "Mar",
      "Apr",
      "May",
      "Jun",
      "Jul",
      "Aug",
      "Sep",
      "Oct",
      "Nov",
      "Dec",
    ];
    return "${date.day} ${months[date.month - 1]} • ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}";
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String? value;
  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w900,
            color: cs.onSurfaceVariant.withOpacity(0.5),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value ?? "N/A",
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String text;
  final Color color;
  const _StatusBadge({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w900,
          color: color,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _LoadingMoreIndicator extends StatelessWidget {
  const _LoadingMoreIndicator();
  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(vertical: 24),
    child: Center(
      child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)),
    ),
  );
}

class _EmptyState extends StatelessWidget {
  final String query;
  const _EmptyState({required this.query});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 100),
      child: Column(
        children: [
          Icon(Icons.local_shipping_outlined, size: 64, color: cs.outlineVariant),
          const SizedBox(height: 16),
          Text(
            query.isEmpty ? "No dispatches found" : "No results for \"$query\"",
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
        ],
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
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 48, color: Colors.red),
          const SizedBox(height: 16),
          Text(message, textAlign: TextAlign.center),
          TextButton(onPressed: onRetry, child: const Text("Retry")),
        ],
      ),
    );
  }
}
