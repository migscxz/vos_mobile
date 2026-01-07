import 'package:dio/dio.dart';

class ApiClient {
  final Dio _dio;
  final String baseUrl;

  ApiClient._(this._dio, this.baseUrl);

  factory ApiClient({
    String baseUrl = 'http://goatedcodoer:8091',
    String? token,
  }) {
    final dio = Dio(
      BaseOptions(
        baseUrl: baseUrl,
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 30), // increased
        headers: {
          'Accept': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
        validateStatus: (status) {
          // allow Dio to return non-200 responses instead of throwing
          return status != null && status < 500;
        },
      ),
    );

    return ApiClient._(dio, baseUrl);
  }

  Future<List<dynamic>> getList(String path) async {
    try {
      final res = await _dio.get(path);
      // ignore: avoid_print
      print('GET $baseUrl$path → status: ${res.statusCode}');

      if (res.statusCode == 403) {
        throw Exception('403 Forbidden – Check token or permissions.');
      }

      if (res.data is Map && res.data['data'] is List) {
        return List<dynamic>.from(res.data['data']);
      }

      if (res.data is List) {
        return List<dynamic>.from(res.data);
      }

      return const [];
    } on DioException catch (e) {
      // ignore: avoid_print
      print("DIO ERROR on GET $path: ${e.message}");
      rethrow;
    } catch (e) {
      // ignore: avoid_print
      print("UNKNOWN ERROR on GET $path: $e");
      rethrow;
    }
  }
}
