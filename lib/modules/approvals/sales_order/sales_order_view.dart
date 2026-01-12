import "dart:async";
import "package:flutter/material.dart";

class SalesOrderApprovalView extends StatefulWidget {
  const SalesOrderApprovalView({super.key});

  @override
  State<SalesOrderApprovalView> createState() => _SalesOrderApprovalViewState();
}

class _SalesOrderApprovalViewState extends State<SalesOrderApprovalView> {
  final TextEditingController _searchCtrl = TextEditingController();
  Timer? _debounce;

  SalesOrderStatus _selectedStatus = SalesOrderStatus.all;
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
    final selected = await showModalBottomSheet<SalesOrderStatus>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        final visible = SalesOrderStatus.values.toList();

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
              ...visible.map((s) {
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

  bool _matchesStatus(_SOHeader o, SalesOrderStatus filter) {
    if (filter == SalesOrderStatus.all) return true;
    if (filter == SalesOrderStatus.pending) return o.status == _SOStatus.pending;
    if (filter == SalesOrderStatus.approved) return o.status == _SOStatus.approved;
    if (filter == SalesOrderStatus.rejected) return o.status == _SOStatus.rejected;
    return true;
  }

  bool _matchesQuery(_SOHeader o, String qLower) {
    if (qLower.isEmpty) return true;
    final hay = <String>[
      o.soNo,
      o.customerName,
      o.requestedBy,
    ].join(" ").toLowerCase();
    return hay.contains(qLower);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    // Static demo data
    final orders = <_SOHeader>[
      _SOHeader(
        soNo: "SO-100245",
        customerName: "ACME Trading",
        requestedBy: "Juan Dela Cruz",
        createdAt: DateTime.now().subtract(const Duration(hours: 2)),
        totalAmount: 152340.50,
        status: _SOStatus.pending,
        itemsCount: 6,
      ),
      _SOHeader(
        soNo: "SO-100244",
        customerName: "Murex Lab Supplies",
        requestedBy: "Maria Cruz",
        createdAt: DateTime.now().subtract(const Duration(days: 1, hours: 1)),
        totalAmount: 49850.00,
        status: _SOStatus.pending,
        itemsCount: 3,
      ),
      _SOHeader(
        soNo: "SO-100243",
        customerName: "Vertex Operations",
        requestedBy: "Mark Santos",
        createdAt: DateTime.now().subtract(const Duration(days: 2)),
        totalAmount: 8899.75,
        status: _SOStatus.approved,
        itemsCount: 2,
      ),
      _SOHeader(
        soNo: "SO-100242",
        customerName: "Alpha Medical",
        requestedBy: "Jake R.",
        createdAt: DateTime.now().subtract(const Duration(days: 3, hours: 4)),
        totalAmount: 210000.00,
        status: _SOStatus.rejected,
        itemsCount: 4,
        rejectReason: "Invalid price type / missing approval.",
      ),
    ];

    // Filter logic matches Stock Transfer behavior:
    // - If query is not empty: show query matches (ignore status filter)
    // - If query empty: apply status filter
    final qLower = _query.toLowerCase();
    final filtered = orders.where((o) {
      final matchesQuery = _matchesQuery(o, qLower);
      final matchesStatus = _matchesStatus(o, _selectedStatus);
      if (_query.isNotEmpty) return matchesQuery;
      return matchesStatus;
    }).toList();

    // Group by date (same as Stock Transfer)
    final groups = <String, List<_SOHeader>>{};
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
              "Sales Orders",
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
          // Search (same style)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: SearchBar(
              controller: _searchCtrl,
              hintText: "Search SO #, customer, requester...",
              onChanged: _onSearchChanged,
              leading: const Icon(Icons.search),
              elevation: WidgetStateProperty.all(0),
              backgroundColor: WidgetStateProperty.all(cs.surfaceContainerHigh),
              shape: WidgetStateProperty.all(
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),

          // Filter row (same pattern as Stock Transfer)
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
                  "${filtered.length} orders",
                  style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),

          const SizedBox(height: 4),

          // List (date grouped like Stock Transfer)
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
                          // Like Stock Transfer: only allow action for Pending
                          if (o.status != _SOStatus.pending) return;
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

  void _openStaticDetail(BuildContext context, _SOHeader header) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _SalesOrderDetailSheet(header: header),
    );
  }
}

