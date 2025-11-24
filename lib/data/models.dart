// lib/data/models.dart

/// Main navigation modules in the app (sidebar)
enum Module { dashboard, reports, chats, approvals, profile }

/// Tabs for approvals module
enum ApprovalTab { pending, approved, rejected }

/// Represents a report type (e.g., Inventory Report, Sales Report)
class ReportType {
  final String id;
  final String title;

  const ReportType(this.id, this.title);

  @override
  String toString() => 'ReportType(id: $id, title: $title)';
}

/// Represents an approval queue (e.g., Sales Order Approval)
class ApprovalQueue {
  final String id;
  final String title;
  final int pendingCount;

  const ApprovalQueue(
      this.id,
      this.title, {
        this.pendingCount = 0,
      });

  ApprovalQueue copyWith({String? id, String? title, int? pendingCount}) {
    return ApprovalQueue(
      id ?? this.id,
      title ?? this.title,
      pendingCount: pendingCount ?? this.pendingCount,
    );
  }

  @override
  String toString() =>
      'ApprovalQueue(id: $id, title: $title, pending: $pendingCount)';
}

/// Summary info for a chat conversation (sidebar list)
class ConversationSummary {
  final String id;
  final String name;
  final String lastMessage;
  final DateTime time;
  final int unread;

  // Not const because DateTime is not const
  ConversationSummary({
    required this.id,
    required this.name,
    required this.lastMessage,
    required this.time,
    this.unread = 0,
  });

  ConversationSummary copyWith({
    String? id,
    String? name,
    String? lastMessage,
    DateTime? time,
    int? unread,
  }) {
    return ConversationSummary(
      id: id ?? this.id,
      name: name ?? this.name,
      lastMessage: lastMessage ?? this.lastMessage,
      time: time ?? this.time,
      unread: unread ?? this.unread,
    );
  }

  @override
  String toString() =>
      'ConversationSummary(id: $id, name: $name, unread: $unread)';
}
