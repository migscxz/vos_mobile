import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vos_mobile/state/data_providers.dart';

class DeliveryReportList extends ConsumerWidget {
  const DeliveryReportList({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncRows = ref.watch(deliveryReportProvider);

    return asyncRows.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (rows) => ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: rows.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (_, i) {
          final r = rows[i];
          final title =
              '${r['invoice_no'] ?? '-'} • ${r['customer_name'] ?? ''}';
          final sub =
              'Driver: ${r['driver_name'] ?? ''} • ${r['city_town_name'] ?? ''}';
          return ListTile(
            tileColor: Theme.of(context).colorScheme.surface,
            shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(sub, maxLines: 2, overflow: TextOverflow.ellipsis),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {},
          );
        },
      ),
    );
  }
}
