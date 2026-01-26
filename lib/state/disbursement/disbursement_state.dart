// lib/state/disbursement/disbursement_state.dart
import "package:flutter/foundation.dart";

/// Matches your UI chip filters (and can be extended later).
enum DisbursementFilter {
  all("All"),
  trade("Trade"),
  nonTrade("Non-Trade"),
  posted("Posted"),
  unpaid("Unpaid");

  final String label;
  const DisbursementFilter(this.label);

  static DisbursementFilter fromLabel(String label) {
    return DisbursementFilter.values.firstWhere(
          (e) => e.label == label,
      orElse: () => DisbursementFilter.all,
    );
  }
}

/// Query params used by the controller/provider.
/// Later you can add payeeId, divisionId, coaId, etc.
@immutable
class DisbursementQuery {
  final DisbursementFilter filter;
  final String search;
  final DateTime? from;
  final DateTime? to;

  const DisbursementQuery({
    this.filter = DisbursementFilter.all,
    this.search = "",
    this.from,
    this.to,
  });

  DisbursementQuery copyWith({
    DisbursementFilter? filter,
    String? search,
    DateTime? from,
    DateTime? to,
    bool clearFrom = false,
    bool clearTo = false,
  }) {
    return DisbursementQuery(
      filter: filter ?? this.filter,
      search: search ?? this.search,
      from: clearFrom ? null : (from ?? this.from),
      to: clearTo ? null : (to ?? this.to),
    );
  }
}

/// One payable line from the view (line item inside accordion).
@immutable
class DisbursementItem {
  final int payableId;
  final String? referenceNo;
  final DateTime? payableDate;

  final int? divisionId;
  final String? divisionName;

  final int? coaId;
  final String? coaTitle;

  final double amount;
  final String? payableRemarks;

  final DateTime? payableDateCreated;

  const DisbursementItem({
    required this.payableId,
    required this.referenceNo,
    required this.payableDate,
    required this.divisionId,
    required this.divisionName,
    required this.coaId,
    required this.coaTitle,
    required this.amount,
    required this.payableRemarks,
    required this.payableDateCreated,
  });
}

/// A grouped DV header with its line items.
@immutable
class DisbursementGroup {
  final int disbursementId;

  final String docNo;

  /// 1=Trade, 2=Non-Trade (from your CASE)
  final int transactionType;
  final String transactionTypeName;

  final int? payeeId;
  final String? payeeName;

  final String? disbursementRemarks;

  final double totalAmount;
  final double paidAmount;

  final int? encoderId;
  final String? encoderName;

  final int? approverId;
  final String? approverName;

  final int? postedById;
  final String? postedByName;

  final int isPosted; // 0/1
  final DateTime? transactionDate;

  final DateTime? disbursementDateCreated;
  final DateTime? disbursementDateUpdated;

  /// Some systems keep division in header, but your view exposes division at line-level.
  /// We keep these as “primary” division seen first (optional).
  final int? divisionId;
  final String? divisionName;

  final List<DisbursementItem> items;

  const DisbursementGroup({
    required this.disbursementId,
    required this.docNo,
    required this.transactionType,
    required this.transactionTypeName,
    required this.payeeId,
    required this.payeeName,
    required this.disbursementRemarks,
    required this.totalAmount,
    required this.paidAmount,
    required this.encoderId,
    required this.encoderName,
    required this.approverId,
    required this.approverName,
    required this.postedById,
    required this.postedByName,
    required this.isPosted,
    required this.transactionDate,
    required this.disbursementDateCreated,
    required this.disbursementDateUpdated,
    required this.divisionId,
    required this.divisionName,
    required this.items,
  });

  bool get posted => isPosted == 1;

  /// “Unpaid” definition (safe default):
  /// - total > paid (with small tolerance)
  bool get unpaid => (totalAmount - paidAmount) > 0.00001;
}

/// State for the view.
@immutable
class DisbursementState {
  final DisbursementQuery query;

  /// Grouped results for UI cards.
  final List<DisbursementGroup> groups;

  /// Convenience metadata for UI.
  final int totalGroups;
  final int totalItems;
  final double totalDisbursement;

  const DisbursementState({
    required this.query,
    required this.groups,
    required this.totalGroups,
    required this.totalItems,
    required this.totalDisbursement,
  });

  factory DisbursementState.initial() => const DisbursementState(
    query: DisbursementQuery(),
    groups: [],
    totalGroups: 0,
    totalItems: 0,
    totalDisbursement: 0,
  );

  DisbursementState copyWith({
    DisbursementQuery? query,
    List<DisbursementGroup>? groups,
    int? totalGroups,
    int? totalItems,
    double? totalDisbursement,
  }) {
    return DisbursementState(
      query: query ?? this.query,
      groups: groups ?? this.groups,
      totalGroups: totalGroups ?? this.totalGroups,
      totalItems: totalItems ?? this.totalItems,
      totalDisbursement: totalDisbursement ?? this.totalDisbursement,
    );
  }
}
