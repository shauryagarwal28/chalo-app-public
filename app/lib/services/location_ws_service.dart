import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../config/app_config.dart';

/// One other rider's most recently broadcast position, per
/// `location:broadcast { userId, lat, lng, speed, timestamp }`
/// (technical/architecture/api-design.md / system-overview.md's WebSocket
/// Event Map).
class RiderLocation {
  final String userId;
  final double lat;
  final double lng;
  final double speedKmph;

  /// Local receive time, not the server/client `timestamp` field — good
  /// enough for this pass's "is this marker fresh" purposes. Matching the
  /// server's own `updatedAt`-is-receive-time reasoning (Task 6 senior
  /// review, build-status.md) rather than trusting a peer's clock.
  final DateTime receivedAt;

  const RiderLocation({
    required this.userId,
    required this.lat,
    required this.lng,
    required this.speedKmph,
    required this.receivedAt,
  });
}

/// The party's stage-1 banner trigger — `emergency:stage1
/// { stoppedUserId, stoppedUserName }`, sent to every party member except
/// the stopped rider (technical/systems/emergency-detection.md step 3 /
/// system-overview.md's Event Map). Deliberately has **no countdown
/// field on the wire** — only `emergency:confirm` (sent to the stopped
/// rider only) carries one. See live_ride_screen.dart's handling of this
/// for how that's resolved (not guessed) on the UI side.
class EmergencyStage1Event {
  final String stoppedUserId;
  final String stoppedUserName;

  const EmergencyStage1Event({
    required this.stoppedUserId,
    required this.stoppedUserName,
  });
}

/// The stopped rider's own confirmation prompt trigger — `emergency:confirm
/// { countdown }`, sent only to the rider who tripped the detector.
class EmergencyConfirmEvent {
  final int countdownSeconds;

  const EmergencyConfirmEvent({required this.countdownSeconds});
}

/// `emergency:resolved { userId }` — the stopped rider tapped "I Am Fine"
/// within the confirmation window. Per emergency.ts's `resolveEmergency`,
/// broadcast to every party member with no exclusion, including the
/// stopped rider themselves.
class EmergencyResolvedEvent {
  final String userId;

  const EmergencyResolvedEvent({required this.userId});
}

/// `emergency:full_alert { userId, name, lat, lng, stoppedAt, elapsed,
/// distanceBehind }` — Stage 3, broadcast to every party member with no
/// exclusion (same recipient set as [EmergencyResolvedEvent]). `lat`/`lng`
/// and `distanceBehind` are nullable on the wire (server has no cached
/// location for the stopped rider, or no other member to compare against,
/// respectively — see emergency.ts's `computeDistanceBehindKm` doc
/// comment) — kept nullable here too rather than substituting a fake 0.0.
class EmergencyFullAlertEvent {
  final String userId;
  final String name;
  final double? lat;
  final double? lng;
  final DateTime? stoppedAt;
  final int elapsedSeconds;
  final double? distanceBehindKm;

  const EmergencyFullAlertEvent({
    required this.userId,
    required this.name,
    required this.lat,
    required this.lng,
    required this.stoppedAt,
    required this.elapsedSeconds,
    required this.distanceBehindKm,
  });
}

/// `ptt:started { userId }` — someone else in the party began transmitting.
/// Per ptt.ts's own doc comment, this is purely a relay for the local
/// audio-cue beeps in ptt-audio.md's "Audio Cue Playback" section — never
/// echoed back to the sender (server-side exclusion, same as
/// `location:broadcast`), so every notification here is genuinely "someone
/// else".
class PttStartedEvent {
  final String userId;

  const PttStartedEvent({required this.userId});
}

/// `ptt:ended { userId }` — the counterpart to [PttStartedEvent], sent when
/// that same rider releases PTT.
class PttEndedEvent {
  final String userId;

  const PttEndedEvent({required this.userId});
}

