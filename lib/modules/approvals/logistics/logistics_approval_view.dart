import "dart:async";
import "package:flutter/material.dart";

class LogisticsApprovalView extends StatefulWidget {
  const LogisticsApprovalView({super.key});

  @override
  State<LogisticsApprovalView> createState() => _LogisticsApprovalViewState();
}

class _LogisticsApprovalViewState extends State<LogisticsApprovalView> {
  final TextEditingController _searchCtrl = TextEditingController();
  Timer? _debounce;

  LogisticsStatus _selectedStatus = LogisticsStatus.all;
  String _query = "";

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
    final selected = await showModalBottomSheet<LogisticsStatus>(
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
              ...LogisticsStatus.values.map((s) {
                final isSelected = s == _selectedStatus;
                return ListTile(
                  leading: Icon(
                    isSelected
                        ? Icons.check_circle_rounded
                        : Icons.circle_outlined,
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

  bool _matchesStatus(_LogiHeader o, LogisticsStatus filter) {
    if (filter == LogisticsStatus.all) return true;
    if (filter == LogisticsStatus.pending) return o.status == _LogiStatus.pending;
    if (filter == LogisticsStatus.approved) return o.status == _LogiStatus.approved;
    if (filter == LogisticsStatus.rejected) return o.status == _LogiStatus.rejected;
    return true;
  }

  bool _matchesQuery(_LogiHeader o, String qLower) {
    if (qLower.isEmpty) return true;
    final hay = <String>[
      o.refNo,
      o.customerName,
      o.destination,
      o.requestedBy,
      o.vehiclePlateNo ?? "",
      o.driverName ?? "",
    ].join(" ").toLowerCase();
    return hay.contains(qLower);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    // Static demo data
    final requests = <_LogiHeader>[
      _LogiHeader(
        refNo: "LOGI-000312",
        customerName: "ACME Trading",
        destination: "Cebu City",
        requestedBy: "Dispatch Coordinator",
        createdAt: DateTime.now().subtract(const Duration(hours: 3)),
        itemsCount: 8,
        status: _LogiStatus.pending,
        driverName: "R. Dizon",
        vehiclePlateNo: "ABC-1234",
        notes: "Deliver ASAP. Confirm receiving contact.",
      ),
      _LogiHeader(
        refNo: "LOGI-000311",
        customerName: "Murex Lab Supplies",
        destination: "Davao City",
        requestedBy: "Sales Admin",
        createdAt: DateTime.now().subtract(const Duration(days: 1, hours: 2)),
        itemsCount: 3,
        status: _LogiStatus.pending,
        driverName: null,
        vehiclePlateNo: null,
        notes: "Waiting for vehicle assignment.",
      ),
      _LogiHeader(
        refNo: "LOGI-000310",
        customerName: "Vertex Operations",
        destination: "Bacolod",
        requestedBy: "Warehouse",
        createdAt: DateTime.now().subtract(const Duration(days: 2)),
        itemsCount: 5,
        status: _LogiStatus.approved,
        driverName: "A. Santos",
        vehiclePlateNo: "XYZ-9081",
        notes: "Approved and scheduled for dispatch.",
      ),
      _LogiHeader(
        refNo: "LOGI-000309",
        customerName: "Alpha Medical",
        destination: "Iloilo",
        requestedBy: "Dispatch Coordinator",
        createdAt: DateTime.now().subtract(const Duration(days: 3, hours: 4)),
        itemsCount: 2,
        status: _LogiStatus.rejected,
        rejectReason: "Missing delivery address and contact person.",
        driverName: null,
        vehiclePlateNo: null,
        notes: "",
      ),
    ];

    final qLower = _query.toLowerCase();

    final filtered = requests.where((o) {
      final matchesQuery = _matchesQuery(o, qLower);
      final matchesStatus = _matchesStatus(o, _selectedStatus);

      if (_query.isNotEmpty) return matchesQuery;
      return matchesStatus;
    }).toList();

    // Group by date
    final groups = <String, List<_LogiHeader>>{};
    for (final o in filtered) {
      final key = _fmtYmd(o.createdAt);
      (groups[key] ??= []).add(o);
    }
    final groupKeys = groups.keys.toList()..sort((a, b) => b.compareTo(a));
    for (final k in groupKeys) {
      groups[k]!.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    }

    return Scaffold(
      backgroundColor: cs.surfaceContainerLowest,
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Logistics",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            Text(
              "Approvals (Boss View)",
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.normal),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          // Search
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: SearchBar(
              controller: _searchCtrl,
              hintText: "Search LOGI #, customer, destination, driver, plate...",
              onChanged: _onSearchChanged,
              leading: const Icon(Icons.search),
              elevation: WidgetStateProperty.all(0),
              backgroundColor: WidgetStateProperty.all(cs.surfaceContainerHigh),
              shape: WidgetStateProperty.all(
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),

          // Filter row
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
                  "${filtered.length} requests",
                  style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),

          const SizedBox(height: 4),

          // List
          Expanded(
            child: filtered.isEmpty
                ? ListView(
                    children: [
                      _EmptyState(query: _query),
                    ],
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    itemCount: groupKeys.length,
                    itemBuilder: (context, gi) {
                      final dateKey = groupKeys[gi];
                      final rows = groups[dateKey]!;
                      return _DateGroup(
                        dateKey: dateKey,
                        rows: rows,
                        onTapRow: (o) {
                          if (o.status != _LogiStatus.pending) return;
                          _openStaticDetail(context, o);
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  void _openStaticDetail(BuildContext context, _LogiHeader header) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _LogisticsDetailSheet(header: header),
    );
  }
}

// =====================
// UI: DATE GROUP
// =====================

class _DateGroup extends StatelessWidget {
  final String dateKey;
  final List<_LogiHeader> rows;
  final ValueChanged<_LogiHeader> onTapRow;

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
          (o) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _LogisticsHeaderCard(header: o, onTap: () => onTapRow(o)),
          ),
        ),
      ],
    );
  }
}

// =====================
// UI: HEADER CARD
// =====================

class _LogisticsHeaderCard extends StatelessWidget {
  final _LogiHeader header;
  final VoidCallback onTap;

  const _LogisticsHeaderCard({required this.header, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final statusColor = _statusColor(header.status, cs);
    final isActionable = header.status == _LogiStatus.pending;

    return InkWell(
      onTap: isActionable ? onTap : null,
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
                              header.refNo,
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
                        header.customerName,
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
                              "Destination: ${header.destination}",
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: cs.onSurfaceVariant,
                                fontWeight: FontWeight.w800,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (isActionable)
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
                              value: header.requestedBy,
                            ),
                          ),
                          Expanded(
                            child: _MiniKV(
                              label: "Items",
                              value: "${header.itemsCount}",
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: _MiniKV(
                              label: "Driver",
                              value: (header.driverName ?? "Unassigned"),
                              valueTone: header.driverName == null
                                  ? cs.onSurfaceVariant
                                  : cs.onSurface,
                            ),
                          ),
                          Expanded(
                            child: _MiniKV(
                              label: "Plate",
                              value: (header.vehiclePlateNo ?? "Unassigned"),
                              valueTone: header.vehiclePlateNo == null
                                  ? cs.onSurfaceVariant
                                  : cs.onSurface,
                            ),
                          ),
                        ],
                      ),
                      if (!isActionable) ...[
                        const SizedBox(height: 10),
                        Text(
                          "This request cannot be approved here because it is not in PENDING status.",
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                      if (header.status == _LogiStatus.rejected &&
                          (header.rejectReason ?? "").trim().isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          decoration: BoxDecoration(
                            color: cs.errorContainer,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: cs.error.withOpacity(0.25)),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.error_rounded, size: 18, color: cs.onErrorContainer),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  "Rejected: ${header.rejectReason}",
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: cs.onErrorContainer,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ],
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

  static Color _statusColor(_LogiStatus s, ColorScheme cs) {
    switch (s) {
      case _LogiStatus.pending:
        return cs.primary;
      case _LogiStatus.approved:
        return Colors.green;
      case _LogiStatus.rejected:
        return cs.error;
    }
  }
}

// =====================
// DETAIL SHEET
// =====================

class _LogisticsDetailSheet extends StatelessWidget {
  final _LogiHeader header;
  const _LogisticsDetailSheet({required this.header});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    // Static demo packages/items
    final packages = const [
      ("Delivery Receipt DR-22018", "8 carton(s)"),
      ("Invoice INV-99121", "3 box(es)"),
      ("Notes", "Handle with care"),
    ];

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
                          "Logistics ${header.refNo}",
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
                            _kv("Customer", header.customerName),
                            const SizedBox(height: 6),
                            _kv("Destination", header.destination),
                            const SizedBox(height: 6),
                            _kv("Requester", header.requestedBy),
                            const SizedBox(height: 6),
                            _kv("Created at", "${_fmtYmd(header.createdAt)} ${_fmtHm(header.createdAt)}"),
                            const SizedBox(height: 6),
                            _kv("Driver", header.driverName ?? "Unassigned"),
                            const SizedBox(height: 6),
                            _kv("Vehicle", header.vehiclePlateNo ?? "Unassigned"),
                            if ((header.notes ?? "").trim().isNotEmpty) ...[
                              const SizedBox(height: 6),
                              _kv("Notes", header.notes!.trim()),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        "Documents / Packages (${packages.length})",
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 8),
                      ...packages.map((p) {
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
                                p.$1,
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                p.$2,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: cs.onSurfaceVariant,
                                  fontWeight: FontWeight.w800,
                                ),
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
                          onPressed: () {},
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
                          onPressed: () {},
                          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
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

// =====================
// Shared small widgets
// =====================

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
              query.isEmpty ? "No logistics requests found." : "No results for '$query'.",
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
// Models (static)
// =====================

enum LogisticsStatus {
  all("All"),
  pending("Pending"),
  approved("Approved"),
  rejected("Rejected");

  final String label;
  const LogisticsStatus(this.label);
}

enum _LogiStatus { pending, approved, rejected }

extension on _LogiStatus {
  String get label => switch (this) {
        _LogiStatus.pending => "Pending",
        _LogiStatus.approved => "Approved",
        _LogiStatus.rejected => "Rejected",
      };
}

class _LogiHeader {
  final String refNo;
  final String customerName;
  final String destination;
  final String requestedBy;
  final DateTime createdAt;
  final int itemsCount;

  final _LogiStatus status;
  final String? rejectReason;

  final String? driverName;
  final String? vehiclePlateNo;
  final String? notes;

  const _LogiHeader({
    required this.refNo,
    required this.customerName,
    required this.destination,
    required this.requestedBy,
    required this.createdAt,
    required this.itemsCount,
    required this.status,
    this.rejectReason,
    this.driverName,
    this.vehiclePlateNo,
    this.notes,
  });
}

// =====================
// Utils (same helpers)
// =====================

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
