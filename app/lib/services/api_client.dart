import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import '../config/app_config.dart';
import 'api_exception.dart';
import 'mock_backend.dart';

/// Thin, shared REST helper — every real backend call in this app
/// (auth_service.dart, party_service.dart, user_service.dart) goes through
/// this rather than each calling `http.post`/`http.put` directly, so the
/// error-envelope parsing (`{ error: { code, message } }`,
/// api-design.md's "Error response shape") only lives in one place. This is
/// also the single seam where the web build's self-contained demo mode
/// plugs in (see `_send`'s `kIsWeb` guard) — iOS/Android never take that
/// branch and keep hitting the real `backend/` exactly as before.
class ApiClient {
  static const _uuid = Uuid();
  static const _timeout = Duration(seconds: 10);

  /// POSTs [body] as JSON to `AppConfig.apiBaseUrl + path`. If [token] is
  /// given, sends it as `Authorization: Bearer <token>` (every protected
  /// endpoint this app calls needs one except /auth/*). If
  /// [idempotent] is true, attaches a fresh `Idempotency-Key` UUID v4 header
  /// (opt-in server-side per backend/src/middleware/idempotency.ts — used
  /// for POST /parties and POST /parties/join so a double-tap on "Create"/
  /// "Join" can't create two parties or double-join).
  ///
  /// Returns the decoded JSON body on any 2xx response. Throws
  /// [ApiException] otherwise — either the backend's own error envelope
  /// (malformed input, 401, 404 PARTY_NOT_FOUND, 409 PARTY_FULL, etc.) or
  /// an `ApiException.network` if the request never got a response at all
  /// (backend not running, wrong host/port, no connectivity).
  static Future<Map<String, dynamic>> post(
    String path,
    Map<String, dynamic> body, {
    String? token,
    bool idempotent = false,
  }) {
    return _send('POST', path, body, token: token, idempotent: idempotent);
  }

  /// PUTs [body] as JSON to `AppConfig.apiBaseUrl + path`. Same auth/error
  /// handling as [post] — see its doc comment. Used for `PUT /users/me`
  /// (user_service.dart), the first PUT endpoint this client calls; no
  /// endpoint it's used for so far needs `idempotent`, but the parameter is
  /// kept for symmetry with [post] rather than assuming it'll never apply.
  static Future<Map<String, dynamic>> put(
    String path,
    Map<String, dynamic> body, {
    String? token,
    bool idempotent = false,
  }) {
    return _send('PUT', path, body, token: token, idempotent: idempotent);
  }

  /// GETs `AppConfig.apiBaseUrl + path` — no request body. Added 2026-08-17
  /// for `GET /parties/:id` (party_service.dart's `getPartyDetail`, the
  /// backend REST backstop for party_ready_screen.dart's roster-listener
  /// race condition — see that file's doc comment), the first GET call this
  /// client makes to a protected endpoint. Same auth/error handling as
  /// [post]/[put] — see [post]'s doc comment.
  static Future<Map<String, dynamic>> get(
    String path, {
    String? token,
  }) {
    return _send('GET', path, null, token: token, idempotent: false);
  }

  static Future<Map<String, dynamic>> _send(
    String method,
    String path,
    Map<String, dynamic>? body, {
    String? token,
    bool idempotent = false,
  }) async {
    // Web-only demo swap: no publicly reachable backend exists for a
    // GitHub Pages link to call (see current-implementation.md's "Web
    // build" section), so the web target answers every call from the
    // in-memory MockBackend instead of ever touching the network. Mobile
    // (iOS/Android) never has kIsWeb true, so this never runs there.
    if (kIsWeb) {
      return MockBackend.handle(method, path, body);
    }

    final uri = Uri.parse('${AppConfig.apiBaseUrl}$path');
    final headers = <String, String>{
      if (body != null) 'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
      if (idempotent) 'Idempotency-Key': _uuid.v4(),
    };

    http.Response response;
    try {
      final encodedBody = body != null ? jsonEncode(body) : null;
      response = await (switch (method) {
        'PUT' => http.put(uri, headers: headers, body: encodedBody),
        'GET' => http.get(uri, headers: headers),
        _ => http.post(uri, headers: headers, body: encodedBody),
      })
          .timeout(_timeout);
    } catch (e) {
      throw ApiException.network(
        'Could not reach the Chalo server at $uri. Is the backend running? ($e)',
      );
    }

    Map<String, dynamic> decoded;
    try {
      decoded = response.body.isEmpty
          ? <String, dynamic>{}
          : jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      decoded = <String, dynamic>{};
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return decoded;
    }

    final error = decoded['error'] as Map<String, dynamic>?;
    throw ApiException(
      statusCode: response.statusCode,
      code: (error?['code'] as String?) ?? 'UNKNOWN_ERROR',
      message: (error?['message'] as String?) ??
          'Something went wrong talking to the Chalo server (HTTP ${response.statusCode}).',
    );
  }
}
