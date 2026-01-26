// lib/modules/reports/accounts_payable/ap_view.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

// State + models
import 'package:vos_mobile/state/accounts_payable/accounts_payable_state.dart';

class APView extends ConsumerStatefulWidget {
  const APView({super.key});

  @override
  ConsumerState<APView> createState() => _APViewState();
}

class _APViewState extends ConsumerState<APView> {
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ap = ref.watch(accountsPayableProvider);
    final currencyFmt = ref.watch(currencyFmtPHProvider);

    // Sync text field with provider search
    if (_searchCtrl.text != ap.search) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _searchCtrl.text = ap.search;
        _searchCtrl.selection = TextSelection.fromPosition(
          TextPosition(offset: _searchCtrl.text.length),
        );
      });
    }

    final width = MediaQuery.sizeOf(context).width;
    final isTablet = width >= 900;
    final edge = EdgeInsets.all(isTablet ? 24 : 20);
    final topGap = isTablet ? 28.0 : 24.0;

    final headerTitleStyle = TextStyle(
      fontSize: isTablet ? 30 : 26,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.5,
    );
    final subtitleStyle = TextStyle(
      fontSize: isTablet ? 15 : 14,
      color: Colors.grey.shade600,
    );

    final fmtDate = DateFormat('MMM d, yyyy h:mm a').format(ap.lastUpdated);

    return RefreshIndicator(
      onRefresh: () => ref.read(accountsPayableProvider.notifier).refresh(),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: edge,
        children: [
          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  'Accounts Payable',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: headerTitleStyle,
                ),
              ),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.access_time, size: 14, color: Colors.orange.shade700),
                    const SizedBox(width: 4),
                    Text(
                      DateFormat('MMM d').format(ap.lastUpdated),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.orange.shade700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text('Outstanding payments to suppliers', style: subtitleStyle),
          SizedBox(height: topGap),

          // Key Metrics Cards
          Row(
            children: [
              Expanded(
                child: _metricCard(
                  title: 'Total Payables',
                  value: '₱${currencyFmt.format(ap.totalAP)}',
                  icon: Icons.payment_outlined,
                  color: Colors.orange,
                  isTablet: isTablet,
                ),
              ),
              SizedBox(width: isTablet ? 16 : 12),
              Expanded(
                child: _metricCard(
                  title: 'Overdue',
                  value: '₱${currencyFmt.format(ap.overdueAP)}',
                  icon: Icons.warning_amber_rounded,
                  color: ap.overdueAP > 0 ? Colors.red : Colors.green,
                  subtitle: ap.dueSoonCount > 0 ? '${ap.dueSoonCount} due soon' : 'All current',
                  isTablet: isTablet,
                ),
              ),
            ],
          ),
          SizedBox(height: isTablet ? 28 : 24),

          // Search
          TextField(
            controller: _searchCtrl,
            style: TextStyle(fontSize: isTablet ? 16 : 14),
            decoration: InputDecoration(
              hintText: 'Search Supplier',
              hintStyle: TextStyle(color: Colors.grey.shade400),
              prefixIcon: Icon(Icons.search, color: Colors.grey.shade400),
              filled: true,
              fillColor: Colors.grey.shade50,
              contentPadding: EdgeInsets.symmetric(
                vertical: isTablet ? 16 : 14,
                horizontal: isTablet ? 18 : 16,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.grey.shade200),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.grey.shade200),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.orange.shade300, width: 2),
              ),
            ),
            onChanged: (v) => ref.read(accountsPayableProvider.notifier).setSearch(v),
          ),
          SizedBox(height: isTablet ? 24 : 20),

          // Section Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Supplier',
                style: TextStyle(
                  fontSize: isTablet ? 18 : 16,
                  fontWeight: FontWeight.w700,
                  color: Colors.grey.shade800,
                ),
              ),
              Text(
                '${ap.vendors.length} ${ap.vendors.length == 1 ? 'supplier' : 'suppliers'}',
                style: TextStyle(
                  fontSize: isTablet ? 15 : 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Content (loading / error / empty / data)
          if (ap.loading) ...[
            _skeletonCard(isTablet: isTablet),
            const SizedBox(height: 12),
            _skeletonCard(isTablet: isTablet),
            const SizedBox(height: 12),
            _skeletonCard(isTablet: isTablet),
          ] else if ((ap.error ?? '').isNotEmpty) ...[
            _errorTile(ap.error!, isTablet: isTablet),
          ] else if (ap.vendors.isEmpty) ...[
            _emptyTile(
              ap.search.isEmpty ? 'No supplier found.' : 'No results for “${ap.search}”.',
              isTablet: isTablet,
            ),
          ] else ...[
            // ✅ Proper branching: list on mobile, grid on tablet
            if (!isTablet) ...[
              for (final v in ap.vendors)
                _apCard(
                  context,
                  vendorName: (v as dynamic).vendor ?? '',
                  total: ((v as dynamic).total ?? 0.0).toDouble(),
                  dueStr: (v as dynamic).due as String?,
                  status: (v as dynamic).status ?? 'Current',
                  remarks: (v as dynamic).remarks ?? '',
                  onTap: () => _openVendorDetail(
                    context,
                    ((v as dynamic).payeeId ?? 0) as int,
                    (v as dynamic).vendor ?? '',
                  ),
                  vendorName: v.vendor,
                  total: v.total,
                  dueStr: v.due,
                  status: v.status.isEmpty ? 'Not Due' : v.status,
                  remarks: v.remarks,
                  onTap: () => _openVendorDetail(context, v.payeeId, v.vendor),
                  currencyFmt: currencyFmt,
                  isTablet: isTablet,
                ),
            ] else ...[
              _VendorGrid(
                vendors: ap.vendors,
                buildCard: (APVendorCard v) {
                  return _GridApCard(
                    vendorName: v.vendor,
                    total: v.total,
                    dueStr: v.due,
                    status: v.status.isEmpty ? 'Not Due' : v.status,
                    remarks: v.remarks,
                    currencyFmt: currencyFmt,
                    onTap: () => _openVendorDetail(context, v.payeeId, v.vendor),
                  );
                },
              ),
            ],
          ],

          SizedBox(height: isTablet ? 28 : 24),
          Center(
            child: Text(
              'Last updated: $fmtDate',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade400),
            ),
          ),
        ],
      ),
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
          Row(
            children: [
              Container(
                padding: EdgeInsets.all(isTablet ? 10 : 8),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: isTablet ? 22 : 20, color: color),
              ),
              const Spacer(),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
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
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
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
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
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

  Widget _apCard(
      BuildContext context, {
        required String vendorName,
        required double total,
        required String? dueStr,
        required String status,
        required String remarks,
        required NumberFormat currencyFmt,
        required VoidCallback onTap,
        required bool isTablet,
      }) {
    final dueDate = (dueStr ?? '').isNotEmpty ? DateTime.tryParse(dueStr!) : null;

    final statusColor = switch (status) {
      'Overdue' => Colors.red,
      'Due Soon' => Colors.orange,
      'Settled' => Colors.teal,
      _ => Colors.green,
    };

    final statusIcon = switch (status) {
      'Overdue' => Icons.error_outline,
      'Due Soon' => Icons.schedule,
      'Settled' => Icons.task_alt,
      _ => Icons.check_circle_outline,
    };

    // Days until due
    String daysInfo = '';
    if (dueDate != null) {
      final now = DateTime.now();
      final diff = dueDate.difference(DateTime(now.year, now.month, now.day)).inDays;
      if (diff < 0) {
        daysInfo = '${diff.abs()} days overdue';
      } else if (diff == 0) {
        daysInfo = 'Due today';
      } else if (diff <= 7) {
        daysInfo = 'Due in $diff days';
      } else {
        daysInfo = 'Due in ${(diff / 7).floor()} weeks';
      }
    }

    final remarkBullets = (remarks.isEmpty
        ? <String>[]
        : remarks
        .split(' | ')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .take(3)
        .toList());

    return InkWell(
      onTap: onTap,
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
            // Header row
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    vendorName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: isTablet ? 18 : 17,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.3,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 160),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
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
                        Flexible(
                          child: Text(
                            status,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: statusColor,
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                              letterSpacing: 0.2,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Amount + Due
            Container(
              padding: EdgeInsets.all(isTablet ? 14 : 12),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
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
                        const SizedBox(height: 2),
                        Text(
                          'unpaid balance (per bill)',
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.grey.shade500,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (dueDate != null)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          DateFormat('MMM d, yyyy').format(dueDate),
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: Colors.grey.shade700,
                          ),
                        ),
                        if (daysInfo.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            daysInfo,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: statusColor,
                            ),
                          ),
                        ],
                      ],
                    ),
                ],
              ),
            ),

            // Remarks
            if (remarkBullets.isNotEmpty) ...[
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.notes_rounded, size: 14, color: Colors.grey.shade500),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final b in remarkBullets)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 2),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('• ', style: TextStyle(fontSize: 12)),
                                Expanded(
                                  child: Text(
                                    b,
                                    softWrap: true,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey.shade700,
                                      fontStyle: FontStyle.italic,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        if (remarks.split(' | ').length > 3)
                          Text(
                            '… more',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey.shade500,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _openVendorDetail(BuildContext context, int payeeId, String vendorName) {
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
          child: _VendorDetail(payeeId: payeeId, name: vendorName),
        ),
      ),
    );
  }

  Widget _skeletonCard({required bool isTablet}) {
    return Container(
      height: isTablet ? 96 : 88,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade100),
      ),
      child: Row(
        children: [
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _shimmerBar(width: double.infinity, height: 12),
                const SizedBox(height: 8),
                _shimmerBar(width: double.infinity, height: 12),
              ],
            ),
          ),
          const SizedBox(width: 16),
        ],
      ),
    );
  }

  Widget _shimmerBar({required double width, required double height}) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(8),
      ),
    );
  }

  Widget _errorTile(String error, {required bool isTablet}) {
    return Container(
      padding: EdgeInsets.all(isTablet ? 18 : 16),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.shade100),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: Colors.red.shade400),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              error,
              style: TextStyle(color: Colors.red.shade700),
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyTile(String msg, {required bool isTablet}) {
    return Container(
      padding: EdgeInsets.all(isTablet ? 18 : 16),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Text(
        msg,
        style: TextStyle(color: Colors.grey.shade500, fontStyle: FontStyle.italic),
      ),
    );
  }
}

