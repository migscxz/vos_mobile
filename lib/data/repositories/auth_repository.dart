// lib/data/repositories/auth_repository.dart
import "dart:convert";
import "package:crypto/crypto.dart";
import "../../core/network/api_client.dart";
import "../../core/auth/auth_storage.dart";

class AuthRepository {
  AuthRepository(this._api, this._storage);

  final ApiClient _api;
  final AuthStorage _storage;

  /// Restore session for app-level login (no Directus token)
  Future<bool> restoreSession() async {
    final userId = await _storage.readUserId();
    return userId != null;
  }

  /// OFFLINE-FIRST LOGIN (custom collection: /items/user)
  ///
  /// Flow:
  /// 1) Try ONLINE login:
  ///    - GET /items/user?filter[user_email]=...
  ///    - validate password vs user_password
  ///    - save current userId
  ///    - cache user locally for offline login next time
  ///
  /// 2) If OFFLINE (network error / no response):
  ///    - validate against cached users using local hash
  ///    - save current userId
  Future<void> login({
    required String email,
    required String password,
  }) async {
    final e = email.trim().toLowerCase();
    final p = password.trim();

    if (e.isEmpty) throw Exception("Login failed: email is required.");
    if (p.isEmpty) throw Exception("Login failed: password is required.");

    try {
      // ---- ONLINE ATTEMPT ----
      final res = await _api.getJson(
        "/items/user",
        query: {
          "limit": "1",
          "filter[user_email][_eq]": e,
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
      if (dbPass != p) {
        // IMPORTANT: do not fallback to offline when password is wrong online
        throw Exception("Login failed: invalid password.");
      }

      final userId = _asInt(row["user_id"]);
      if (userId == null) {
        throw Exception("Login failed: user_id missing.");
      }

      await _storage.saveUserId(userId);

      // Cache user for offline login
      final fname = (row["user_fname"] ?? "").toString().trim();
      final lname = (row["user_lname"] ?? "").toString().trim();

      await _storage.upsertCachedUser(
        CachedUser(
          userId: userId,
          email: e,
          passwordHash: _hashForOffline(emailLower: e, password: p),
          fname: fname.isEmpty ? null : fname,
          lname: lname.isEmpty ? null : lname,
        ),
      );

      return;
    } catch (eOnline) {
      // ---- OFFLINE FALLBACK ----
      // Only fallback if this looks like "offline / cannot reach server".
      if (!_looksOfflineError(eOnline)) {
        rethrow;
      }

      final cached = await _storage.readCachedUsers();
      final match = cached.where((u) => u.email.trim().toLowerCase() == e).toList();

      if (match.isEmpty) {
        throw Exception(
          "Offline login unavailable for this account.\n"
          "Please login once while online to cache your credentials.",
        );
      }

      final user = match.first;
      final inputHash = _hashForOffline(emailLower: e, password: p);

      if (user.passwordHash != inputHash) {
        throw Exception("Offline login failed: invalid password.");
      }

      await _storage.saveUserId(user.userId);
      return;
    }
  }

  Future<int?> getCurrentAppUserId() => _storage.readUserId();

  Future<void> logout() async {
    await _storage.clearAll();
  }

  // -------------------------
  // Helpers
  // -------------------------

  String _hashForOffline({required String emailLower, required String password}) {
    // simple deterministic hash: sha256("email:password")
    final bytes = utf8.encode("$emailLower:$password");
    return sha256.convert(bytes).toString();
  }

  bool _looksOfflineError(Object e) {
    final s = e.toString().toLowerCase();

    // Heuristics to detect "no network / cannot reach server"
    return s.contains("dioexception") ||
        s.contains("socketexception") ||
        s.contains("failed host lookup") ||
        s.contains("connection refused") ||
        s.contains("timed out") ||
        s.contains("network is unreachable") ||
        s.contains("connection error") ||
        s.contains("receive timeout") ||
        s.contains("connecttimeout") ||
        s.contains("unknown error on get") ||
        s.contains("unknown error on post");
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
