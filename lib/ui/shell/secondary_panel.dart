import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../data/models.dart';
import 'package:vos_mobile/modules/reports/reports_panel.dart';
import 'package:vos_mobile/modules/chats/chats_panel.dart';
import 'package:vos_mobile/modules/approvals/approvals_panel.dart';
class SecondaryPanel extends ConsumerWidget {
  final Module module;
  const SecondaryPanel({super.key, required this.module});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    switch (module) {
      case Module.dashboard:
        return const ReportsPanel(showHeader: true);
      case Module.reports:
        return const ReportsPanel();
      case Module.chats:
        return const ChatsPanel();
      case Module.approvals:
        return const ApprovalsPanel();
      case Module.profile:
        return const _ProfilePanel();
    }
  }
}

class _ProfilePanel extends StatelessWidget {
  const _ProfilePanel();
  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: const [
        SizedBox(height: 12),
        ListTile(title: Text('Settings'), subtitle: Text('Account, Notifications, Appearance')),
        ListTile(title: Text('About'), subtitle: Text('VOS Mobile v0.1.0')),
      ],
    );
  }
}