/// `party:ended { partyId }` — the organiser tapped End Ride and
/// `POST /parties/:id/end` succeeded (added 2026-08-17,
/// process/build-status.md Next Steps item 30). Broadcast to every
/// still-connected party member with no exclusion, including the
/// organiser's own connection — see `live_ride_screen.dart`'s
/// `_onPartyEnded` for why the organiser's device ignores its own echo of
/// this event.
class PartyEndedEvent {
  final String partyId;

  const PartyEndedEvent({required this.partyId});
}

/// Owns one party's WebSocket connection lifecycle for the live ride
/// screen — location relay, the emergency-alert event set
/// (`emergency:stage1`/`confirm`/`resolved`/`full_alert` in,
/// `emergency:respond` out), the PTT relay (`ptt:state` out,
/// `ptt:started`/`ptt:ended` in), and, as of 2026-08-17, `party:ended` in
/// (see [PartyEndedEvent]). Per api-design.md's WS
/// section, the backend serves exactly one `/ws?token=` connection per
/// party and multiplexes every event type (location, party, emergency,
/// ptt) over it — so this class, not a second connection, is where any new
/// event type belonging to that same connection is meant to be added.
///
/// **2026-08-09 — the file's own prior note flagged a third unrelated
/// concern (e.g. `ptt:*`) as the trigger to revisit the file's name.**
/// That's now happened. Still not renamed this pass, for the same reason
/// as before (every call site + doc cross-reference would need touching
/// for a naming-only diff) — but this is now the second time this
/// decision's been deferred rather than made, worth a deliberate call
/// next time this file is touched for an unrelated reason rather than a
/// third silent defer.
///
/// **Left un-renamed, decided explicitly rather than silently**: this
/// class/file is still called `LocationWsService`/`location_ws_service.dart`
/// even though it's no longer location-only. Considered renaming to
/// something like `PartyWsService` to match its real scope, but decided
/// against it for this pass — the class's own doc comment already framed
/// it as "one party's WebSocket connection lifecycle" (not
/// location-specific) before this change, the four new emergency cases
/// added to `_onMessage` below are a small, additive diff to an existing
/// dispatch switch (the same shape `location:broadcast`/
/// `party:member_joined`/`error` already used), and a rename would touch
/// every call site (`live_ride_screen.dart`) and doc cross-reference for a
/// naming-only change with no behavioural benefit. Worth revisiting if a
/// future task adds a third unrelated concern (e.g. `ptt:*`) to this same
/// connection and the "Location" name starts actively misleading readers.
///
/// Mirrors agora_ptt_service.dart's established pattern for this codebase:
/// an explicit init/dispose lifecycle, `ValueNotifier`s for anything a
/// screen needs to react to, and every failure caught and surfaced via
/// [lastError] instead of thrown/crashing — "no App ID configured" there is
/// this service's "connection closed / never connected" here.
///
/// State management note: this app has no Provider/Riverpod/Bloc dependency
/// (technical/architecture/current-implementation.md's "State management"
/// section, which explicitly flagged that a decision was needed before real
/// WS wiring happened). Decided here: keep using the same
/// `ValueNotifier` + `StatefulWidget` listener pattern `AgoraPttService`
/// already established, rather than introducing a new state management
/// dependency for this one screen. It's a smaller, more consistent change,
/// and this is the only screen in the app that currently needs to react to
/// a live server-pushed stream — not a broad enough need yet to justify a
/// new architectural dependency across the whole app.
class LocationWsService {
  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  bool _connected = false;

  /// userId -> that rider's latest known position. Never includes this
  /// device's own userId — the server never echoes a sender's own
  /// `location:update` back to them (confirmed live, Task 6 senior review),
  /// so there's nothing to filter out here, only to be aware of.
  final ValueNotifier<Map<String, RiderLocation>> riderLocations =
      ValueNotifier({});

  /// userId -> display name, learned incrementally from `party:member_joined`
  /// events for members who join *after* this connection is open. Members
  /// already in the party before this connection opened are NOT covered by
  /// this — see live_ride_screen.dart for how it merges this with the
  /// initial roster from `POST /parties/join`'s response instead.
  final ValueNotifier<Map<String, String>> riderNames = ValueNotifier({});

  final ValueNotifier<String?> lastError = ValueNotifier(null);

