import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:getwidget/getwidget.dart';

import 'package:vos_mobile/state/accounts_receivable_state/account_receivable_state.dart';

class ARView extends ConsumerStatefulWidget {
  const ARView({super.key});

  @override
  ConsumerState<ARView> createState() => _ARViewState();
}

class _ARViewState extends ConsumerState<ARView> {
  final currencyFmt = NumberFormat('#,##0.00', 'en_PH');

  // Aging filter state
  // Allowed values: 'All', 'Current', '1-30', '31-60', '61-90', '90+'
  String _selectedAging = 'All';
  static const List<String> _agingFilters = [
    'All',
    'Current',
    '1-30',
    '31-60',
    '61-90',
    '90+',
  ];

  // Salesman filter state
  // 'All' + distinct salesman names/codes from data
  String _selectedSalesman = 'All';

  @override
  void initState() {
    super.initState();
    // Ensure we load fresh data when the screen opens
    Future.microtask(() => ref.read(arNotifierProvider.notifier).refresh());
  }

  @override
  Widget build(BuildContext context) {
    final clients = ref.watch(arFilteredClientsProvider); // List<ClientAR> (already search-filtered)
    final totals = ref.watch(arTotalsProvider); // (totalAR, totalOverdue, overdueClientCount, agingTotals)
    final lastUpdated = ref.watch(arLastUpdatedProvider);
    final isLoading = ref.watch(arIsLoadingProvider);

    // Build salesman options from current dataset
    final salesmanOptions = _buildSalesmanOptions(clients);
    if (!salesmanOptions.contains(_selectedSalesman)) {
      _selectedSalesman = 'All';
    }

    // Apply aging + salesman filters on top of search-filtered clients
    final filteredClients = _applyAgingFilter(clients);

    final width = MediaQuery.sizeOf(context).width;
    final isTablet = width >= 900;

    final horizontalPadding = isTablet ? 24.0 : 20.0;
    final verticalPadding = isTablet ? 24.0 : 20.0;

    final headerTitleStyle = TextStyle(
      fontSize: isTablet ? 30 : 26,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.5,
    );
    final subStyle = TextStyle(
      fontSize: isTablet ? 15 : 14,
      color: Colors.grey.shade600,
    );
    final blockGap = isTablet ? 28.0 : 24.0;

    return RefreshIndicator(
      onRefresh: () async => ref.read(arNotifierProvider.notifier).refresh(),
      child: Stack(
        children: [
          CustomScrollView(
            slivers: [
              // ---------- Header + metrics + aging analysis + search + chips + salesman filter ----------
              SliverPadding(
                padding: EdgeInsets.fromLTRB(
                  horizontalPadding,
                  verticalPadding,
                  horizontalPadding,
                  0,
                ),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Accounts Receivable',
                            style: headerTitleStyle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.blue.shade50,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.access_time,
                                  size: 14,
                                  color: Colors.blue.shade700,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  DateFormat('MMM d').format(lastUpdated),
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.blue.shade700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Outstanding payments from customers',
                        style: subStyle,
                      ),
                      SizedBox(height: blockGap),

                      // Key Metrics Cards
                      Row(
                        children: [
                          Expanded(
                            child: _metricCard(
                              title: 'Total Receivables',
                              value: '₱${currencyFmt.format(totals.totalAR)}',
                              icon: Icons.account_balance_wallet_outlined,
                              color: Colors.blue,
                              isTablet: isTablet,
                            ),
                          ),
                          SizedBox(width: isTablet ? 16 : 12),
                          Expanded(
                            child: _metricCard(
                              title: 'Overdue Amount',
                              value:
                              '₱${currencyFmt.format(totals.totalOverdue)}',
                              icon: Icons.warning_amber_rounded,
                              color: totals.totalOverdue > 0
                                  ? Colors.red
                                  : Colors.green,
                              subtitle: totals.overdueClientCount > 0
                                  ? '${totals.overdueClientCount} ${totals.overdueClientCount == 1 ? 'client' : 'clients'}'
                                  : 'All current',
                              isTablet: isTablet,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: blockGap),

                      // Aging Analysis Section (now with GFProgressBar)
                      Container(
                        padding: EdgeInsets.all(isTablet ? 22 : 20),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Colors.indigo.shade50,
                              Colors.blue.shade50,
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.indigo.shade100),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: EdgeInsets.all(
                                    isTablet ? 12 : 10,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.indigo.shade100,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Icon(
                                    Icons.analytics_outlined,
                                    color: Colors.indigo.shade700,
                                    size: isTablet ? 26 : 24,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  'Aging Analysis',
                                  style: TextStyle(
                                    fontSize: isTablet ? 20 : 18,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: -0.3,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            _agingBar(
                              label: 'Current',
                              amount: totals.agingTotals['current'] ?? 0,
                              total: totals.totalAR,
                              color: Colors.green,
                            ),
                            const SizedBox(height: 10),
                            _agingBar(
                              label: '1-30 days',
                              amount: totals.agingTotals['1-30'] ?? 0,
                              total: totals.totalAR,
                              color: Colors.blue,
                            ),
                            const SizedBox(height: 10),
                            _agingBar(
                              label: '31-60 days',
                              amount: totals.agingTotals['31-60'] ?? 0,
                              total: totals.totalAR,
                              color: Colors.orange,
                            ),
                            const SizedBox(height: 10),
                            _agingBar(
                              label: '61-90 days',
                              amount: totals.agingTotals['61-90'] ?? 0,
                              total: totals.totalAR,
                              color: Colors.deepOrange,
                            ),
                            const SizedBox(height: 10),
                            _agingBar(
                              label: '90+ days',
                              amount: totals.agingTotals['90+'] ?? 0,
                              total: totals.totalAR,
                              color: Colors.red,
                            ),
                          ],
                        ),
                      ),
                      SizedBox(height: blockGap),

                      // Search
                      TextField(
                        decoration: InputDecoration(
                          hintText: 'Search clients...',
                          hintStyle: TextStyle(color: Colors.grey.shade400),
                          prefixIcon: Icon(
                            Icons.search,
                            color: Colors.grey.shade400,
                          ),
                          filled: true,
                          fillColor: Colors.grey.shade50,
                          contentPadding: EdgeInsets.symmetric(
                            vertical: isTablet ? 16 : 14,
                            horizontal: isTablet ? 18 : 16,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: Colors.grey.shade200,
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: Colors.grey.shade200,
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: Colors.blue.shade300,
                              width: 2,
                            ),
                          ),
                        ),
                        onChanged: (v) =>
                            ref.read(arNotifierProvider.notifier).setSearch(v),
                      ),
                      const SizedBox(height: 12),

                      // Aging filter chips
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: _agingFilters.map((label) {
                            final selected = _selectedAging == label;
                            return Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ChoiceChip(
                                label: Text(
                                  label == 'Current'
                                      ? 'Current'
                                      : label == 'All'
                                      ? 'All'
                                      : '$label days',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: selected
                                        ? Colors.white
                                        : Colors.grey.shade700,
                                  ),
                                ),
                                selected: selected,
                                selectedColor: Colors.blue,
                                backgroundColor: Colors.grey.shade100,
                                onSelected: (_) {
                                  setState(() {
                                    _selectedAging = label;
                                  });
                                },
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Salesman filter (dropdown)
                      DropdownButtonFormField<String>(
                        value: _selectedSalesman,
                        decoration: InputDecoration(
                          labelText: 'Filter by salesman',
                          prefixIcon: const Icon(
                            Icons.person_search_outlined,
                            size: 20,
                          ),
                          contentPadding: EdgeInsets.symmetric(
                            vertical: isTablet ? 14 : 12,
                            horizontal: isTablet ? 18 : 16,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: Colors.grey.shade200,
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: Colors.grey.shade200,
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: Colors.blue.shade300,
                              width: 2,
                            ),
                          ),
                        ),
                        items: salesmanOptions
                            .map(
                              (name) => DropdownMenuItem<String>(
                            value: name,
                            child: Text(
                              name == 'All' ? 'All salesmen' : name,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                            .toList(),
                        onChanged: (value) {
                          if (value == null) return;
                          setState(() {
                            _selectedSalesman = value;
                          });
                        },
                      ),
                      const SizedBox(height: 20),

                      // Section Header
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Client Accounts',
                            style: TextStyle(
                              fontSize: isTablet ? 18 : 16,
                              fontWeight: FontWeight.w700,
                              color: Colors.grey.shade800,
                            ),
                          ),
                          Text(
                            '${filteredClients.length} ${filteredClients.length == 1 ? 'client' : 'clients'}',
                            style: TextStyle(
                              fontSize: isTablet ? 15 : 14,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey.shade500,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                    ],
                  ),
                ),
              ),

              // ---------- Client cards list / grid ----------
              SliverPadding(
                padding: EdgeInsets.symmetric(
                  horizontal: horizontalPadding,
                ),
                sliver: filteredClients.isEmpty
                    ? SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Text(
                      'No clients match the current filters.',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade500,
                      ),
                    ),
                  ),
                )
                    : (isTablet
                    ? SliverGrid(
                  delegate: SliverChildBuilderDelegate(
                        (ctx, index) {
                      final c = filteredClients[index];
                      return _GridClientCard(
                        client: c,
                        currencyFmt: currencyFmt,
                        onTap: () => _openClientDetail(context, c),
                      );
                    },
                    childCount: filteredClients.length,
                  ),
                  gridDelegate:
                  const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisExtent: 150,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                  ),
                )
                    : SliverList(
                  delegate: SliverChildBuilderDelegate(
                        (ctx, index) {
                      final c = filteredClients[index];
                      return Padding(
                        padding: EdgeInsets.only(
                          bottom: index ==
                              filteredClients.length - 1
                              ? 0
                              : 12,
                        ),
                        child: _arCard(
                          context,
                          c,
                          isTablet: false,
                        ),
                      );
                    },
                    childCount: filteredClients.length,
                  ),
                )),
              ),

              // ---------- Footer (last updated) ----------
              SliverPadding(
                padding: EdgeInsets.fromLTRB(
                  horizontalPadding,
                  blockGap,
                  horizontalPadding,
                  blockGap,
                ),
                sliver: SliverToBoxAdapter(
                  child: Center(
                    child: Text(
                      'Last updated: ${DateFormat('MMM d, yyyy h:mm a').format(lastUpdated)}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade400,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),

          if (isLoading)
            Positioned.fill(
              child: IgnorePointer(
                child: Center(
                  child: GFLoader(
                    type: GFLoaderType.circle,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ---------- Helpers for filters ----------

  // Build salesman options from current clients
  List<String> _buildSalesmanOptions(List<ClientAR> clients) {
    final set = <String>{};
    for (final client in clients) {
      for (final inv in client.invoices) {
        final name = inv.salesmanName.trim();
        final code = inv.salesmanCode.trim();
        if (name.isNotEmpty) {
          set.add(name);
        } else if (code.isNotEmpty) {
          set.add(code);
        }
      }
    }

    final list = set.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    return ['All', ...list];
  }

  // Aging + salesman filtering logic
  List<ClientAR> _applyAgingFilter(List<ClientAR> clients) {
    // Start from the search-filtered list
    List<ClientAR> result = clients;

    // Apply aging filter (use cents to avoid "₱0.00 but > 0" issues)
    if (_selectedAging != 'All') {
      String bucketKey;
      switch (_selectedAging) {
        case 'Current':
          bucketKey = 'current';
          break;
        case '1-30':
          bucketKey = '1-30';
          break;
        case '31-60':
          bucketKey = '31-60';
          break;
        case '61-90':
          bucketKey = '61-90';
          break;
        case '90+':
          bucketKey = '90+';
          break;
        default:
          bucketKey = 'current';
      }
      result = result
          .where((c) => (c.agingCents[bucketKey] ?? 0) > 0)
          .toList();
    }

    // Apply salesman filter
    if (_selectedSalesman == 'All') return result;

    final target = _selectedSalesman;
    return result.where((c) {
      return c.invoices.any((inv) {
        final name = inv.salesmanName.trim();
        final code = inv.salesmanCode.trim();
        final label = name.isNotEmpty ? name : (code.isNotEmpty ? code : '');
        return label == target;
      });
    }).toList();
  }

  // ---------- Widgets ----------

  Widget _agingBar({
    required String label,
    required double amount,
    required double total,
    required Color color,
  }) {
    final percentage = total > 0 ? (amount / total * 100) : 0.0;
    final fraction = total > 0 ? (amount / total).clamp(0.0, 1.0) : 0.0;

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade700,
              ),
            ),
            Text(
              '₱${currencyFmt.format(amount)}',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Colors.grey.shade800,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        GFProgressBar(
          percentage: fraction,
          lineHeight: 8,
          backgroundColor: Colors.white.withOpacity(0.5),
          progressBarColor: color,
          animation: true,
        ),
        const SizedBox(height: 4),
        Align(
          alignment: Alignment.centerRight,
          child: Text(
            '${percentage.toStringAsFixed(1)}%',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade600,
            ),
          ),
        ),
      ],
    );
  }

  Widget _metricCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
    required bool isTablet,
    String? subtitle,
  }) {
    return Container(
      padding: EdgeInsets.all(isTablet ? 18 : 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              padding: EdgeInsets.all(isTablet ? 10 : 8),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, size: isTablet ? 22 : 20, color: color),
            ),
            const Spacer(),
          ]),
          const SizedBox(height: 12),
          Text(
            title,
            style: TextStyle(
              fontSize: isTablet ? 13 : 12,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade600,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: isTablet ? 20 : 18,
              fontWeight: FontWeight.w800,
              color: Colors.grey.shade900,
              letterSpacing: -0.5,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: isTablet ? 12 : 11,
                fontWeight: FontWeight.w500,
                color: Colors.grey.shade500,
              ),
            ),
          ],
        ],
      ),
    );
  }

  // Build a summary salesman label per client
  String _buildSalesmanLabel(ClientAR c) {
    final names = c.invoices
        .map((inv) {
      final name = inv.salesmanName.trim();
      final code = inv.salesmanCode.trim();
      if (name.isNotEmpty) return name;
      if (code.isNotEmpty) return code;
      return '';
    })
        .where((s) => s.isNotEmpty)
        .toSet()
        .toList();

    if (names.isEmpty) return 'Salesman: Unassigned';
    if (names.length == 1) return 'Salesman: ${names.first}';
    final first = names.first;
    final others = names.length - 1;
    return 'Salesmen: $first +$others more';
  }

  Widget _arCard(BuildContext context, ClientAR c, {required bool isTablet}) {
    final clientName = c.client;
    final overdue = c.overdue;
    final total = c.total;
    final status = c.status;

    final statusColor = switch (status) {
      'Overdue' => Colors.red,
      'Partial' => Colors.orange,
      _ => Colors.green,
    };
    final statusIcon = switch (status) {
      'Overdue' => Icons.error_outline,
      'Partial' => Icons.schedule,
      _ => Icons.check_circle_outline,
    };

    final salesmanLabel = _buildSalesmanLabel(c);

    return InkWell(
      onTap: () => _openClientDetail(context, c),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: EdgeInsets.all(isTablet ? 18 : 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade200),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.02),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // header row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        clientName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: isTablet ? 18 : 17,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Total Outstanding',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade500,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        salesmanLabel,
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade600,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(.12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: statusColor.withOpacity(.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(statusIcon, size: 14, color: statusColor),
                      const SizedBox(width: 4),
                      Text(
                        status,
                        style: TextStyle(
                          color: statusColor,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // amount area
            Container(
              padding: EdgeInsets.all(isTablet ? 14 : 12),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '₱${currencyFmt.format(total)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: isTablet ? 22 : 20,
                        fontWeight: FontWeight.w800,
                        color: Colors.grey.shade900,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ),
                  if (overdue > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.red.shade200),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            'OVERDUE',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              color: Colors.red.shade700,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '₱${currencyFmt.format(overdue)}',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: Colors.red.shade700,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openClientDetail(BuildContext context, ClientAR client) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: _ClientDetail(client: client, currencyFmt: currencyFmt),
        ),
      ),
    );
  }
}

// ==================== Grid Card (tablet) ====================

class _GridClientCard extends StatelessWidget {
  final ClientAR client;
  final NumberFormat currencyFmt;
  final VoidCallback onTap;

  const _GridClientCard({
    required this.client,
    required this.currencyFmt,
    required this.onTap,
  });

  // local helper to summarize salesmen per client
  String _buildSalesmanLabel() {
    final names = client.invoices
        .map((inv) {
      final name = inv.salesmanName.trim();
      final code = inv.salesmanCode.trim();
      if (name.isNotEmpty) return name;
      if (code.isNotEmpty) return code;
      return '';
    })
        .where((s) => s.isNotEmpty)
        .toSet()
        .toList();

    if (names.isEmpty) return 'Salesman: Unassigned';
    if (names.length == 1) return 'Salesman: ${names.first}';
    final first = names.first;
    final others = names.length - 1;
    return 'Salesmen: $first +$others more';
  }

  @override
  Widget build(BuildContext context) {
    final status = client.status;
    final overdue = client.overdue;
    final statusColor = switch (status) {
      'Overdue' => Colors.red,
      'Partial' => Colors.orange,
      _ => Colors.green,
    };

    final salesmanLabel = _buildSalesmanLabel();

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: Text(
                    client.client,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.2,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    status,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: statusColor,
                    ),
                  ),
                ),
              ]),
              const SizedBox(height: 4),
              Text(
                salesmanLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey.shade600,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                  child: Text(
                    '₱${currencyFmt.format(client.total)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3,
                    ),
                  ),
                ),
                if (overdue > 0) ...[
                  const SizedBox(width: 8),
                  Text(
                    '₱${currencyFmt.format(overdue)}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Colors.red.shade700,
                    ),
                  ),
                ],
              ]),
            ],
          ),
        ),
      ),
    );
  }
}

