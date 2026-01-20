import 'package:flutter/material.dart';

enum DispatchStatus {
  pending("Pending"),
  approved("Approved"),
  picking("Picking"),
  picked("Picked"),
  dispatched("Dispatched");

  final String label;
  const DispatchStatus(this.label);
}

class DispatchPlanHeader {
  final int dispatchId;
  final String dispatchNo;
  final DispatchStatus status;
  final DateTime createdAt;
  final DateTime dispatchDate;
  final double totalAmount;
  final String remarks;
  final int branchId;
  final int driverId;
  final String? branchName;
  final String? driverName;

  const DispatchPlanHeader({
    required this.dispatchId,
    required this.dispatchNo,
    required this.status,
    required this.createdAt,
    required this.dispatchDate,
    required this.totalAmount,
    required this.remarks,
    required this.branchId,
    required this.driverId,
    this.branchName,
    this.driverName,
  });

  bool get isApprovable => status == DispatchStatus.pending;
}

class DispatchPlanItem {
  final int id;
  final int productId;
  final String productName;
  final double quantity;
  final String? unit;

  const DispatchPlanItem({
    required this.id,
    required this.productId,
    required this.productName,
    required this.quantity,
    this.unit,
  });
}

Color getDispatchStatusColor(DispatchStatus s, ColorScheme cs) {
  switch (s) {
    case DispatchStatus.pending:
      return cs.primary;
    case DispatchStatus.approved:
      return Colors.deepPurple;
    case DispatchStatus.picking:
      return Colors.orange;
    case DispatchStatus.picked:
      return Colors.teal;
    case DispatchStatus.dispatched:
      return Colors.green;
  }
}