  /// Each set to a fresh instance (never mutated in place) on every
  /// matching server message, so a listener sees every distinct event even
  /// if two consecutive payloads happen to carry identical field values —
  /// `ValueNotifier` only skips notification on `==`-equal values, and
  /// these classes don't override `==`, so plain object identity is enough
  /// (same reasoning `riderLocations`'s `Map.from(...)` replacement above
  /// already relies on). Not reset to null after being consumed — the
  /// listener (live_ride_screen.dart) reads `.value` once per notification
  /// and doesn't need it cleared, same pattern `riderLocations`/
  /// `riderNames` already use.
  final ValueNotifier<EmergencyStage1Event?> stage1Event = ValueNotifier(null);
  final ValueNotifier<EmergencyConfirmEvent?> confirmEvent = ValueNotifier(null);
  final ValueNotifier<EmergencyResolvedEvent?> resolvedEvent = ValueNotifier(null);
  final ValueNotifier<EmergencyFullAlertEvent?> fullAlertEvent = ValueNotifier(null);

  /// `ptt:started`/`ptt:ended`, per ptt.ts and ptt-audio.md's "Audio Cue
  /// Playback" section — see [PttStartedEvent]/[PttEndedEvent]. Modelled as
  /// two separate notifiers, one per distinct wire event, matching the
  /// emergency events above rather than collapsing into a single nullable
  /// "currently speaking" notifier — there are exactly two independent
  /// triggers (a start beep, an end beep), each with its own listener need,
  /// same shape as `stage1Event`/`resolvedEvent` being separate rather than
  /// one "current emergency" field.
  final ValueNotifier<PttStartedEvent?> pttStartedEvent = ValueNotifier(null);
  final ValueNotifier<PttEndedEvent?> pttEndedEvent = ValueNotifier(null);

  /// `party:ended` — see [PartyEndedEvent]'s doc comment.
  final ValueNotifier<PartyEndedEvent?> partyEndedEvent = ValueNotifier(null);

  bool get isConnected => _connected;

  /// Opens the WS connection for [partyId] using [accessToken], per
  /// api-design.md's handshake spec (`ws://<host>/ws?token=<accessToken>`).
  /// Safe to call once per screen lifetime; a second call while already
  /// connected is a no-op.
  ///
  /// **Fixed 2026-08-17** (found live while fixing `party_ready_screen.dart`'s
  /// roster-listener race condition, process/build-status.md Next Steps item
  /// 29): this previously set [isConnected] to true and returned immediately
  /// after `WebSocketChannel.connect(uri)` — which only *constructs* the
  /// channel object, it does not wait for the underlying handshake to
  /// actually finish. A caller `await`ing [connect] was therefore never
  /// getting a real "the socket is open" signal, only "the connect attempt
  /// started" — a meaningfully different, much weaker guarantee. Now awaits
  /// `channel.ready` (the client-side handshake genuinely completing) before
  /// setting [isConnected]/returning.
  ///
  /// This closes most, but not all, of the race a caller like
  /// `party_ready_screen.dart` can hit: the server's own party-room
  /// registration (`websocket/partyPresence.ts`'s `handlePartyConnect`) is
  /// itself fire-and-forget relative to the WS `'connection'` event
  /// (`websocket/server.ts` — a deliberate "never let a side effect block
  /// the connection" choice, not a bug), so it can still finish a few
  /// milliseconds *after* this Future resolves. That residual window is a
  /// single in-memory/Redis round trip, not the indeterminate multi-second
  /// gap this fix closes (a human reading/typing a room code, or a fast
  /// automated join) — small enough that `party_ready_screen.dart`'s own
  /// REST backstop fetch, called right after this resolves, is judged
  /// sufficient without also adding a fixed artificial delay here. Documented
  /// honestly rather than claimed as fully eliminated.
  Future<void> connect(String accessToken) async {
    if (_connected) return;

    final uri = Uri.parse('${AppConfig.wsBaseUrl}?token=$accessToken');
    try {
      final channel = WebSocketChannel.connect(uri);
      _channel = channel;
      _subscription = channel.stream.listen(
        _onMessage,
        onError: _onError,
        onDone: _onDone,
        cancelOnError: false,
      );
      await channel.ready;
      _connected = true;
    } catch (e) {
      lastError.value = 'Could not connect to live location — $e';
      _connected = false;
    }
  }

