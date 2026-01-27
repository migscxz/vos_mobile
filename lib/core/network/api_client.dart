import "package:dio/dio.dart";

class ApiClient {
  final Dio _dio;
  final String baseUrl;

  ApiClient._(this._dio, this.baseUrl);

  factory ApiClient({String baseUrl = "http://goatedcodoer:8056", String? token}) {
    final dio = Dio(
      BaseOptions(
        baseUrl: baseUrl,
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 30),
        headers: {
          "Accept": "application/json",
          "Content-Type": "application/json",
          if (token != null && token.trim().isNotEmpty) "Authorization": "Bearer ${token.trim()}",
        },
        // IMPORTANT:
        // Let Dio return ALL status codes so we can read res.data (including 500 bodies).
        validateStatus: (status) => status != null,
      ),
    );

    return ApiClient._(dio, baseUrl);
  }

  void setToken(String token) {
    final t = token.trim();
    if (t.isEmpty) return;
    _dio.options.headers["Authorization"] = "Bearer $t";
  }

  void clearToken() {
    _dio.options.headers.remove("Authorization");
  }

  Future<Map<String, dynamic>> getJson(
    String path, {
    Map<String, dynamic>? query,
    bool allow403 = false,
  }) async {
    try {
      final res = await _dio.get(path, queryParameters: query);
      // ignore: avoid_print
      print("GET $baseUrl$path → status: ${res.statusCode}");

      if (allow403 && res.statusCode == 403) {
        return {"error": "403 Forbidden – Check token or permissions.", "data": res.data};
      }
      if (res.statusCode == 401) {
        throw Exception("401 Unauthorized – Invalid credentials or token expired.");
      }
      if (res.statusCode == 403) {
        throw Exception("403 Forbidden – Check token or permissions.");
      }
      if (res.statusCode == null || res.statusCode! >= 400) {
        throw Exception("HTTP ${res.statusCode} – ${res.statusMessage} – ${res.data}");
      }

      if (res.data is Map) {
        return Map<String, dynamic>.from(res.data as Map);
      }
      return {"data": res.data};
    } on DioException catch (e) {
      // ignore: avoid_print
      print("DIO ERROR on GET $path: ${e.message}");
      // ignore: avoid_print
      print("DIO ERROR status: ${e.response?.statusCode}");
      // ignore: avoid_print
      print("DIO ERROR data: ${e.response?.data}");
      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout) {
        throw Exception("The server is down");
      }
      rethrow;
    } catch (e) {
      // ignore: avoid_print
      print("UNKNOWN ERROR on GET $path: $e");
      rethrow;
    }
  }

  Future<List<dynamic>> getList(String path, {Map<String, dynamic>? query}) async {
    try {
      final res = await _dio.get(path, queryParameters: query);
      // ignore: avoid_print
      print("GET $baseUrl$path → status: ${res.statusCode}");

      if (res.statusCode == 401) {
        throw Exception("401 Unauthorized – Invalid credentials or token expired.");
      }
      if (res.statusCode == 403) {
        throw Exception("403 Forbidden – Check token or permissions.");
      }
      if (res.statusCode == null || res.statusCode! >= 400) {
        throw Exception("HTTP ${res.statusCode} – ${res.statusMessage} – ${res.data}");
      }

      if (res.data is Map && (res.data as Map)["data"] is List) {
        return List<dynamic>.from((res.data as Map)["data"] as List);
      }
      if (res.data is List) {
        return List<dynamic>.from(res.data as List);
      }
      return const [];
    } on DioException catch (e) {
      // ignore: avoid_print
      print("DIO ERROR on GET $path: ${e.message}");
      // ignore: avoid_print
      print("DIO ERROR status: ${e.response?.statusCode}");
      // ignore: avoid_print
      print("DIO ERROR data: ${e.response?.data}");
      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout) {
        throw Exception("The server is down");
      }
      rethrow;
    } catch (e) {
      // ignore: avoid_print
      print("UNKNOWN ERROR on GET $path: $e");
      rethrow;
    }
  }

  Future<Map<String, dynamic>> postJson(
    String path, {
    required Map<String, dynamic> body,
    Map<String, dynamic>? query,
  }) async {
    try {
      final res = await _dio.post(path, data: body, queryParameters: query);
      // ignore: avoid_print
      print("POST $baseUrl$path → status: ${res.statusCode}");

      if (res.statusCode == 401) {
        throw Exception("401 Unauthorized – Invalid credentials or token expired.");
      }
      if (res.statusCode == 403) {
        throw Exception("403 Forbidden – Check token or permissions.");
      }
      if (res.statusCode == null || res.statusCode! >= 400) {
        throw Exception("HTTP ${res.statusCode} – ${res.statusMessage} – ${res.data}");
      }

      if (res.data is Map) {
        return Map<String, dynamic>.from(res.data as Map);
      }
      return {"data": res.data};
    } on DioException catch (e) {
      // ignore: avoid_print
      print("DIO ERROR on POST $path: ${e.message}");
      // ignore: avoid_print
      print("DIO ERROR status: ${e.response?.statusCode}");
      // ignore: avoid_print
      print("DIO ERROR data: ${e.response?.data}");
      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout) {
        throw Exception("The server is down");
      }
      rethrow;
    } catch (e) {
      // ignore: avoid_print
      print("UNKNOWN ERROR on POST $path: $e");
      rethrow;
    }
  }

  Future<Map<String, dynamic>> patchJson(
    String path, {
    required Map<String, dynamic> body,
    Map<String, dynamic>? query,
  }) async {
    try {
      final res = await _dio.patch(path, data: body, queryParameters: query);
      // ignore: avoid_print
      print("PATCH $baseUrl$path → status: ${res.statusCode}");

      if (res.statusCode == 401) {
        throw Exception("401 Unauthorized – Invalid credentials or token expired.");
      }
      if (res.statusCode == 403) {
        throw Exception("403 Forbidden – Check token or permissions.");
      }
      if (res.statusCode == null || res.statusCode! >= 400) {
        throw Exception("HTTP ${res.statusCode} – ${res.statusMessage} – ${res.data}");
      }

      if (res.data is Map) {
        return Map<String, dynamic>.from(res.data as Map);
      }
      return {"data": res.data};
    } on DioException catch (e) {
      // ignore: avoid_print
      print("DIO ERROR on PATCH $path: ${e.message}");
      // ignore: avoid_print
      print("DIO ERROR status: ${e.response?.statusCode}");
      // ignore: avoid_print
      print("DIO ERROR data: ${e.response?.data}");
      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout) {
        throw Exception("The server is down");
      }
      rethrow;
    } catch (e) {
      // ignore: avoid_print
      print("UNKNOWN ERROR on PATCH $path: $e");
      rethrow;
    }
  }

  Future<Map<String, dynamic>> patch(String path, {required Map<String, dynamic> data}) async {
    final res = await patchJson(path, body: data);
    final d = res["data"];
    if (d is Map) return Map<String, dynamic>.from(d);
    return res; // Return the full response if data is not a map
  }

  Future<void> deleteJson(String path, {Map<String, dynamic>? query}) async {
    try {
      final res = await _dio.delete(path, queryParameters: query);
      // ignore: avoid_print
      print("DELETE $baseUrl$path → status: ${res.statusCode}");

      if (res.statusCode == 401) {
        throw Exception("401 Unauthorized – Invalid credentials or token expired.");
      }
      if (res.statusCode == 403) {
        throw Exception("403 Forbidden – Check token or permissions.");
      }
      if (res.statusCode == null || res.statusCode! >= 400) {
        throw Exception("HTTP ${res.statusCode} – ${res.statusMessage} – ${res.data}");
      }
    } on DioException catch (e) {
      // ignore: avoid_print
      print("DIO ERROR on DELETE $path: ${e.message}");
      // ignore: avoid_print
      print("DIO ERROR status: ${e.response?.statusCode}");
      // ignore: avoid_print
      print("DIO ERROR data: ${e.response?.data}");
      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout) {
        throw Exception("The server is down");
      }
      rethrow;
    } catch (e) {
      // ignore: avoid_print
      print("UNKNOWN ERROR on DELETE $path: $e");
      rethrow;
    }
  }
}
