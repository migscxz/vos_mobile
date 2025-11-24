import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart'; // NEW
import '../../../core/theme/app_theme.dart' as core_theme;
import '../../../state/delivery_report/delivery_report_state.dart';
import '../../../state/data_providers.dart' show syncRepoProvider, deliveryReportProvider;

enum DRGroupMode { driver, plan }
final drGroupModeProvider = StateProvider<DRGroupMode>((_) => DRGroupMode.plan);

class DeliveryReportView extends ConsumerWidget {
  const DeliveryReportView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final grandTotal = ref.watch(deliveryGrandTotalProvider);
    final groupMode = ref.watch(drGroupModeProvider);
    final driversAsync = ref.watch(driversProvider);
    final from = ref.watch(drFromProvider);
    final to = ref.watch(drToProvider);
    final search = ref.watch(drSearchProvider);
    final driver = ref.watch(drDriverProvider);

    final width = MediaQuery.of(context).size.width;
    final compact = width < 390;

    return Column(
      children: [
        // Header
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 22),
          decoration: BoxDecoration(
            gradient: core_theme.AppTheme.primaryGradient,
            boxShadow: const [
              BoxShadow(
                color: Color(0x336B73FF),
                blurRadius: 24,
                offset: Offset(0, 10),
              )
            ],
            borderRadius: const BorderRadius.vertical(bottom: Radius.circular(24)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: const [
                  Expanded(
                    child: Text(
                      'Delivery Report',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.6,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: SegmentedButton<DRGroupMode>(
                      style: SegmentedButton.styleFrom(
                        foregroundColor: Colors.white,
                        selectedForegroundColor: Theme.of(context).colorScheme.primary,
                        backgroundColor: Colors.white.withOpacity(0.15),
                        side: BorderSide(color: Colors.white.withOpacity(0.4), width: 1.5),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      segments: const [
                        ButtonSegment(value: DRGroupMode.plan, label: Text('By Plan')),
                        ButtonSegment(value: DRGroupMode.driver, label: Text('By Driver')),
                      ],
                      selected: {groupMode},
                      onSelectionChanged: (s) => ref.read(drGroupModeProvider.notifier).state = s.first,
                    ),
                  ),
                  const SizedBox(width: 16),
                  if (!compact) _Chip(text: 'Total: ${currencyFmt.format(grandTotal)}'),
                ],
              ),
              const SizedBox(height: 16),
              if (compact)
                Row(
                  children: [
                    _PillButton(
                      icon: Icons.tune_rounded,
                      label: 'Filters',
                      onTap: () => _openFilterSheet(context, ref),
                    ),
                    const SizedBox(width: 12),
                    _Chip(text: 'Total: ${currencyFmt.format(grandTotal)}'),
                  ],
                )
              else
                _FilterBar(
                  from: from,
                  to: to,
                  driver: driver,
                  search: search,
                  driversAsync: driversAsync,
                  onPickDateRange: () => _pickDateRange(context, ref),
                  onDriverChanged: (v) => ref.read(drDriverProvider.notifier).state = (v?.isEmpty ?? true) ? null : v,
                  onSearchChanged: (s) => ref.read(drSearchProvider.notifier).state = s,
                ),
            ],
          ),
        ),

        // Body
        Expanded(
          child: Builder(builder: (context) {
            if (groupMode == DRGroupMode.driver) {
              final groupsAsync = ref.watch(deliveryGroupedProvider);
              return groupsAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('Error: $e')),
                data: (groups) {
                  if (groups.isEmpty) return const Center(child: Text('No records found'));

                  // Build analytics inputs
                  final mergedCustomerMap = <String, List<DeliveryRow>>{};
                  final mergedSupplier = <String, double>{};
                  double mergedSubtotal = 0;
                  final seenPlans = <String>{};
                  double mergedBudget = 0;

                  for (final g in groups) {
                    g.supplierTotals.forEach((k, v) {
                      mergedSupplier.update(k, (old) => old + v, ifAbsent: () => v);
                    });
                    mergedSubtotal += g.subtotal;
                    g.customerGroups.forEach((cust, cg) {
                      (mergedCustomerMap[cust] ??= []).addAll(cg.rows);
                    });
                    for (final r in g.rowsRaw) {
                      final doc = r.docNo.isNotEmpty ? r.docNo : r.invoiceNo;
                      if (doc.isNotEmpty && !seenPlans.contains(doc)) {
                        seenPlans.add(doc);
                        mergedBudget += r.totalBudget;
                      }
                    }
                  }
                  final mergedRows = mergedCustomerMap.values.expand((e) => e).toList();

                  return ListView(
                    padding: const EdgeInsets.all(20),
                    children: [
                      // --- ANALYTICS (Driver scope) ---
                      _AnalyticsSection(rows: mergedRows, supplierTotals: mergedSupplier),

                      const SizedBox(height: 16),
                      _DriverView(groups: groups),
                    ],
                  );
                },
              );
            } else {
              final plansAsync = ref.watch(deliveryByPlanProvider);
              return plansAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('Error: $e')),
                data: (plans) {
                  if (plans.isEmpty) return const Center(child: Text('No records found'));

                  // Aggregate for analytics
                  final supplierAgg = <String, double>{};
                  final allRows = <DeliveryRow>[];
                  for (final p in plans) {
                    p.supplierTotals.forEach((k, v) {
                      supplierAgg.update(k, (old) => old + v, ifAbsent: () => v);
                    });
                    for (final cg in p.customerGroups.values) {
                      allRows.addAll(cg.rows);
                    }
                  }

                  return ListView(
                    padding: const EdgeInsets.all(20),
                    children: [
                      // --- ANALYTICS (Plan scope) ---
                      _AnalyticsSection(rows: allRows, supplierTotals: supplierAgg),

                      const SizedBox(height: 16),
                      _PlanView(plans: plans),
                    ],
                  );
                },
              );
            }
          }),
        ),
      ],
    );
  }

  Future<void> _pickDateRange(BuildContext context, WidgetRef ref) async {
    final from = ref.read(drFromProvider);
    final to = ref.read(drToProvider);
    final now = DateTime.now();
    final initialRange = (from != null && to != null)
        ? DateTimeRange(start: from, end: to)
        : DateTimeRange(start: now.subtract(const Duration(days: 30)), end: now);
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: now.add(const Duration(days: 365)),
      initialDateRange: initialRange,
    );
    if (picked != null) {
      ref.read(drFromProvider.notifier).state = picked.start;
      ref.read(drToProvider.notifier).state = picked.end;
    }
  }

  void _openFilterSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => const _FilterSheet(),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// FILTER BAR
