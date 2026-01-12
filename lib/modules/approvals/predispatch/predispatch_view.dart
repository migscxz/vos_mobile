import "dart:async";
import "package:flutter/material.dart";

class PreDispatchView extends StatefulWidget {
  const PreDispatchView({super.key});

  @override
  State<PreDispatchView> createState() => _PreDispatchViewState();
}

// =====================
// MODELS (STATIC UI)
// =====================

enum PreDispatchStatus {
  all("All"),
  pending("Pending"),
  approved("Approved"),
  rejected("Rejected");

  final String label;
  const PreDispatchStatus(this.label);
}

class PreDispatchHeader {
  final String dpNo;
  final PreDispatchStatus status;
  final DateTime requestedAt;

  final String requesterName;
  final String route;
  final String vehicle;
  final int totalStops;
  final int totalQty;

  final List<PreDispatchItem> items;

  const PreDispatchHeader({
    required this.dpNo,
    required this.status,
    required this.requestedAt,
    required this.requesterName,
    required this.route,
    required this.vehicle,
    required this.totalStops,
    required this.totalQty,
    required this.items,
  });
}

class PreDispatchItem {
  final String customerName;
  final String address;
  final String itemsSummary;
  final int qty;

  const PreDispatchItem({
    required this.customerName,
    required this.address,
    required this.itemsSummary,
    required this.qty,
  });
}

// =====================
// PAGE
// =====================

class _PreDispatchViewState extends State<PreDispatchView> {
  final TextEditingController _searchCtrl = TextEditingController();
  Timer? _debounce;

  PreDispatchStatus _selectedStatus = PreDispatchStatus.all;
  String _query = "";

  // Static sample dataset
  late final List<PreDispatchHeader> _headers = _seed();

  @override
  void dispose() {
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

  void _showFilterMenu() async {
    final selected = await showModalBottomSheet<PreDispatchStatus>(
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
              ...PreDispatchStatus.values.map((s) {
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

    // Filter: query + status
    final qLower = _query.toLowerCase();

    final filtered = _headers.where((h) {
      final matchesQuery = qLower.isEmpty
          ? true
          : <String>[
              h.dpNo,
              h.requesterName,
              h.route,
              h.vehicle,
              ...h.items.map((e) => e.customerName),
              ...h.items.map((e) => e.address),
              ...h.items.map((e) => e.itemsSummary),
            ].join(" ").toLowerCase().contains(qLower);

      final matchesStatus =
          _selectedStatus == PreDispatchStatus.all ? true : h.status == _selectedStatus;

      // If searching, ignore status filter (same UX pattern you used before)
      if (_query.isNotEmpty) return matchesQuery;
      return matchesStatus;
    }).toList();

    // Group by date
    final groups = <String, List<PreDispatchHeader>>{};
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
              "Pre-Dispatch",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            Text(
              "Approvals (Static UI)",
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.normal),
            ),
          ],
        ),
        actions: [
          IconButton(
            onPressed: _showFilterMenu,
            icon: const Icon(Icons.tune_rounded),
            tooltip: "Filter",
          ),
          IconButton(
            onPressed: () {
              // static placeholder refresh
              setState(() {});
            },
            icon: const Icon(Icons.refresh_rounded),
            tooltip: "Reload",
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: SearchBar(
              controller: _searchCtrl,
              hintText: "Search DP #, customers, requester, route...",
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
                        Icon(
                          Icons.filter_alt_rounded,
                          size: 16,
                          color: cs.onSurfaceVariant,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _query.isNotEmpty ? "Search Results" : _selectedStatus.label,
                          style: theme.textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.w900,
                            color: cs.onSurface,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Icon(
                          Icons.expand_more_rounded,
                          size: 18,
                          color: cs.onSurfaceVariant,
                        ),
                      ],
                    ),
                  ),
                ),
                const Spacer(),
                Text(
                  "${filtered.length} plans",
                  style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Expanded(
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
                        onTapRow: (h) => _openDetail(h),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _openDetail(PreDispatchHeader header) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PreDispatchDetailSheet(header: header),
    );
  }
}

// =====================
// UI: DATE GROUP
// =====================

class _DateGroup extends StatelessWidget {
  final String dateKey;
  final List<PreDispatchHeader> rows;
  final ValueChanged<PreDispatchHeader> onTapRow;

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
            child: _PreDispatchHeaderCard(header: h, onTap: () => onTapRow(h)),
          ),
        ),
      ],
    );
  }
}

// =====================
// UI: HEADER CARD
// =====================

class _PreDispatchHeaderCard extends StatelessWidget {
  final PreDispatchHeader header;
  final VoidCallback onTap;

