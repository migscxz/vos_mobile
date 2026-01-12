// lib/modules/approvals/stock_transfer/stock_transfer_view.dart
import "dart:async";

import "package:flutter/material.dart";
import "package:connectivity_plus/connectivity_plus.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";

import "../../../app.dart"; // apiClientProvider, authRepositoryProvider
import "../../../core/network/api_client.dart";
import "../../../data/repositories/stock_transfer_repository.dart";

class StockTransferView extends ConsumerStatefulWidget {
  const StockTransferView({super.key});

  @override
  ConsumerState<StockTransferView> createState() => _StockTransferViewState();
}

class _StockTransferViewState extends ConsumerState<StockTransferView> {
  final TextEditingController _searchCtrl = TextEditingController();
  Timer? _debounce;

  StockTransferStatus _selectedStatus = StockTransferStatus.all;
  String _query = "";

  late final ApiClient _api;
  late final StockTransferRepository _repo;

  bool _loading = true;
  String? _error;
  bool _syncing = false;

  bool _isOnline = false;
  StreamSubscription<dynamic>? _connSub;

  List<StockTransferRow> _lines = const [];

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

    // Use the SAME ApiClient instance from Riverpod
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
    _debounce = Timer(const Duration(milliseconds: 280), () {
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

      // Fetch lookup data
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

        final isDeleted = _truthyDeleted(u["is_deleted"]);
        if (isDeleted) continue;

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

      if (!mounted) return;
      setState(() {
        _lines = lines;
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

  bool _truthyDeleted(Object? v) {
    if (v == null) return false;
    if (v is bool) return v;
    if (v is num) return v != 0;

    // handle: { type: "Buffer", data: [1] }
    if (v is Map) {
      final data = v["data"];
      if (data is List && data.isNotEmpty) {
        final first = data.first;
        if (first is num) return first != 0;
        final parsed = int.tryParse(first.toString());
        if (parsed != null) return parsed != 0;
      }
    }

    final s = v.toString().trim().toLowerCase();
    return s == "1" || s == "true" || s == "yes";
  }

  // Consolidate raw line rows into header groups by orderNo
  List<StockTransferHeader> _buildHeaders(List<StockTransferRow> rows) {
    final map = <String, List<StockTransferRow>>{};
    for (final r in rows) {
      final key = r.orderNo.trim().isEmpty ? 'ST-${r.id}' : r.orderNo.trim();
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

  bool _headerMatchesStatus(StockTransferHeader h, StockTransferStatus filter) {
    if (filter == StockTransferStatus.all) return true;

    if (h.statusEnum == StockTransferStatus.mixed) {
      return h.items.any((e) => e.statusEnum == filter);
    }

    return h.statusEnum == filter;
  }

  bool _headerMatchesQuery(StockTransferHeader h, String qLower) {
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

    // Boss can only act if ALL items are Requested
    final allRequested =
        header.items.isNotEmpty &&
        header.items.every((e) => e.statusEnum == StockTransferStatus.requested);

    if (!allRequested) return;

    final result = await showModalBottomSheet<_ApprovalAction?>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _RequestedApprovalSheet(header: header),
    );

    if (result == null) return;

    if (result.type == _ApprovalActionType.reject) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Reject is not implemented yet (online-only).")),
      );
      return;
    }

    if (_syncing) return;
    setState(() => _syncing = true);

    try {
      // createdBy must be a valid /items/user.user_id
      final createdBy = await ref.read(authRepositoryProvider).getCurrentAppUserId();

      if (createdBy == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("No user session found (user_id missing). Please login again."),
          ),
        );
        return;
      }

      final approveRes = await _repo.approveStockTransferAndCreateCldtst(
        stockTransferNo: header.orderNo,
        createdBy: createdBy,
      );

      if (!mounted) return;

      await _loadFromServer();
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "Approved. Created ${approveRes.consolidatorNo ?? "CLDTST"} (ID: ${approveRes.consolidatorId}).",
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Approve failed: $e")),
      );
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  void _showFilterMenu() async {
    final selected = await showModalBottomSheet<StockTransferStatus>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        final visibleStatuses = StockTransferStatus.values
            .where((s) => s != StockTransferStatus.mixed)
            .toList();

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
              ...visibleStatuses.map((s) {
                final isSelected = s == _selectedStatus;
                return ListTile(
                  leading: Icon(
                    isSelected ? Icons.check_circle_rounded : Icons.circle_outlined,
                    color: isSelected ? cs.primary : cs.onSurfaceVariant,
                  ),
                  title: Text(
                    s.label,
                    style: TextStyle(
                      fontWeight: isSelected ? FontWeight.w900 : FontWeight.w700,
                    ),
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
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final headers = _buildHeaders(_lines);
    final qLower = _query.toLowerCase();

    final filtered = headers.where((h) {
      final matchesQuery = _headerMatchesQuery(h, qLower);
      final matchesStatus = _headerMatchesStatus(h, _selectedStatus);

      if (_query.isNotEmpty) return matchesQuery;
      return matchesStatus;
    }).toList();

    final groups = <String, List<StockTransferHeader>>{};
    for (final h in filtered) {
      final key = _fmtYmd(h.requestedAt);
      (groups[key] ??= []).add(h);
    }
    final groupKeys = groups.keys.toList()..sort((a, b) => b.compareTo(a));

    return Scaffold(
      backgroundColor: cs.surfaceContainerLowest,
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Stock Transfers",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            Text(
              "Approvals",
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.normal),
            ),
          ],
        ),
        actions: [
          _onlineIndicator(cs),
          if (_syncing)
            const Padding(
              padding: EdgeInsets.only(right: 12),
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
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
                          _query.isNotEmpty ? "Search Results" : _selectedStatus.label,
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
                  "${filtered.length} transfers",
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
                                itemCount: groupKeys.length,
                                itemBuilder: (context, gi) {
                                  final dateKey = groupKeys[gi];
                                  final rows = groups[dateKey]!;
                                  return _DateGroup(
                                    dateKey: dateKey,
                                    rows: rows,
                                    onTapRow: (header) => _openApprovalModal(header),
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
    final s = (raw ?? '').trim().toLowerCase();
    final norm = s.replaceAll('_', '').replaceAll(' ', '');

    if (norm.isEmpty) return StockTransferStatus.requested;

    if (norm == 'requested') return StockTransferStatus.requested;
    if (norm == 'forpicking') return StockTransferStatus.forPicking;
    if (norm == 'picking') return StockTransferStatus.picking;
    if (norm == 'picked') return StockTransferStatus.picked;
    if (norm == 'forloading') return StockTransferStatus.forLoading;
    if (norm == 'received') return StockTransferStatus.received;

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
// UI: DATE GROUP (HEADERS)
// ------------------------------

class _DateGroup extends StatelessWidget {
  final String dateKey;
  final List<StockTransferHeader> rows;
  final ValueChanged<StockTransferHeader> onTapRow;

  const _DateGroup({
    required this.dateKey,
    required this.rows,
    required this.onTapRow,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8, top: 10),
          child: Text(
            dateKey,
            style: TextStyle(
              fontWeight: FontWeight.w900,
              color: cs.onSurfaceVariant,
            ),
          ),
        ),
        ...rows.map(
          (h) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _BossStockHeaderCard(header: h, onTap: () => onTapRow(h)),
          ),
        ),
      ],
    );
  }
}

// ------------------------------
// UI: HEADER CARD
// ------------------------------

class _BossStockHeaderCard extends StatelessWidget {
  final StockTransferHeader header;
  final VoidCallback onTap;

  const _BossStockHeaderCard({required this.header, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final statusColor = _statusColor(header.statusEnum, cs);

    final allRequested =
        header.items.isNotEmpty &&
        header.items.every((e) => e.statusEnum == StockTransferStatus.requested);

    return InkWell(
      onTap: allRequested ? onTap : null,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: cs.outlineVariant.withOpacity(0.4)),
        ),
        child: IntrinsicHeight(
          child: Row(
            children: [
              Container(
                width: 5,
                decoration: BoxDecoration(
                  color: statusColor,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(12),
                    bottomLeft: Radius.circular(12),
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(12),
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
                            ),
                          ),
                          _Pill(
                            text: header.statusEnum.label.toUpperCase(),
                            bg: statusColor.withOpacity(0.14),
                            fg: statusColor,
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        "${header.items.length} item(s)",
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(Icons.fork_right_rounded, size: 16, color: cs.primary),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              "${header.sourceBranchName} → ${header.targetBranchName}",
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: cs.onSurfaceVariant,
                                fontWeight: FontWeight.w800,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (allRequested)
                            Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Divider(height: 1, color: cs.outlineVariant.withOpacity(0.45)),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: _MiniKV(
                              label: "Requester",
                              value: header.requesterName,
                            ),
                          ),
                          Expanded(
                            child: _MiniKV(
                              label: "Qty",
                              value: "${header.totalReceivedQty}/${header.totalOrderedQty}",
                              valueTone:
                                  header.totalReceivedQty == 0 ? cs.onSurface : cs.primary,
                            ),
                          ),
                        ],
                      ),
                      if (!allRequested) ...[
                        const SizedBox(height: 10),
                        Text(
                          "This transfer cannot be approved here because items are not all in REQUESTED status.",
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Color _statusColor(StockTransferStatus s, ColorScheme cs) {
    switch (s) {
      case StockTransferStatus.all:
        return cs.outline;
      case StockTransferStatus.mixed:
        return cs.outline;
      case StockTransferStatus.requested:
        return cs.primary;
      case StockTransferStatus.forPicking:
        return Colors.deepPurple;
      case StockTransferStatus.picking:
        return Colors.orange;
      case StockTransferStatus.picked:
        return Colors.teal;
      case StockTransferStatus.forLoading:
        return Colors.blue;
      case StockTransferStatus.received:
        return Colors.green;
    }
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

class _MiniKV extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueTone;

  const _MiniKV({required this.label, required this.value, this.valueTone});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: cs.onSurfaceVariant,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w900,
            color: valueTone ?? cs.onSurface,
          ),
        ),
      ],
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
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inbox_rounded, size: 64, color: cs.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(
              query.isEmpty ? "No stock transfers found." : "No results for '$query'.",
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
            Text(
              "Failed to load data",
              style: TextStyle(fontWeight: FontWeight.w900, color: cs.onSurface),
            ),
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

enum _ApprovalActionType { approve, reject }

class _ApprovalAction {
  final _ApprovalActionType type;
  final String? reason;

  const _ApprovalAction.approve()
      : type = _ApprovalActionType.approve,
        reason = null;

  const _ApprovalAction.reject(this.reason) : type = _ApprovalActionType.reject;
}

// ------------------------------
// APPROVAL SHEET
// ------------------------------

class _RequestedApprovalSheet extends StatefulWidget {
  final StockTransferHeader header;

  const _RequestedApprovalSheet({required this.header});

  @override
  State<_RequestedApprovalSheet> createState() => _RequestedApprovalSheetState();
}

class _RequestedApprovalSheetState extends State<_RequestedApprovalSheet> {
  Future<void> _reject() async {
    final reasonCtrl = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        return AlertDialog(
          title: const Text("Reject Request"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text("Reason for rejection"),
              const SizedBox(height: 12),
              TextField(
                controller: reasonCtrl,
                maxLines: 3,
                decoration: InputDecoration(
                  hintText: "e.g. wrong branch / insufficient stock / incomplete details",
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  filled: true,
                  fillColor: cs.surfaceContainerLowest,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text("Cancel"),
            ),
            FilledButton.tonal(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text("Reject"),
            ),
          ],
        );
      },
    );

    if (ok == true) {
      Navigator.pop(context, _ApprovalAction.reject(reasonCtrl.text));
    }
    reasonCtrl.dispose();
  }

  void _approve() {
    Navigator.pop(context, const _ApprovalAction.approve());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final header = widget.header;

    return Container(
      color: Colors.transparent,
      child: DraggableScrollableSheet(
        initialChildSize: 0.78,
        minChildSize: 0.55,
        maxChildSize: 0.92,
        builder: (ctx, scrollCtrl) {
          return Container(
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(18),
                topRight: Radius.circular(18),
              ),
              border: Border.all(color: cs.outlineVariant.withOpacity(0.4)),
            ),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 10, bottom: 6),
                  child: Container(
                    width: 44,
                    height: 4,
                    decoration: BoxDecoration(
                      color: cs.onSurfaceVariant.withOpacity(0.35),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          "Stock Transfer ${header.orderNo}",
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView(
                    controller: scrollCtrl,
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: cs.surfaceContainerLowest,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: cs.outlineVariant.withOpacity(0.35)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _kv("Requested by", header.requesterName),
                            const SizedBox(height: 6),
                            _kv(
                              "Requested at",
                              "${_fmtYmd(header.requestedAt)} ${_fmtHm(header.requestedAt)}",
                            ),
                            const SizedBox(height: 6),
                            _kv(
                              "Route",
                              "${header.sourceBranchName} → ${header.targetBranchName}",
                            ),
                            const SizedBox(height: 6),
                            _kv("Total Qty", "${header.totalOrderedQty}"),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        "Items (${header.items.length})",
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ...header.items.map((item) {
                        return Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: cs.surfaceContainerLowest,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: cs.outlineVariant.withOpacity(0.35)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.productName,
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                "Qty: ${item.orderedQty}",
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: cs.onSurfaceVariant,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              if (item.remarks.trim().isNotEmpty) ...[
                                const SizedBox(height: 10),
                                Text(
                                  "Remarks",
                                  style: theme.textTheme.labelLarge?.copyWith(
                                    fontWeight: FontWeight.w900,
                                    color: cs.onSurfaceVariant,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(item.remarks),
                              ],
                            ],
                          ),
                        );
                      }),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _reject,
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(48),
                            side: BorderSide(color: cs.error.withOpacity(0.45)),
                          ),
                          child: Text(
                            "Reject",
                            style: TextStyle(fontWeight: FontWeight.w900, color: cs.error),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          onPressed: _approve,
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(48),
                          ),
                          child: const Text(
                            "Approve",
                            style: TextStyle(fontWeight: FontWeight.w900),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  static Widget _kv(String k, String v) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 96,
          child: Text(k, style: const TextStyle(fontWeight: FontWeight.w900)),
        ),
        Expanded(child: Text(v)),
      ],
    );
  }
}

// ------------------------------
// MODELS
// ------------------------------

enum StockTransferStatus {
  all("All"),
  mixed("Mixed"),
  requested("Requested"),
  forPicking("For Picking"),
  picking("Picking"),
  picked("Picked"),
  forLoading("For Loading"),
  received("Received");

  final String label;
  const StockTransferStatus(this.label);
}

class StockTransferHeader {
  final String orderNo;
  final StockTransferStatus statusEnum;

  final DateTime requestedAt;
  final String requesterName;
  final String sourceBranchName;
  final String targetBranchName;

  final List<StockTransferRow> items;

  final int totalOrderedQty;
  final int totalReceivedQty;

  final String? bossActionBy;
  final DateTime? bossActionAt;

  final bool rejected;
  final String? rejectReason;

  const StockTransferHeader({
    required this.orderNo,
    required this.statusEnum,
    required this.requestedAt,
    required this.requesterName,
    required this.sourceBranchName,
    required this.targetBranchName,
    required this.items,
    required this.totalOrderedQty,
    required this.totalReceivedQty,
    this.bossActionBy,
    this.bossActionAt,
    this.rejected = false,
    this.rejectReason,
  });
}

class StockTransferRow {
  final int id;
  final String orderNo;

  final StockTransferStatus statusEnum;

  final String productName;
  final String sourceBranchName;
  final String targetBranchName;

  final int orderedQty;
  final int receivedQty;

  final DateTime requestedAt;

  final String requesterName;
  final String remarks;

  final String? bossActionBy;
  final DateTime? bossActionAt;

  final bool rejected;
  final String? rejectReason;

  const StockTransferRow({
    required this.id,
    required this.orderNo,
    required this.statusEnum,
    required this.productName,
    required this.sourceBranchName,
    required this.targetBranchName,
    required this.orderedQty,
    required this.receivedQty,
    required this.requestedAt,
    required this.requesterName,
    required this.remarks,
    this.bossActionBy,
    this.bossActionAt,
    this.rejected = false,
    this.rejectReason,
  });
}

// ------------------------------
// Utils
// ------------------------------

String _fmtYmd(DateTime dt) {
  final d = dt.toLocal();
  String two(int n) => n.toString().padLeft(2, "0");
  return "${d.year}-${two(d.month)}-${two(d.day)}";
}

String _fmtHm(DateTime dt) {
  final d = dt.toLocal();
  String two(int n) => n.toString().padLeft(2, "0");
  return "${two(d.hour)}:${two(d.minute)}";
}