// ─────────────────────────────────────────────────────────────────────────────

class _FilterBar extends StatelessWidget {
  final DateTime? from;
  final DateTime? to;
  final String? driver;
  final String search;
  final AsyncValue<List<String>> driversAsync;
  final VoidCallback onPickDateRange;
  final ValueChanged<String?> onDriverChanged;
  final ValueChanged<String> onSearchChanged;

  const _FilterBar({
    required this.from,
    required this.to,
    required this.driver,
    required this.search,
    required this.driversAsync,
    required this.onPickDateRange,
    required this.onDriverChanged,
    required this.onSearchChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _PillButton(
            icon: Icons.calendar_today_rounded,
            label: (from == null || to == null)
                ? 'Date: All'
                : 'Date: ${dateFmt.format(from!)} – ${dateFmt.format(to!)}',
            onTap: onPickDateRange,
          ),
          const SizedBox(width: 12),
          driversAsync.when(
            loading: () => const _Chip(text: 'Drivers…'),
            error: (_, __) => const _Chip(text: 'Drivers (!)', danger: true),
            data: (drivers) => _DriverDropdown(
              value: (driver != null && drivers.contains(driver)) ? driver : null,
              items: drivers,
              onChanged: onDriverChanged,
            ),
          ),
          const SizedBox(width: 12),
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 200, maxWidth: 340),
            child: SizedBox(
              width: 240,
              child: TextField(
                decoration: const InputDecoration(
                  hintText: 'Search customer/invoice/doc…',
                  prefixIcon: Icon(Icons.search, size: 20),
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                ),
                onChanged: onSearchChanged,
                controller: TextEditingController(text: search)
                  ..selection = TextSelection.fromPosition(
                    TextPosition(offset: search.length),
                  ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// COMPONENTS
// ─────────────────────────────────────────────────────────────────────────────

class _DriverDropdown extends StatelessWidget {
  final String? value;
  final List<String> items;
  final ValueChanged<String?> onChanged;
  const _DriverDropdown({required this.value, required this.items, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 180, maxWidth: 260),
      child: DropdownButtonFormField<String>(
        value: value,
        isExpanded: true,
        menuMaxHeight: 320,
        items: [
          const DropdownMenuItem<String>(value: null, child: Text('All Drivers')),
          ...items.map((d) => DropdownMenuItem<String>(value: d, child: Text(d))),
        ],
        onChanged: onChanged,
        decoration: const InputDecoration(
          prefixIcon: Icon(Icons.person_outline, size: 20),
          hintText: 'Driver',
          isDense: true,
          contentPadding: EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        ),
      ),
    );
  }
}

class _PillButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _PillButton({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(.16),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withOpacity(.4), width: 1.5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 18),
            const SizedBox(width: 10),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String text;
  final bool danger;
  const _Chip({required this.text, this.danger = false});

  @override
  Widget build(BuildContext context) {
    final bg = danger ? Colors.red.withOpacity(.16) : Colors.white.withOpacity(.16);
    final bd = danger ? Colors.red.withOpacity(.45) : Colors.white.withOpacity(.4);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: bd, width: 1.5),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w600,
          fontSize: 14,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// FILTER SHEET
// ─────────────────────────────────────────────────────────────────────────────

class _FilterSheet extends ConsumerWidget {
  const _FilterSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final from = ref.watch(drFromProvider);
    final to = ref.watch(drToProvider);
    final driver = ref.watch(drDriverProvider);
    final search = ref.watch(drSearchProvider);
    final driversAsync = ref.watch(driversProvider);

    Future<void> pickDateRange() async {
      final initialRange = (from != null && to != null)
          ? DateTimeRange(start: from, end: to)
          : DateTimeRange(
        start: DateTime.now().subtract(const Duration(days: 30)),
        end: DateTime.now(),
      );
      final picked = await showDateRangePicker(
        context: context,
        firstDate: DateTime(2020),
        lastDate: DateTime.now().add(const Duration(days: 365)),
        initialDateRange: initialRange,
      );
      if (picked != null) {
        ref.read(drFromProvider.notifier).state = picked.start;
        ref.read(drToProvider.notifier).state = picked.end;
      }
    }

    return Padding(
      padding: EdgeInsets.fromLTRB(
        24,
        20,
        24,
        MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.calendar_today_rounded, size: 24),
            title: Text(
              (from == null || to == null)
                  ? 'Date: All'
                  : 'Date: ${dateFmt.format(from)} – ${dateFmt.format(to)}',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            trailing: FilledButton(
              onPressed: pickDateRange,
              child: const Text('Change'),
            ),
          ),
          const SizedBox(height: 16),
          driversAsync.when(
            loading: () => const Center(child: Text('Loading drivers…')),
            error: (e, _) => Center(child: Text('Drivers error: $e')),
            data: (drivers) => DropdownButtonFormField<String>(
              value: (driver != null && drivers.contains(driver)) ? driver : null,
              isExpanded: true,
              menuMaxHeight: 320,
              items: [
                const DropdownMenuItem<String>(value: null, child: Text('All Drivers')),
                ...drivers.map((d) => DropdownMenuItem<String>(value: d, child: Text(d))),
              ],
              onChanged: (v) => ref.read(drDriverProvider.notifier).state = (v?.isEmpty ?? true) ? null : v,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.person_outline, size: 20),
                labelText: 'Driver',
                hintText: 'Select driver',
                isDense: true,
              ),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            decoration: const InputDecoration(
              hintText: 'Search customer/invoice/doc…',
              labelText: 'Search',
              prefixIcon: Icon(Icons.search, size: 20),
            ),
            controller: TextEditingController(text: search),
            onChanged: (s) => ref.read(drSearchProvider.notifier).state = s,
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () {
                  ref.invalidate(drFromProvider);
                  ref.invalidate(drToProvider);
                  ref.invalidate(drDriverProvider);
                  ref.invalidate(drSearchProvider);
                  Navigator.pop(context);
                },
                child: const Text('Clear All'),
              ),
              const SizedBox(width: 12),
              FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Apply Filters'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// DELIVERY DETAIL SHEET
// ─────────────────────────────────────────────────────────────────────────────

class _DeliveryDetailSheet extends StatelessWidget {
  final DeliveryRow row;
  const _DeliveryDetailSheet({required this.row});

  @override
  Widget build(BuildContext context) {
    Widget item(String label, String value, {IconData? icon}) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (icon != null) ...[
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  icon,
                  size: 20,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(width: 16),
            ],
            SizedBox(
              width: 100,
              child: Text(
                label,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurface.withOpacity(.6),
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  letterSpacing: 0.2,
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                value,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.fromLTRB(
        24,
        20,
        24,
        MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Invoice ${row.invoiceNo}',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    fontSize: 22,
                    letterSpacing: -0.5,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                currencyFmt.format(row.total),
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  fontSize: 22,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            row.customer,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
              fontSize: 15,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 24),
          Container(height: 1, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.1)),
          const SizedBox(height: 24),
          item('Driver', row.driver, icon: Icons.badge_outlined),
          item('Seq', row.seq.toString(), icon: Icons.format_list_numbered),
          item('City/Town', row.city, icon: Icons.location_on_outlined),
          item('Supplier', row.supplier, icon: Icons.store_mall_directory_outlined),
          item('Doc No', row.docNo, icon: Icons.description_outlined),
          item('Invoice No', row.invoiceNo, icon: Icons.receipt_long_outlined),
          item('Invoice Date', row.invoiceDate == null ? '—' : dateFmt.format(row.invoiceDate!), icon: Icons.event_outlined),
          item('Vehicle', row.vehicle.isEmpty ? '—' : row.vehicle, icon: Icons.local_shipping_outlined),
          item('Post Status', row.postStatus.isEmpty ? '—' : row.postStatus, icon: Icons.check_circle_outline),
          item('Remarks', row.remarks.isEmpty ? '—' : row.remarks, icon: Icons.notes_outlined),
          const SizedBox(height: 20),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close, size: 18),
              label: const Text('Close'),
            ),
          ),
        ],
      ),
    );
  }
}

void _openDetailStatic(BuildContext context, DeliveryRow r) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => _DeliveryDetailSheet(row: r),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// ANALYTICS SECTION (NEW)
// ─────────────────────────────────────────────────────────────────────────────

class _AnalyticsSection extends StatefulWidget {
  final List<DeliveryRow> rows;
  final Map<String, double> supplierTotals;
  const _AnalyticsSection({required this.rows, required this.supplierTotals});

