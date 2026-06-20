// lib/data/repositories/price_change_repository.dart

import "../../core/network/api_client.dart";
import "../../modules/approvals/price_change/price_change_models.dart";

class PriceChangeRepository {
  PriceChangeRepository(this._api);

  final ApiClient _api;
  static const String _collection = "price_change_requests";

  // Fields to fetch with expansion for joined tables
  static const String _fields =
      "request_id,proposed_price,status,requested_at,approved_at,rejected_at,reject_reason,"
      "product_id.product_id,product_id.product_name,price_type_id.price_type_id,price_type_id.price_type_name,"
      "requested_by.user_id,requested_by.user_fname,requested_by.user_lname";

  Future<List<PriceChangeRequest>> fetchRequests({
    String? status,
    int limit = 50,
    int offset = 0,
  }) async {
    final query = <String, String>{
      "limit": limit.toString(),
      "offset": offset.toString(),
      "sort": "-requested_at",
      "fields": _fields,
    };

    if (status != null && status.trim().isNotEmpty) {
      query["filter[status][_eq]"] = status.trim();
    }

    final json = await _api.getJson("/items/$_collection", query: query);
    final data = json["data"] as List?;
    if (data == null) return [];

    return data.map((e) => PriceChangeRequest.fromJson(e)).toList();
  }

  Future<int> fetchCount({String? status}) async {
    final query = <String, String>{"limit": "0", "meta": "filter_count"};

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
  }) async {
    final now = DateTime.now().toUtc().toIso8601String();

    await _api.patch(
      "/items/$_collection/$requestId",
      data: {
        "status": "APPROVED",
        "approved_by": approvedByUserId,
        "approved_at": now,
      },
    );
  }

  Future<void> rejectRequest({
    required int requestId,
    required String reason,
    required int rejectedByUserId,
  }) async {
    final now = DateTime.now().toUtc().toIso8601String();

    await _api.patch(
      "/items/$_collection/$requestId",
      data: {
        "status": "REJECTED",
        "reject_reason": reason,
        "rejected_by": rejectedByUserId,
        "rejected_at": now,
      },
    );
  }
}
