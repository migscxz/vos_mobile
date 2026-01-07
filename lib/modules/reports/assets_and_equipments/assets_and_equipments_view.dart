import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
    // watch core read models
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

    final error =
        rowsAsync.error ?? metricsAsync.error ?? depsAsync.error ?? condsAsync.error;

    final rows = rowsAsync.value ?? const [];
    final metrics = metricsAsync.value;
    final departments = depsAsync.value ?? const ['All Departments'];
    final conditions = condsAsync.value ?? const ['All Conditions'];

    // Keep the search field in sync with filter (one-way init)
    if (filters.search.isNotEmpty && _searchCtrl.text != filters.search) {
      _searchCtrl.text = filters.search;
      _searchCtrl.selection = TextSelection.fromPosition(
        TextPosition(offset: _searchCtrl.text.length),
      );
    }

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        title: const Text(
          'Assets & Equipment Management',
          style: TextStyle(
            color: Colors.black87,
            fontWeight: FontWeight.w600,
            fontSize: 20,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.black87),
            onPressed: () {
              // force refresh of read models
              ref.invalidate(assetsAllRowsProvider);
              ref.invalidate(assetsRowsProvider);
              ref.invalidate(assetsMetricsProvider);
              ref.invalidate(assetsDepartmentsProvider);
              ref.invalidate(assetsConditionsProvider);
            },
          ),
          IconButton(
            icon: const Icon(Icons.download, color: Colors.black87),
            onPressed: () {
              // TODO: export to CSV/PDF if needed
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          // Summary + Filters
          Container(
            color: Colors.white,
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _buildSummaryCard(
                        'Total Assets',
                        isLoading ? '—' : '${rows.length}',
                        Icons.inventory_2,
                        Colors.blue,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildSummaryCard(
                        'Current Total Value',
                        (isLoading || metrics == null)
                            ? '—'
                            : '₱${metrics.currentTotalValue.toStringAsFixed(2)}',
                        Icons.account_balance_wallet,
                        Colors.green,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: _searchCtrl,
                        decoration: InputDecoration(
                          hintText: 'Search assets...',
                          prefixIcon: const Icon(Icons.search, size: 20),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(color: Colors.grey[300]!),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(color: Colors.grey[300]!),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 12,
                          ),
                          filled: true,
                          fillColor: Colors.grey[50],
                        ),
                        onChanged: (v) =>
                            ref.read(assetsFiltersProvider.notifier).setSearch(v),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildDropdown(
                        value: filters.department,
                        items: departments,
                        onChanged: (v) {
                          if (v != null) {
                            ref
                                .read(assetsFiltersProvider.notifier)
                                .setDepartment(v);
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildDropdown(
                        value: filters.condition,
                        items: conditions,
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

          // Depreciation Period
          Container(
            color: Colors.white,
            padding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                const Text(
                  'Depreciation Period:',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(width: 12),
                ...depreciationFilters.map((label) {
                  final isSelected = filters.period.label == label;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(label),
                      selected: isSelected,
                      onSelected: (_) {
                        final p = DepreciationPeriod.values.firstWhere(
                              (e) => e.label == label,
                        );
                        ref
                            .read(assetsFiltersProvider.notifier)
                            .setPeriod(p);
                      },
                      selectedColor: Colors.blue,
                      labelStyle: TextStyle(
                        color: isSelected ? Colors.white : Colors.black87,
                        fontWeight: FontWeight.w500,
                        fontSize: 13,
                      ),
                      backgroundColor: Colors.grey[200],
                      padding:
                      const EdgeInsets.symmetric(horizontal: 8),
                    ),
                  );
                }).toList(),
              ],
            ),
          ),

          const Divider(height: 1),

          // Body
          Expanded(
            child: Builder(
              builder: (_) {
                if (error != null) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        'Error: $error',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.red[700]),
                      ),
                    ),
                  );
                }
                if (isLoading) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (rows.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.inventory_2_outlined,
                          size: 64,
                          color: Colors.grey[400],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No assets found',
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.grey[600],
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

                    // compute current value (same rules; clamp >= 0)
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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          // TODO: Add new asset
        },
        icon: const Icon(Icons.add),
        label: const Text('Add Asset'),
        backgroundColor: Colors.blue,
      ),
    );
  }

  // ------------ helpers -------------

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

  Widget _buildSummaryCard(
      String title,
      String value,
      IconData icon,
      Color color,
      ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: Colors.white, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[700],
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
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
    required void Function(String?) onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: items.contains(value)
              ? value
              : (items.isNotEmpty ? items.first : value),
          isExpanded: true,
          items: items.map((String item) {
            return DropdownMenuItem<String>(
              value: item,
              child: Text(
                item,
                style: const TextStyle(fontSize: 13),
                overflow: TextOverflow.ellipsis,
              ),
            );
          }).toList(),
          onChanged: onChanged,
          icon: const Icon(Icons.arrow_drop_down, size: 20),
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
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey[200]!),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          // TODO: Show asset details
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _buildAssetImage(itemImage),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          itemType.isEmpty ? '(No item type)' : itemType,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(
                              Icons.qr_code,
                              size: 14,
                              color: Colors.grey[600],
                            ),
                            const SizedBox(width: 4),
                            Text(
                              rfidCode ?? '-',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600],
                              ),
                            ),
                            const SizedBox(width: 12),
                            Icon(
                              Icons.person_outline,
                              size: 14,
                              color: Colors.grey[600],
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                employee,
                                style: TextStyle(
                                  fontSize: 12,
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
                  _buildConditionBadge(condition),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey[50],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _info(
                            'Department',
                            department.isEmpty ? '-' : department,
                            Icons.business,
                          ),
                        ),
                        Expanded(
                          child: _info(
                            'Quantity',
                            '$quantity',
                            Icons.inventory,
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: _info(
                            'Original Cost',
                            '₱${totalCost.toStringAsFixed(2)}',
                            Icons.attach_money,
                          ),
                        ),
                        Expanded(
                          child: _info(
                            'Current Value',
                            '₱${currentValue.toStringAsFixed(2)}',
                            Icons.account_balance_wallet,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _info(
                            'Life Span',
                            _lifeSpanLabel(lifeSpanYears),
                            Icons.schedule,
                          ),
                        ),
                        Expanded(
                          child: _info(
                            'Depreciation/Year',
                            '₱${depreciationYear.toStringAsFixed(2)}',
                            Icons.trending_down,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment:
                            CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'Depreciation ($periodLabel)',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey[600],
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  Text(
                                    '${depPct.toStringAsFixed(1)}%',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.red[700],
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: LinearProgressIndicator(
                                  value: (depPct.clamp(0, 100)) / 100,
                                  backgroundColor: Colors.grey[300],
                                  valueColor:
                                  AlwaysStoppedAnimation<Color>(
                                    depPct > 75
                                        ? Colors.red
                                        : depPct > 50
                                        ? Colors.orange
                                        : Colors.green,
                                  ),
                                  minHeight: 8,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(
                    Icons.calendar_today,
                    size: 12,
                    color: Colors.grey[500],
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Acquired: ${dateAcquired ?? '-'}',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey[600],
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    Icons.person,
                    size: 12,
                    color: Colors.grey[500],
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'By: $encoder',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey[600],
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
    final border = BoxDecoration(
      color: Colors.grey[200],
      borderRadius: BorderRadius.circular(8),
    );
    if (url == null || url.trim().isEmpty) {
      return Container(
        width: 60,
        height: 60,
        decoration: border,
        child: Icon(
          Icons.inventory_2,
          color: Colors.grey[600],
          size: 30,
        ),
      );
    }
    return Container(
      width: 60,
      height: 60,
      decoration: border,
      clipBehavior: Clip.antiAlias,
      child: Image.network(
        url,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) {
          return Icon(
            Icons.inventory_2,
            color: Colors.grey[600],
            size: 30,
          );
        },
      ),
    );
  }

  Widget _buildConditionBadge(String condition) {
    Color color;
    switch (condition) {
      case 'Excellent':
        color = Colors.green;
        break;
      case 'Good':
        color = Colors.blue;
        break;
      case 'Fair':
        color = Colors.orange;
        break;
      case 'Poor':
        color = Colors.red;
        break;
      default:
        color = Colors.grey;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Text(
        condition.isEmpty ? 'Unknown' : condition,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }

  Widget _info(String label, String value, IconData icon) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 14, color: Colors.grey[600]),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey[600],
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Colors.black87,
          ),
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  String _lifeSpanLabel(int? years) {
    if (years == null || years <= 0) return '-';
    if (years == 1) return '1 year';
    return '$years years';
  }
}
