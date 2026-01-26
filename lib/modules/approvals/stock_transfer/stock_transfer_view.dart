// lib/modules/approvals/stock_transfer/stock_transfer_view.dart
import "dart:async";

import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";

import "../../../app.dart";
import "../../../core/network/api_client.dart";
import "../../../data/repositories/stock_transfer_repository.dart";
import "stock_transfer_models.dart";
import "stock_transfer_sheet.dart";

class StockTransferView extends ConsumerStatefulWidget {
  const StockTransferView({super.key});

  @override
  ConsumerState<StockTransferView> createState() => _StockTransferViewState();
}

class _StockTransferViewState extends ConsumerState<StockTransferView> {
  static const int _headerPageSize = 40;

  final TextEditingController _searchCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  Timer? _debounce;

  StockTransferFilter _selectedFilter = StockTransferFilter.requested;
  String _query = "";

  late final ApiClient _api;
  late final StockTransferRepository _repo;

  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  String? _error;

  int _lineCursor = 0;
  final Set<String> _seenOrderNos = <String>{};
  final Map<String, List<StockTransferRow>> _itemsByOrder = <String, List<StockTransferRow>>{};
  final List<StockTransferHeader> _headers = <StockTransferHeader>[];

  bool _autoFilling = false;

  @override
  void initState() {
    super.initState();
    _api = ref.read(apiClientProvider);
    _repo = StockTransferRepository(_api);
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

  // --- LOGIC (Untouched as requested) ---

  void _onScroll() {
    if (_loading || _loadingMore || !_hasMore || !_scrollCtrl.hasClients) {
      return;
    }
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
      final next = normalizeQuery(value);
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
      _lineCursor = 0;
      _seenOrderNos.clear();
      _itemsByOrder.clear();
      _headers.clear();
    });
    _fetchFirstPage();
  }

  Future<void> _fetchFirstPage() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await _fetchHeaderPage(resetCursor: true);
      if (!mounted) return;
      setState(() => _loading = false);
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
      await _fetchHeaderPage(resetCursor: false);
      if (!mounted) return;
      setState(() => _loadingMore = false);
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
    if (!mounted) return;
    if (_autoFilling) return;
    if (!_hasMore) return;
    if (_loading || _loadingMore) return;
    if (!_scrollCtrl.hasClients) return;

    final pos = _scrollCtrl.position;
    if (pos.maxScrollExtent > 0) return;

    _autoFilling = true;
    try {
      int safety = 0;
      while (mounted && _hasMore && !_loadingMore && _scrollCtrl.hasClients) {
        final p = _scrollCtrl.position;
        if (p.maxScrollExtent > 0) break;
        if (safety++ > 8) break;
        await _fetchNextPage();
      }
    } finally {
      _autoFilling = false;
    }
  }

  Future<void> _fetchHeaderPage({required bool resetCursor}) async {
    final searching = _query.trim().isNotEmpty;
    final status = searching ? null : _selectedFilter.statusValue;

    final page = await _repo.fetchStockTransferHeadersPaged(
      headerLimit: _headerPageSize,
      lineOffsetCursor: resetCursor ? 0 : _lineCursor,
      search: searching ? _query.trim() : null,
      status: status,
    );

    _lineCursor = page.nextLineOffset;
    _hasMore = page.hasMore;

    if (page.lines.isEmpty || page.orderNos.isEmpty) return;
    await _ingestLinesForHeaders(page.lines, page.orderNos);
  }

  Future<void> _ingestLinesForHeaders(
    List<Map<String, dynamic>> rawLines,
    List<String> orderNos,
  ) async {
    final newOrderNos = orderNos
        .where((o) => o.trim().isNotEmpty && !_seenOrderNos.contains(o))
        .toList();
    if (newOrderNos.isEmpty) return;

    final productIds = <int>{};
    final branchIds = <int>{};
    final userIds = <int>{};

    for (final r in rawLines) {
      final orderNo = (r["order_no"]?.toString() ?? "").trim();
      if (!newOrderNos.contains(orderNo)) continue;

      final pid = _asInt(r["product_id"]);
      if (pid != null) productIds.add(pid);

      final sb = _asInt(r["source_branch"]);
      if (sb != null) branchIds.add(sb);

      final tb = _asInt(r["target_branch"]);
      if (tb != null) branchIds.add(tb);

      final enc = _asInt(r["encoder_id"]);
      if (enc != null) userIds.add(enc);
    }

    final results = await Future.wait([
      _repo.fetchProductsByIds(productIds.toList()),
      _repo.fetchBranchesByIds(branchIds.toList()),
      _repo.fetchUsersByIds(userIds.toList()),
    ]);

    final products = results[0];
    final branches = results[1];
    final users = results[2];

    final productNameById = <int, String>{};
    for (final p in products) {
      final id = _asInt(p["product_id"]);
      if (id == null) continue;
      productNameById[id] = (p["product_name"]?.toString() ?? "Unknown Product").trim();
    }

    final branchNameById = <int, String>{};
    for (final b in branches) {
      final id = _asInt(b["id"]);
      if (id == null) continue;
      branchNameById[id] = (b["branch_name"]?.toString() ?? "Unknown").trim();
    }

    final userNameById = <int, String>{};
    for (final u in users) {
      final uid = _asInt(u["user_id"]);
      if (uid == null) continue;
      if (truthyDeleted(u["is_deleted"])) continue;

      final fn = (u["user_fname"]?.toString() ?? "").trim();
      final ln = (u["user_lname"]?.toString() ?? "").trim();
      final name = ("$fn $ln").trim();
      if (name.isNotEmpty) userNameById[uid] = name;
    }

    for (final orderNo in newOrderNos) {
      final lines = rawLines
          .where((m) => (m["order_no"]?.toString() ?? "").trim() == orderNo)
          .toList();
      if (lines.isEmpty) continue;

      final items = <StockTransferRow>[];
      for (final m in lines) {
        final lineId = _asInt(m["id"]) ?? 0;
        if (lineId <= 0) continue;

        final statusEnum = _parseStatus(m["status"]?.toString());
        final pid = _asInt(m["product_id"]);
        final productName = pid != null
            ? (productNameById[pid] ?? "Unknown Product")
            : "Unknown Product";

        final sb = _asInt(m["source_branch"]);
        final tb = _asInt(m["target_branch"]);
        final sourceName = sb != null ? (branchNameById[sb] ?? "Unknown") : "Unknown";
        final targetName = tb != null ? (branchNameById[tb] ?? "Unknown") : "Unknown";

        final orderedQty = _asInt(m["ordered_quantity"]) ?? 0;
        final receivedQty = _asInt(m["received_quantity"]) ?? 0;

        final requestedAt =
            _parseDateTime(m["date_requested"]?.toString()) ??
            _parseDateTime(m["date_encoded"]?.toString()) ??
            DateTime.fromMillisecondsSinceEpoch(0);

        final enc = _asInt(m["encoder_id"]);
        final requesterName = enc != null ? (userNameById[enc] ?? "Unknown") : "Unknown";
        final remarks = (m["remarks"]?.toString() ?? "").trim();

        items.add(
          StockTransferRow(
            id: lineId,
            orderNo: orderNo,
            statusEnum: statusEnum,
            productName: productName,
            sourceBranchName: sourceName,
            targetBranchName: targetName,
            orderedQty: orderedQty,
            receivedQty: receivedQty,
            requestedAt: requestedAt.toLocal(),
            requesterName: requesterName,
            remarks: remarks,
            bossActionBy: null,
            bossActionAt: null,
            rejected: false,
            rejectReason: null,
          ),
        );
      }

      if (items.isEmpty) continue;
      _itemsByOrder[orderNo] = items;
      _seenOrderNos.add(orderNo);
    }

    _headers
      ..clear()
      ..addAll(_itemsByOrder.entries.map((e) => _buildHeader(e.key, e.value)));

    _headers.sort((a, b) => b.requestedAt.compareTo(a.requestedAt));

    if (mounted) setState(() {});
  }

  StockTransferHeader _buildHeader(String orderNo, List<StockTransferRow> items) {
    final sorted = [...items]..sort((a, b) => a.productName.compareTo(b.productName));
    final requestedAt = sorted.map((e) => e.requestedAt).reduce((a, b) => a.isAfter(b) ? a : b);
    final requesterName = sorted.first.requesterName;
    final sourceBranchName = sorted.first.sourceBranchName;
    final targetBranchName = sorted.first.targetBranchName;
    final status = _deriveHeaderStatus(sorted);
    final totalOrdered = sorted.fold<int>(0, (sum, r) => sum + r.orderedQty);
    final totalReceived = sorted.fold<int>(0, (sum, r) => sum + r.receivedQty);

    return StockTransferHeader(
      orderNo: orderNo,
      statusEnum: status,
      requestedAt: requestedAt,
      requesterName: requesterName,
      sourceBranchName: sourceBranchName,
      targetBranchName: targetBranchName,
      items: sorted,
      totalOrderedQty: totalOrdered,
      totalReceivedQty: totalReceived,
      rejected: false,
      rejectReason: null,
      bossActionAt: null,
      bossActionBy: null,
    );
  }

  StockTransferStatus _deriveHeaderStatus(List<StockTransferRow> items) {
    if (items.isEmpty) return StockTransferStatus.requested;
    final first = items.first.statusEnum;
    final allSame = items.every((e) => e.statusEnum == first);
    return allSame ? first : StockTransferStatus.mixed;
  }

  Future<void> _openApprovalModal(StockTransferHeader header) async {
    if (!header.allRequested) return;

    final outcome = await showModalBottomSheet<StockTransferApproveOutcome?>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => StockTransferApprovalSheet(header: header),
    );

    if (outcome == null) return;
    _resetAndFetch();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          "Approved. Created ${outcome.consolidatorNo ?? "CLDTST"} (ID: ${outcome.consolidatorId}).",
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  Future<void> _showFilterMenu() async {
    final selected = await showModalBottomSheet<StockTransferFilter>(
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
              ...StockTransferFilter.values.map((f) {
                final isSelected = f == _selectedFilter;
                return Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => Navigator.pop(ctx, f),
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
                              border: Border.all(
                                color: isSelected ? cs.primary : cs.outline,
                                width: 2,
                              ),
                            ),
                            child: isSelected
                                ? Icon(Icons.check, size: 16, color: cs.onPrimary)
                                : null,
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Text(
                              f.label,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                                color: isSelected ? cs.onSurface : cs.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );

    if (selected == null || selected == _selectedFilter) return;
    setState(() => _selectedFilter = selected);
    _resetAndFetch();
  }

  StockTransferStatus _parseStatus(String? raw) {
    final s = (raw ?? "").trim().toLowerCase();
    final norm = s.replaceAll("_", "").replaceAll(" ", "");
    if (norm.isEmpty) return StockTransferStatus.requested;
    if (norm == "requested") return StockTransferStatus.requested;
    if (norm == "forpicking") return StockTransferStatus.forPicking;
    if (norm == "picking") return StockTransferStatus.picking;
    if (norm == "picked") return StockTransferStatus.picked;
    if (norm == "forloading") return StockTransferStatus.forLoading;
    if (norm == "received") return StockTransferStatus.received;
    return StockTransferStatus.requested;
  }

  DateTime? _parseDateTime(String? s) {
    if (s == null) return null;
    final v = s.trim();
    if (v.isEmpty) return null;
    return DateTime.tryParse(v);
  }

  int? _asInt(Object? v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString());
  }

  // --- REVISED UI ---

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
              "Stock Transfers",
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 24,
                color: cs.onSurface,
                letterSpacing: -0.8,
              ),
            ),
            Text(
              "Manage and approve inventory moves",
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: () => _resetAndFetch())],
      ),
      body: Column(
        children: [
          _buildSearchAndFilterHeader(cs, searching),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : (_error != null)
                ? _ErrorState(message: _error!, onRetry: _fetchFirstPage)
                : RefreshIndicator(
                    onRefresh: () async => _resetAndFetch(),
                    child: _headers.isEmpty
                        ? ListView(children: [_EmptyState(query: _query)])
                        : ListView.builder(
                            controller: _scrollCtrl,
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                            itemCount: _headers.length + (_loadingMore ? 1 : 0),
                            itemBuilder: (context, i) {
                              if (_loadingMore && i == _headers.length) {
                                return const _LoadingMoreIndicator();
                              }
                              final h = _headers[i];
                              return _StockTransferCard(
                                header: h,
                                enabled: h.allRequested,
                                onTap: () => _openApprovalModal(h),
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
                hintText: "Search ID, product, or branch...",
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
                        searching ? "Search Results" : _selectedFilter.label,
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
                  "${_headers.length} Items",
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

// ------------------------------
// PROFESSIONAL UI COMPONENTS
// ------------------------------

class _StockTransferCard extends StatelessWidget {
  final StockTransferHeader header;
  final bool enabled;
  final VoidCallback onTap;

  const _StockTransferCard({required this.header, required this.enabled, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final statusColor = stockTransferStatusColor(header.statusEnum, cs);

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
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          header.orderNo,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: cs.onSurface,
                          ),
                        ),
                        Text(
                          _formatSimpleDate(header.requestedAt),
                          style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                        ),
                      ],
                    ),
                    _StatusBadge(text: header.statusEnum.name.toUpperCase(), color: statusColor),
                  ],
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Divider(height: 1, thickness: 0.5),
                ),
                Row(
                  children: [
                    Column(
                      children: [
                        Icon(Icons.radio_button_checked, size: 12, color: cs.primary),
                        Container(width: 1, height: 20, color: cs.outlineVariant),
                        Icon(Icons.location_on, size: 12, color: cs.secondary),
                      ],
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _BranchRow(label: "FROM", name: header.sourceBranchName),
                          const SizedBox(height: 8),
                          _BranchRow(label: "TO", name: header.targetBranchName),
                        ],
                      ),
                    ),
                    _ItemCountBadge(count: header.items.length),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    CircleAvatar(
                      radius: 10,
                      backgroundColor: cs.primaryContainer,
                      child: Icon(Icons.person, size: 12, color: cs.onPrimaryContainer),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      header.requesterName,
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

class _BranchRow extends StatelessWidget {
  final String label, name;
  const _BranchRow({required this.label, required this.name});

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
            name,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _ItemCountBadge extends StatelessWidget {
  final int count;
  const _ItemCountBadge({required this.count});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          Text(
            "$count",
            style: TextStyle(fontWeight: FontWeight.bold, color: cs.primary),
          ),
          Text(
            "ITEMS",
            style: TextStyle(fontSize: 8, fontWeight: FontWeight.w900, color: cs.onSurfaceVariant),
          ),
        ],
      ),
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
          Icon(Icons.inventory_2_outlined, size: 64, color: cs.outlineVariant),
          const SizedBox(height: 16),
          Text(
            query.isEmpty ? "No transfers found" : "No results for \"$query\"",
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