  const _PreDispatchHeaderCard({required this.header, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final statusColor = _statusColor(header.status, cs);

    return InkWell(
      onTap: onTap,
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
                              header.dpNo,
                              style: const TextStyle(
                                fontFamily: "monospace",
                                fontWeight: FontWeight.w900,
                                fontSize: 15,
                              ),
                            ),
                          ),
                          _Pill(
                            text: header.status.label.toUpperCase(),
                            bg: statusColor.withOpacity(0.14),
                            fg: statusColor,
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        "${header.totalStops} stop(s) • ${header.totalQty} total qty",
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(Icons.route_rounded, size: 16, color: cs.primary),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              header.route,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: cs.onSurfaceVariant,
                                fontWeight: FontWeight.w800,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Divider(height: 1, color: cs.outlineVariant.withOpacity(0.45)),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: _MiniKV(label: "Requester", value: header.requesterName),
                          ),
                          Expanded(
                            child: _MiniKV(label: "Vehicle", value: header.vehicle),
                          ),
                        ],
                      ),
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

  static Color _statusColor(PreDispatchStatus s, ColorScheme cs) {
    switch (s) {
      case PreDispatchStatus.all:
        return cs.outline;
      case PreDispatchStatus.pending:
        return cs.primary;
      case PreDispatchStatus.approved:
        return Colors.green;
      case PreDispatchStatus.rejected:
        return cs.error;
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

  const _MiniKV({required this.label, required this.value});

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
            color: cs.onSurface,
          ),
        ),
      ],
    );
  }
}

// =====================
// UI: DETAIL SHEET (STATIC)
// =====================

class _PreDispatchDetailSheet extends StatelessWidget {
  final PreDispatchHeader header;
  const _PreDispatchDetailSheet({required this.header});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Container(
      color: Colors.transparent,
      child: DraggableScrollableSheet(
        initialChildSize: 0.80,
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
                          "Pre-Dispatch ${header.dpNo}",
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
                            _kv("Requester", header.requesterName),
                            const SizedBox(height: 6),
                            _kv(
                              "Requested at",
                              "${_fmtYmd(header.requestedAt)} ${_fmtHm(header.requestedAt)}",
                            ),
                            const SizedBox(height: 6),
                            _kv("Route", header.route),
                            const SizedBox(height: 6),
                            _kv("Vehicle", header.vehicle),
                            const SizedBox(height: 6),
                            _kv("Total Qty", "${header.totalQty}"),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        "Stops (${header.items.length})",
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
                                item.customerName,
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                item.address,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: cs.onSurfaceVariant,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      item.itemsSummary,
                                      style: theme.textTheme.bodyMedium?.copyWith(
                                        fontWeight: FontWeight.w800,
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  _qtyChip(item.qty, cs),
                                ],
                              ),
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
                          onPressed: () {
                            // static action
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text("Reject (static UI)")),
                            );
                          },
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
                          onPressed: () {
                            // static action
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text("Approve (static UI)")),
                            );
                          },
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

  static Widget _qtyChip(int qty, ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: cs.primary.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: cs.primary.withOpacity(0.25)),
      ),
      child: Text(
        "Qty $qty",
        style: TextStyle(
          fontWeight: FontWeight.w900,
          color: cs.primary,
          fontSize: 12,
        ),
      ),
    );
  }
}

// =====================
// EMPTY STATE
// =====================

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
              query.isEmpty ? "No pre-dispatch plans found." : "No results for '$query'.",
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

// =====================
// UTIL
// =====================

List<PreDispatchHeader> _seed() {
  final now = DateTime.now();

  PreDispatchHeader mk({
    required String dpNo,
    required PreDispatchStatus status,
    required DateTime at,
  }) {
    final items = <PreDispatchItem>[
      const PreDispatchItem(
        customerName: "ACME Trading",
        address: "Brgy. San Isidro, Quezon City",
        itemsSummary: "3 item(s): Gloves, Masks, Alcohol",
        qty: 24,
      ),
      const PreDispatchItem(
        customerName: "MedLab Supplies",
        address: "Makati City",
        itemsSummary: "2 item(s): Reagents, Test kits",
        qty: 10,
      ),
      const PreDispatchItem(
        customerName: "Hospital X",
        address: "Pasig City",
        itemsSummary: "4 item(s): Syringes, IV sets, Gauze, Tape",
        qty: 40,
      ),
    ];

    return PreDispatchHeader(
      dpNo: dpNo,
      status: status,
      requestedAt: at,
      requesterName: "Juan Dela Cruz",
      route: "Main Branch → Metro Manila Route",
      vehicle: "VAN-123 (Toyota HiAce)",
      totalStops: items.length,
      totalQty: items.fold<int>(0, (s, i) => s + i.qty),
      items: items,
    );
  }

  return [
    mk(dpNo: "DP-2026-00021", status: PreDispatchStatus.pending, at: now.subtract(const Duration(hours: 3))),
    mk(dpNo: "DP-2026-00020", status: PreDispatchStatus.pending, at: now.subtract(const Duration(hours: 6))),
    mk(dpNo: "DP-2026-00019", status: PreDispatchStatus.approved, at: now.subtract(const Duration(days: 1, hours: 2))),
    mk(dpNo: "DP-2026-00018", status: PreDispatchStatus.rejected, at: now.subtract(const Duration(days: 1, hours: 5))),
    mk(dpNo: "DP-2026-00017", status: PreDispatchStatus.approved, at: now.subtract(const Duration(days: 2, hours: 1))),
  ];
}

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
