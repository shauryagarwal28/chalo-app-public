/// Thrown by api_client.dart on any non-2xx REST response, or on a network-
/// level failure (no connection, timeout, malformed response). Carries the
/// backend's own `{ error: { code, message } }` envelope
/// (technical/architecture/api-design.md's "Error response shape") when one
/// was actually returned, so callers can branch on `code` (e.g.
/// `PARTY_NOT_FOUND`, `PARTY_FULL`) instead of parsing `message` strings.
class ApiException implements Exception {
  final int statusCode;
  final String code;
  final String message;

  const ApiException({
    required this.statusCode,
    required this.code,
    required this.message,
  });

  /// statusCode 0 signals a network-level failure (backend unreachable) —
  /// there was never a real HTTP response to read a status code from.
  const ApiException.network(this.message)
      : statusCode = 0,
        code = 'NETWORK_ERROR';

  @override
  String toString() => message;
}
