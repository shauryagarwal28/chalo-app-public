import 'api_client.dart';
import 'auth_service.dart';

/// Result of a successful `PUT /users/me` call — same MVP-minimal shape
/// `GET /users/me` returns (api-design.md's `PUT /users/me` section):
/// `{ id, phoneNumber, name, kycStatus }`. Only `name` is used by any
/// caller today; the rest are decoded for completeness/future use rather
/// than dropped.
class UpdateUserResult {
  final String id;
  final String phoneNumber;
  final String name;
  final String kycStatus;

  const UpdateUserResult({
    required this.id,
    required this.phoneNumber,
    required this.name,
    required this.kycStatus,
  });
}

/// `PUT /users/me`, per api-design.md's `users` section (Task 10,
/// 2026-08-09) — persists the signed-in user's display name server-side.
/// This is the piece that closes the "empty-name gap" documented in
/// build-status.md and party_service.dart's file-level comment: without
/// this call, every rider's server-side `name` stays `''` forever, and
/// every screen that shows another rider's name keeps falling back to a
/// generic label.
class UserService {
  /// [name] is sent as-is — callers are expected to have already trimmed
  /// it and confirmed it's non-empty (the backend also validates this and
  /// throws `ApiException` with code `INVALID_REQUEST` if not, per
  /// api-design.md's `PUT /users/me` MVP-subset note).
  static Future<UpdateUserResult> updateName(String name) async {
    final token = AuthSession.accessToken;
    if (token == null) {
      throw StateError(
        'UserService.updateName called before AuthSession has an access '
        'token — this should be unreachable, since every screen that calls '
        'this comes after the phone/OTP flow.',
      );
    }

    final json = await ApiClient.put(
      '/users/me',
      {'name': name},
      token: token,
    );

    return UpdateUserResult(
      id: json['id'] as String,
      phoneNumber: json['phoneNumber'] as String,
      name: json['name'] as String,
      kycStatus: json['kycStatus'] as String,
    );
  }
}
