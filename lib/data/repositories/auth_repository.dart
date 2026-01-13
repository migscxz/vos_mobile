// lib/data/repositories/auth_repository.dart
import "dart:convert";
import "dart:io";

import "package:crypto/crypto.dart";
import "package:dio/dio.dart";

import "../../core/network/api_client.dart";
import "../../core/auth/auth_storage.dart";

class AuthRepository {
  AuthRepository(this._api, this._storage);

  final ApiClient _api;
  final AuthStorage _storage;

  // -------------------------
  // Session
  // -------------------------

  /// Restore session for app-level login (no Directus token).
  Future<bool> restoreSession() async {
    final userId = await _storage.readUserId();
    return userId != null;
  }

  Future<int?> getCurrentAppUserId() => _storage.readUserId();

  Future<void> logout() async {
    await _storage.clearAll();
  }

  // -------------------------
  // Login (offline-first)
  // -------------------------

  /// OFFLINE-FIRST LOGIN using custom collection: /items/user
  ///
  /// Behavior:
  /// - Online: validate email/password against Directus items/user (plaintext user_password)
  /// - On successful online: save userId + cache local hash for offline login
  /// - Offline/network failure: validate against cached users (sha256("email:password"))
  Future<void> login({
    required String email,
    required String password,
  }) async {
    final emailLower = email.trim().toLowerCase();
    final pass = password.trim();

    if (emailLower.isEmpty) {
      throw Exception("Login failed: email is required.");
    }
    if (pass.isEmpty) {
      throw Exception("Login failed: password is required.");
    }

    try {
      final user = await _loginOnline(emailLower: emailLower, password: pass);
      await _storage.saveUserId(user.userId);

      // Cache for offline login
      await _storage.upsertCachedUser(
        CachedUser(
          userId: user.userId,
          email: user.emailLower,
          passwordHash: _offlineHash(emailLower: user.emailLower, password: pass),
          fname: user.fname,
          lname: user.lname,
        ),
      );
      return;
    } catch (e) {
      // Only fall back if this is plausibly a network/offline error.
      if (!_isNetworkFailure(e)) rethrow;

      await _loginOffline(emailLower: emailLower, password: pass);
      return;
    }
  }

  // -------------------------
  // Internals
  // -------------------------

  Future<_OnlineUser> _loginOnline({
    required String emailLower,
    required String password,
  }) async {
    final res = await _api.getJson(
      "/items/user",
      query: {
        "limit": "1",
        "filter[user_email][_eq]": emailLower,
        "fields": "user_id,user_email,user_password,is_deleted,user_fname,user_lname",
      },
    );

    final list = (res["data"] as List?) ?? const [];
    if (list.isEmpty) {
      throw Exception("Login failed: user email not found.");
    }

    final row = Map<String, dynamic>.from(list.first as Map);

    if (_truthy(row["is_deleted"])) {
      throw Exception("Login failed: user is marked as deleted.");
    }

    final dbPass = (row["user_password"] ?? "").toString().trim();
    if (dbPass != password) {
      // IMPORTANT: do not fall back offline if credentials are wrong online
      throw Exception("Login failed: invalid password.");
    }

    final userId = _asInt(row["user_id"]);
    if (userId == null) {
      throw Exception("Login failed: user_id missing.");
    }

    final emailDb = (row["user_email"] ?? emailLower).toString().trim().toLowerCase();
    final fname = (row["user_fname"] ?? "").toString().trim();
    final lname = (row["user_lname"] ?? "").toString().trim();

    return _OnlineUser(
      userId: userId,
      emailLower: emailDb.isEmpty ? emailLower : emailDb,
      fname: fname.isEmpty ? null : fname,
      lname: lname.isEmpty ? null : lname,
    );
  }

  Future<void> _loginOffline({
    required String emailLower,
    required String password,
  }) async {
    final cached = await _storage.readCachedUsers();

    final matches = cached.where((u) => u.email.trim().toLowerCase() == emailLower).toList();
    if (matches.isEmpty) {
      throw Exception(
        "Offline login unavailable for this account.\n"
        "Please login once while online to cache your credentials.",
      );
    }

    final wantedHash = _offlineHash(emailLower: emailLower, password: password);
    final ok = matches.any((u) => u.passwordHash == wantedHash);

    if (!ok) {
      throw Exception("Offline login failed: invalid password.");
    }

    // Use the first userId for that email
    await _storage.saveUserId(matches.first.userId);
  }

  /// Deterministic hash for offline login:
  /// sha256("email:password")
  String _offlineHash({required String emailLower, required String password}) {
    final bytes = utf8.encode("$emailLower:$password");
    return sha256.convert(bytes).toString();
  }

  bool _isNetworkFailure(Object e) {
    // Prefer Dio classification if present
    if (e is DioException) {
      // If server responded (status code exists), this is NOT offline.
      // Example: 403/401/500 => do not fallback to offline.
      if (e.response != null) return false;

      // No response typically means connection issue / DNS / timeout
      return true;
    }

    // Low-level socket errors
    if (e is SocketException) return true;

    // Fallback heuristics for wrapped Exceptions
    final s = e.toString().toLowerCase();
    return s.contains("socketexception") ||
        s.contains("failed host lookup") ||
        s.contains("connection refused") ||
        s.contains("timed out") ||
        s.contains("network is unreachable") ||
        s.contains("connection error") ||
        s.contains("receive timeout") ||
        s.contains("connecttimeout");
  }

  bool _truthy(Object? v) {
    if (v == null) return false;
    if (v is bool) return v;
    if (v is num) return v != 0;

    // handle: { type: "Buffer", data: [1] }
    if (v is Map) {
      final data = v["data"];
      if (data is List && data.isNotEmpty) {
        final first = data.first;
        if (first is num) return first != 0;
        final parsed = int.tryParse(first.toString());
        if (parsed != null) return parsed != 0;
      }
    }

    final s = v.toString().trim().toLowerCase();
    return s == "1" || s == "true" || s == "yes";
  }

  int? _asInt(Object? v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString());
  }
}

class _OnlineUser {
  final int userId;
  final String emailLower;
  final String? fname;
  final String? lname;

  const _OnlineUser({
    required this.userId,
    required this.emailLower,
    required this.fname,
    required this.lname,
  });
}