// =====================
// UI: DATE GROUP
// =====================

class _DateGroup extends StatelessWidget {
  final String dateKey;
  final List<_SOHeader> rows;
  final ValueChanged<_SOHeader> onTapRow;

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
            child: _SalesOrderHeaderCard(
              header: o,
              onTap: () => onTapRow(o),
            ),
          ),
        ),
      ],
    );
  }
}

// =====================
// UI: HEADER CARD (matches Stock Transfer card style)
// =====================

class _SalesOrderHeaderCard extends StatelessWidget {
  final _SOHeader header;
  final VoidCallback onTap;

  const _SalesOrderHeaderCard({
    required this.header,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final statusColor = _statusColor(header.status, cs);
    final isActionable = header.status == _SOStatus.pending;

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
                              header.soNo,
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
                          Icon(Icons.person_rounded, size: 16, color: cs.primary),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              "Requester: ${header.requestedBy}",
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
                              label: "Created",
                              value: "${_fmtYmd(header.createdAt)} ${_fmtHm(header.createdAt)}",
                            ),
                          ),
                          Expanded(
                            child: _MiniKV(
                              label: "Items",
                              value: "${header.itemsCount}",
                            ),
                          ),
                          Expanded(
                            child: _MiniKV(
                              label: "Total",
                              value: _fmtMoney(header.totalAmount),
                              valueTone: cs.primary,
                            ),
                          ),
                        ],
                      ),
                      if (!isActionable) ...[
                        const SizedBox(height: 10),
                        Text(
                          "This sales order cannot be approved here because it is not in PENDING status.",
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                      if (header.status == _SOStatus.rejected &&
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

  static Color _statusColor(_SOStatus s, ColorScheme cs) {
    switch (s) {
      case _SOStatus.pending:
        return cs.primary;
      case _SOStatus.approved:
        return Colors.green;
      case _SOStatus.rejected:
        return cs.error;
    }
  }
}

// =====================
// DETAIL SHEET (matches Stock Transfer sheet look)
// =====================

class _SalesOrderDetailSheet extends StatelessWidget {
  final _SOHeader header;
  const _SalesOrderDetailSheet({required this.header});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final items = const [
      ("Hemodialysis Kit", 2, 45000.00),
      ("Syringe 10ml", 50, 12.50),
      ("IV Set", 10, 85.00),
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
                          "Sales Order ${header.soNo}",
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
                            _kv("Requester", header.requestedBy),
                            const SizedBox(height: 6),
                            _kv(
                              "Created at",
                              "${_fmtYmd(header.createdAt)} ${_fmtHm(header.createdAt)}",
                            ),
                            const SizedBox(height: 6),
                            _kv("Total", _fmtMoney(header.totalAmount)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        "Items (${items.length})",
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ...items.map((x) {
                        final name = x.$1;
                        final qty = x.$2;
                        final price = x.$3;

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
                                name,
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                "Qty: $qty • Unit: ${_fmtMoney(price)}",
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

// =====================
// Shared small widgets (same as Stock Transfer style)
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
              query.isEmpty ? "No sales orders found." : "No results for '$query'.",
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

enum SalesOrderStatus {
  all("All"),
  pending("Pending"),
  approved("Approved"),
  rejected("Rejected");

  final String label;
  const SalesOrderStatus(this.label);
}

enum _SOStatus { pending, approved, rejected }

extension on _SOStatus {
  String get label => switch (this) {
        _SOStatus.pending => "Pending",
        _SOStatus.approved => "Approved",
        _SOStatus.rejected => "Rejected",
      };
}

class _SOHeader {
  final String soNo;
  final String customerName;
  final String requestedBy;
  final DateTime createdAt;
  final double totalAmount;
  final _SOStatus status;
  final int itemsCount;
  final String? rejectReason;

  const _SOHeader({
    required this.soNo,
    required this.customerName,
    required this.requestedBy,
    required this.createdAt,
    required this.totalAmount,
    required this.status,
    required this.itemsCount,
    this.rejectReason,
  });
}

// =====================
// Utils (same date format helpers as Stock Transfer)
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

String _fmtMoney(double v) {
  final s = v.toStringAsFixed(2);
  return "₱ $s";
}
