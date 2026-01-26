// lib/modules/disbursement/coa_graphs.dart
import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:getwidget/getwidget.dart";
import "package:fl_chart/fl_chart.dart";

import "package:vos_mobile/state/disbursement/disbursement_providers.dart";

class CoaGraphsView extends ConsumerStatefulWidget {
  const CoaGraphsView({Key? key}) : super(key: key);

  @override
  ConsumerState<CoaGraphsView> createState() => _CoaGraphsViewState();
}

class _CoaGraphsViewState extends ConsumerState<CoaGraphsView> {
  String _selectedView = "Frequency";
  final List<String> _viewOptions = ["Frequency", "Amount"];

  @override
  Widget build(BuildContext context) {
    final asyncState = ref.watch(disbursementControllerProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF1A1A1A)),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          "COA Analytics",
          style: TextStyle(
            color: Color(0xFF1A1A1A),
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Color(0xFF6366F1)),
            onPressed: () {
              ref.read(disbursementControllerProvider.notifier).refresh();
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: asyncState.when(
        loading: () => _buildLoadingState(),
        error: (e, _) => _buildErrorState(e.toString()),
        data: (state) {
          final coaStats = _computeCoaStats(state.groups);

          if (coaStats.isEmpty) {
            return _buildEmptyState();
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildViewToggle(),
                const SizedBox(height: 20),
                _buildSummaryCards(coaStats),
                const SizedBox(height: 24),
                _buildBarChart(coaStats),
                const SizedBox(height: 24),
                _buildPieChart(coaStats),
                const SizedBox(height: 24),
                _buildDetailedList(coaStats),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildViewToggle() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          const Icon(Icons.pie_chart, color: Color(0xFF6366F1), size: 24),
          const SizedBox(width: 12),
          const Text(
            "View By:",
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1A1A1A),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Row(
              children: _viewOptions.map((option) {
                final isSelected = _selectedView == option;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GFButton(
                    onPressed: () => setState(() => _selectedView = option),
                    text: option,
                    size: GFSize.SMALL,
                    color: isSelected ? const Color(0xFF6366F1) : Colors.grey[200]!,
                    textColor: isSelected ? Colors.white : Colors.grey[700],
                    shape: GFButtonShape.pills,
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCards(List<CoaStat> stats) {
    final totalAccounts = stats.length;
    final totalTransactions = stats.fold<int>(0, (sum, s) => sum + s.count);
    final totalAmount = stats.fold<double>(0.0, (sum, s) => sum + s.totalAmount);
    final mostUsed = stats.isNotEmpty ? stats.first : null;

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _buildStatCard(
                "Total Accounts",
                totalAccounts.toString(),
                Icons.account_balance,
                const Color(0xFF6366F1),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildStatCard(
                "Total Usage",
                totalTransactions.toString(),
                Icons.trending_up,
                const Color(0xFF10B981),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildStatCard(
                "Total Amount",
                "₱${_formatAmount(totalAmount)}",
                Icons.attach_money,
                const Color(0xFFF59E0B),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildStatCard(
                "Most Used",
                mostUsed?.coaTitle ?? "—",
                Icons.star,
                const Color(0xFFEC4899),
                isLarge: true,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStatCard(
      String label,
      String value,
      IconData icon,
      Color color, {
        bool isLarge = false,
      }) {
    return GFCard(
      elevation: 0,
      color: Colors.white,
      padding: const EdgeInsets.all(16),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: TextStyle(
              fontSize: isLarge ? 14 : 20,
              fontWeight: FontWeight.bold,
              color: const Color(0xFF1A1A1A),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildBarChart(List<CoaStat> stats) {
    final topStats = stats.take(10).toList();

    if (topStats.isEmpty) return const SizedBox.shrink();

    final useFrequency = _selectedView == "Frequency";
    final maxValue = useFrequency
        ? topStats.map((s) => s.count.toDouble()).reduce((a, b) => a > b ? a : b)
        : topStats.map((s) => s.totalAmount).reduce((a, b) => a > b ? a : b);

    return GFCard(
      elevation: 0,
      color: Colors.white,
      padding: const EdgeInsets.all(16),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.bar_chart, color: Color(0xFF6366F1), size: 20),
              const SizedBox(width: 8),
              Text(
                "Top 10 Accounts by ${_selectedView}",
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1A1A1A),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 300,
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                maxY: maxValue * 1.2,
                barTouchData: BarTouchData(
                  enabled: true,
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipColor: (group) => const Color(0xFF1A1A1A),
                    tooltipPadding: const EdgeInsets.all(8),
                    getTooltipItem: (group, groupIndex, rod, rodIndex) {
                      final stat = topStats[groupIndex];
                      return BarTooltipItem(
                        '${stat.coaTitle}\n',
                        const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                        children: [
                          TextSpan(
                            text: useFrequency
                                ? '${stat.count} uses'
                                : '₱${_formatAmount(stat.totalAmount)}',
                            style: const TextStyle(
                              color: Color(0xFF6366F1),
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
                titlesData: FlTitlesData(
                  show: true,
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, meta) {
                        if (value.toInt() >= topStats.length) return const SizedBox.shrink();
                        final title = topStats[value.toInt()].coaTitle;
                        return Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            title.length > 10 ? '${title.substring(0, 10)}...' : title,
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 10,
                            ),
                          ),
                        );
                      },
                      reservedSize: 40,
                    ),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 50,
                      getTitlesWidget: (value, meta) {
                        return Text(
                          useFrequency
                              ? value.toInt().toString()
                              : _formatCompactAmount(value),
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 10,
                          ),
                        );
                      },
                    ),
                  ),
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                ),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: maxValue / 5,
                  getDrawingHorizontalLine: (value) {
                    return FlLine(
                      color: Colors.grey[200]!,
                      strokeWidth: 1,
                    );
                  },
                ),
                borderData: FlBorderData(show: false),
                barGroups: topStats.asMap().entries.map((entry) {
                  final index = entry.key;
                  final stat = entry.value;
                  final value = useFrequency ? stat.count.toDouble() : stat.totalAmount;

                  return BarChartGroupData(
                    x: index,
                    barRods: [
                      BarChartRodData(
                        toY: value,
                        color: const Color(0xFF6366F1),
                        width: 16,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(4),
                        ),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPieChart(List<CoaStat> stats) {
    final topStats = stats.take(8).toList();

    if (topStats.isEmpty) return const SizedBox.shrink();

    final useFrequency = _selectedView == "Frequency";
    final colors = [
      const Color(0xFF6366F1),
      const Color(0xFF10B981),
      const Color(0xFFF59E0B),
      const Color(0xFFEC4899),
      const Color(0xFF8B5CF6),
      const Color(0xFF14B8A6),
      const Color(0xFFF97316),
      const Color(0xFF06B6D4),
    ];

    return GFCard(
      elevation: 0,
      color: Colors.white,
      padding: const EdgeInsets.all(16),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.pie_chart_outline, color: Color(0xFF6366F1), size: 20),
              const SizedBox(width: 8),
              Text(
                "Distribution by ${_selectedView}",
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1A1A1A),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 200,
            child: PieChart(
              PieChartData(
                sections: topStats.asMap().entries.map((entry) {
                  final index = entry.key;
                  final stat = entry.value;
                  final value = useFrequency ? stat.count.toDouble() : stat.totalAmount;
                  final total = useFrequency
                      ? topStats.fold<double>(0, (sum, s) => sum + s.count)
                      : topStats.fold<double>(0, (sum, s) => sum + s.totalAmount);
                  final percentage = (value / total * 100).toStringAsFixed(1);

                  return PieChartSectionData(
                    color: colors[index % colors.length],
                    value: value,
                    title: '$percentage%',
                    radius: 80,
                    titleStyle: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  );
                }).toList(),
                sectionsSpace: 2,
                centerSpaceRadius: 40,
                pieTouchData: PieTouchData(
                  touchCallback: (FlTouchEvent event, pieTouchResponse) {},
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: topStats.asMap().entries.map((entry) {
              final index = entry.key;
              final stat = entry.value;
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: colors[index % colors.length],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    stat.coaTitle.length > 20
                        ? '${stat.coaTitle.substring(0, 20)}...'
                        : stat.coaTitle,
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey[700],
                    ),
                  ),
                ],
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailedList(List<CoaStat> stats) {
    return GFCard(
      elevation: 0,
      color: Colors.white,
      padding: const EdgeInsets.all(16),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.list, color: Color(0xFF6366F1), size: 20),
              const SizedBox(width: 8),
              const Text(
                "All Accounts",
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1A1A1A),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...stats.map((stat) => _buildStatRow(stat)).toList(),
        ],
      ),
    );
  }

  Widget _buildStatRow(CoaStat stat) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF6366F1).withOpacity(0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Icon(
              Icons.account_balance_wallet,
              color: Color(0xFF6366F1),
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  stat.coaTitle,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1A1A1A),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  "${stat.count} transactions • ₱${_formatAmount(stat.totalAmount)}",
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              GFBadge(
                text: stat.count.toString(),
                color: const Color(0xFF6366F1),
                textColor: Colors.white,
                size: GFSize.SMALL,
              ),
              const SizedBox(height: 4),
              Text(
                "₱${_formatAmount(stat.totalAmount)}",
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF10B981),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  List<CoaStat> _computeCoaStats(List groups) {
    final Map<String, CoaStat> coaMap = {};

    for (final group in groups) {
      for (final item in group.items) {
        final title = item.coaTitle ?? "Unknown";
        if (!coaMap.containsKey(title)) {
          coaMap[title] = CoaStat(coaTitle: title, count: 0, totalAmount: 0.0);
        }
        coaMap[title] = CoaStat(
          coaTitle: title,
          count: coaMap[title]!.count + 1,
          totalAmount: coaMap[title]!.totalAmount + item.amount,
        );
      }
    }

    final stats = coaMap.values.toList();
    stats.sort((a, b) {
      if (_selectedView == "Frequency") {
        return b.count.compareTo(a.count);
      } else {
        return b.totalAmount.compareTo(a.totalAmount);
      }
    });

    return stats;
  }

  Widget _buildLoadingState() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF6366F1)),
          ),
          SizedBox(height: 16),
          Text(
            "Loading analytics...",
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.analytics_outlined, size: 80, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text(
            "No data available",
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            "Analytics will appear once you have disbursements",
            style: TextStyle(fontSize: 14, color: Colors.grey[500]),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(String error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 70, color: Colors.red[300]),
            const SizedBox(height: 12),
            Text(
              "Failed to load analytics",
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Colors.grey[800],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              error,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
            const SizedBox(height: 14),
            GFButton(
              onPressed: () {
                ref.read(disbursementControllerProvider.notifier).refresh();
              },
              text: "Retry",
              size: GFSize.SMALL,
              color: const Color(0xFF6366F1),
              textColor: Colors.white,
              shape: GFButtonShape.pills,
            ),
          ],
        ),
      ),
    );
  }

  String _formatAmount(double amount) {
    return amount.toStringAsFixed(2).replaceAllMapped(
      RegExp(r"(\d{1,3})(?=(\d{3})+(?!\d))"),
          (Match m) => "${m[1]},",
    );
  }

  String _formatCompactAmount(double amount) {
    if (amount >= 1000000) {
      return '${(amount / 1000000).toStringAsFixed(1)}M';
    } else if (amount >= 1000) {
      return '${(amount / 1000).toStringAsFixed(1)}K';
    }
    return amount.toStringAsFixed(0);
  }
}

class CoaStat {
  final String coaTitle;
  final int count;
  final double totalAmount;

  CoaStat({
    required this.coaTitle,
    required this.count,
    required this.totalAmount,
  });
}