// lib/modules/approvals/invoice_cancellation/invoice_cancellation_models.dart

class InvoiceCancellationRequest {
  final int requestId;
  final int invoiceId;
  final String salesOrderId; // using string as per schema (varchar)
  final int requestedBy;
  final String reasonCode;
  final String? remarks;

  // Status & Approval
  final String status;
  final int? approvedBy;
  final String? actionDate;
  final String? dateApproved;
  final String? rejectionReason;

  // Metadata
  final String createdAt;

  // Joined fields (optional, for UI if backend expands, but sticking to schema for now)
  // For now we assume these are just IDs. We might need to fetch names separately or if Directus auto-expands.

  const InvoiceCancellationRequest({
    required this.requestId,
    required this.invoiceId,
    required this.salesOrderId,
    required this.requestedBy,
    required this.reasonCode,
    this.remarks,
    required this.status,
    this.approvedBy,
    this.actionDate,
    this.dateApproved,
    this.rejectionReason,
    required this.createdAt,
  });

  factory InvoiceCancellationRequest.fromJson(Map<String, dynamic> json) {
    int asInt(Object? v) => (v is num) ? v.toInt() : int.tryParse("$v") ?? 0;
    int? asIntN(Object? v) => (v is num) ? v.toInt() : int.tryParse("$v");

    return InvoiceCancellationRequest(
      requestId: asInt(json["request_id"]),
      invoiceId: asInt(json["invoice_id"]),
      salesOrderId: (json["sales_order_id"] ?? "").toString(),
      requestedBy: asInt(json["requested_by"]),
      reasonCode: (json["reason_code"] ?? "").toString(),
      remarks: json["remarks"]?.toString(),
      status: (json["status"] ?? "PENDING").toString(),
      approvedBy: asIntN(json["approved_by"]),
      actionDate: json["action_date"]?.toString(),
      dateApproved: json["date_approved"]?.toString(),
      rejectionReason: json["rejection_reason"]?.toString(),
      createdAt: (json["created_at"] ?? "").toString(),
    );
  }
}

enum InvoiceCancellationFilter {
  pending("Pending", "PENDING"),
  approved("Approved", "APPROVED"),
  rejected("Rejected", "REJECTED");

  final String label;
  final String value;
  const InvoiceCancellationFilter(this.label, this.value);
}
