import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/models.dart';
import '../data/seed.dart';

// Active module (sidebar)
final moduleProvider = StateProvider<Module>((_) => Module.dashboard);

// Reports
final selectedReportProvider = StateProvider<ReportType?>((_) => null);

// Approvals
final selectedApprovalQueueProvider = StateProvider<ApprovalQueue?>((_) => null);
final approvalTabProvider = StateProvider<ApprovalTab>((_) => ApprovalTab.pending);

// Chats
final selectedConversationIdProvider = StateProvider<String?>((_) => null);

// badge counts for the main sidebar
final approvalsBadgeCountProvider = Provider<int>((ref) {
  return approvalQueues.fold(0, (s, q) => s + q.pendingCount);
});

final chatsBadgeCountProvider = Provider<int>((ref) {
  return sampleConvos.fold(0, (s, c) => s + c.unread);
});

// Expose lists (dummy data) for panels
final reportTypesProvider = Provider<List<ReportType>>((_) => reportTypes);
final approvalQueuesProvider = Provider<List<ApprovalQueue>>((_) => approvalQueues);
final conversationsProvider = Provider((_) => sampleConvos);