  void _onMessage(dynamic raw) {
    try {
      final decoded = jsonDecode(raw as String) as Map<String, dynamic>;
      final type = decoded['type'] as String?;
      final payload = decoded['payload'] as Map<String, dynamic>?;
      if (type == null || payload == null) return;

      switch (type) {
        case 'location:broadcast':
          final userId = payload['userId'] as String;
          final updated = Map<String, RiderLocation>.from(riderLocations.value);
          updated[userId] = RiderLocation(
            userId: userId,
            lat: (payload['lat'] as num).toDouble(),
            lng: (payload['lng'] as num).toDouble(),
            speedKmph: (payload['speed'] as num).toDouble(),
            receivedAt: DateTime.now(),
          );
          riderLocations.value = updated;
          break;

        case 'party:member_joined':
          final userId = payload['userId'] as String;
          final name = (payload['name'] as String?) ?? '';
          final updatedNames = Map<String, String>.from(riderNames.value);
          updatedNames[userId] = name;
          riderNames.value = updatedNames;
          break;

        case 'emergency:stage1':
          stage1Event.value = EmergencyStage1Event(
            stoppedUserId: payload['stoppedUserId'] as String,
            stoppedUserName: (payload['stoppedUserName'] as String?) ?? '',
          );
          break;

        case 'emergency:confirm':
          confirmEvent.value = EmergencyConfirmEvent(
            countdownSeconds: (payload['countdown'] as num).toInt(),
          );
          break;

        case 'emergency:resolved':
          resolvedEvent.value = EmergencyResolvedEvent(
            userId: payload['userId'] as String,
          );
          break;

        case 'emergency:full_alert':
          final stoppedAtRaw = payload['stoppedAt'] as String?;
          fullAlertEvent.value = EmergencyFullAlertEvent(
            userId: payload['userId'] as String,
            name: (payload['name'] as String?) ?? '',
            lat: (payload['lat'] as num?)?.toDouble(),
            lng: (payload['lng'] as num?)?.toDouble(),
            stoppedAt: stoppedAtRaw != null ? DateTime.tryParse(stoppedAtRaw) : null,
            elapsedSeconds: (payload['elapsed'] as num?)?.toInt() ?? 0,
            distanceBehindKm: (payload['distanceBehind'] as num?)?.toDouble(),
          );
          break;

        case 'ptt:started':
          pttStartedEvent.value = PttStartedEvent(
            userId: payload['userId'] as String,
          );
          break;

        case 'ptt:ended':
          pttEndedEvent.value = PttEndedEvent(
            userId: payload['userId'] as String,
          );
          break;

        case 'party:ended':
          partyEndedEvent.value = PartyEndedEvent(
            partyId: payload['partyId'] as String,
          );
          break;

        case 'error':
          // Server-side rejection of something we sent (e.g.
          // NOT_PARTY_MEMBER, INVALID_PAYLOAD, NO_PENDING_EMERGENCY for a
          // stray/late emergency:respond) — surface it, don't crash.
          final code = payload['code'] as String? ?? 'ERROR';
          final message = payload['message'] as String? ?? 'Unknown error';
          lastError.value = 'Live location: $code — $message';
          break;

        default:
          // party:* events this screen doesn't need are silently ignored,
          // same "not every message needs a handler" discipline the
          // server's own dispatch.ts uses in reverse.
          break;
      }
    } catch (e) {
      // Malformed/unexpected frame from the server — never let a bad frame
      // take down the whole listener, same discipline agora_ptt_service.dart
      // uses around its own SDK callbacks.
      lastError.value = 'Received a malformed message from the server: $e';
    }
  }

  void _onError(Object error) {
    lastError.value = 'Live location connection error — $error';
    _connected = false;
  }