// ==================== Bottom Sheet ====================

class _ClientDetail extends StatelessWidget {
  final ClientAR client;
  final NumberFormat currencyFmt;

  const _ClientDetail({required this.client, required this.currencyFmt});

  @override
  Widget build(BuildContext context) {
    // Outstanding per-invoice = invoice.balance (cent-based filter)
    final invoices = client.invoices
        .where((i) => i.balanceCents > 0)
        .toList()
      ..sort(
            (a, b) => (a.dueDate ?? DateTime(2100))
            .compareTo(b.dueDate ?? DateTime(2100)),
      );

    final total = invoices.fold<double>(
      0,
          (sum, inv) => sum + inv.balance,
    );

    // Group by salesman for this client
    final bySalesman = <String, double>{};
    for (final inv in invoices) {
      final name = _invoiceSalesmanLabel(inv);
      bySalesman[name] = (bySalesman[name] ?? 0) + inv.balance;
    }

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.8,
      ),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
        shrinkWrap: true,
        children: [
          Text(
            client.client,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Client Details',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 20),

          // Summary Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.blue.shade200),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Total Outstanding',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.blue.shade700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '₱${currencyFmt.format(total)}',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: Colors.blue.shade900,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade100,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.receipt_long,
                    color: Colors.blue.shade700,
                    size: 28,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Client Aging Breakdown
          Text(
            'Aging Breakdown',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Colors.grey.shade800,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Column(
              children: [
                _agingRow('Current', client.aging['current'], Colors.green),
                _divider(),
                _agingRow('1-30 days', client.aging['1-30'], Colors.blue),
                _divider(),
                _agingRow('31-60 days', client.aging['31-60'], Colors.orange),
                _divider(),
                _agingRow('61-90 days', client.aging['61-90'],
                    Colors.deepOrange),
                _divider(),
                _agingRow('90+ days', client.aging['90+'], Colors.red),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // By salesman
          if (bySalesman.isNotEmpty) ...[
            Text(
              'By Salesman',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Colors.grey.shade800,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Column(
                children: bySalesman.entries
                    .map((e) => _salesmanRow(e.key, e.value))
                    .toList(),
              ),
            ),
            const SizedBox(height: 20),
          ],

          Text(
            'Outstanding Invoices',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Colors.grey.shade800,
            ),
          ),
          const SizedBox(height: 12),

          for (final inv in invoices) _invoiceCard(inv),
        ],
      ),
    );
  }

