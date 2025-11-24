import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../state/app_state.dart';
import '../../../data/models.dart';

class ApprovalView extends ConsumerWidget {
  const ApprovalView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final queue = ref.watch(selectedApprovalQueueProvider);
    final tab = ref.watch(approvalTabProvider);
    if (queue == null) return const Center(child: Text('Select an approval queue'));

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
          child: Row(
            children: [
              // Title shrinks if space is tight
              Expanded(
                child: Text(
                  queue.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 8),
              // 👇 SegmentedButton can overflow on phones; make it horizontally scrollable
              Flexible(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SegmentedButton<ApprovalTab>(
                    segments: const [
                      ButtonSegment(value: ApprovalTab.pending, label: Text('Pending')),
                      ButtonSegment(value: ApprovalTab.approved, label: Text('Approved')),
                      ButtonSegment(value: ApprovalTab.rejected, label: Text('Rejected')),
                    ],
                    selected: {tab},
                    onSelectionChanged: (s) => ref.read(approvalTabProvider.notifier).state = s.first,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.all(12),
            itemBuilder: (_, i) => ListTile(
              tileColor: Theme.of(context).colorScheme.surface,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              title: Text('Sales Order #SO-${1000 + i}', overflow: TextOverflow.ellipsis),
              subtitle: const Text('Requester: Juan Dela Cruz • Customer: ACME Trading'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _openDetail(context),
            ),
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemCount: 8,
          ),
        ),
      ],
    );
  }

  void _openDetail(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const _ApprovalDetailSheet(),
    );
  }
}

class _ApprovalDetailSheet extends StatelessWidget {
  const _ApprovalDetailSheet();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: .8,
        maxChildSize: .95,
        minChildSize: .5,
        builder: (_, controller) => Padding(
          padding: const EdgeInsets.all(16),
          child: ListView(
            controller: controller,
            children: [
              Row(
                children: [
                  Text(
                    'Sales Order #SO-12345',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const Spacer(),
                  IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
                ],
              ),
              const SizedBox(height: 8),
              const Text('Requester: Maria Cruz\nDate: 2025-09-26'),
              const SizedBox(height: 12),
              const Divider(),
              const Text('Items', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              ...List.generate(
                3,
                    (i) => ListTile(
                  title: Text('Item ${i + 1}'),
                  subtitle: const Text('Qty: 10 • Price: 1,200.00'),
                ),
              ),
              const SizedBox(height: 12),
              const Divider(),
              const Text('Attachments', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              const ListTile(leading: Icon(Icons.picture_as_pdf), title: Text('PO.pdf')),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                      onPressed: () {},
                      child: const Text('Reject'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: FilledButton(onPressed: () {}, child: const Text('Approve'))),
                ],
              ),
              const SizedBox(height: 8),
              OutlinedButton(onPressed: () {}, child: const Text('Comment / Request Info')),
            ],
          ),
        ),
      ),
    );
  }
}
