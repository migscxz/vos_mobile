// lib/ui/shell/content_area.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../data/models.dart';
import '../../../state/app_state.dart';

// Use your project’s package name or relative paths:
import 'package:vos_mobile/modules/dashboard/dashboard_view.dart';
import 'package:vos_mobile/modules/reports/report_view.dart';
import 'package:vos_mobile/modules/chats/chat_view.dart';
import 'package:vos_mobile/modules/approvals/approval_view.dart';
import 'package:vos_mobile/modules/profile/profile_view.dart';

class ContentArea extends ConsumerWidget {
  const ContentArea({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final module = ref.watch(moduleProvider);
    switch (module) {
      case Module.dashboard:
        return const DashboardView();
      case Module.reports:
        return const ReportView();
      case Module.chats:
        return const ChatView();
      case Module.approvals:
        return ApprovalView();
      case Module.profile:
        return const ProfileView();
    }
  }
}
