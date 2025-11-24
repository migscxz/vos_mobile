// lib/core/network/api_client.dart
import 'package:dio/dio.dart';

class ApiClient {
  final Dio _dio;
  final String baseUrl; // <-- expose base URL

  ApiClient._(this._dio, this.baseUrl);

  factory ApiClient({String baseUrl = 'http://100.126.246.124:8060'}) {
    final dio = Dio(BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 20),
      headers: {'Accept': 'application/json'},
    ));
    return ApiClient._(dio, baseUrl);
  }

  Future<List<dynamic>> getList(String path) async {
    final res = await _dio.get(path);
    if (res.data is Map && res.data['data'] is List) {
      return List<dynamic>.from(res.data['data']);
    }
    if (res.data is List) return List<dynamic>.from(res.data);
    return const [];
  }
}
