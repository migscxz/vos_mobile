// lib/modules/approvals/disbursement/disbursement_view.dart
import "dart:async";

import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";

import "../../../app.dart";
import "../../../core/network/api_client.dart";
import "../../../data/repositories/disbursement_repository.dart";
import "disbursement_models.dart";
import "disbursement_sheet.dart";

class DisbursementView extends ConsumerStatefulWidget {
  const DisbursementView({super.key});

  @override
  ConsumerState<DisbursementView> createState() => _DisbursementViewState();
}

class _DisbursementViewState extends ConsumerState<DisbursementView> {
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

  int _rowOffset = 0; // offset in disbursement rows
  int _rowTotal = 0;

  // Merge-safe row ingest
  final Set<int> _seenIds = <int>{};
  final Map<String, List<DisbursementRow>> _rowsByDoc = <String, List<DisbursementRow>>{};
  final List<String> _docKeys = <String>[];
  final List<DisbursementApprovalHeader> _headers = <DisbursementApprovalHeader>[];

  // Lightweight caches for joins (avoid re-fetching names)
  final Map<int, String> _userNameById = <int, String>{};
  final Map<int, String> _supplierNameById = <int, String>{};

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
    if (_loading || _loadingMore || !_hasMore || !_scrollCtrl.hasClients) return;

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

      _rowOffset = 0;
      _rowTotal = 0;

      _seenIds.clear();
      _rowsByDoc.clear();
      _docKeys.clear();
      _headers.clear();