  @override
  State<_AnalyticsSection> createState() => _AnalyticsSectionState();
}

class _AnalyticsSectionState extends State<_AnalyticsSection> {
  bool _expanded = true;

  bool _isFulfilled(String raw) {
    final t = raw.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
    if (t.isEmpty) return false;
    const negs = ['not ', 'unfulfilled', 'undelivered', 'pending', 'open', 'cancel', 'void', 'return', 'failed', 'partial'];
    if (negs.any((n) => t.contains(n))) return false;
    const poss = ['delivered', 'fulfilled', 'cleared', 'completed', 'done', 'ok'];
    return poss.any((p) => t == p || t.startsWith('$p '));
  }

  @override
  Widget build(BuildContext context) {
    // Split fulfilled vs not
    int fulfilled = 0, notFulfilled = 0;
    for (final r in widget.rows) {
      _isFulfilled(r.postStatus) ? fulfilled++ : notFulfilled++;
    }

    // Daily totals
    final byDay = <DateTime, double>{};
    for (final r in widget.rows) {
      if (r.invoiceDate == null) continue;
      final d = DateTime(r.invoiceDate!.year, r.invoiceDate!.month, r.invoiceDate!.day);
      byDay.update(d, (old) => old + r.total, ifAbsent: () => r.total);
    }
    final daysSorted = byDay.keys.toList()..sort();
    final dayPoints = [
      for (var i = 0; i < daysSorted.length; i++)
        FlSpot(i.toDouble(), (byDay[daysSorted[i]] ?? 0).toDouble())
    ];

    // Supplier top N
    final supplier = Map<String, double>.from(widget.supplierTotals);
    final supplierSorted = supplier.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    const maxBars = 6;
    final top = supplierSorted.take(maxBars).toList();
    if (supplierSorted.length > maxBars) {
      final others = supplierSorted.skip(maxBars).fold<double>(0, (s, e) => s + e.value);
      top.add(MapEntry('Others', others));
    }

    return Card(
      elevation: 3,
      shadowColor: Colors.black.withOpacity(0.08),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            InkWell(
              onTap: () => setState(() => _expanded = !_expanded),
              child: Row(
                children: [
                  const Icon(Icons.insights, size: 20),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Analytics',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, letterSpacing: -.2),
                    ),
                  ),
                  Icon(_expanded ? Icons.expand_less : Icons.expand_more),
                ],
              ),
            ),
            AnimatedCrossFade(
              crossFadeState: _expanded ? CrossFadeState.showFirst : CrossFadeState.showSecond,
              duration: const Duration(milliseconds: 180),
              firstChild: Column(
                children: [
                  const SizedBox(height: 12),

                  // Row of 2 cards (Pie + Bar)
                  LayoutBuilder(
                    builder: (ctx, c) {
                      final isNarrow = c.maxWidth < 640;
                      return isNarrow
                          ? Column(
                        children: [
                          _MiniCard(
                            title: 'Fulfillment',
                            child: _FulfillmentPie(fulfilled: fulfilled, notFulfilled: notFulfilled),
                          ),
                          const SizedBox(height: 12),
                          _MiniCard(
                            title: 'Totals by Supplier',
                            child: _SupplierBars(entries: top),
                          ),
                        ],
                      )
                          : Row(
                        children: [
                          Expanded(
                            child: _MiniCard(
                              title: 'Fulfillment',
                              child: _FulfillmentPie(fulfilled: fulfilled, notFulfilled: notFulfilled),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _MiniCard(
                              title: 'Totals by Supplier',
                              child: _SupplierBars(entries: top),
                            ),
                          ),
                        ],
                      );
                    },
                  ),

                  const SizedBox(height: 12),

                  // Line
                  _MiniCard(
                    title: 'Daily Totals',
                    child: _DailyLine(points: dayPoints, labels: daysSorted.map(dateFmt.format).toList()),
                  ),
                ],
              ),
              secondChild: const SizedBox.shrink(),
            )
          ],
        ),
      ),
    );
  }
}

