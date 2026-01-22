// lib/modules/approvals/disbursement/disbursement_view.dart
import "dart:async";

import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";

import "../../../app.dart";
import "../../../core/network/api_client.dart";
import "../../../data/repositories/disbursement_repository.dart";
import "disbursement_models.dart";
import "disbursement_sheet.dart";

class DisbursementApprovalView extends ConsumerStatefulWidget {
  const DisbursementApprovalView({super.key});

  @override
  ConsumerState<DisbursementApprovalView> createState() => _DisbursementApprovalViewState();
}

class _DisbursementApprovalViewState extends ConsumerState<DisbursementApprovalView> {
  static const int _pageSize = 40;

  final TextEditingController _searchCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  Timer? _debounce;

  DisbursementFilter _selectedFilter = DisbursementFilter.pending;
  String _query = "";

  late final ApiClient _api;
  late final DisbursementRepository _repo;

  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  String? _error;

  int _offset = 0;
  int _total = 0;

  final Set<int> _seenIds = <int>{};
  final List<DisbursementHeader> _items = <DisbursementHeader>[];

  @override
  void initState() {
    super.initState();
    _api = ref.read(apiClientProvider);
    _repo = DisbursementRepository(_api);

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
    if (_loading || _loadingMore || !_hasMore || !_scrollCtrl.hasClients) {
      return;
    }
    final maxScroll = _scrollCtrl.position.maxScrollExtent;
    final currentScroll = _scrollCtrl.position.pixels;
    if (currentScroll >= maxScroll - 220) {
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
      _total = 0;

      _seenIds.clear();
      _items.clear();
    });
    _fetchFirstPage();
  }

  Future<void> _fetchFirstPage() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final res = await _repo.fetchDisbursementsPaged(
        limit: _pageSize,
        offset: 0,
        search: _query.isNotEmpty ? _query : null,
        filter: _selectedFilter,
      );

      await _ingestPage(res);

      if (!mounted) return;
      setState(() {
        _offset = res.items.length;
        _total = res.total;
        _hasMore = res.hasMore;
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

  Future<void> _fetchNextPage() async {
    if (_loadingMore || !_hasMore) return;

    setState(() => _loadingMore = true);

    try {
      final res = await _repo.fetchDisbursementsPaged(
        limit: _pageSize,
        offset: _offset,
        search: _query.isNotEmpty ? _query : null,
        filter: _selectedFilter,
      );

      await _ingestPage(res);

      if (!mounted) return;
      setState(() {
        _offset += res.items.length;
        _total = res.total;
        _hasMore = res.hasMore;
        _loadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loadingMore = false;
      });
    }
  }

  Future<void> _ingestPage(PagedResult<Map<String, dynamic>> page) async {
    final raw = page.items;
    if (raw.isEmpty) return;

    final supplierIds = <int>{};
    final userIds = <int>{};

    for (final r in raw) {
      final id = _asInt(r["id"]);
      if (id != null && _seenIds.contains(id)) continue;

      final payee = _asInt(r["payee"]);
      if (payee != null) supplierIds.add(payee);

      final enc = _asInt(r["encoder_id"]);
      if (enc != null) userIds.add(enc);

      final appr = _asInt(r["approver_id"]);
      if (appr != null) userIds.add(appr);
    }

    final results = await Future.wait([
      _repo.fetchSuppliersByIds(supplierIds.toList()),
      _repo.fetchUsersByIds(userIds.toList()),
    ]);

    final suppliers = results[0];
    final users = results[1];

    final supplierNameById = <int, String>{};
    for (final s in suppliers) {
      final id = _asInt(s["id"]);
      if (id == null) continue;
      supplierNameById[id] = (s["supplier_name"]?.toString() ?? "Unknown Supplier").trim();
    }

    final userNameById = <int, String>{};
    for (final u in users) {
      final uid = _asInt(u["user_id"]);
      if (uid == null) continue;

      // Ignore deleted users if the backend uses buffer/bool/int patterns
      if (_truthy(u["is_deleted"])) continue;

      final fn = (u["user_fname"]?.toString() ?? "").trim();
      final mn = (u["user_mname"]?.toString() ?? "").trim();
      final ln = (u["user_lname"]?.toString() ?? "").trim();
      final name = ("$fn ${mn.isEmpty ? "" : "$mn "} $ln").replaceAll(RegExp(r"\s+"), " ").trim();
      if (name.isNotEmpty) userNameById[uid] = name;
    }

    for (final m in raw) {
      final id = _asInt(m["id"]) ?? 0;
      if (id <= 0) continue;
      if (_seenIds.contains(id)) continue;
      _seenIds.add(id);

      final docNo = (m["doc_no"]?.toString() ?? "").trim();
      final encoderId = _asInt(m["encoder_id"]) ?? 0;
      final payeeId = _asInt(m["payee"]) ?? 0;

      final encoderName = encoderId > 0 ? (userNameById[encoderId] ?? "Unknown") : "Unknown";
      final payeeName = payeeId > 0 ? (supplierNameById[payeeId] ?? "Unknown") : "Unknown";

      final totalAmount = _asDouble(m["total_amount"]) ?? 0;
      final paidAmount = _asDouble(m["paid_amount"]) ?? 0;

      final txDate =
          _parseDate(m["transaction_date"]?.toString()) ?? DateTime.fromMillisecondsSinceEpoch(0);

      final approverId = _asInt(m["approver_id"]);
      final dateApproved = _parseDateTime(m["date_approved"]?.toString());

      final remarks = (m["remarks"]?.toString() ?? "").trim();

      _items.add(
        DisbursementHeader(
          id: id,
          docNo: docNo.isEmpty ? "DISB-$id" : docNo,
          totalAmount: totalAmount,
          paidAmount: paidAmount,
          encoderId: encoderId,
          encoderName: encoderName,
          payeeId: payeeId,
          payeeName: payeeName,
          transactionDate: txDate.toLocal(),
          approverId: approverId,
          dateApproved: dateApproved?.toLocal(),
          remarks: remarks,
        ),
      );
    }

    // newest first: by transaction_date then id
    _items.sort((a, b) {
      final c = b.transactionDate.compareTo(a.transactionDate);
      if (c != 0) return c;
      return b.id.compareTo(a.id);
    });
  }

  Future<void> _openApprovalModal(DisbursementHeader header) async {
    if (header.isApproved) return; // non-clickable as requested

    final outcome = await showModalBottomSheet<DisbursementApproveOutcome?>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DisbursementApprovalSheet(header: header),
    );

    if (outcome == null) return;

    // refresh like Sales Order / Stock Transfer style
    _resetAndFetch();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Approved ${outcome.docNo} (ID: ${outcome.disbursementId}).")),
    );
  }

  Future<void> _showFilterMenu() async {
    final selected = await showModalBottomSheet<DisbursementFilter>(
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
                child: Text("Filter", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
              ),
              ...DisbursementFilter.values.map((f) {
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
                hintText: "Search Doc #, remarks, payee, encoder...",
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
                  "${_items.length} item(s)",
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
              "Disbursements",
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 24,
                color: cs.onSurface,
                letterSpacing: -0.8,
              ),
            ),
            Text(
              "Manage and approve disbursements",
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
                              final h = _items[i];
                              final enabled = !h.isApproved;

                              return _DisbursementCard(
                                header: h,
                                enabled: enabled,
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

  DateTime? _parseDate(String? s) {
    if (s == null) return null;
    final v = s.trim();
    if (v.isEmpty) return null;
    // disbursement.transaction_date looks like YYYY-MM-DD
    return DateTime.tryParse(v);
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

  double? _asDouble(Object? v) {
    if (v == null) return null;
    if (v is double) return v;
    if (v is int) return v.toDouble();
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }

  bool _truthy(Object? v) {
    if (v == null) return false;
    if (v is bool) return v;
    if (v is int) return v != 0;
    if (v is num) return v.toInt() != 0;
    if (v is Map) {
      // handle Buffer-like map: {"type":"Buffer","data":[1]}
      final m = v.cast<String, dynamic>();
      final data = m["data"];
      if (data is List && data.isNotEmpty) {
        final first = data.first;
        if (first is int) return first != 0;
      }
    }
    return v.toString() == "1" || v.toString().toLowerCase() == "true";
  }
}

// ------------------------------
// UI: DISBURSEMENT CARD
// ------------------------------

class _DisbursementCard extends StatelessWidget {
  final DisbursementHeader header;
  final bool enabled;
  final VoidCallback onTap;

  const _DisbursementCard({required this.header, required this.enabled, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final statusColor = disbursementStatusColor(header, cs);

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
                          header.docNo,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: cs.onSurface,
                          ),
                        ),
                        Text(
                          _formatSimpleDate(header.transactionDate),
                          style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                        ),
                      ],
                    ),
                    _StatusBadge(
                      text: header.isApproved ? "APPROVED" : "PENDING",
                      color: statusColor,
                    ),
                  ],
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Divider(height: 1, thickness: 0.5),
                ),
                Row(
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(color: cs.primary, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            header.payeeName,
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            "Encoder: ${header.encoderName}",
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant,
                              fontWeight: FontWeight.w700,
                            ),
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
                          money(header.totalAmount),
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          "Paid: ${money(header.paidAmount)}",
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          "Balance: ${money(header.totalAmount - header.paidAmount)}",
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 12),
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
              query.trim().isEmpty ? "No disbursements found." : "No results for '$query'.",
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