  Widget _divider() => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Divider(
      color: Colors.grey.shade300,
      height: 1,
    ),
  );

  Widget _agingRow(String label, dynamic amount, Color color) {
    final value = (amount as num?)?.toDouble() ?? 0;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade700,
            ),
          ),
        ]),
        Text(
          '₱${currencyFmt.format(value)}',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: value > 0 ? Colors.grey.shade900 : Colors.grey.shade400,
          ),
        ),
      ],
    );
  }

  Widget _salesmanRow(String name, double amount) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(children: [
            const Icon(Icons.person_outline, size: 16),
            const SizedBox(width: 8),
            Text(
              name,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade800,
              ),
            ),
          ]),
          Text(
            '₱${currencyFmt.format(amount)}',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: Colors.grey.shade900,
            ),
          ),
        ],
      ),
    );
  }

  String _invoiceSalesmanLabel(InvoiceAR inv) {
    final name = inv.salesmanName.trim();
    final code = inv.salesmanCode.trim();
    if (name.isNotEmpty) return name;
    if (code.isNotEmpty) return code;
    return 'Unassigned';
  }

  String _agingLabel(String bucket) {
    switch (bucket) {
      case '1-30':
        return '1-30 days';
      case '31-60':
        return '31-60 days';
      case '61-90':
        return '61-90 days';
      case '90+':
        return '90+ days';
      case 'current':
      default:
        return 'Current';
    }
  }

  Widget _invoiceCard(InvoiceAR inv) {
    final status = inv.uiStatus; // 'Current' or 'Overdue'
    final statusColor = status == 'Overdue' ? Colors.red : Colors.green;
    final dueDate = inv.dueDate;
    final amount = inv.balance;
    final salesman = _invoiceSalesmanLabel(inv);
    final aging = _agingLabel(inv.agingBucket);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 70,
            decoration: BoxDecoration(
              color: statusColor,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // top row with invoice no + chip
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      inv.invoiceNo,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: statusColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        status,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: statusColor,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                // due + amount
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      dueDate == null
                          ? '—'
                          : 'Due: ${DateFormat('MMM d, yyyy').format(dueDate)}',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    Text(
                      '₱${currencyFmt.format(amount)}',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                // salesman + aging
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Salesman: $salesman',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    Text(
                      aging,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: statusColor,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
