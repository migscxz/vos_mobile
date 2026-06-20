// lib/modules/approvals/price_change/price_change_models.dart

class PriceChangeRequest {
  final int requestId;
  final int? productId;
  final int? priceTypeId;
  final double proposedPrice;
  final String status;
  final int? requestedBy;
  final String requestedAt;
  final int? approvedBy;
  final String? approvedAt;
  final int? rejectedBy;
  final String? rejectedAt;
  final String? rejectReason;

  // Joined/Relational Data
  final String? productName;
  final String? priceTypeName;
  final String? requestedByName;

  const PriceChangeRequest({
    required this.requestId,
    this.productId,
    this.priceTypeId,
    required this.proposedPrice,
    required this.status,
    this.requestedBy,
    required this.requestedAt,
    this.approvedBy,
    this.approvedAt,
    this.rejectedBy,
    this.rejectedAt,
    this.rejectReason,
    this.productName,
    this.priceTypeName,
    this.requestedByName,
  });

  factory PriceChangeRequest.fromJson(Map<String, dynamic> json) {
    int asInt(Object? v) => (v is num) ? v.toInt() : int.tryParse("$v") ?? 0;
    int? asIntN(Object? v) => (v is num) ? v.toInt() : int.tryParse("$v");
    double asDouble(Object? v) =>
        (v is num) ? v.toDouble() : double.tryParse("$v") ?? 0.0;

    // Directus relations often come in as Objects if fields are expanded, or just IDs.
    // We'll handle both cases for ProductName, etc.
    String? getString(dynamic field, String key) {
      if (field == null) return null;
      if (field is Map) return field[key]?.toString();
      return null;
    }

    return PriceChangeRequest(
      requestId: asInt(json["request_id"]),
      productId: asIntN(
        json["product_id"] is Map
            ? json["product_id"]["product_id"]
            : json["product_id"],
      ),
      priceTypeId: asIntN(
        json["price_type_id"] is Map
            ? json["price_type_id"]["price_type_id"]
            : json["price_type_id"],
      ),
      proposedPrice: asDouble(json["proposed_price"]),
      status: (json["status"] ?? "PENDING").toString(),
      requestedBy: asIntN(
        json["requested_by"] is Map
            ? json["requested_by"]["user_id"]
            : json["requested_by"],
      ),
      requestedAt: (json["requested_at"] ?? "").toString(),
      approvedBy: asIntN(json["approved_by"]),
      approvedAt: json["approved_at"]?.toString(),
      rejectedBy: asIntN(json["rejected_by"]),
      rejectedAt: json["rejected_at"]?.toString(),
      rejectReason: json["reject_reason"]?.toString(),

      // Relational Fields (expanded via 'fields' query)
      productName:
          getString(json["product_id"], "product_name") ??
          getString(json["product_id"], "name"),
      priceTypeName:
          getString(json["price_type_id"], "price_type_name") ??
          getString(json["price_type_id"], "name"),
      requestedByName: getString(json["requested_by"], "user_fname") != null
          ? "${json["requested_by"]["user_fname"]} ${json["requested_by"]["user_lname"] ?? ""}"
                .trim()
          : null,
    );
  }
}

enum PriceChangeFilter {
  pending("Pending", "PENDING"),
  approved("Approved", "APPROVED"),
  rejected("Rejected", "REJECTED"),
  cancelled("Cancelled", "CANCELLED");

  final String label;
  final String value;
  const PriceChangeFilter(this.label, this.value);
}
