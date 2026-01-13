// lib/modules/approvals/stock_transfer/stock_transfer_view.dart
import "dart:async";
import "package:flutter/material.dart";
import "package:connectivity_plus/connectivity_plus.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";

import "../../../app.dart"; // apiClientProvider, authRepositoryProvider
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
  final TextEditingController _searchCtrl = TextEditingController();
  Timer? _debounce;

  StockTransferFilter _selectedFilter = StockTransferFilter.all;
  String _query = "";

  late final ApiClient _api;
  late final StockTransferRepository _repo;

  bool _loading = true;
  String? _error;
  bool _syncing = false;

  bool _isOnline = false;
  StreamSubscription<dynamic>? _connSub;

  List<StockTransferRow> _lines = const [];

  // cached headers
  List<StockTransferHeader> _headers = const [];

  // -------------------------
  // CONNECTIVITY
  // -------------------------

  Future<void> _initConnectivity() async {
    final connectivity = Connectivity();

    final initial = await connectivity.checkConnectivity();
    _applyConnectivity(initial);

    _connSub = connectivity.onConnectivityChanged.listen(_applyConnectivity);
  }

  void _applyConnectivity(dynamic result) {
    bool online;

    if (result is List<ConnectivityResult>) {
      online = result.isNotEmpty && !result.contains(ConnectivityResult.none);
    } else if (result is ConnectivityResult) {
      online = result != ConnectivityResult.none;
    } else {
      online = false;
    }

    if (!mounted) {
      _isOnline = online;
      return;
    }
    setState(() => _isOnline = online);
  }

  Widget _onlineIndicator(ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _isOnline ? Icons.wifi_rounded : Icons.wifi_off_rounded,
            size: 20,
            color: _isOnline ? cs.primary : cs.onSurfaceVariant,
          ),
          const SizedBox(width: 6),
          Text(
            _isOnline ? "Online" : "Offline",
            style: TextStyle(
              fontWeight: FontWeight.w900,
              color: _isOnline ? cs.primary : cs.onSurfaceVariant,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  void _showOfflineNote() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("You are offline. Please connect to the internet.")),
    );
  }

  @override
  void initState() {
    super.initState();
    _api = ref.read(apiClientProvider);
    _repo = StockTransferRepository(_api);

    _initConnectivity();
    _loadFromServer();
  }

  @override
  void dispose() {
    _connSub?.cancel();
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 320), () {
      if (!mounted) return;
      setState(() => _query = value.trim());
    });
  }

  Future<void> _loadFromServer() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final res = await _repo.fetchAllStockTransferLines();
      final raw = res.rows;

      // Collect IDs for joins
      final productIds = <int>[];
      final branchIds = <int>[];
      final userIds = <int>[];

      for (final r in raw) {
        final pid = _asInt(r["product_id"]);
        if (pid != null) productIds.add(pid);

        final sb = _asInt(r["source_branch"]);
        if (sb != null) branchIds.add(sb);

        final tb = _asInt(r["target_branch"]);
        if (tb != null) branchIds.add(tb);

        final enc = _asInt(r["encoder_id"]);
        if (enc != null) userIds.add(enc);
      }

      final products = await _repo.fetchProductsByIds(productIds);
      final branches = await _repo.fetchBranchesByIds(branchIds);
      final users = await _repo.fetchUsersByIds(userIds);

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

      final lines = raw.map((m) {
        final id = _asInt(m["id"]) ?? 0;
        final orderNo = (m["order_no"]?.toString() ?? "").trim();
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

        return StockTransferRow(
          id: id,
          orderNo: orderNo.isEmpty ? "ST-$id" : orderNo,
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
        );
      }).toList();

      final headers = _buildHeaders(lines);

      if (!mounted) return;
      setState(() {
        _lines = lines;
        _headers = headers;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  // Consolidate raw line rows into header groups by orderNo
  List<StockTransferHeader> _buildHeaders(List<StockTransferRow> rows) {
    final map = <String, List<StockTransferRow>>{};
    for (final r in rows) {
      final key = r.orderNo.trim().isEmpty ? "ST-${r.id}" : r.orderNo.trim();
      (map[key] ??= []).add(r);
    }

    final headers = <StockTransferHeader>[];
    map.forEach((orderNo, items) {
      items.sort((a, b) => a.productName.compareTo(b.productName));

      final requestedAt = items
          .map((e) => e.requestedAt)
          .fold<DateTime>(
            items.first.requestedAt,
            (prev, cur) => cur.isAfter(prev) ? cur : prev,
          );

      final requesterName = items.first.requesterName;
      final sourceBranchName = items.first.sourceBranchName;
      final targetBranchName = items.first.targetBranchName;

      final status = _deriveHeaderStatus(items);

      final totalOrdered = items.fold<int>(0, (sum, r) => sum + r.orderedQty);
      final totalReceived = items.fold<int>(0, (sum, r) => sum + r.receivedQty);

      headers.add(
        StockTransferHeader(
          orderNo: orderNo,
          statusEnum: status,
          requestedAt: requestedAt,
          requesterName: requesterName,
          sourceBranchName: sourceBranchName,
          targetBranchName: targetBranchName,
          items: items,
          totalOrderedQty: totalOrdered,
          totalReceivedQty: totalReceived,
          rejected: false,
          rejectReason: null,
          bossActionAt: null,
          bossActionBy: null,
        ),
      );
    });

    headers.sort((a, b) => b.requestedAt.compareTo(a.requestedAt));
    return headers;
  }

  StockTransferStatus _deriveHeaderStatus(List<StockTransferRow> items) {
    if (items.isEmpty) return StockTransferStatus.requested;
    final first = items.first.statusEnum;
    final allSame = items.every((e) => e.statusEnum == first);
    if (allSame) return first;
    return StockTransferStatus.mixed;
  }

  bool _matchesFilter(StockTransferHeader h) {
    final f = _selectedFilter;
    if (f == StockTransferFilter.all) return true;

    // if header is mixed, match if any item matches chosen status
    if (h.statusEnum == StockTransferStatus.mixed) {
      return h.items.any((e) => e.statusEnum == f.status);
    }
    return h.statusEnum == f.status;
  }

  bool _matchesQuery(StockTransferHeader h, String qLower) {
    if (qLower.isEmpty) return true;
    final hay = <String>[
      h.orderNo,
      h.requesterName,
      h.sourceBranchName,
      h.targetBranchName,
      ...h.items.map((e) => e.productName),
    ].join(" ").toLowerCase();
    return hay.contains(qLower);
  }

  Future<void> _openApprovalModal(StockTransferHeader header) async {
    if (!_isOnline) {
      _showOfflineNote();
      return;
    }

    if (!header.allRequested) return;

    final outcome = await showModalBottomSheet<StockTransferApproveOutcome?>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => StockTransferApprovalSheet(header: header),
    );

    if (outcome == null) return;

    if (_syncing) return;
    setState(() => _syncing = true);

    try {
      await _loadFromServer();
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "Approved. Created ${outcome.consolidatorNo ?? "CLDTST"} (ID: ${outcome.consolidatorId}).",
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  Future<void> _showFilterMenu() async {
    final selected = await showModalBottomSheet<StockTransferFilter>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        final visible = StockTransferFilter.values.toList();

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
              ...visible.map((f) {
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

    if (selected == null) return;
    setState(() => _selectedFilter = selected);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final qLower = _query.trim().toLowerCase();
    final filtered = _headers.where((h) {
      final mq = _matchesQuery(h, qLower);
      final mf = _matchesFilter(h);

      // Sales Order behavior: when searching, show search results regardless of filter
      if (_query.trim().isNotEmpty) return mq;
      return mf;
    }).toList();

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
        actions: [
          _onlineIndicator(cs),
          if (_syncing)
            const Padding(
              padding: EdgeInsets.only(right: 12),
              child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: SearchBar(
              controller: _searchCtrl,
              hintText: "Search ST #, products, requester, route...",
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
                          _query.trim().isNotEmpty ? "Search Results" : _selectedFilter.label,
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
                  "${filtered.length} transfer(s)",
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
                    ? _ErrorState(message: _error!, onRetry: _loadFromServer)
                    : RefreshIndicator(
                        onRefresh: _loadFromServer,
                        child: filtered.isEmpty
                            ? ListView(children: [_EmptyState(query: _query)])
                            : ListView.builder(
                                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                                itemCount: filtered.length,
                                itemBuilder: (context, i) {
                                  final h = filtered[i];
                                  final enabled = _isOnline && h.allRequested;
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
// UI: STOCK TRANSFER CARD (Sales-Order style)
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
              child: Icon(Icons.swap_horiz_rounded, color: cs.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
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
                  const SizedBox(height: 6),
                  Text(
                    header.routeLabel,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                      fontWeight: FontWeight.w800,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
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
                      if (enabled) ...[
                        const SizedBox(width: 8),
                        Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
                      ],
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
                      _disabledReason(header, cs),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _disabledReason(StockTransferHeader h, ColorScheme cs) {
    if (!h.allRequested) {
      return "Not actionable: items not all in REQUESTED status.";
    }
    return "Offline: connect to approve.";
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
      child: Text(text, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: fg)),
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