class _MiniCard extends StatelessWidget {
  final String title;
  final Widget child;
  const _MiniCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.08), width: 1.2),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Text(title, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(height: 180, child: child),
        ],
      ),
    );
  }
}

// Pie (Fulfillment) — FIXED: removed titlesData & gridData from PieChartData
class _FulfillmentPie extends StatelessWidget {
  final int fulfilled;
  final int notFulfilled;
  const _FulfillmentPie({required this.fulfilled, required this.notFulfilled});

  @override
  Widget build(BuildContext context) {
    final total = (fulfilled + notFulfilled).toDouble();
    final f = total == 0 ? 0.0 : fulfilled / total;
    final nf = total == 0 ? 0.0 : notFulfilled / total;

    return Stack(
      children: [
        PieChart(
          PieChartData(
            centerSpaceRadius: 36,
            sectionsSpace: 2,
            startDegreeOffset: -90,
            // NOTE: PieChartData does NOT support titlesData or gridData.
            borderData: FlBorderData(show: false),
            sections: [
              PieChartSectionData(
                value: f,
                title: '${(f * 100).round()}%',
                radius: 46,
                titleStyle: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
                color: Colors.green.shade600,
              ),
              PieChartSectionData(
                value: nf,
                title: '${(nf * 100).round()}%',
                radius: 46,
                titleStyle: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
                color: Colors.orange.shade600,
              ),
            ],
          ),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Wrap(
              alignment: WrapAlignment.center,
              spacing: 12,
              children: [
                _LegendDot(label: 'Fulfilled', color: Colors.green.shade600),
                _LegendDot(label: 'Not fulfilled', color: Colors.orange.shade600),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _LegendDot extends StatelessWidget {
  final String label;
  final Color color;
  const _LegendDot({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
      const SizedBox(width: 6),
      Text(label, style: Theme.of(context).textTheme.bodySmall),
    ]);
  }
}

// Bars (Suppliers)
class _SupplierBars extends StatelessWidget {
  final List<MapEntry<String, double>> entries;
  const _SupplierBars({required this.entries});

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return const Center(child: Text('No data'));
    }
    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        barTouchData: BarTouchData(enabled: false),
        titlesData: FlTitlesData(
          leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 40,
              getTitlesWidget: (v, meta) {
                final idx = v.toInt();
                if (idx < 0 || idx >= entries.length) return const SizedBox.shrink();
                final label = entries[idx].key;
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    maxLines: 2,
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                  ),
                );
              },
            ),
          ),
        ),
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        barGroups: [
          for (var i = 0; i < entries.length; i++)
            BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: entries[i].value,
                  width: 14,
                  borderRadius: BorderRadius.circular(6),
                  color: Theme.of(context).colorScheme.primary,
                ),
              ],
            ),
        ],
      ),
    );
  }
}
// Line (Daily totals)
class _DailyLine extends StatelessWidget {
  final List<FlSpot> points;
  final List<String> labels;
  const _DailyLine({required this.points, required this.labels});

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) return const Center(child: Text('No data'));
    return LineChart(
      LineChartData(
        minX: 0,
        maxX: points.length > 1 ? (points.length - 1).toDouble() : 1,
        lineTouchData: LineTouchData(enabled: false),
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 24,
              interval: (labels.length / 4).clamp(1, 4).toDouble(),
              getTitlesWidget: (v, meta) {
                final i = v.round();
                if (i < 0 || i >= labels.length) return const SizedBox.shrink();
                // Sparse labels for readability
                if (labels.length > 8 && i % ((labels.length ~/ 4).clamp(1, 4)) != 0) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(labels[i], style: const TextStyle(fontSize: 10)),
                );
              },
            ),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: points,
            isCurved: true,
            barWidth: 3,
            color: Theme.of(context).colorScheme.primary,
            dotData: const FlDotData(show: false),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PLAN VIEW