      _userNameById.clear();
      _supplierNameById.clear();
    });

    _fetchFirstPage();
  }

  Future<void> _fetchFirstPage() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      // Sales-order behavior: search shows results across all statuses.
      final st = _query.trim().isNotEmpty ? null : _selectedFilter.statusValue;

      final res = await _repo.fetchDisbursementsPaged(
        limit: _pageSize,
        offset: 0,
        search: _query.isNotEmpty ? _query : null,
        status: st,
      );

      await _ingestPage(res);

      if (!mounted) return;
      setState(() {
        _rowOffset = res.items.length;
        _rowTotal = res.total;
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
      final st = _query.trim().isNotEmpty ? null : _selectedFilter.statusValue;

      final res = await _repo.fetchDisbursementsPaged(
        limit: _pageSize,
        offset: _rowOffset,
        search: _query.isNotEmpty ? _query : null,
        status: st,
      );

      await _ingestPage(res);

      if (!mounted) return;
      setState(() {
        _rowOffset += res.items.length;
        _rowTotal = res.total;
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

    // Determine which join ids we still need
    final needUserIds = <int>{};
    final needSupplierIds = <int>{};

    for (final m in raw) {
      final id = asInt(m["id"]);
      if (id == null || id <= 0) continue;
      if (_seenIds.contains(id)) continue;

      final encoderId = asInt(m["encoder_id"]) ?? 0;
      final payeeId = asInt(m["payee"]) ?? 0;

      if (encoderId > 0 && !_userNameById.containsKey(encoderId)) needUserIds.add(encoderId);
      if (payeeId > 0 && !_supplierNameById.containsKey(payeeId)) needSupplierIds.add(payeeId);
    }

    // Fetch joins in parallel (performance)
    final results = await Future.wait([
      needUserIds.isEmpty ? Future.value(const <Map<String, dynamic>>[]) : _repo.fetchUsersByIds(needUserIds.toList()),
      needSupplierIds.isEmpty ? Future.value(const <Map<String, dynamic>>[]) : _repo.fetchSuppliersByIds(needSupplierIds.toList()),
    ]);

    final users = results[0];
    final suppliers = results[1];

    for (final u in users) {
      final uid = asInt(u["user_id"]);
      if (uid == null || uid <= 0) continue;

      final fn = (u["user_fname"]?.toString() ?? "").trim();
      final mn = (u["user_mname"]?.toString() ?? "").trim();
      final ln = (u["user_lname"]?.toString() ?? "").trim();
      final name = ([fn, mn, ln]..removeWhere((e) => e.trim().isEmpty)).join(" ").trim();
      if (name.isNotEmpty) _userNameById[uid] = name;
    }

    for (final s in suppliers) {
      final sid = asInt(s["id"]);
      if (sid == null || sid <= 0) continue;

      final name = (s["supplier_name"]?.toString() ?? "").trim();
      if (name.isNotEmpty) _supplierNameById[sid] = name;
    }

    // Convert rows and group by doc_no
    for (final m in raw) {
      final disbId = asInt(m["id"]) ?? 0;
      if (disbId <= 0) continue;
      if (_seenIds.contains(disbId)) continue;
      _seenIds.add(disbId);

      final docNo = (m["doc_no"]?.toString() ?? "").trim();
      if (docNo.isEmpty) continue;

      if (!_rowsByDoc.containsKey(docNo)) {
        _rowsByDoc[docNo] = <DisbursementRow>[];
        _docKeys.add(docNo);
      }

      final encoderId = asInt(m["encoder_id"]) ?? 0;
      final payeeId = asInt(m["payee"]) ?? 0;

      final txDate = parseDateOrIso(m["transaction_date"]?.toString());

      final totalAmount = asDouble(m["total_amount"]);
      final paidAmount = asDouble(m["paid_amount"]);

      final approverId = asInt(m["approver_id"]);
      final dateApproved = (m["date_approved"] == null)
          ? null
          : parseDateOrIso(m["date_approved"]?.toString());

      _rowsByDoc[docNo]!.add(
        DisbursementRow(
          disbursementId: disbId,
          docNo: docNo,
          payeeId: payeeId,
          encoderId: encoderId,
          transactionDate: txDate,
          totalAmount: totalAmount,
          paidAmount: paidAmount,
          approverId: approverId,
          dateApproved: dateApproved,
        ),
      );
    }

    _rebuildHeaders();
  }

  void _rebuildHeaders() {
    _headers
      ..clear()
      ..addAll(
        _docKeys.map((docNo) {
          final rows = _rowsByDoc[docNo] ?? const <DisbursementRow>[];
          final sorted = [...rows]..sort((a, b) => b.transactionDate.compareTo(a.transactionDate));

          final txDate = sorted.isEmpty
              ? DateTime.fromMillisecondsSinceEpoch(0)
              : sorted.map((e) => e.transactionDate).reduce((a, b) => a.isAfter(b) ? a : b);

          final payeeId = sorted.isEmpty ? 0 : sorted.first.payeeId;
          final encoderId = sorted.isEmpty ? 0 : sorted.first.encoderId;

          final payeeName = payeeId > 0 ? (_supplierNameById[payeeId] ?? "Unknown") : "Unknown";
          final encoderName = encoderId > 0 ? (_userNameById[encoderId] ?? "Unknown") : "Unknown";

          final totalAmount = sorted.fold<double>(0.0, (sum, r) => sum + r.totalAmount);
          final paidAmount = sorted.fold<double>(0.0, (sum, r) => sum + r.paidAmount);

          final status = _deriveDocStatus(sorted);

          return DisbursementApprovalHeader(
            docNo: docNo,
            transactionDate: txDate,
            payeeId: payeeId,
            payeeName: payeeName,
            encoderId: encoderId,
            encoderName: encoderName,
            totalAmount: totalAmount,
            paidAmount: paidAmount,
            status: status,
            rows: sorted,
          );
        }),
      );

    // Newest first
    _headers.sort((a, b) => b.transactionDate.compareTo(a.transactionDate));
  }

  DisbursementStatus _deriveDocStatus(List<DisbursementRow> rows) {
    if (rows.isEmpty) return DisbursementStatus.pending;

    final allPending = rows.every((r) => r.isPending);
    if (allPending) return DisbursementStatus.pending;

    final allApproved = rows.every((r) => r.isApproved);
    if (allApproved) return DisbursementStatus.approved;

    return DisbursementStatus.mixed;
  }

  Future<void> _openApprovalModal(DisbursementApprovalHeader header) async {
    if (!header.isActionable) return;

    final outcome = await showModalBottomSheet<DisbursementApproveOutcome?>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DisbursementApprovalSheet(header: header),
    );

    if (outcome == null) return;

    // Refresh cheap + consistent
    _resetAndFetch();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Approved ${outcome.docNo}.")),
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
                child: Text(
                  "Filter by Status",
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                ),
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    // Client-side filter (doc-level) only when not searching.
    final list = _headers.where((h) {
      if (_query.trim().isNotEmpty) return true;
      if (_selectedFilter == DisbursementFilter.all) return true;
      if (_selectedFilter == DisbursementFilter.pending) return h.status == DisbursementStatus.pending;
      if (_selectedFilter == DisbursementFilter.approved) return h.status == DisbursementStatus.approved;
      return true;
    }).toList();

    return Scaffold(
      backgroundColor: cs.surfaceContainerLowest,
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Disbursements", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
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
              hintText: "Search Doc #, supplier, encoder...",
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
                  _loading ? "Loading..." : (_rowTotal > 0 ? "${list.length} / $_rowTotal" : "${list.length}"),
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
                        child: list.isEmpty
                            ? ListView(children: [_EmptyState(query: _query)])
                            : ListView.builder(
                                controller: _scrollCtrl,
                                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                                itemCount: list.length + (_loadingMore ? 1 : 0),
                                itemBuilder: (context, i) {
                                  if (_loadingMore && i == list.length) {
                                    return const Padding(
                                      padding: EdgeInsets.symmetric(vertical: 18),
                                      child: Center(child: CircularProgressIndicator()),
                                    );
                                  }

                                  final h = list[i];
                                  final enabled = h.isActionable;

                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 12),
                                    child: _DisbursementCard(
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
}

// ------------------------------
// UI: Card
// ------------------------------

class _DisbursementCard extends StatelessWidget {
  final DisbursementApprovalHeader header;
  final bool enabled;
  final VoidCallback onTap;

  const _DisbursementCard({
    required this.header,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final statusColor = header.status == DisbursementStatus.pending
        ? cs.primary
        : (header.status == DisbursementStatus.approved ? Colors.green : cs.outline);

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
                    header.docNo,
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
                  text: header.status.label.toUpperCase(),
                  bg: statusColor.withOpacity(0.12),
                  fg: statusColor,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              "Payee: ${header.payeeName}",
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w800,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 6),
            Text(
              "Encoder: ${header.encoderName} • Date: ${fmtYmd(header.transactionDate)}",
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
                Expanded(
                  child: Text(
                    "Total: ${formatMoney(header.totalAmount)}",
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                Text(
                  "Paid: ${formatMoney(header.paidAmount)}",
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(width: 6),
                Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
              ],
            ),
            if (!enabled) ...[
              const SizedBox(height: 8),
              Text(
                "Not actionable: already approved.",
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
