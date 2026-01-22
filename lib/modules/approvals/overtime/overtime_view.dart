// lib/modules/approvals/overtime/overtime_view.dart
import "dart:async";

import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";

import "../../../app.dart"; // apiClientProvider
import "../../../data/repositories/overtime_repository.dart";
import "overtime_models.dart";
import "overtime_sheet.dart";

class OvertimeApprovalView extends ConsumerStatefulWidget {
  const OvertimeApprovalView({super.key});

  @override
  ConsumerState<OvertimeApprovalView> createState() => _OvertimeApprovalViewState();
}

class _OvertimeApprovalViewState extends ConsumerState<OvertimeApprovalView> {
  static const int _pageSize = 30;

  final TextEditingController _searchCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  Timer? _debounce;

  // Default: Pending queue, but keep "All" available.
  OvertimeFilter _selectedFilter = OvertimeFilter.pending;
  String _query = "";

  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  String? _error;

  int _offset = 0;
  late final OvertimeRepository _repo;

  final List<OvertimeApprovalHeader> _items = [];

  @override
  void initState() {
    super.initState();
    _repo = OvertimeRepository(ref.read(apiClientProvider));
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

      // Server-side search requires reload
      await _reload();
    });
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;

      _offset = 0;
      _hasMore = true;

      _items.clear();
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
      final status = _selectedFilter.statusValue; // null => All
      final q = _query.trim().isEmpty ? null : _query.trim();

      final page = await _repo.fetchOvertimeApprovalsPaged(
        status: status,
        search: q,
        limit: _pageSize,
        offset: _offset,
      );

      final fetched = page.items;

      if (!mounted) return;

      if (fetched.isEmpty) {
        setState(() {
          _hasMore = false;
          _loadingMore = false;
        });
        return;
      }

      // Append page results
      _items.addAll(fetched);

      setState(() {
        _offset += fetched.length;
        _hasMore = page.hasMore; // reliable: uses total_count from API
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
    final selected = await showModalBottomSheet<OvertimeFilter>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        final visible = OvertimeFilter.values.toList(); // includes All + Cancelled if in enum
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

    // No-op if same filter
    if (selected == _selectedFilter) return;

    setState(() => _selectedFilter = selected);
    await _reload();
  }

  Future<void> _openApprovalModal(OvertimeApprovalHeader row) async {
    // Only pending is actionable
    if (!row.isPending) return;

    final outcome = await showModalBottomSheet<OvertimeApproveOutcome?>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => OvertimeApprovalSheet(header: row),
    );

    if (outcome == null) return;

    await _reload();
    if (!mounted) return;

    final msg = outcome.newStatus == OvertimeStatus.approved
        ? "Approved OT #${outcome.overtimeId}."
        : "Rejected OT #${outcome.overtimeId}.";
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
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
                hintText: "Search employee, department, purpose, date...",
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
                  "${_items.length} request(s)",
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
              "Overtime",
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 24,
                color: cs.onSurface,
                letterSpacing: -0.8,
              ),
            ),
            Text(
              "Manage and approve overtime requests",
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _reload)],
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
                    child: _items.isEmpty
                        ? ListView(children: [_EmptyState(query: _query)])
                        : ListView.builder(
                            controller: _scrollCtrl,
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                            itemCount: _items.length + 1,
                            itemBuilder: (context, i) {
                              if (i == _items.length) {
                                return Padding(
                                  padding: const EdgeInsets.only(top: 8, bottom: 24),
                                  child: Center(
                                    child: _loadingMore
                                        ? const SizedBox(
                                            width: 22,
                                            height: 22,
                                            child: CircularProgressIndicator(strokeWidth: 2),
                                          )
                                        : (!_hasMore
                                              ? const Text("— end —")
                                              : const SizedBox.shrink()),
                                  ),
                                );
                              }

                              final row = _items[i];
                              final enabled = row.isPending;

                              return Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: _OvertimeCard(
                                  header: row,
                                  enabled: enabled,
                                  onTap: () => _openApprovalModal(row),
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
// UI: OVERTIME CARD
// ------------------------------
class _OvertimeCard extends StatelessWidget {
  final OvertimeApprovalHeader header;
  final bool enabled;
  final VoidCallback onTap;

  const _OvertimeCard({required this.header, required this.enabled, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final statusColor = _statusColor(header.status, cs);

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
                          header.employeeName,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: cs.onSurface,
                          ),
                        ),
                        Text(
                          _formatSimpleDate(header.requestDateLabel),
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
                            header.departmentName,
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            "${header.timeRangeLabel} • ${header.durationLabel}",
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
                const SizedBox(height: 12),
                Text(
                  header.purpose.trim().isEmpty ? "—" : header.purpose,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatSimpleDate(String dateStr) {
    // Simple date formatting, assuming dateStr is in a parseable format
    try {
      final date = DateTime.parse(dateStr);
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
    } catch (e) {
      return dateStr;
    }
  }

  static Color _statusColor(OvertimeStatus s, ColorScheme cs) {
    switch (s) {
      case OvertimeStatus.pending:
        return cs.primary;
      case OvertimeStatus.approved:
        return Colors.green;
      case OvertimeStatus.rejected:
        return cs.error;
      case OvertimeStatus.cancelled:
        return cs.outline;
      case OvertimeStatus.all:
        return cs.outline;
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
              query.trim().isEmpty ? "No overtime requests found." : "No results for '$query'.",
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