// ─────────────────────────────────────────────────────────────────────────────

class _PlanView extends StatelessWidget {
  final List<PlanGroup> plans;
  const _PlanView({required this.plans});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
      itemCount: plans.length,
      itemBuilder: (_, i) {
        final p = plans[i];
        return Card(
          margin: const EdgeInsets.only(bottom: 20),
          elevation: 3,
          shadowColor: Colors.black.withOpacity(0.08),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _PlanCardHeader(plan: p),
                const SizedBox(height: 24),
                Container(height: 1, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.1)),
                const SizedBox(height: 24),
                _GroupedInvoiceList(customerGroups: p.customerGroups),
                const SizedBox(height: 20),
                _CardFooter(
                  supplierTotals: p.supplierTotals,
                  subtotal: p.subtotal,
                  trips: p.trips,
                  helperName: (p.helperName.isEmpty) ? '—' : p.helperName,
                  totalBudget: p.totalBudget,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// DRIVER VIEW
// ─────────────────────────────────────────────────────────────────────────────

class _DriverView extends ConsumerWidget {
  final List<DriverGroup> groups;
  const _DriverView({required this.groups});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedDriver = ref.watch(drDriverProvider);

    final mergedCustomerMap = <String, List<DeliveryRow>>{};
    final mergedSupplier = <String, double>{};
    double mergedSubtotal = 0;
    final seenPlans = <String>{};
    double mergedBudget = 0;

    final iterable = (selectedDriver == null)
        ? groups
        : groups.where((g) => g.driver == selectedDriver);

    for (final g in iterable) {
      g.supplierTotals.forEach((k, v) {
        mergedSupplier.update(k, (old) => old + v, ifAbsent: () => v);
      });
      mergedSubtotal += g.subtotal;

      g.customerGroups.forEach((cust, cg) {
        (mergedCustomerMap[cust] ??= []).addAll(cg.rows);
      });

      for (final r in g.rowsRaw) {
        final doc = r.docNo.isNotEmpty ? r.docNo : r.invoiceNo;
        if (doc.isNotEmpty && !seenPlans.contains(doc)) {
          seenPlans.add(doc);
          mergedBudget += r.totalBudget;
        }
      }
    }

    final mergedCustomerGroups = mergedCustomerMap.map((k, v) => MapEntry(k, CustomerGroup(v)));
    final mergedTrips = mergedCustomerGroups.length;

    return Column(
      children: [
        Card(
          elevation: 3,
          shadowColor: Colors.black.withOpacity(0.08),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  selectedDriver ?? 'All Drivers',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    fontSize: 22,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 24),
                Container(height: 1, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.1)),
                const SizedBox(height: 24),
                _GroupedInvoiceList(customerGroups: mergedCustomerGroups),
                const SizedBox(height: 20),
                _CardFooter(
                  supplierTotals: mergedSupplier,
                  subtotal: mergedSubtotal,
                  trips: mergedTrips,
                  helperName: '—',
                  totalBudget: mergedBudget,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PLAN CARD HEADER + STATUS BAR (unchanged logic)
// ─────────────────────────────────────────────────────────────────────────────

class _PlanCardHeader extends StatelessWidget {
  final PlanGroup plan;
  const _PlanCardHeader({required this.plan});

  String _norm(String s) => s.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();

  bool _isFulfilled(String raw) {
    final t = _norm(raw);
    if (t.isEmpty) return false;
    const negs = ['not ', 'unfulfilled', 'undelivered', 'pending', 'open', 'cancel', 'void', 'return', 'failed', 'partial'];
    if (negs.any((n) => t.contains(n))) return false;
    const poss = ['delivered', 'fulfilled', 'cleared', 'completed', 'done', 'ok'];
    return poss.any((p) => t == p || t.startsWith('$p '));
  }

  (int f, int nf) _count() {
    var f = 0, nf = 0;
    for (final cg in plan.customerGroups.values) {
      for (final r in cg.rows) _isFulfilled(r.postStatus) ? f++ : nf++;
    }
    return (f, nf);
  }

  int _pct(int part, int total) => total <= 0 ? 0 : ((part * 100) / total).round();

  Widget _infoRow(BuildContext ctx, String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 90,
          child: Text(
            label,
            style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
              color: Theme.of(ctx).colorScheme.onSurface.withOpacity(0.6),
              fontSize: 14,
              fontWeight: FontWeight.w600,
              height: 1.5,
              letterSpacing: 0.2,
            ),
          ),
        ),
        const SizedBox(width: 20),
        Expanded(
          child: Text(
            value,
            style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
              fontSize: 14,
              height: 1.5,
              color: Theme.of(ctx).colorScheme.onSurface.withOpacity(0.9),
            ),
          ),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final (fCnt, nfCnt) = _count();
    final tot = fCnt + nfCnt;
    final fPct = _pct(fCnt, tot);
    final nfPct = _pct(nfCnt, tot);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                plan.docNo,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  fontSize: 22,
                  letterSpacing: -0.5,
                  height: 1.2,
                ),
              ),
            ),
            if (plan.ccn.trim().isNotEmpty) ...[
              const SizedBox(width: 20),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.primary.withOpacity(0.25),
                    width: 1.5,
                  ),
                ),
                child: Text(
                  plan.ccn,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: Theme.of(context).colorScheme.primary,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 24),
        _StatusBar(
          fulfilledCount: fCnt,
          notFulfilledCount: nfCnt,
          fulfilledPercent: fPct,
          notFulfilledPercent: nfPct,
        ),
        const SizedBox(height: 28),
        if (plan.vehicle.isNotEmpty) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.5),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.1),
                width: 1.5,
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.local_shipping_outlined, size: 22, color: Theme.of(context).colorScheme.primary),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    plan.vehicle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                      color: Theme.of(context).colorScheme.onSurface.withOpacity(0.9),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
        ],
        _infoRow(context, 'Driver', plan.driver.isEmpty ? '—' : plan.driver),
        _infoRow(
          context,
          'Dispatch',
          plan.timeOfDispatch == null ? '—' : '${dateFmt.format(plan.timeOfDispatch!)} • ${timeFmt.format(plan.timeOfDispatch!)}',
        ),
        _infoRow(
          context,
          'Arrival',
          plan.timeOfArrival == null ? '—' : '${dateFmt.format(plan.timeOfArrival!)} • ${timeFmt.format(plan.timeOfArrival!)}',
        ),
      ],
    );
  }
}

