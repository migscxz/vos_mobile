import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../state/app_state.dart';
import '../../data/models.dart';

class ApprovalsPanel extends ConsumerWidget {
  const ApprovalsPanel({super.key});

  IconData _iconFor(ApprovalQueue q) {
    switch (q.id) {
      case 'so': return Icons.assignment_turned_in_outlined;
      case 'predispatch': return Icons.outbox_outlined;
      case 'logi': return Icons.local_shipping_outlined;
      case 'transfer': return Icons.swap_horiz_rounded;
      case 'audit': return Icons.verified_user_outlined;
      default: return Icons.check_circle_outline;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final queues = ref.watch(approvalQueuesProvider);

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        for (final q in queues)
          Card(
            margin: const EdgeInsets.symmetric(vertical: 6),
            child: ListTile(
              leading: Stack(
                children: [
                  Icon(_iconFor(q)),
                  if (q.pendingCount > 0)
                    Positioned(
                      right: -2,
                      top: -2,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                        decoration: BoxDecoration(color: Colors.redAccent, borderRadius: BorderRadius.circular(10)),
                        child: Text('${q.pendingCount}', style: const TextStyle(color: Colors.white, fontSize: 10)),
                      ),
                    ),
                ],
              ),
              title: Text(q.title, maxLines: 1, overflow: TextOverflow.ellipsis),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                ref.read(selectedApprovalQueueProvider.notifier).state = q;
                if (Navigator.of(context).canPop()) Navigator.of(context).pop();
                ref.read(moduleProvider.notifier).state = Module.approvals;
              },
            ),
          ),
      ],
    );
  }
}
