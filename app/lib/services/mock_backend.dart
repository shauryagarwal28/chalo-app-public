import 'dart:convert';

import 'api_exception.dart';

/// Self-contained, in-memory stand-in for `backend/` — used **only** on the
/// web build (`kIsWeb`), so a public GitHub Pages link has something to talk
/// to without depending on anyone's laptop staying up as a live server (see
/// `process/build-status.md`'s web-demo entry for why: free-tier hosts
/// cold-start/sleep, which is worse for a recruiter-facing link than a
/// static build that always works).
///
/// **iOS/Android are completely untouched by this file** — `api_client.dart`
/// is the only caller, reaching into here behind a `kIsWeb` check, so
/// mobile keeps hitting the real `backend/` exactly as before.
/// `location_ws_service.dart` has its own separate, self-contained `kIsWeb`
/// demo-simulation branch (party-member-joined + moving-rider-location
/// events) rather than importing this file, since a WebSocket's event
/// stream isn't a request/response call this class's `handle()` shape fits
/// — see that file's `_startDemoSimulation()`.
///
/// Deliberately not a general-purpose fake-server framework — just enough
/// fixed/derived responses to make S1-S9's click-through work end to end,
/// matching the exact response shapes `auth_service.dart`/`party_service.dart`/
/// `user_service.dart` already expect (so those files needed zero changes).
/// Demo party/rider names reuse names already used as mock fixtures
/// elsewhere in this app (`join_party_screen.dart`, `ride_chat_screen.dart`,
/// `ride_day_screen.dart`) so the demo reads as one consistent world instead
/// of introducing a fourth set of placeholder names.
class MockBackend {
  MockBackend._();

  static const String demoUserId = 'demo-rider-you';
  static const String partyId = 'demo-party-1';
  static const String roomCode = 'DEMO42';

  static const String rideName = 'Weekend Warriors Ride';
  static const String meetPoint = 'Bandra Toll Plaza';
  static const String date = '2026-09-13';
  static const String time = '06:30';
  static const int maxRiders = 6;

  /// Set by the mocked `PUT /users/me` (profile creation's "Let's Ride"),
  /// same "empty until the user sets it" shape the real backend has for a
  /// brand-new user. Read back by the mocked `GET`/roster responses below so
  /// the rider's own name (not a placeholder) shows up in the party roster,
  /// same as a real backend would.
  static String riderName = '';

  /// A fixed, non-secret JWT-*shaped* string — real enough for
  /// `auth_service.dart`'s `_decodeUserIdFromJwt` to parse a `userId` claim
  /// out of (that function only reads the payload segment, never verifies a
  /// signature, by design — see its doc comment), but not a real signed
  /// token and not accepted by anything except this mock backend. Built at
  /// call time, not hardcoded base64, so it stays correct if [demoUserId]
  /// ever changes.
  static String _fakeAccessToken() {
    String seg(Map<String, dynamic> json) =>
        base64Url.encode(utf8.encode(jsonEncode(json))).replaceAll('=', '');
    final header = seg({'alg': 'none', 'typ': 'JWT'});
    final payload = seg({'userId': demoUserId});
    return '$header.$payload.mock-web-demo-signature';
  }

  /// Whether the visitor is this demo party's organiser — true once they've
  /// gone through `POST /parties` (Create Party). Defaults false so the
  /// **Join Party** flow (a visitor who never creates, just enters any
  /// 6-char code — see `handle`'s `POST /parties/join` case) sees a
  /// consistent, distinct host ("Arjun Mehta", reusing the same name
  /// `join_party_screen.dart`'s own `_recentParties` mock fixture already
  /// uses) instead of `waiting_room_screen.dart` rendering "Waiting for
  /// {your own name} to Start", which [JoinPartyResult.hostName] would
  /// otherwise resolve to if this member entry were also marked host.
  static bool _demoUserIsHost = false;

  static Map<String, dynamic> _rosterJson() => {
        'partyId': partyId,
        'rideName': rideName,
        'meetPoint': meetPoint,
        'date': date,
        'time': time,
        'maxRiders': maxRiders,
        'members': [
          {
            'userId': demoUserId,
            'name': riderName,
            'isHost': _demoUserIsHost,
          },
          {
            'userId': 'demo-rider-organiser',
            'name': 'Arjun Mehta',
            'isHost': !_demoUserIsHost,
          },
          {
            'userId': 'demo-rider-vikram',
            'name': 'Vikram Singh',
            'isHost': false,
          },
          {
            'userId': 'demo-rider-neha',
            'name': 'Neha Kapoor',
            'isHost': false,
          },
        ],
      };

  /// Mirrors `ApiClient._send`'s method+path dispatch closely enough that
  /// `api_client.dart` can hand off to this with almost no branching of its
  /// own — see that file's `kIsWeb` guard at the top of `_send`.
  static Map<String, dynamic> handle(
    String method,
    String path,
    Map<String, dynamic>? body,
  ) {
    switch ('$method $path') {
      case 'POST /auth/request-otp':
        return {
          'success': true,
          'expiresInSeconds': 300,
          // Auto-fills otp_screen.dart's 6 boxes, same field the real
          // backend's dev mode uses — no SMS involved either way.
          'debugOtp': '123456',
        };

      case 'POST /auth/verify-otp':
        return {
          'accessToken': _fakeAccessToken(),
          'refreshToken': 'mock-web-demo-refresh-token',
          'isNewUser': true,
        };

      case 'PUT /users/me':
        final name = body?['name'] as String? ?? '';
        if (name.trim().isEmpty) {
          throw const ApiException(
            statusCode: 400,
            code: 'INVALID_REQUEST',
            message: 'name is required.',
          );
        }
        riderName = name.trim();
        return {
          'id': demoUserId,
          'phoneNumber': '+919876500000',
          'name': riderName,
          'kycStatus': 'not_started',
        };

      case 'POST /parties':
        _demoUserIsHost = true;
        return {'partyId': partyId, 'roomCode': roomCode};

      case 'POST /parties/join':
        // The real backend rejects an unknown code with PARTY_NOT_FOUND;
        // this demo has exactly one party to join, so anything that looks
        // like a real attempt (a fully-typed 6-char code, matching
        // join_party_screen.dart's entry UI) succeeds into it rather than
        // dead-ending a visitor who doesn't know a "real" code — there is
        // no real code, only this demo party.
        final code = (body?['roomCode'] as String? ?? '').trim();
        if (code.length != 6) {
          throw const ApiException(
            statusCode: 404,
            code: 'PARTY_NOT_FOUND',
            message: 'No party found with that code.',
          );
        }
        return _rosterJson();

      default:
        if (method == 'GET' && path == '/parties/$partyId') {
          return _rosterJson();
        }
        if (method == 'POST' && path == '/parties/$partyId/end') {
          return {'ended': true, 'endedAt': DateTime.now().toUtc().toIso8601String()};
        }
        throw ApiException(
          statusCode: 404,
          code: 'NOT_FOUND',
          message: 'No mock web-demo response wired for $method $path.',
        );
    }
  }
}