class _StatusBar extends StatelessWidget {
  final int fulfilledCount;
  final int notFulfilledCount;
  final int fulfilledPercent;
  final int notFulfilledPercent;

  const _StatusBar({
    required this.fulfilledCount,
    required this.notFulfilledCount,
    required this.fulfilledPercent,
    required this.notFulfilledPercent,
  });

  @override
  Widget build(BuildContext context) {
    final total = fulfilledCount + notFulfilledCount;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 24,
          runSpacing: 14,
          children: [
            _LegendItem(
              color: Colors.green.shade600,
              label: 'Fulfilled',
              count: fulfilledCount,
              percent: fulfilledPercent,
            ),
            _LegendItem(
              color: Colors.orange.shade600,
              label: 'Not fulfilled',
              count: notFulfilledCount,
              percent: notFulfilledPercent,
            ),
          ],
        ),
        const SizedBox(height: 16),
        Container(
          height: 16,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.08),
          ),
          child: total > 0
              ? ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Row(
              children: [
                if (fulfilledCount > 0)
                  Expanded(
                    flex: fulfilledCount,
                    child: Container(color: Colors.green.shade600),
                  ),
                if (notFulfilledCount > 0)
                  Expanded(
                    flex: notFulfilledCount,
                    child: Container(color: Colors.orange.shade600),
                  ),
              ],
            ),
          )
              : null,
        ),
      ],
    );
  }
}

