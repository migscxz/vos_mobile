// lib/modules/reports/report_view.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vos_mobile/modules/reports/assets_and_equipments/assets_and_equipments_view.dart';
import '../../core/theme/app_theme.dart' as core_theme;
import '../../state/app_state.dart';

// Specific report UIs
import 'delivery_report/delivery_report_view.dart';
import 'accounts_payable/ap_view.dart';
import 'accounts_receivable/ar_view.dart';
import 'disbursement/disburment_view.dart';
import 'sales_report/sr_view.dart';
import 'assets_and_equipments/assets_and_equipments_view.dart';

class ReportView extends ConsumerWidget {
  const ReportView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(selectedReportProvider);
    if (selected == null) {
      return const _EmptyState(title: 'Select a report on the left');
    }

    // Route to rich, dedicated screens based on ID
    switch (selected.id) {
      case 'delivery':
        return const DeliveryReportView(); // full-featured Delivery report
      case 'ar':
        return const ARView(); // Accounts Receivable screen
      case 'ap':
        return const APView(); // Accounts Payable screen
      case 'disb':
        return const DisbursementView(); // Disbursement screen
      case 'sales':
        return const SalesReportView(); // Sales Report screen
      case 'asset':
        return const AssetsAndEquipmentsView();
      default:
      // Fallback: generic shell for other report types
        final visual = _resolveVisual(selected.id, selected.title);
        return _GenericReportShell(
          title: selected.title,
          icon: visual.icon,
          iconName: visual.name,
        );
    }
  }
}

/// Small holder for header visuals
class _ReportVisual {
  final IconData icon;
  final String name;
  const _ReportVisual(this.icon, this.name);
}

_ReportVisual _resolveVisual(String id, String titleFallback) {
  switch (id) {
    case 'delivery':
      return const _ReportVisual(Icons.local_shipping, 'Delivery');
    case 'ar':
      return const _ReportVisual(Icons.request_quote, 'Accounts Receivable');
    case 'ap':
      return const _ReportVisual(Icons.account_balance_wallet, 'Accounts Payable');
    case 'disb':
      return const _ReportVisual(Icons.receipt_long, 'Disbursement');
    case 'sales':
      return const _ReportVisual(Icons.bar_chart, 'Sales Report');
    default:
      return _ReportVisual(Icons.insert_chart_outlined, titleFallback);
  }
}

class _GenericReportShell extends StatelessWidget {
  final String title;
  final IconData icon;
  final String iconName;
  const _GenericReportShell({
    required this.title,
    required this.icon,
    required this.iconName,
  });

  bool get _isWideTablet => false; // reserved for future if needed

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final isTablet = width >= 900;

    final headerPad = EdgeInsets.fromLTRB(
      isTablet ? 24 : 16,
      isTablet ? 24 : 16,
      isTablet ? 24 : 16,
      isTablet ? 18 : 14,
    );

    final contentPad = EdgeInsets.fromLTRB(
      isTablet ? 16 : 12,
      isTablet ? 12 : 10,
      isTablet ? 16 : 12,
      isTablet ? 16 : 12,
    );

    final actionsGap = isTablet ? 12.0 : 8.0;

    // Constrain super-wide tablets/desktops for better readability
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1200),
        child: Column(
          children: [
            // Gradient hero
            Container(
              width: double.infinity,
              padding: headerPad,
              decoration: BoxDecoration(
                gradient: core_theme.AppTheme.primaryGradient,
                boxShadow: const [
                  BoxShadow(color: Color(0x336B73FF), blurRadius: 18, offset: Offset(0, 10))
                ],
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
              ),
              child: _ReportHeader(
                title: title,
                icon: icon,
                iconName: iconName,
                isTablet: isTablet,
              ),
            ),

            // Actions
            Padding(
              padding: EdgeInsets.fromLTRB(
                isTablet ? 20 : 12,
                isTablet ? 14 : 10,
                isTablet ? 20 : 12,
                0,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Wrap(
                    spacing: actionsGap,
                    children: [
                      FilledButton.tonal(
                        onPressed: () {},
                        child: const Text('Export PDF'),
                      ),
                      FilledButton(
                        onPressed: () {},
                        child: const Text('Export Excel'),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Placeholder content (cards/grid)
            Expanded(
              child: Padding(
                padding: contentPad,
                child: _ResponsiveRecords(isTablet: isTablet),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReportHeader extends StatelessWidget {
  final String title;
  final IconData icon;
  final String iconName;
  final bool isTablet;

  const _ReportHeader({
    required this.title,
    required this.icon,
    required this.iconName,
    required this.isTablet,
  });

  @override
  Widget build(BuildContext context) {
    final titleStyle = TextStyle(
      color: Colors.white,
      fontSize: isTablet ? 24 : 20,
      fontWeight: FontWeight.w800,
    );

    final iconLabelStyle = TextStyle(
      color: Colors.white70,
      fontSize: isTablet ? 14 : 12,
      fontWeight: FontWeight.w600,
      letterSpacing: .3,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Icon + Titles
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(.18),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white.withOpacity(.28)),
              ),
              padding: EdgeInsets.all(isTablet ? 14 : 10),
              child: Icon(icon, color: Colors.white, size: isTablet ? 32 : 26),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(iconName, style: iconLabelStyle, maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: titleStyle),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: const [
            _StatPill(label: 'This Month', value: 'Sept'),
            _StatPill(label: 'Branches', value: 'All'),
            _StatPill(label: 'Status', value: 'All'),
          ],
        ),
      ],
    );
  }
}

class _ResponsiveRecords extends StatelessWidget {
  final bool isTablet;
  const _ResponsiveRecords({required this.isTablet});

  @override
  Widget build(BuildContext context) {
    const itemCount = 12;

    if (!isTablet) {
      // Phone: single column list
      return ListView.builder(
        itemCount: itemCount,
        itemBuilder: (_, i) => Card(
          margin: const EdgeInsets.symmetric(vertical: 6),
          child: ListTile(
            leading: CircleAvatar(
              child: Text('${i + 1}'),
            ),
            title: Text('Record #$i', overflow: TextOverflow.ellipsis),
            subtitle: const Text('Tap to view details'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {},
          ),
        ),
      );
    }

    // Tablet: 2-column grid
    return GridView.builder(
      itemCount: itemCount,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisExtent: 92, // nice compact card height
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemBuilder: (_, i) => Card(
        elevation: 1,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {},
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                CircleAvatar(radius: 22, child: Text('${i + 1}')),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Record #$i',
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 2),
                      Text('Tap to view details',
                          style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StatPill extends StatelessWidget {
  final String label;
  final String value;
  const _StatPill({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$label: ', style: const TextStyle(color: Colors.white70, fontSize: 12)),
          Text(value, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String title;
  const _EmptyState({required this.title});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(title, style: Theme.of(context).textTheme.titleMedium),
    );
  }
}
