import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../state/app_state.dart';
import '../../data/models.dart';

class ReportsPanel extends ConsumerWidget {
  final bool showHeader;
  const ReportsPanel({super.key, this.showHeader = false});

  IconData _iconFor(ReportType r) {
    switch (r.id) {
      case 'sales':
        return Icons.query_stats_rounded;
      case 'inventory':
        return Icons.inventory_2_outlined;
      case 'asset':
        return Icons.handyman_outlined;
      case 'delivery':
        return Icons.local_shipping_outlined;
      case 'ar':
        return Icons.request_page_outlined;
      case 'ap':
        return Icons.receipt_long_outlined;
      case 'disb':
        return Icons.payments_outlined;
      case 'audit':
        return Icons.fact_check_outlined;
      default:
        return Icons.insert_drive_file_outlined;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reports = ref.watch(reportTypesProvider);

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      children: [
        if (showHeader)
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Row(
              children: const [
                Icon(Icons.bar_chart_rounded, size: 18),
                SizedBox(width: 6),
                Text('Reports', style: TextStyle(fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        for (final r in reports)
          Card(
            margin: const EdgeInsets.symmetric(vertical: 6),
            clipBehavior: Clip.antiAlias,
            child: Tooltip(
              message: r.title,
              waitDuration: const Duration(milliseconds: 400),
              preferBelow: false,
              child: InkWell(
                onTap: () {
                  ref.read(selectedReportProvider.notifier).state = r;
                  if (Navigator.of(context).canPop()) Navigator.of(context).pop();
                  ref.read(moduleProvider.notifier).state = Module.reports;
                },
                child: Semantics(
                  button: true,
                  label: r.title,
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    leading: Icon(_iconFor(r), size: 28),
                    title: Text(
                      r.title,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    // If your ReportType has a description, uncomment the next lines:
                    // subtitle: (r.description?.isNotEmpty ?? false)
                    //     ? Text(r.description!)
                    //     : null,
                    trailing: const Icon(Icons.chevron_right_rounded),
                    dense: false,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
