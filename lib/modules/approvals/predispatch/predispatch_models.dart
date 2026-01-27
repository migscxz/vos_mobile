import 'package:flutter/material.dart';

enum PredispatchStatus {
  pending("Pending"),
  approved("Approved"),
  picking("Picking"),
  picked("Picked"),
  dispatched("Dispatched");

  final String label;
  const PredispatchStatus(this.label);
}

class PredispatchHeader {
  final int dispatchId;
  final String dispatchNo;
  final PredispatchStatus status;
  final DateTime createdAt;
  final DateTime dispatchDate;
  final double totalAmount;
  final String remarks;
  final int branchId;
  final int driverId;
  final String? branchName;
  final String? driverName;
  final List<PredispatchSalesOrder> salesOrders;

  const PredispatchHeader({
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
    required this.salesOrders,
  });

  bool get isApprovable => status == PredispatchStatus.pending;
}

class PredispatchSalesOrder {
  final int orderId;
  final String orderNo;
  final String customerName;
  final double allocatedAmount;

  const PredispatchSalesOrder({
    required this.orderId,
    required this.orderNo,
    required this.customerName,
    required this.allocatedAmount,
  });
}

class PredispatchApproveOutcome {
  final bool success;
  final String? error;

  const PredispatchApproveOutcome({required this.success, this.error});
}

Color getPredispatchStatusColor(PredispatchStatus s, ColorScheme cs) {
  switch (s) {
    case PredispatchStatus.pending:
      return cs.primary;
    case PredispatchStatus.approved:
      return Colors.green;
    case PredispatchStatus.picking:
      return Colors.orange;
    case PredispatchStatus.picked:
      return Colors.purple;
    case PredispatchStatus.dispatched:
      return Colors.grey;
  }
}
