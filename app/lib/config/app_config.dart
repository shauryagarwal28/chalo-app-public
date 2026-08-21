import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;

/// Local backend connection config for this dev/integration-testing pass.
///
/// Not a secret (no key, no credential) — unlike agora_config.dart or
/// Secrets.xcconfig, this is just "where is the backend" and is fine to
/// commit. `backend/docker-compose.yml` binds the backend to port 3000 on
/// the host machine.
///
/// The host differs by platform because "localhost" means something
/// different depending on where the app is actually running:
/// - iOS Simulator shares the host Mac's network namespace, so
///   `localhost`/`127.0.0.1` correctly reaches a backend running on the Mac.
/// - The Android emulator runs in its own virtual machine — `localhost`
///   there means the emulator itself, not the host machine. `10.0.2.2` is
///   the documented special alias Android emulators provide specifically to
///   reach the host loopback interface (see
///   https://developer.android.com/studio/run/emulator-networking).
/// - A physical device (either platform) would need the host machine's real
///   LAN IP instead of either of these — out of scope for this pass, which
///   only targets simulators/emulators per the verification plan in
///   process/build-status.md.
class AppConfig {
  static String get _backendHost {
    if (!kIsWeb && Platform.isAndroid) return '10.0.2.2';
    return 'localhost';
  }

  static const int backendPort = 3000;

  /// e.g. http://localhost:3000/api/v1
  static String get apiBaseUrl => 'http://$_backendHost:$backendPort/api/v1';

  /// e.g. ws://10.0.2.2:3000/ws — token appended as a query param by the
  /// caller, per api-design.md's WebSocket handshake spec.
  static String get wsBaseUrl => 'ws://$_backendHost:$backendPort/ws';
}
