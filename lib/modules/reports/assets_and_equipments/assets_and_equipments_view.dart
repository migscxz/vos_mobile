import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:getwidget/getwidget.dart';

import 'package:vos_mobile/state/assets_and_equipments/assets_and_equipments_providers.dart';

class AssetsAndEquipmentsView extends ConsumerStatefulWidget {
  const AssetsAndEquipmentsView({Key? key}) : super(key: key);

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

    final depreciationFilters =
    DepreciationPeriod.values.map((e) => e.label).toList();

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

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: GFAppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        title: const Text(
          'Assets & Equipment',
          style: TextStyle(
            color: Color(0xFF2C3E50),
            fontWeight: FontWeight.w700,
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
      body: Column(
        children: [
          // Summary Cards Section
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _buildSummaryCard(
                        title: 'Total Assets',
                        value: isLoading ? '—' : '${rows.length}',
                        icon: Icons.inventory_2,
                        color: const Color(0xFF3498DB),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildSummaryCard(
                        title: 'Current Value',
                        value: (isLoading || metrics == null)
                            ? '—'
                            : '₱${_formatNumber(metrics.currentTotalValue)}',
                        icon: Icons.account_balance_wallet,
                        color: const Color(0xFF27AE60),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Filters Section
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              children: [
                // Search Bar
                TextField(
                  controller: _searchCtrl,
                  decoration: InputDecoration(
                    hintText: 'Search assets...',
                    hintStyle: TextStyle(
                      color: Colors.grey[400],
                      fontSize: 14,
                    ),
                    prefixIcon: Icon(Icons.search,
                      size: 20,
                      color: Colors.grey[600],
                    ),
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

                // Dropdown Filters
                Row(
                  children: [
                    Expanded(
                      child: _buildDropdown(
                        value: filters.department,
                        items: departments,
                        hint: 'Department',
                        onChanged: (v) {
                          if (v != null) {
                            ref
                                .read(assetsFiltersProvider.notifier)
                                .setDepartment(v);
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildDropdown(
                        value: filters.condition,
                        items: conditions,
                        hint: 'Condition',
                        onChanged: (v) {
                          if (v != null) {
                            ref
                                .read(assetsFiltersProvider.notifier)
                                .setCondition(v);
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Depreciation Period Chips
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Depreciation Period',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: Color(0xFF2C3E50),
                  ),
                ),
                const SizedBox(height: 10),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: depreciationFilters.map((label) {
                      final isSelected = filters.period.label == label;
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: GFButton(
                          onPressed: () {
                            final p = DepreciationPeriod.values.firstWhere(
                                  (e) => e.label == label,
                            );
                            ref
                                .read(assetsFiltersProvider.notifier)
                                .setPeriod(p);
                          },
                          text: label,
                          color: isSelected
                              ? const Color(0xFF3498DB)
                              : Colors.grey[200]!,
                          textColor: isSelected
                              ? Colors.white
                              : const Color(0xFF2C3E50),
                          size: GFSize.SMALL,
                          shape: GFButtonShape.pills,
                          type: isSelected
                              ? GFButtonType.solid
                              : GFButtonType.outline2x,
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),

          const Divider(height: 1, thickness: 1),

          // Assets List
          Expanded(
            child: Builder(
              builder: (_) {
                if (error != null) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.error_outline,
                            size: 64,
                            color: Colors.red[300],
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Error: $error',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.red[700],
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                if (isLoading) {
                  return const Center(
                    child: GFLoader(type: GFLoaderType.circle),
                  );
                }

                if (rows.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.inventory_2_outlined,
                          size: 80,
                          color: Colors.grey[300],
                        ),
                        const SizedBox(height: 20),
                        Text(
                          'No assets found',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            color: Colors.grey[600],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Try adjusting your filters',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey[500],
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: rows.length,
                  itemBuilder: (context, index) {
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
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: GFButton(
        onPressed: () {
          // TODO: Add new asset
        },
        text: 'Add Asset',
        icon: const Icon(Icons.add, color: Colors.white),
        color: const Color(0xFF3498DB),
        size: GFSize.LARGE,
        shape: GFButtonShape.pills,
      ),
    );
  }

  // Helper Methods

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

  String _formatNumber(double number) {
    if (number >= 1000000) {
      return '${(number / 1000000).toStringAsFixed(2)}M';
    } else if (number >= 1000) {
      return '${(number / 1000).toStringAsFixed(2)}K';
    }
    return number.toStringAsFixed(2);
  }

  Widget _buildSummaryCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return GFCard(
      elevation: 0,
      color: color.withOpacity(0.08),
      padding: const EdgeInsets.all(14),
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: color.withOpacity(0.2), width: 1),
      ),
      content: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(10),
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
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: color,
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
    required void Function(String?) onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F9FA),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: items.contains(value)
              ? value
              : (items.isNotEmpty ? items.first : value),
          isExpanded: true,
          hint: Text(
            hint,
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey[600],
            ),
          ),
          items: items.map((String item) {
            return DropdownMenuItem<String>(
              value: item,
              child: Text(
                item,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            );
          }).toList(),
          onChanged: onChanged,
          icon: const Icon(Icons.arrow_drop_down, size: 22),
        ),
      ),
    );
  }

  Widget _buildAssetCard({
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
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header with Image and Basic Info
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildAssetImage(itemImage),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          itemType.isEmpty ? '(No item type)' : itemType,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF2C3E50),
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 6),
                        _buildInfoRow(
                          icon: Icons.qr_code,
                          text: rfidCode ?? 'No RFID',
                        ),
                        const SizedBox(height: 4),
                        _buildInfoRow(
                          icon: Icons.person_outline,
                          text: employee,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  _buildConditionBadge(condition),
                ],
              ),

              const SizedBox(height: 16),

              // Details Section
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8F9FA),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _buildDetailItem(
                            label: 'Department',
                            value: department.isEmpty ? '-' : department,
                            icon: Icons.business,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _buildDetailItem(
                            label: 'Quantity',
                            value: '$quantity',
                            icon: Icons.inventory,
                          ),
                        ),
                      ],
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Divider(height: 1),
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: _buildDetailItem(
                            label: 'Original Cost',
                            value: '₱${totalCost.toStringAsFixed(2)}',
                            icon: Icons.attach_money,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _buildDetailItem(
                            label: 'Current Value',
                            value: '₱${currentValue.toStringAsFixed(2)}',
                            icon: Icons.account_balance_wallet,
                          ),
                        ),
                      ],
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Divider(height: 1),
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: _buildDetailItem(
                            label: 'Life Span',
                            value: _lifeSpanLabel(lifeSpanYears),
                            icon: Icons.schedule,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _buildDetailItem(
                            label: 'Depreciation/Year',
                            value: '₱${depreciationYear.toStringAsFixed(2)}',
                            icon: Icons.trending_down,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Depreciation Progress
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Depreciation ($periodLabel)',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[700],
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              '${depPct.toStringAsFixed(1)}%',
                              style: TextStyle(
                                fontSize: 12,
                                color: _getDepreciationColor(depPct),
                                fontWeight: FontWeight.w700,
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
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 14),

              // Footer Info
              Row(
                children: [
                  Icon(
                    Icons.calendar_today,
                    size: 13,
                    color: Colors.grey[500],
                  ),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      'Acquired: ${dateAcquired ?? '-'}',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey[600],
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Icon(
                    Icons.person,
                    size: 13,
                    color: Colors.grey[500],
                  ),
                  const SizedBox(width: 5),
                  Flexible(
                    child: Text(
                      'By: $encoder',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey[600],
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
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
          ? Icon(
        Icons.inventory_2,
        color: Colors.grey[400],
        size: 32,
      )
          : Image.network(
        url,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) {
          return Icon(
            Icons.inventory_2,
            color: Colors.grey[400],
            size: 32,
          );
        },
        loadingBuilder: (_, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return Center(
            child: GFLoader(
              type: GFLoaderType.circle,
              size: GFSize.SMALL,
            ),
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
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[700],
            ),
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
        fontWeight: FontWeight.w600,
        color: conditionData['textColor'],
      ),
      shape: GFBadgeShape.pills,
      border: BorderSide(
        color: conditionData['borderColor'],
        width: 1,
      ),
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

  Widget _buildDetailItem({
    required String label,
    required String value,
    required IconData icon,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 14, color: Colors.grey[600]),
            const SizedBox(width: 5),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 5),
        Text(
          value,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Color(0xFF2C3E50),
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
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
}