class _LegendItem extends StatelessWidget {
  final Color color;
  final String label;
  final int count;
  final int percent;

  const _LegendItem({
    required this.color,
    required this.label,
    required this.count,
    required this.percent,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 14, height: 14, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 10),
        Text(
          label,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            fontSize: 14,
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '$count',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            fontSize: 14,
            color: color,
            fontWeight: FontWeight.w700,
          ),
        ),
        Text(
          ' ($percent%)',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            fontSize: 13,
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.55),
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// GROUPED INVOICE LIST + FOOTER (unchanged)
// ─────────────────────────────────────────────────────────────────────────────

class _GroupedInvoiceList extends StatelessWidget {
  final Map<String, CustomerGroup> customerGroups;
  const _GroupedInvoiceList({required this.customerGroups});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: customerGroups.entries.map((entry) {
        final customerName = entry.key;
        final customerGroup = entry.value;
        return Padding(
          padding: const EdgeInsets.only(bottom: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        customerName,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                          letterSpacing: 0.1,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      currencyFmt.format(customerGroup.subtotal),
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.only(left: 16),
                child: Column(
                  children: customerGroup.rows.map((r) => _InvoiceRow(row: r)).toList(),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

class _InvoiceRow extends StatelessWidget {
  final DeliveryRow row;
  const _InvoiceRow({required this.row});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => _openDetailStatic(context, row),
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    row.invoiceNo,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  if (row.postStatus.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        '(${row.postStatus})',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontStyle: FontStyle.italic,
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.55),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Text(
              currencyFmt.format(row.total),
              textAlign: TextAlign.right,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CardFooter extends StatelessWidget {
  final Map<String, double> supplierTotals;
  final double subtotal;
  final int trips;
  final String helperName;
  final double totalBudget;

  const _CardFooter({
    required this.supplierTotals,
    required this.subtotal,
    required this.trips,
    required this.helperName,
    required this.totalBudget,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(height: 1, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.1)),
        const SizedBox(height: 20),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // LEFT
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _footerLine(context, 'Trips', '$trips'),
                  const SizedBox(height: 10),
                  _footerLine(context, 'Helper', helperName.isEmpty ? '—' : helperName),
                  const SizedBox(height: 10),
                  _footerLine(context, 'Budget', currencyFmt.format(totalBudget)),
                ],
              ),
            ),
            const SizedBox(width: 24),
            // RIGHT
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  ...supplierTotals.entries.map(
                        (e) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        '${e.key} = ${currencyFmt.format(e.value)}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Total',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      letterSpacing: 0.3,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    currencyFmt.format(subtotal),
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      fontSize: 22,
                      color: Theme.of(context).colorScheme.primary,
                      letterSpacing: -0.5,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _footerLine(BuildContext context, String label, String value) {
    return Row(
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            fontSize: 13,
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.left,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ),
      ],
    );
  }
}
