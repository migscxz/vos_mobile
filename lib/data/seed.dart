// lib/data/seed.dart
import 'models.dart';

const reportTypes = <ReportType>[
  ReportType('audit', 'Audit Finding Report'),
  ReportType('inventory', 'Inventory Report'),
  ReportType('asset', 'Asset & Equipment Report'),
  ReportType('delivery', 'Delivery Report'),
  ReportType('ar', 'Account Receivables'),
  ReportType('disb', 'Disbursement Report'),
  ReportType('sales', 'Sales Report'),
  ReportType('ap', 'Accounts Payables'),
];

const approvalQueues = <ApprovalQueue>[
  ApprovalQueue('predispatch', 'Pre Dispatch Approval', pendingCount: 3),
  ApprovalQueue('so', 'Sales Order Approval', pendingCount: 12),
  ApprovalQueue('logi', 'Logistic Approval', pendingCount: 5),
  ApprovalQueue('transfer', 'Stock Transfer Approval', pendingCount: 2),
  ApprovalQueue('audit', 'Consolidation Auditing', pendingCount: 1),
];

// Not const (contains DateTime)
final sampleConvos = <ConversationSummary>[
  ConversationSummary(
    id: 'g-ops',
    name: 'Ops Team',
    lastMessage: 'ETA for delivery wave 2?',
    time: DateTime(2025, 9, 25, 11, 30),
    unread: 4,
  ),
  ConversationSummary(
    id: 'u-ana',
    name: 'Anna Santos',
    lastMessage: 'Pushed latest AR report ✅',
    time: DateTime(2025, 9, 25, 9, 12),
  ),
];
