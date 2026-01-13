// lib/modules/approvals/sales_order/sales_order_models.dart

class SalesOrderApprovalHeader {
  final int orderId;

  final String orderNo;
  final String? poNo;
  final String? customerCode;
  final String orderStatus;

  final String customerName;
  final String requestedBy;

  final int? createdBy;
  final String? createdDate;
  final String? forApprovalAt;
  final String? orderDate;

  final DateTime createdAt;

  final double totalAmount;
  final double netAmount;

  const SalesOrderApprovalHeader({
    required this.orderId,
    required this.orderNo,
    required this.poNo,
    required this.customerCode,
    required this.orderStatus,
    required this.customerName,
    required this.requestedBy,
    required this.createdBy,
    required this.createdDate,
    required this.forApprovalAt,
    required this.orderDate,
    required this.createdAt,
    required this.totalAmount,
    required this.netAmount,
  });
}

enum SalesOrderFilter {
  all("All", null),
  forApproval("For Approval", "For Approval"),
  forConsolidation("For Consolidation", "For Consolidation"),
  forPicking("For Picking", "For Picking"),
  forInvoicing("For Invoicing", "For Invoicing"),
  forLoading("For Loading", "For Loading"),
  forShipping("For Shipping", "For Shipping"),
  enRoute("En Route", "En Route"),
  delivered("Delivered", "Delivered"),
  onHold("On Hold", "On Hold"),
  cancelled("Cancelled", "Cancelled"),
  notFulfilled("Not Fulfilled", "Not Fulfilled");

  final String label;
  final String? statusValue;
  const SalesOrderFilter(this.label, this.statusValue);
}
