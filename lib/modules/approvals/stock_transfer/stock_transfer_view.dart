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

  // Cursor is LINE offset, but we page in HEADERS.
  int _lineCursor = 0;

  // Header keys we already rendered (prevents duplicates)
  final Set<String> _seenOrderNos = <String>{};

  // orderNo -> items
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

      // Ensure the list becomes scrollable; otherwise infinite scroll never triggers.
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

    // If not scrollable yet, keep fetching until it is (or no more data).
    final pos = _scrollCtrl.position;
    if (pos.maxScrollExtent > 0) return;

    _autoFilling = true;
    try {
      int safety = 0;
      while (mounted && _hasMore && !_loadingMore && _scrollCtrl.hasClients) {
        final p = _scrollCtrl.position;
        if (p.maxScrollExtent > 0) break; // now scrollable
        if (safety++ > 8) break; // prevent runaway

        await _fetchNextPage();
      }
    } finally {
      _autoFilling = false;
    }
  }

  Future<void> _fetchHeaderPage({required bool resetCursor}) async {
    final searching = _query.trim().isNotEmpty;

    // Sales-order behavior: when searching, ignore status filter.
    final status = searching ? null : _selectedFilter.statusValue;

    final page = await _repo.fetchStockTransferHeadersPaged(
      headerLimit: _headerPageSize,
      lineOffsetCursor: resetCursor ? 0 : _lineCursor,
      search: searching ? _query.trim() : null,
      status: status,
    );

    // Update cursor/hasMore first.
    _lineCursor = page.nextLineOffset;
    _hasMore = page.hasMore;

    if (page.lines.isEmpty || page.orderNos.isEmpty) return;

    // Enrich lines (joins) then merge into headers.
    await _ingestLinesForHeaders(page.lines, page.orderNos);
  }

  Future<void> _ingestLinesForHeaders(
    List<Map<String, dynamic>> rawLines,
    List<String> orderNos,
  ) async {
    // Filter out headers we already have
    final newOrderNos = orderNos.where((o) => o.trim().isNotEmpty && !_seenOrderNos.contains(o)).toList();
    if (newOrderNos.isEmpty) return;

    // Collect IDs for joins
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

    // Build item lists for each new header
    for (final orderNo in newOrderNos) {
      final lines = rawLines.where((m) => (m["order_no"]?.toString() ?? "").trim() == orderNo).toList();
      if (lines.isEmpty) continue;

      final items = <StockTransferRow>[];
      for (final m in lines) {
        final lineId = _asInt(m["id"]) ?? 0;
        if (lineId <= 0) continue;

        final statusEnum = _parseStatus(m["status"]?.toString());

        final pid = _asInt(m["product_id"]);
        final productName = pid != null ? (productNameById[pid] ?? "Unknown Product") : "Unknown Product";

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

      // Save
      _itemsByOrder[orderNo] = items;
      _seenOrderNos.add(orderNo);
    }

    // Rebuild headers from current map (stable + accurate)
    _headers
      ..clear()
      ..addAll(_itemsByOrder.entries.map((e) => _buildHeader(e.key, e.value)));

    // Sort newest first
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
      ),
    );
  }

  Future<void> _showFilterMenu() async {
    final selected = await showModalBottomSheet<StockTransferFilter>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
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
              ...StockTransferFilter.values.map((f) {
                final isSelected = f == _selectedFilter;
                return ListTile(
                  leading: Icon(
                    isSelected ? Icons.check_circle_rounded : Icons.circle_outlined,
                    color: isSelected ? cs.primary : cs.onSurfaceVariant,
                  ),
                  title: Text(
                    f.label,
                    style: TextStyle(fontWeight: isSelected ? FontWeight.w900 : FontWeight.w700),
                  ),
                  onTap: () => Navigator.pop(ctx, f),
                );
              }),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );

    if (selected == null || selected == _selectedFilter) return;
    setState(() => _selectedFilter = selected);
    _resetAndFetch();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final searching = _query.trim().isNotEmpty;

    return Scaffold(
      backgroundColor: cs.surfaceContainerLowest,
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Stock Transfers", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
            Text("Approval Queue", style: TextStyle(fontSize: 12)),
          ],
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: SearchBar(
              controller: _searchCtrl,
              hintText: "Search ST #, remarks, product, requester, branch...",
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
                          searching ? "Search Results" : _selectedFilter.label,
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
                  _loading ? "Loading..." : "${_headers.length} transfer(s)",
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
                    ? _ErrorState(message: _error!, onRetry: _fetchFirstPage)
                    : RefreshIndicator(
                        onRefresh: () async => _resetAndFetch(),
                        child: _headers.isEmpty
                            ? ListView(children: [_EmptyState(query: _query)])
                            : ListView.builder(
                                controller: _scrollCtrl,
                                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                                itemCount: _headers.length + (_loadingMore ? 1 : 0),
                                itemBuilder: (context, i) {
                                  if (_loadingMore && i == _headers.length) {
                                    return const Padding(
                                      padding: EdgeInsets.symmetric(vertical: 18),
                                      child: Center(child: CircularProgressIndicator()),
                                    );
                                  }

                                  final h = _headers[i];
                                  final enabled = h.allRequested;

                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 12),
                                    child: _StockTransferCard(
                                      header: h,
                                      enabled: enabled,
                                      onTap: () => _openApprovalModal(h),
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
}

// ------------------------------
// UI: STOCK TRANSFER CARD (icon removed)
// ------------------------------

class _StockTransferCard extends StatelessWidget {
  final StockTransferHeader header;
  final bool enabled;
  final VoidCallback onTap;

  const _StockTransferCard({
    required this.header,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final statusColor = stockTransferStatusColor(header.statusEnum, cs);

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
                      fontSize: 15,
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
            const SizedBox(height: 8),
            Text(
              header.routeLabel,
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w800,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Text(
                    "${header.items.length} item(s) • ${header.qtyLabel}",
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                      fontWeight: FontWeight.w800,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              "Requester: ${header.requesterName}",
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (!enabled) ...[
              const SizedBox(height: 8),
              Text(
                "Not actionable: items not all in REQUESTED status.",
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
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

class _EmptyState extends StatelessWidget {
  final String query;
  const _EmptyState({required this.query});

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
              query.trim().isEmpty ? "No stock transfers found." : "No results for '$query'.",
              style: TextStyle(fontWeight: FontWeight.w900, color: cs.onSurface),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              "Try adjusting search or filter.",
              style: TextStyle(color: cs.onSurfaceVariant),
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
            Text("Failed to load data", style: TextStyle(fontWeight: FontWeight.w900, color: cs.onSurface)),
            const SizedBox(height: 10),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220),
              child: SingleChildScrollView(
                child: SelectableText(
                  message,
                  style: TextStyle(color: cs.onSurfaceVariant),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
            const SizedBox(height: 14),
            FilledButton(onPressed: onRetry, child: const Text("Retry")),
          ],
        ),
      ),
    );
  }
}
