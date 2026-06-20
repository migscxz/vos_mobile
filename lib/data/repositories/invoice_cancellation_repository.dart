// lib/data/repositories/invoice_cancellation_repository.dart

import "../../core/network/api_client.dart";
import "../../modules/approvals/invoice_cancellation/invoice_cancellation_models.dart";

class InvoiceCancellationRepository {
  InvoiceCancellationRepository(this._api);

  final ApiClient _api;
  static const String _collection = "invoice_cancellation_requests";

  // Fields to fetch
  static const String _fields =
      "request_id,invoice_id,sales_order_id,requested_by,reason_code,remarks,status,approved_by,action_date,created_at,date_approved,rejection_reason";

  Future<List<InvoiceCancellationRequest>> fetchRequests({
    String? status,
    int limit = 50,
    int offset = 0,
  }) async {
    final query = <String, String>{
      "limit": limit.toString(),
      "offset": offset.toString(),
      "sort": "-created_at",
      "fields": _fields,
    };

    if (status != null && status.trim().isNotEmpty) {
      query["filter[status][_eq]"] = status.trim();
    }

    final json = await _api.getJson("/items/$_collection", query: query);
    final data = json["data"] as List?;
    if (data == null) return [];

    return data.map((e) => InvoiceCancellationRequest.fromJson(e)).toList();
  }

  Future<int> fetchCount({String? status}) async {
    final query = <String, String>{
      "limit": "0",
      "meta": "filter_count", // IMPORTANT: filtered count, not total_count
    };

    if (status != null && status.trim().isNotEmpty) {
      query["filter[status][_eq]"] = status.trim();
    }

    final json = await _api.getJson("/items/$_collection", query: query);
    final meta = json["meta"];
    if (meta is Map) {
      return int.tryParse("${meta["filter_count"]}") ?? 0;
    }
    return 0;
  }

  Future<void> approveRequest({
    required int requestId,
    required int approvedByUserId,
    required int invoiceId,
    required String salesOrderId,
  }) async {
    final nowCheck = DateTime.now().toUtc().toIso8601String();

    // 1. Approve the request
    // ignore: avoid_print
    print(
      "IC APPROVE: requestId=$requestId invoiceId=$invoiceId salesOrderId=$salesOrderId",
    );
    await _api.patch(
      "/items/$_collection/$requestId",
      data: {
        "status": "APPROVED",
        "approved_by": approvedByUserId,
        "date_approved": nowCheck,
        "action_date": nowCheck,
      },
    );

    // 2. Cancel the invoice (title-case to match DB convention)
    await _api.patch(
      "/items/sales_invoice/$invoiceId",
      data: {"transaction_status": "CANCELLED"},
    );

    // 3. Unlock the Sales Order
    // salesOrderId is the order_no (e.g. "MP12198"), NOT the numeric PK.
    // We need to look up the actual order_id first, then patch it.
    final soOrderNo = salesOrderId.trim();
    if (soOrderNo.isNotEmpty) {
      // Try numeric PK first
      final numericId = int.tryParse(soOrderNo);
      if (numericId != null) {
        // It IS a numeric ID, patch directly
        await _api.patch(
          "/items/sales_order/$numericId",
          data: {"order_status": "For Invoicing"},
        );
      } else {
        // It's an order_no string — look up real PK via filter
        final lookup = await _api.getJson(
          "/items/sales_order",
          query: {
            "filter[order_no][_eq]": soOrderNo,
            "fields": "order_id",
            "limit": "1",
          },
        );
        final data = lookup["data"];
        if (data is List && data.isNotEmpty) {
          final realId = data[0]["order_id"];
          // ignore: avoid_print
          print("APPROVE: Resolved order_no=$soOrderNo → order_id=$realId");
          await _api.patch(
            "/items/sales_order/$realId",
            data: {"order_status": "For Invoicing"},
          );
        } else {
          // ignore: avoid_print
          print("APPROVE: Could not find sales_order with order_no=$soOrderNo");
        }
      }
    }
  }

  Future<void> rejectRequest({
    required int requestId,
    required String reason,
    required int invoiceId,
    int? actionByUserId,
  }) async {
    final nowCheck = DateTime.now().toUtc().toIso8601String();

    // 1. Reject the request
    await _api.patch(
      "/items/$_collection/$requestId",
      data: {
        "status": "REJECTED",
        "rejection_reason": reason,
        "action_date": nowCheck,
      },
    );

    // 2. Revert the invoice (title-case to match DB convention)
    await _api.patch(
      "/items/sales_invoice/$invoiceId",
      data: {"transaction_status": "For Dispatch"},
    );
  }
}
