import 'api_client.dart';
import 'auth_service.dart';

class CreatePartyResult {
  final String partyId;
  final String roomCode;
  const CreatePartyResult({required this.partyId, required this.roomCode});
}

class PartyMemberInfo {
  final String userId;
  final String name;
  final bool isHost;
  const PartyMemberInfo({
    required this.userId,
    required this.name,
    required this.isHost,
  });
}

/// `POST /parties/:id/agora-token` response — a channel-scoped, short-lived
/// Agora RTC token, per `technical/architecture/api-design.md`'s `parties`
/// section (added 2026-09-16, see that doc's entry and
/// `agora_ptt_service.dart`'s doc comment for the full story). [channelName]
/// is the party's real room code (server-resolved, not client-supplied) —
/// callers should use this, not any locally-known value, as the Agora
/// `channelId` when joining.
class AgoraTokenResult {
  final String token;
  final String channelName;
  final int uid;
  final DateTime expiresAt;
  const AgoraTokenResult({
    required this.token,
    required this.channelName,
    required this.uid,
    required this.expiresAt,
  });
}

class JoinPartyResult {
  final String partyId;
  final String rideName;
  final String meetPoint;
  final String date;
  final String time;
  final int maxRiders;
  final List<PartyMemberInfo> members;
  const JoinPartyResult({
    required this.partyId,
    required this.rideName,
    required this.meetPoint,
    required this.date,
    required this.time,
    required this.maxRiders,
    required this.members,
  });

  /// Host's display name, per waiting_room_screen.dart's `hostName` field —
  /// falls back to 'the host' (this screen's existing generic-fallback
  /// text) if the organiser's server-side name is empty. See
  /// party_service.dart's file-level note on the empty-name gap.
  String get hostName {
    final host = members.where((m) => m.isHost).toList();
    if (host.isEmpty) return 'the host';
    return host.first.name.isNotEmpty ? host.first.name : 'the host';
  }
}

/// `POST /parties` / `POST /parties/join`, per api-design.md's `parties`
/// section. Both are protected + idempotent (constants/idempotency.ts) —
/// ApiClient.post's `idempotent: true` attaches a fresh Idempotency-Key per
/// call, guarding against a double-tap on "Generate Party Code"/"Join
/// Party" creating two parties or double-joining.
///
/// **Known gap, not fixed here (Flutter-side scope only)**: the backend has
/// no `PUT /users/me` in MVP scope (api-design.md's `users` section — only
/// `GET /users/me` exists) — nothing ever sets a user's server-side `name`,
/// so every `members[].name` this backend returns is `''` today, for every
/// user, always. Screens that display another rider's name (waiting room's
/// host name, live ride's party menu/marker labels) fall back to a generic
/// label when name is empty, same pattern as home_screen.dart's "Rider"
/// greeting fallback — see live_ride_screen.dart and this file's
/// `JoinPartyResult.hostName`. Flagged for the PM/a future backend task,
/// not silently worked around by adding profile-name persistence here.
class PartyService {
  static String _requireToken() {
    final token = AuthSession.accessToken;
    if (token == null) {
      throw StateError(
        'PartyService called before AuthSession has an access token — this '
        'should be unreachable, since every screen that calls this comes '
        'after the phone/OTP flow.',
      );
    }
    return token;
  }

  /// `POST /parties` — matches create_party_screen.dart's existing form
  /// fields 1:1 (api-design.md's file-level note on this).
  static Future<CreatePartyResult> createParty({
    required String rideName,
    required String meetPoint,
    required DateTime date,
    required int hour24,
    required int minute,
    required int maxRiders,
  }) async {
    final dateStr =
        '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    final timeStr =
        '${hour24.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

    final json = await ApiClient.post(
      '/parties',
      {
        'rideName': rideName,
        'meetPoint': meetPoint,
        'date': dateStr,
        'time': timeStr,
        'maxRiders': maxRiders,
      },
      token: _requireToken(),
      idempotent: true,
    );

    return CreatePartyResult(
      partyId: json['partyId'] as String,
      roomCode: json['roomCode'] as String,
    );
  }

