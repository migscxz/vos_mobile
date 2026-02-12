import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:getwidget/getwidget.dart';

import 'package:vos_mobile/state/assets_and_equipments/assets_and_equipments_providers.dart';

class AssetsAndEquipmentsView extends ConsumerStatefulWidget {
  const AssetsAndEquipmentsView({super.key});

  @override
  ConsumerState<AssetsAndEquipmentsView> createState() =>
      _AssetsAndEquipmentsViewState();
}

class _AssetsAndEquipmentsViewState
    extends ConsumerState<AssetsAndEquipmentsView> {
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rowsAsync = ref.watch(assetsRowsProvider);
    final metricsAsync = ref.watch(assetsMetricsProvider);
    final depsAsync = ref.watch(assetsDepartmentsProvider);
    final condsAsync = ref.watch(assetsConditionsProvider);
    final filters = ref.watch(assetsFiltersProvider);

    final isLoading = rowsAsync.isLoading ||
        metricsAsync.isLoading ||
        depsAsync.isLoading ||
        condsAsync.isLoading;

    final error = rowsAsync.error ??
        metricsAsync.error ??
        depsAsync.error ??
        condsAsync.error;

    final rows = rowsAsync.value ?? const [];
    final metrics = metricsAsync.value;
    final departments = depsAsync.value ?? const ['All Departments'];
    final conditions = condsAsync.value ?? const ['All Conditions'];

    if (filters.search.isNotEmpty && _searchCtrl.text != filters.search) {
      _searchCtrl.text = filters.search;
      _searchCtrl.selection = TextSelection.fromPosition(
        TextPosition(offset: _searchCtrl.text.length),
      );
    }

    final insights = _computeInsights(rows, filters.period);

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: GFAppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        title: const Text(
          'Assets & Equipment',
          style: TextStyle(
            color: Color(0xFF2C3E50),
            fontWeight: FontWeight.w800,
            fontSize: 20,
          ),
        ),
        actions: [
          GFIconButton(
            icon: const Icon(Icons.refresh, color: Color(0xFF2C3E50)),
            onPressed: () {
              ref.invalidate(assetsAllRowsProvider);
              ref.invalidate(assetsRowsProvider);
              ref.invalidate(assetsMetricsProvider);
              ref.invalidate(assetsDepartmentsProvider);
              ref.invalidate(assetsConditionsProvider);
            },
            type: GFButtonType.transparent,
          ),
          GFIconButton(
            icon: const Icon(Icons.download, color: Color(0xFF2C3E50)),
            onPressed: () {
              // TODO: export to CSV/PDF
            },
            type: GFButtonType.transparent,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Builder(
          builder: (_) {
            if (error != null) {
              return _buildErrorState(
                context,
                error.toString(),
                onRetry: () {
                  ref.invalidate(assetsAllRowsProvider);
                  ref.invalidate(assetsRowsProvider);
                  ref.invalidate(assetsMetricsProvider);
                  ref.invalidate(assetsDepartmentsProvider);
                  ref.invalidate(assetsConditionsProvider);
                },
              );
            }

            if (isLoading) {
              return const Center(
                child: GFLoader(type: GFLoaderType.circle),
              );
            }

            return CustomScrollView(
              physics: const BouncingScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(
                  child: _buildHeaderSurface(
                    context: context,
                    totalAssets: rows.length,
                    totalOriginalCost: insights.totalOriginalCost,
                    totalCurrentValue: insights.totalCurrentValue,
                    avgDepPct: insights.avgDepPct,
                    metricsValue: metrics?.currentTotalValue,
                    periodLabel: filters.period.label,
                  ),
                ),

                // Filters
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  sliver: SliverToBoxAdapter(
                    child: _buildFiltersCard(
                      context: context,
                      departments: departments,
                      conditions: conditions,
                      filters: filters,
                    ),
                  ),
                ),

                // Depreciation Period (fixed: compact, wrap, no duplicates)
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  sliver: SliverToBoxAdapter(
                    child: _buildDepreciationPeriodCard(filters),
                  ),
                ),

                // Insights / Charts
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  sliver: SliverToBoxAdapter(
                    child: _buildInsightsSection(context, insights, filters.period),
                  ),
                ),

                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
                  sliver: SliverToBoxAdapter(
                    child: _buildResultsHeader(
                      context,
                      rows.length,
                      onClear: () {
                        ref.read(assetsFiltersProvider.notifier).setSearch("");
                        ref.read(assetsFiltersProvider.notifier).setDepartment("All Departments");
                        ref.read(assetsFiltersProvider.notifier).setCondition("All Conditions");
                        // Keep period as-is (usually intended). If you want reset:
                        // ref.read(assetsFiltersProvider.notifier).setPeriod(DepreciationPeriod.month);
                        _searchCtrl.clear();
                      },
                    ),
                  ),
                ),

                // List
                if (rows.isEmpty)
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
                    sliver: SliverToBoxAdapter(child: _buildEmptyState()),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                            (context, index) {
                          final a = rows[index];

                          final currentValue = _currentValue(
                            total: a.total,
                            depreciationYear: a.depreciationValueYear,
                            period: filters.period,
                          );
                          final depPct = a.total <= 0
                              ? 0.0
                              : ((a.total - currentValue) / a.total * 100.0);

                          return _buildAssetCard(
                            context: context,
                            itemImage: a.itemImage,
                            itemType: a.itemType,
                            rfidCode: a.rfidCode,
                            employee: a.employee,
                            condition: a.condition,
                            department: a.department,
                            quantity: a.quantity,
                            totalCost: a.total,
                            currentValue: currentValue,
                            lifeSpanYears: a.lifeSpan,
                            depreciationYear: a.depreciationValueYear,
                            depPct: depPct,
                            dateAcquired: a.dateAcquired,
                            encoder: a.encoder,
                            periodLabel: filters.period.label,
                          );
                        },
                        childCount: rows.length,
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),

      // ✅ Removed floatingActionButton (no feature)
    );
  }

  // ---------------------------
  // Header / Summary Surface
  // ---------------------------

  Widget _buildHeaderSurface({
    required BuildContext context,
    required int totalAssets,
    required double totalOriginalCost,
    required double totalCurrentValue,
    required double avgDepPct,
    required double? metricsValue,
    required String periodLabel,
  }) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFFFFFFFF), Color(0xFFF2F7FF)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle(
              "Overview",
              subtitle: "Quick metrics and insights for your assets",
              icon: Icons.auto_graph,
              iconColor: const Color(0xFF3498DB),
            ),
            const SizedBox(height: 12),
            _buildSummaryGrid(
              context,
              totalAssets: totalAssets,
              totalOriginalCost: totalOriginalCost,
              totalCurrentValue: totalCurrentValue,
              avgDepPct: avgDepPct,
              metricsValue: metricsValue,
              periodLabel: periodLabel,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryGrid(
      BuildContext context, {
        required int totalAssets,
        required double totalOriginalCost,
        required double totalCurrentValue,
        required double avgDepPct,
        required double? metricsValue,
        required String periodLabel,
      }) {
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        final cols = w >= 980 ? 4 : (w >= 560 ? 2 : 1);
        const gap = 12.0;
        final itemW = cols == 1 ? w : (w - (gap * (cols - 1))) / cols;

        final cards = <Widget>[
          _buildSummaryCard(
            title: 'Total Assets',
            value: '$totalAssets',
            icon: Icons.inventory_2,
            color: const Color(0xFF3498DB),
            sub: "items",
          ),
          _buildSummaryCard(
            title: 'Original Cost',
            value: '₱${_formatCompact(totalOriginalCost)}',
            icon: Icons.receipt_long,
            color: const Color(0xFF6C5CE7),
            sub: "sum",
          ),
          _buildSummaryCard(
            title: 'Current Value',
            value: '₱${_formatCompact(totalCurrentValue)}',
            icon: Icons.account_balance_wallet,
            color: const Color(0xFF27AE60),
            sub: periodLabel,
          ),
          _buildSummaryCard(
            title: 'Avg Depreciation',
            value: '${avgDepPct.toStringAsFixed(1)}%',
            icon: Icons.trending_down,
            color: const Color(0xFFF39C12),
            sub: "ratio",
          ),
        ];

        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: cards.map((card) => SizedBox(width: itemW, child: card)).toList(),
        );
      },
    );
  }

  Widget _sectionTitle(String title,
      {String? subtitle, required IconData icon, required Color iconColor}) {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: iconColor.withOpacity(0.12),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: iconColor.withOpacity(0.25)),
          ),
          child: Icon(icon, color: iconColor, size: 20),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF2C3E50),
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  // ---------------------------
  // Filters
  // ---------------------------

  Widget _buildFiltersCard({
    required BuildContext context,
    required List<String> departments,
    required List<String> conditions,
    required dynamic filters,
  }) {
    return GFCard(
      elevation: 0,
      margin: EdgeInsets.zero,
      padding: EdgeInsets.zero,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey[200]!, width: 1),
      ),
      content: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _inlineHeader("Filters", Icons.tune, const Color(0xFF2D9CDB)),
            const SizedBox(height: 12),

            // Search
            TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: 'Search assets...',
                hintStyle: TextStyle(
                  color: Colors.grey[400],
                  fontSize: 14,
                ),
                prefixIcon: Icon(Icons.search, size: 20, color: Colors.grey[600]),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey[300]!),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey[300]!),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(
                    color: Color(0xFF3498DB),
                    width: 2,
                  ),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                filled: true,
                fillColor: const Color(0xFFF8F9FA),
              ),
              onChanged: (v) =>
                  ref.read(assetsFiltersProvider.notifier).setSearch(v),
            ),
            const SizedBox(height: 12),

            // Dropdowns responsive (row on wide, stack on narrow)
            LayoutBuilder(
              builder: (context, c) {
                final narrow = c.maxWidth < 520;

                final dept = _buildDropdown(
                  value: filters.department,
                  items: departments,
                  hint: 'Department',
                  icon: Icons.business,
                  onChanged: (v) {
                    if (v != null) {
                      ref.read(assetsFiltersProvider.notifier).setDepartment(v);
                    }
                  },
                );

                final cond = _buildDropdown(
                  value: filters.condition,
                  items: conditions,
                  hint: 'Condition',
                  icon: Icons.verified_outlined,
                  onChanged: (v) {
                    if (v != null) {
                      ref.read(assetsFiltersProvider.notifier).setCondition(v);
                    }
                  },
                );

                if (narrow) {
                  return Column(
                    children: [
                      dept,
                      const SizedBox(height: 10),
                      cond,
                    ],
                  );
                }

                return Row(
                  children: [
                    Expanded(child: dept),
                    const SizedBox(width: 12),
                    Expanded(child: cond),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _inlineHeader(String title, IconData icon, Color color) {
    return Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 14,
              color: Color(0xFF2C3E50),
            ),
          ),
        ),
      ],
    );
  }

  // ---------------------------
  // Depreciation Period (FIXED)
  // ---------------------------

  Widget _buildDepreciationPeriodCard(dynamic filters) {
    final items = DepreciationPeriod.values;

    return GFCard(
      elevation: 0,
      margin: EdgeInsets.zero,
      padding: EdgeInsets.zero,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey[200]!, width: 1),
      ),
      content: Padding(
        padding: const EdgeInsets.all(14),
        child: LayoutBuilder(
          builder: (context, c) {
            final wide = c.maxWidth >= 680;

            final chips = Wrap(
              spacing: 8,
              runSpacing: 8,
              children: items.map((p) {
                final selected = filters.period == p;
                return ChoiceChip(
                  label: Text(p.label),
                  selected: selected,
                  onSelected: (_) {
                    ref.read(assetsFiltersProvider.notifier).setPeriod(p);
                  },
                  selectedColor: const Color(0xFF3498DB),
                  backgroundColor: const Color(0xFFF2F4F7),
                  labelStyle: TextStyle(
                    color: selected ? Colors.white : const Color(0xFF2C3E50),
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  shape: StadiumBorder(
                    side: BorderSide(
                      color: selected
                          ? const Color(0xFF3498DB)
                          : Colors.grey[300]!,
                    ),
                  ),
                );
              }).toList(),
            );

            final header = _inlineHeader(
              "Depreciation Period",
              Icons.date_range,
              const Color(0xFF6C5CE7),
            );

            if (!wide) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  header,
                  const SizedBox(height: 10),
                  chips,
                ],
              );
            }

            // wide: label on left, chips on right
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: 190, child: header),
                const SizedBox(width: 12),
                Expanded(child: chips),
              ],
            );
          },
        ),
      ),
    );
  }

  // ---------------------------
  // Insights / Charts (NO extra deps)
  // ---------------------------

  Widget _buildInsightsSection(
      BuildContext context,
      _AssetsInsights insights,
      DepreciationPeriod period,
      ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(
          "Insights",
          subtitle: "Visual summary based on current filters",
          icon: Icons.insights,
          iconColor: const Color(0xFF27AE60),
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, c) {
            final w = c.maxWidth;
            final cols = w >= 980 ? 3 : (w >= 620 ? 2 : 1);
            const gap = 12.0;
            final itemW = cols == 1 ? w : (w - (gap * (cols - 1))) / cols;

            final conditionSegments = insights.conditionCounts.entries
                .where((e) => e.value > 0)
                .toList()
              ..sort((a, b) => b.value.compareTo(a.value));

            final donutSegments = <_ChartSegment>[];
            final palette = [
              const Color(0xFF3498DB),
              const Color(0xFF27AE60),
              const Color(0xFFF39C12),
              const Color(0xFFE74C3C),
              const Color(0xFF6C5CE7),
              const Color(0xFF00B894),
              const Color(0xFF0984E3),
            ];

            for (var i = 0; i < conditionSegments.length; i++) {
              donutSegments.add(
                _ChartSegment(
                  label: conditionSegments[i].key.isEmpty ? "Unknown" : conditionSegments[i].key,
                  value: conditionSegments[i].value.toDouble(),
                  color: palette[i % palette.length],
                ),
              );
            }

            final topDepts = insights.departmentCost.entries.toList()
              ..sort((a, b) => b.value.compareTo(a.value));
            final deptBars = topDepts.take(5).map((e) {
              return _BarDatum(
                label: _shortLabel(e.key, 6),
                value: e.value,
                color: const Color(0xFF6C5CE7),
                fullLabel: e.key,
              );
            }).toList();

            final depBars = insights.depBuckets.entries.map((e) {
              return _BarDatum(
                label: e.key,
                value: e.value.toDouble(),
                color: const Color(0xFF3498DB),
                fullLabel: e.key,
              );
            }).toList();

            final cards = <Widget>[
              _insightCard(
                title: "Condition Mix",
                subtitle: "Count by condition",
                icon: Icons.verified,
                iconColor: const Color(0xFF27AE60),
                child: Row(
                  children: [
                    SizedBox(
                      width: 110,
                      height: 110,
                      child: _MiniDonutChart(
                        segments: donutSegments.isEmpty
                            ? [const _ChartSegment(label: "None", value: 1, color: Color(0xFFB2BEC3))]
                            : donutSegments,
                        centerText: "${insights.totalAssets}",
                        centerSubtext: "assets",
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _LegendList(
                        segments: donutSegments.take(4).toList(),
                        emptyText: "No condition data",
                      ),
                    ),
                  ],
                ),
              ),
              _insightCard(
                title: "Depreciation Buckets",
                subtitle: "Count by % range (${"${period.label}"})",
                icon: Icons.trending_down,
                iconColor: const Color(0xFFF39C12),
                child: SizedBox(
                  height: 120,
                  child: _MiniBarChart(
                    data: depBars.isEmpty
                        ? [const _BarDatum(label: "-", value: 0, color: Color(0xFFB2BEC3), fullLabel: "-")]
                        : depBars,
                    valueFormatter: (v) => v.toStringAsFixed(0),
                  ),
                ),
              ),
              _insightCard(
                title: "Top Departments",
                subtitle: "By original cost",
                icon: Icons.apartment,
                iconColor: const Color(0xFF6C5CE7),
                child: SizedBox(
                  height: 120,
                  child: _MiniBarChart(
                    data: deptBars.isEmpty
                        ? [const _BarDatum(label: "-", value: 0, color: Color(0xFFB2BEC3), fullLabel: "-")]
                        : deptBars,
                    valueFormatter: (v) => _formatCompact(v),
                  ),
                ),
              ),
            ];

            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: cards.map((card) => SizedBox(width: itemW, child: card)).toList(),
            );
          },
        ),
      ],
    );
  }

  Widget _insightCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color iconColor,
    required Widget child,
  }) {
    return GFCard(
      elevation: 0,
      margin: EdgeInsets.zero,
      padding: EdgeInsets.zero,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey[200]!, width: 1),
      ),
      content: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: iconColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: iconColor.withOpacity(0.22)),
                  ),
                  child: Icon(icon, size: 18, color: iconColor),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                          color: Color(0xFF2C3E50),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey[600],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }

  Widget _buildResultsHeader(BuildContext context, int count,
      {required VoidCallback onClear}) {
    return Row(
      children: [
        Expanded(
          child: Text(
            "Assets (${count.toString()})",
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 16,
              color: Color(0xFF2C3E50),
            ),
          ),
        ),
        GFButton(
          onPressed: onClear,
          text: "Clear filters",
          icon: const Icon(Icons.close, size: 16, color: Color(0xFF2C3E50)),
          color: Colors.white,
          textColor: const Color(0xFF2C3E50),
          type: GFButtonType.outline2x,
          size: GFSize.SMALL,
          shape: GFButtonShape.pills,
        ),
      ],
    );
  }

  // ---------------------------
  // States
  // ---------------------------

  Widget _buildErrorState(
      BuildContext context,
      String msg, {
        required VoidCallback onRetry,
      }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 64, color: Colors.red[300]),
            const SizedBox(height: 16),
            const Text(
              "Failed to load assets",
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: Color(0xFF2C3E50),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              msg,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.red[700], fontSize: 13),
            ),
            const SizedBox(height: 16),
            GFButton(
              onPressed: onRetry,
              text: "Retry",
              icon: const Icon(Icons.refresh, size: 18, color: Colors.white),
              color: const Color(0xFF3498DB),
              shape: GFButtonShape.pills,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.inventory_2_outlined, size: 80, color: Colors.grey[300]),
          const SizedBox(height: 20),
          Text(
            'No assets found',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.grey[700],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Try adjusting your filters',
            style: TextStyle(fontSize: 13, color: Colors.grey[500]),
          ),
        ],
      ),
    );
  }

  // ---------------------------
  // Cards
  // ---------------------------

  Widget _buildSummaryCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
    required String sub,
  }) {
    return GFCard(
      elevation: 0,
      color: color.withOpacity(0.08),
      padding: const EdgeInsets.all(14),
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: color.withOpacity(0.18), width: 1),
      ),
      content: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: color.withOpacity(0.22),
                  blurRadius: 10,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Icon(icon, color: Colors.white, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey[700],
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 5),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    value,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: color,
                    ),
                    maxLines: 1,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  sub,
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDropdown({
    required String value,
    required List<String> items,
    required String hint,
    required IconData icon,
    required void Function(String?) onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F9FA),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.grey[600]),
          const SizedBox(width: 10),
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: items.contains(value)
                    ? value
                    : (items.isNotEmpty ? items.first : value),
                isExpanded: true,
                menuMaxHeight: 360,
                hint: Text(
                  hint,
                  style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                ),
                items: items.map((String item) {
                  return DropdownMenuItem<String>(
                    value: item,
                    child: Text(
                      item,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  );
                }).toList(),
                onChanged: onChanged,
                icon: const Icon(Icons.arrow_drop_down, size: 22),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAssetCard({
    required BuildContext context,
    required String? itemImage,
    required String itemType,
    required String? rfidCode,
    required String employee,
    required String condition,
    required String department,
    required int quantity,
    required double totalCost,
    required double currentValue,
    required int? lifeSpanYears,
    required double depreciationYear,
    required double depPct,
    required String? dateAcquired,
    required String encoder,
    required String periodLabel,
  }) {
    return GFCard(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      padding: EdgeInsets.zero,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey[200]!, width: 1),
      ),
      content: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          // TODO: Show asset details
        },
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header (responsive)
              LayoutBuilder(
                builder: (context, c) {
                  final narrow = c.maxWidth < 420;

                  final headerMain = Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          itemType.isEmpty ? '(No item type)' : itemType,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF2C3E50),
                          ),
                          maxLines: narrow ? 2 : 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 6),
                        _buildInfoRow(icon: Icons.qr_code, text: rfidCode ?? 'No RFID'),
                        const SizedBox(height: 4),
                        _buildInfoRow(icon: Icons.person_outline, text: employee),
                      ],
                    ),
                  );

                  final badge = ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 120),
                    child: _buildConditionBadge(condition),
                  );

                  if (narrow) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildAssetImage(itemImage),
                            const SizedBox(width: 12),
                            headerMain,
                          ],
                        ),
                        const SizedBox(height: 10),
                        Align(alignment: Alignment.centerLeft, child: badge),
                      ],
                    );
                  }

                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildAssetImage(itemImage),
                      const SizedBox(width: 12),
                      headerMain,
                      const SizedBox(width: 10),
                      badge,
                    ],
                  );
                },
              ),

              const SizedBox(height: 12),

              // Details (responsive grid, avoids overflow)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8F9FA),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.grey[200]!, width: 1),
                ),
                child: LayoutBuilder(
                  builder: (context, c) {
                    final w = c.maxWidth;
                    final cols = w >= 620 ? 2 : 1;
                    const gap = 12.0;
                    final itemW = cols == 1 ? w : (w - gap) / 2;

                    final items = <Widget>[
                      _detailKV("Department", department.isEmpty ? '-' : department, Icons.business),
                      _detailKV("Quantity", "$quantity", Icons.inventory),
                      _detailKV("Original Cost", "₱${totalCost.toStringAsFixed(2)}", Icons.attach_money),
                      _detailKV("Current Value", "₱${currentValue.toStringAsFixed(2)}", Icons.account_balance_wallet),
                      _detailKV("Life Span", _lifeSpanLabel(lifeSpanYears), Icons.schedule),
                      _detailKV("Depreciation/Year", "₱${depreciationYear.toStringAsFixed(2)}", Icons.trending_down),
                    ];

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: gap,
                          runSpacing: 12,
                          children: items.map((x) => SizedBox(width: itemW, child: x)).toList(),
                        ),
                        const SizedBox(height: 14),

                        // Depreciation Progress
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Depreciation ($periodLabel)',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[700],
                                fontWeight: FontWeight.w700,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              '${depPct.toStringAsFixed(1)}%',
                              style: TextStyle(
                                fontSize: 12,
                                color: _getDepreciationColor(depPct),
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        GFProgressBar(
                          percentage: (depPct.clamp(0, 100)) / 100,
                          lineHeight: 10,
                          backgroundColor: Colors.grey[300]!,
                          progressBarColor: _getDepreciationColor(depPct),
                          circleWidth: 0,
                        ),
                      ],
                    );
                  },
                ),
              ),

              const SizedBox(height: 10),

              // Footer (responsive)
              LayoutBuilder(
                builder: (context, c) {
                  final narrow = c.maxWidth < 420;

                  final left = Row(
                    children: [
                      Icon(Icons.calendar_today, size: 13, color: Colors.grey[500]),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          'Acquired: ${dateAcquired ?? '-'}',
                          style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  );

                  final right = Row(
                    children: [
                      Icon(Icons.person, size: 13, color: Colors.grey[500]),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          'By: $encoder',
                          style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  );

                  if (narrow) {
                    return Column(
                      children: [
                        left,
                        const SizedBox(height: 6),
                        right,
                      ],
                    );
                  }

                  return Row(
                    children: [
                      Expanded(child: left),
                      const SizedBox(width: 12),
                      Expanded(child: right),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _detailKV(String label, String value, IconData icon) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 14, color: Colors.grey[600]),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF2C3E50),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAssetImage(String? url) {
    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!, width: 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: (url == null || url.trim().isEmpty)
          ? Icon(Icons.inventory_2, color: Colors.grey[400], size: 32)
          : Image.network(
        url,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) =>
            Icon(Icons.inventory_2, color: Colors.grey[400], size: 32),
        loadingBuilder: (_, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return const Center(
            child: GFLoader(type: GFLoaderType.circle, size: GFSize.SMALL),
          );
        },
      ),
    );
  }

  Widget _buildInfoRow({required IconData icon, required String text}) {
    return Row(
      children: [
        Icon(icon, size: 13, color: Colors.grey[600]),
        const SizedBox(width: 5),
        Expanded(
          child: Text(
            text,
            style: TextStyle(fontSize: 12, color: Colors.grey[700]),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildConditionBadge(String condition) {
    final conditionData = _getConditionData(condition);

    return GFBadge(
      text: condition.isEmpty ? 'Unknown' : condition,
      color: conditionData['color'],
      textStyle: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: conditionData['textColor'],
      ),
      shape: GFBadgeShape.pills,
      border: BorderSide(color: conditionData['borderColor'], width: 1),
    );
  }

  Map<String, dynamic> _getConditionData(String condition) {
    switch (condition) {
      case 'Excellent':
        return {
          'color': const Color(0xFF27AE60).withOpacity(0.15),
          'textColor': const Color(0xFF27AE60),
          'borderColor': const Color(0xFF27AE60).withOpacity(0.4),
        };
      case 'Good':
        return {
          'color': const Color(0xFF3498DB).withOpacity(0.15),
          'textColor': const Color(0xFF3498DB),
          'borderColor': const Color(0xFF3498DB).withOpacity(0.4),
        };
      case 'Fair':
        return {
          'color': const Color(0xFFF39C12).withOpacity(0.15),
          'textColor': const Color(0xFFF39C12),
          'borderColor': const Color(0xFFF39C12).withOpacity(0.4),
        };
      case 'Poor':
        return {
          'color': const Color(0xFFE74C3C).withOpacity(0.15),
          'textColor': const Color(0xFFE74C3C),
          'borderColor': const Color(0xFFE74C3C).withOpacity(0.4),
        };
      default:
        return {
          'color': Colors.grey[200],
          'textColor': Colors.grey[700],
          'borderColor': Colors.grey[400],
        };
    }
  }

  Color _getDepreciationColor(double percent) {
    if (percent > 75) return const Color(0xFFE74C3C);
    if (percent > 50) return const Color(0xFFF39C12);
    return const Color(0xFF27AE60);
  }

  String _lifeSpanLabel(int? years) {
    if (years == null || years <= 0) return '-';
    if (years == 1) return '1 year';
    return '$years years';
  }

  // ---------------------------
  // Computations
  // ---------------------------

  double _currentValue({
    required double total,
    required double depreciationYear,
    required DepreciationPeriod period,
  }) {
    double step;
    switch (period) {
      case DepreciationPeriod.day:
        step = depreciationYear / 365.0;
        break;
      case DepreciationPeriod.week:
        step = depreciationYear / 52.0;
        break;
      case DepreciationPeriod.month:
        step = depreciationYear / 12.0;
        break;
      case DepreciationPeriod.bimonth:
        step = depreciationYear / 2.0;
        break;
      case DepreciationPeriod.year:
        step = depreciationYear;
        break;
    }
    return max(0.0, total - step);
  }

  _AssetsInsights _computeInsights(List rows, DepreciationPeriod period) {
    double totalOriginal = 0;
    double totalCurrent = 0;

    final conditionCounts = <String, int>{};
    final deptCost = <String, double>{};

    final buckets = <String, int>{
      "0-25": 0,
      "25-50": 0,
      "50-75": 0,
      "75-100": 0,
    };

    for (final a in rows) {
      final total = (a.total as double);
      final depYear = (a.depreciationValueYear as double);

      final cur = _currentValue(total: total, depreciationYear: depYear, period: period);
      totalOriginal += total;
      totalCurrent += cur;

      final cond = (a.condition as String?)?.trim().isEmpty == true ? "Unknown" : (a.condition as String);
      conditionCounts[cond] = (conditionCounts[cond] ?? 0) + 1;

      final dept = (a.department as String?)?.trim().isEmpty == true ? "Unknown" : (a.department as String);
      deptCost[dept] = (deptCost[dept] ?? 0) + total;

      final depPct = total <= 0 ? 0.0 : ((total - cur) / total * 100.0);
      if (depPct < 25) buckets["0-25"] = (buckets["0-25"] ?? 0) + 1;
      else if (depPct < 50) buckets["25-50"] = (buckets["25-50"] ?? 0) + 1;
      else if (depPct < 75) buckets["50-75"] = (buckets["50-75"] ?? 0) + 1;
      else buckets["75-100"] = (buckets["75-100"] ?? 0) + 1;
    }

    final avgDep = totalOriginal <= 0 ? 0.0 : ((totalOriginal - totalCurrent) / totalOriginal * 100.0);

    return _AssetsInsights(
      totalAssets: rows.length,
      totalOriginalCost: totalOriginal,
      totalCurrentValue: totalCurrent,
      avgDepPct: avgDep,
      conditionCounts: conditionCounts,
      departmentCost: deptCost,
      depBuckets: buckets,
    );
  }

  // ---------------------------
  // Formatting
  // ---------------------------

  String _formatCompact(double number) {
    if (number.abs() >= 1000000000) {
      return '${(number / 1000000000).toStringAsFixed(2)}B';
    } else if (number.abs() >= 1000000) {
      return '${(number / 1000000).toStringAsFixed(2)}M';
    } else if (number.abs() >= 1000) {
      return '${(number / 1000).toStringAsFixed(2)}K';
    }
    return number.toStringAsFixed(2);
  }

  static String _shortLabel(String s, int maxLen) {
    final t = s.trim();
    if (t.length <= maxLen) return t;
    return "${t.substring(0, maxLen)}…";
  }
}

// ---------------------------
// Insights Data Model
// ---------------------------

class _AssetsInsights {
  final int totalAssets;
  final double totalOriginalCost;
  final double totalCurrentValue;
  final double avgDepPct;

  final Map<String, int> conditionCounts;
  final Map<String, double> departmentCost;
  final Map<String, int> depBuckets;

  const _AssetsInsights({
    required this.totalAssets,
    required this.totalOriginalCost,
    required this.totalCurrentValue,
    required this.avgDepPct,
    required this.conditionCounts,
    required this.departmentCost,
    required this.depBuckets,
  });
}

// ---------------------------
// Mini Donut Chart
// ---------------------------

class _ChartSegment {
  final String label;
  final double value;
  final Color color;
  const _ChartSegment({required this.label, required this.value, required this.color});
}

class _MiniDonutChart extends StatelessWidget {
  final List<_ChartSegment> segments;
  final String centerText;
  final String centerSubtext;

  const _MiniDonutChart({
    required this.segments,
    required this.centerText,
    required this.centerSubtext,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _MiniDonutPainter(segments),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              centerText,
              style: const TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 18,
                color: Color(0xFF2C3E50),
              ),
            ),
            Text(
              centerSubtext,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 11,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniDonutPainter extends CustomPainter {
  final List<_ChartSegment> segments;
  _MiniDonutPainter(this.segments);

  @override
  void paint(Canvas canvas, Size size) {
    final total = segments.fold<double>(0, (s, e) => s + e.value);
    final stroke = 14.0;
    final rect = Offset.zero & size;
    final center = rect.center;
    final radius = min(size.width, size.height) / 2 - stroke / 2;

    final basePaint = Paint()
      ..color = const Color(0xFFEAEFF5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, radius, basePaint);

    if (total <= 0) return;

    var start = -pi / 2;
    for (final seg in segments) {
      final sweep = (seg.value / total) * (2 * pi);
      final p = Paint()
        ..color = seg.color
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        start,
        sweep,
        false,
        p,
      );
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _MiniDonutPainter oldDelegate) {
    return oldDelegate.segments != segments;
  }
}

// ---------------------------
// Mini Bar Chart
// ---------------------------

class _BarDatum {
  final String label;
  final double value;
  final Color color;
  final String fullLabel;

  const _BarDatum({
    required this.label,
    required this.value,
    required this.color,
    required this.fullLabel,
  });
}

class _MiniBarChart extends StatelessWidget {
  final List<_BarDatum> data;
  final String Function(double v) valueFormatter;

  const _MiniBarChart({
    required this.data,
    required this.valueFormatter,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _MiniBarPainter(data),
      child: Padding(
        padding: const EdgeInsets.only(top: 10, bottom: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: data.map((d) {
            return Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      valueFormatter(d.value),
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: Colors.grey[700],
                      ),
                      maxLines: 1,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    d.label,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: Colors.grey[700],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

class _MiniBarPainter extends CustomPainter {
  final List<_BarDatum> data;
  _MiniBarPainter(this.data);

  @override
  void paint(Canvas canvas, Size size) {
    final maxV = data.fold<double>(0.0, (m, e) => max(m, e.value));
    final chartH = size.height - 26.0; // ✅ double
    final barW = size.width / max(1, data.length);

    for (var i = 0; i < data.length; i++) {
      final d = data[i];
      final h = maxV <= 0 ? 0.0 : (d.value / maxV) * (chartH - 6.0);

      final left = i * barW + barW * 0.18;
      final width = barW * 0.64;

      // ✅ clamp returns num, convert to double
      final top = (chartH - h).clamp(0.0, chartH).toDouble();

      final r = RRect.fromRectAndRadius(
        Rect.fromLTWH(left, top, width, h),
        const Radius.circular(10),
      );

      final p = Paint()..color = d.color.withOpacity(0.85);
      canvas.drawRRect(r, p);
    }
  }

  @override
  bool shouldRepaint(covariant _MiniBarPainter oldDelegate) {
    return oldDelegate.data != data;
  }
}


// ---------------------------
// Legend
// ---------------------------

class _LegendList extends StatelessWidget {
  final List<_ChartSegment> segments;
  final String emptyText;

  const _LegendList({required this.segments, required this.emptyText});

  @override
  Widget build(BuildContext context) {
    if (segments.isEmpty) {
      return Text(
        emptyText,
        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: segments.map((s) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: s.color,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  s.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF2C3E50),
                  ),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}