  void _onDone() {
    // Covers both a clean close and the server's own 4001
    // (unauthorized/expired token) close — either way, sending more
    // location:update frames would silently no-op, so surface it once.
    if (_connected) {
      lastError.value = 'Live location connection closed.';
    }
    _connected = false;
  }

  /// Sends one `location:update { partyId, lat, lng, speed, timestamp }`
  /// frame, per api-design.md / real-time-location.md. A no-op (not a
  /// throw) if not currently connected — the caller's periodic timer
  /// doesn't need to know or care about connection state on every tick,
  /// same "never let a transient failure here crash the screen" posture as
  /// the rest of this service.
  void sendLocationUpdate({
    required String partyId,
    required double lat,
    required double lng,
    required double speedKmph,
    required DateTime timestamp,
  }) {
    final channel = _channel;
    if (!_connected || channel == null) return;

    final message = jsonEncode({
      'type': 'location:update',
      'payload': {
        'partyId': partyId,
        'lat': lat,
        'lng': lng,
        'speed': speedKmph,
        'timestamp': timestamp.toUtc().toIso8601String(),
      },
    });

    try {
      channel.sink.add(message);
    } catch (e) {
      lastError.value = 'Could not send location update — $e';
    }
  }

  /// Sends `emergency:respond { partyId, response: 'fine' | 'help' }`, per
  /// system-overview.md's Event Map (Client -> Server) and
  /// emergency.ts's `handleEmergencyRespond`. Only meaningful when this
  /// device is the stopped rider with a currently-pending server-side
  /// confirmation — the server is the source of truth for who's allowed to
  /// respond (matched against the sender's own `userId`, never trusted
  /// from the payload), so this method doesn't attempt to enforce that
  /// client-side. A response sent with no pending confirmation (e.g. a
  /// stray tap after the window already auto-resolved) is simply rejected
  /// by the server with a typed `NO_PENDING_EMERGENCY` error, surfaced via
  /// [lastError] like any other server-side rejection this service already
  /// forwards — not thrown.
  void sendEmergencyRespond({
    required String partyId,
    required String response,
  }) {
    assert(response == 'fine' || response == 'help');
    final channel = _channel;
    if (!_connected || channel == null) return;

    final message = jsonEncode({
      'type': 'emergency:respond',
      'payload': {
        'partyId': partyId,
        'response': response,
      },
    });

    try {
      channel.sink.add(message);
    } catch (e) {
      lastError.value = 'Could not send emergency response — $e';
    }
  }

  /// Sends `ptt:state { partyId, state: 'start' | 'end' }`, per ptt.ts and
  /// ptt-audio.md's PTT State Machine — called alongside (not instead of)
  /// `AgoraPttService.startTalking()`/`stopTalking()`, since this is purely
  /// the local-audio-cue relay, not the PTT audio path itself (Agora
  /// handles that peer-to-peer regardless of this connection). Same no-op-
  /// if-not-connected, catch-don't-throw discipline as
  /// [sendLocationUpdate]/[sendEmergencyRespond] — a dropped cue relay
  /// frame is not worth crashing the hold-to-talk gesture over.
  void sendPttState({
    required String partyId,
    required String state,
  }) {
    assert(state == 'start' || state == 'end');
    final channel = _channel;
    if (!_connected || channel == null) return;

    final message = jsonEncode({
      'type': 'ptt:state',
      'payload': {
        'partyId': partyId,
        'state': state,
      },
    });

    try {
      channel.sink.add(message);
    } catch (e) {
      lastError.value = 'Could not send PTT state — $e';
    }
  }

  Future<void> dispose() async {
    await _subscription?.cancel();
    try {
      await _channel?.sink.close();
    } catch (_) {
      // Already closed/closing — fine.
    }
    _channel = null;
    _connected = false;
    riderLocations.dispose();
    riderNames.dispose();
    stage1Event.dispose();
    confirmEvent.dispose();
    resolvedEvent.dispose();
    fullAlertEvent.dispose();
    pttStartedEvent.dispose();
    pttEndedEvent.dispose();
    partyEndedEvent.dispose();
    lastError.dispose();
  }
}