  /// `POST /parties/join` — { roomCode } -> full party detail + roster.
  /// Throws [ApiException] with code `PARTY_NOT_FOUND` (404) or
  /// `PARTY_FULL` (409) on the documented failure cases — callers show a
  /// friendly message rather than navigating on failure.
  static Future<JoinPartyResult> joinParty(String roomCode) async {
    final json = await ApiClient.post(
      '/parties/join',
      {'roomCode': roomCode},
      token: _requireToken(),
      idempotent: true,
    );

    final membersJson = json['members'] as List<dynamic>;
    return JoinPartyResult(
      partyId: json['partyId'] as String,
      rideName: json['rideName'] as String,
      meetPoint: json['meetPoint'] as String,
      date: json['date'] as String,
      time: json['time'] as String,
      maxRiders: json['maxRiders'] as int,
      members: membersJson
          .map((m) => PartyMemberInfo(
                userId: m['userId'] as String,
                name: m['name'] as String,
                isHost: m['isHost'] as bool,
              ))
          .toList(),
    );
  }

  /// `GET /parties/:id` — REST backstop for `party_ready_screen.dart`'s
  /// roster-listener race condition (found live 2026-08-17,
  /// process/build-status.md Next Steps item 29): `party:member_joined` is
  /// only ever broadcast once, live, to whoever the server has already
  /// registered in the party's WS room at that instant — a connection whose
  /// handshake hasn't finished yet has no way to replay a missed event.
  /// This asks the backend "what's the real membership right now,"
  /// independent of the WS stream. Same response shape as [joinParty]
  /// (minus `isNewMember`, which only makes sense for that call), so it
  /// reuses [JoinPartyResult] rather than a new model. 403
  /// `NOT_PARTY_MEMBER` if this device's own user somehow isn't a member of
  /// [partyId] (shouldn't happen for a caller who created or joined this
  /// party themselves) — surfaced as a normal [ApiException], not
  /// special-cased.
  static Future<JoinPartyResult> getPartyDetail(String partyId) async {
    final json = await ApiClient.get(
      '/parties/$partyId',
      token: _requireToken(),
    );

    final membersJson = json['members'] as List<dynamic>;
    return JoinPartyResult(
      partyId: json['partyId'] as String,
      rideName: json['rideName'] as String,
      meetPoint: json['meetPoint'] as String,
      date: json['date'] as String,
      time: json['time'] as String,
      maxRiders: json['maxRiders'] as int,
      members: membersJson
          .map((m) => PartyMemberInfo(
                userId: m['userId'] as String,
                name: m['name'] as String,
                isHost: m['isHost'] as bool,
              ))
          .toList(),
    );
  }

  /// `POST /parties/:id/end` — organiser-only (403 otherwise, per
  /// api-design.md; the caller is expected to only expose this to the
  /// organiser in the first place, same as the button that calls it in
  /// `live_ride_screen.dart`). No request body. Response is
  /// `{ ended: true, endedAt }` — not consumed here, since callers only
  /// need to know the call succeeded (they navigate home regardless of the
  /// exact server timestamp).
  ///
  /// This also clears the party's Redis state and every connected member's
  /// in-memory WS room membership server-side (Task 5/9's
  /// `clearEmergencyStateForParty`/`clearPartyOnEnd`), and, as of
  /// 2026-08-17, broadcasts a real `party:ended { partyId }` WS event to
  /// every still-connected party member (including the organiser's own
  /// connection) — see `websocket/broadcast.ts`'s `broadcastPartyEnded` and
  /// `live_ride_screen.dart`'s `_onPartyEnded` for the full closing of the
  /// gap this doc comment used to describe as open
  /// (`process/build-status.md` Next Steps item 30).
  static Future<void> endParty(String partyId) async {
    await ApiClient.post(
      '/parties/$partyId/end',
      const {},
      token: _requireToken(),
    );
  }

  /// `POST /parties/:id/agora-token` — member-only (403 `NOT_PARTY_MEMBER`
  /// otherwise, 404 `PARTY_NOT_FOUND` if the party doesn't exist), 503
  /// `AGORA_NOT_CONFIGURED` if the backend's real Agora App Certificate
  /// isn't set yet — all surfaced as normal [ApiException]s, not
  /// special-cased here. Called by `agora_ptt_service.dart`'s `join()`
  /// before every real channel join; see that file's doc comment for why
  /// this exists (the 2026-09-16 App-Certificate-enabled channel-join
  /// failure) and for how a fetch failure here is surfaced to the rider
  /// (via the same `lastError` pattern that file already uses for "no App
  /// ID configured").
  static Future<AgoraTokenResult> fetchAgoraToken(String partyId) async {
    final json = await ApiClient.post(
      '/parties/$partyId/agora-token',
      const {},
      token: _requireToken(),
    );

    return AgoraTokenResult(
      token: json['token'] as String,
      channelName: json['channelName'] as String,
      uid: json['uid'] as int,
      expiresAt: DateTime.parse(json['expiresAt'] as String),
    );
  }
}