class _VendorGrid extends StatelessWidget {
  final List<APVendorCard> vendors;
  final Widget Function(APVendorCard v) buildCard;

  const _VendorGrid({
    required this.vendors,
    required this.buildCard,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (ctx, c) {
        final w = c.maxWidth;
        final ideal = (w / 400).floor();
        final crossAxisCount = ideal.clamp(2, 4);

        return GridView.builder(
          shrinkWrap: true,
          primary: false,
          itemCount: vendors.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            mainAxisExtent: 160,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
          ),
          itemBuilder: (ctx, i) => buildCard(vendors[i]),
        );
      },
    );
  }
}

class _GridApCard extends StatelessWidget {
  final String vendorName;
  final double total;
  final String? dueStr;
  final String status;
  final String remarks;
  final NumberFormat currencyFmt;
  final VoidCallback onTap;

  const _GridApCard({
    required this.vendorName,
    required this.total,
    required this.dueStr,
    required this.status,
    required this.remarks,
    required this.currencyFmt,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final dueDate = (dueStr ?? '').isNotEmpty ? DateTime.tryParse(dueStr!) : null;

    final statusColor = switch (status) {
      'Overdue' => Colors.red,
      'Due Soon' => Colors.orange,
      'Settled' => Colors.teal,
      _ => Colors.green,
    };

    String daysInfo = '';
    if (dueDate != null) {
      final now = DateTime.now();
      final diff = dueDate.difference(DateTime(now.year, now.month, now.day)).inDays;
      if (diff < 0) {
        daysInfo = '${diff.abs()}d overdue';
      } else if (diff == 0) {
        daysInfo = 'Due today';
      } else if (diff <= 7) {
        daysInfo = 'In $diff d';
      } else {
        daysInfo = 'In ${(diff / 7).floor()} w';
      }
    }

    final remarkBullets = (remarks.isEmpty
        ? <String>[]
        : remarks.split(' | ').map((s) => s.trim()).where((s) => s.isNotEmpty).take(2).toList());

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
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      vendorName,
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
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      status,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: statusColor,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              Row(
                children: [
                  Expanded(
                    child: Text(
                      '₱${currencyFmt.format(total)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                      ),
                    ),
                  ),
                  if (dueDate != null) ...[
                    const SizedBox(width: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          DateFormat('MMM d').format(dueDate),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Colors.grey.shade700,
                          ),
                        ),
                        if (daysInfo.isNotEmpty)
                          Text(
                            daysInfo,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: statusColor,
                            ),
                          ),
                      ],
                    ),
                  ],
                ],
              ),

              if (remarkBullets.isNotEmpty) ...[
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.notes_rounded, size: 12, color: Colors.grey.shade400),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final b in remarkBullets)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 2),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('• ', style: TextStyle(fontSize: 11)),
                                  Expanded(
                                    child: Text(
                                      b,
                                      softWrap: true,
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey.shade600,
                                        fontStyle: FontStyle.italic,
                                      ),
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
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _VendorDetail extends ConsumerWidget {
  final int payeeId;
  final String name;
  const _VendorDetail({required this.payeeId, required this.name});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fmt = NumberFormat('#,##0.00', 'en_PH');

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.8,
      ),
      child: FutureBuilder<List<APBillItem>>(
        future: ref.read(accountsPayableProvider.notifier).getVendorBillsForUI(payeeId),
        builder: (context, snap) {
          final loading = snap.connectionState == ConnectionState.waiting;
          final error = snap.error;
          final bills = snap.data;

          double total = 0;
          if (bills != null) {
            for (final b in bills) {
              total += b.amount;
            }
          }

          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
            shrinkWrap: true,
            children: [
              Text(
                name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: -0.5),
              ),
              const SizedBox(height: 4),
              Text(
                'Vendor Details',
                style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 20),

              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Total Amount Due',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.orange.shade700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            loading ? '—' : '₱${fmt.format(total)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: Colors.orange.shade900,
                              letterSpacing: -0.5,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'sum of per-bill unpaid balances',
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.orange.shade700,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade100,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(Icons.receipt_long, color: Colors.orange.shade700, size: 28),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              Text(
                'Outstanding Bills',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Colors.grey.shade800,
                ),
              ),
              const SizedBox(height: 12),

              if (loading) ...[
                _billSkeleton(),
                const SizedBox(height: 8),
                _billSkeleton(),
              ] else if (error != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    border: Border.all(color: Colors.red.shade100),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.error_outline, color: Colors.red.shade300),
                      const SizedBox(width: 8),
                      Expanded(child: Text(error.toString(), style: TextStyle(color: Colors.red.shade700))),
                    ],
                  ),
                ),
              ] else if (bills == null || bills.isEmpty) ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Text('No outstanding bills.', style: TextStyle(color: Colors.grey.shade500)),
                ),
              ] else ...[
                for (final bill in bills) _billCard(bill, fmt),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _billCard(APBillItem bill, NumberFormat fmt) {
    final dueDate = bill.due != null ? DateTime.tryParse(bill.due!) : null;
    String status = 'Current';
    Color statusColor = Colors.green;

    if (dueDate != null) {
      final now = DateTime.now();
      final diff = dueDate.difference(DateTime(now.year, now.month, now.day)).inDays;
      if (diff < 0) {
        status = 'Overdue';
        statusColor = Colors.red;
      } else if (diff <= 7) {
        status = 'Due Soon';
        statusColor = Colors.orange;
      }
    }

    final hasPrimaryCoa = (bill.primaryCoaGl ?? bill.primaryCoaTitle) != null;

    final remarkBullets = (bill.remarks.isEmpty
        ? <String>[]
        : bill.remarks.split(' | ').map((s) => s.trim()).where((s) => s.isNotEmpty).toList());

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      bill.no,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (hasPrimaryCoa) ...[
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '${bill.primaryCoaGl ?? ''}'
                              '${(bill.primaryCoaGl != null && bill.primaryCoaTitle != null) ? ' - ' : ''}'
                              '${bill.primaryCoaTitle ?? ''}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.blue.shade700,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  status,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: statusColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          Row(
            children: [
              Expanded(
                child: Text(
                  dueDate == null ? '—' : 'Due: ${DateFormat('MMM d, yyyy').format(dueDate)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey.shade600,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '₱${fmt.format(bill.amount)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'unpaid balance',
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.grey.shade500,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
            ],
          ),

          if (remarkBullets.isNotEmpty || ((bill.coaList ?? '').trim().isNotEmpty)) ...[
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.notes_rounded, size: 12, color: Colors.grey.shade400),
                const SizedBox(width: 4),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (remarkBullets.isNotEmpty)
                        ...remarkBullets.map(
                              (b) => Padding(
                            padding: const EdgeInsets.only(bottom: 2),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('• ', style: TextStyle(fontSize: 11)),
                                Expanded(
                                  child: Text(
                                    b,
                                    softWrap: true,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey.shade600,
                                      fontStyle: FontStyle.italic,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      if ((bill.coaList ?? '').trim().isNotEmpty) ...[
                        if (remarkBullets.isNotEmpty) const SizedBox(height: 6),
                        Text(
                          bill.coaList!,
                          softWrap: true,
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.blueGrey.shade600,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _billSkeleton() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.grey.shade200),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          Row(children: [
            _sk(90, 12),
            const SizedBox(width: 8),
            Expanded(child: _sk(double.infinity, 12)),
            const SizedBox(width: 8),
            _sk(60, 12),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: _sk(double.infinity, 10)),
            const SizedBox(width: 8),
            _sk(80, 14),
          ]),
        ],
      ),
    );
  }

  Widget _sk(double w, double h) => Container(
    width: w,
    height: h,
    decoration: BoxDecoration(
      color: Colors.grey.shade200,
      borderRadius: BorderRadius.circular(6),
    ),
  );
}
