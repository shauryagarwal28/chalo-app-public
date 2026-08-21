import 'dart:convert';
import 'api_client.dart';

/// Result of a successful `POST /auth/request-otp` call.
class OtpRequestResult {
  final int expiresInSeconds;

  /// Only present when the backend is running with NODE_ENV != 'production'
  /// (backend/src/routes/auth.ts) — this dev backend always is, so this
  /// should always be non-null in practice. Used to auto-fill the OTP boxes
  /// in otp_screen.dart instead of a real SMS, per this task's explicit
  /// instruction to use dev-mode's debugOtp rather than build real SMS
  /// delivery.
  final String? debugOtp;

  const OtpRequestResult({required this.expiresInSeconds, this.debugOtp});
}

/// Result of a successful `POST /auth/verify-otp` call.
class VerifyOtpResult {
  final String accessToken;
  final String refreshToken;
  final bool isNewUser;

  const VerifyOtpResult({
    required this.accessToken,
    required this.refreshToken,
    required this.isNewUser,
  });
}

/// Process-lifetime auth session, deliberately not persisted — same pattern
/// and same explicit non-goal as services/mock_user_state.dart (this app
/// has no persistence/session-restore across restarts anywhere yet; that's
/// a separate decision, out of scope here per this task's instructions).
///
/// A plain static holder (not a singleton instance threaded through every
/// screen's constructor) because the screens that need the token
/// (create/join party, live ride) are navigated to from screens that don't
/// (home, profile creation) — threading a token through every intermediate
/// screen's constructor would touch far more files than this task's scope,
/// for no benefit over a single source of truth read at the point of use.
/// See technical/architecture/current-implementation.md's "State
/// management" section for the fuller reasoning.
class AuthSession {
  static String? accessToken;
  static String? refreshToken;
  static String? userId;
  static String? phoneNumber;

  static bool get isAuthenticated => accessToken != null && userId != null;

  static void clear() {
    accessToken = null;
    refreshToken = null;
    userId = null;
    phoneNumber = null;
  }
}

/// Decodes the `userId` claim out of a JWT's payload segment, without
/// verifying the signature — this is the app reading its own token's claims
/// immediately after receiving it over a connection it already trusts (the
/// same backend that just issued it), not a security check. The backend
/// (backend/src/services/token.ts) is the only party that ever needs to
/// verify these tokens; the client just needs its own userId to key local
/// state (e.g. distinguishing "my own marker" from other riders' markers on
/// the live map). Avoids adding a JWT-decoding package for one field.
String _decodeUserIdFromJwt(String token) {
  final parts = token.split('.');
  if (parts.length != 3) {
    throw const FormatException('Access token is not a valid JWT.');
  }
  var payloadSegment = parts[1];
  payloadSegment += '=' * ((4 - payloadSegment.length % 4) % 4);
  final payloadJson = utf8.decode(base64Url.decode(payloadSegment));
  final payload = jsonDecode(payloadJson) as Map<String, dynamic>;
  final userId = payload['userId'];
  if (userId is! String) {
    throw const FormatException('Access token payload has no userId claim.');
  }
  return userId;
}

class AuthService {
  /// `POST /auth/request-otp` — { phoneNumber } -> { success, expiresInSeconds, debugOtp? }
  /// per api-design.md. [phoneNumberE164] must already be in E.164 format
  /// (e.g. "+919876543210") — phone_entry_screen.dart builds that from the
  /// 10-digit field it already collects.
  static Future<OtpRequestResult> requestOtp(String phoneNumberE164) async {
    final json = await ApiClient.post('/auth/request-otp', {
      'phoneNumber': phoneNumberE164,
    });
    return OtpRequestResult(
      expiresInSeconds: json['expiresInSeconds'] as int,
      debugOtp: json['debugOtp'] as String?,
    );
  }

  /// `POST /auth/verify-otp` — { phoneNumber, code } -> { accessToken, refreshToken, isNewUser }.
  /// On success, populates [AuthSession] (including decoding userId out of
  /// the fresh access token) so every later screen can read it.
  static Future<VerifyOtpResult> verifyOtp(
    String phoneNumberE164,
    String code,
  ) async {
    final json = await ApiClient.post('/auth/verify-otp', {
      'phoneNumber': phoneNumberE164,
      'code': code,
    });
    final accessToken = json['accessToken'] as String;
    final refreshToken = json['refreshToken'] as String;
    final isNewUser = json['isNewUser'] as bool;

    AuthSession.accessToken = accessToken;
    AuthSession.refreshToken = refreshToken;
    AuthSession.phoneNumber = phoneNumberE164;
    AuthSession.userId = _decodeUserIdFromJwt(accessToken);

    return VerifyOtpResult(
      accessToken: accessToken,
      refreshToken: refreshToken,
      isNewUser: isNewUser,
    );
  }
}
