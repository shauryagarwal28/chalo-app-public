import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import '../config/agora_config.dart';
import 'api_exception.dart';
import 'party_service.dart';

/// Mirrors the PTT state machine in docs/technical/systems/ptt-audio.md.
enum PttState { idle, transmitting, sendingEnd }

/// Owns the Agora RtcEngine lifecycle for one live-ride PTT channel.
///
/// Joins the channel muted on [init]/[join] and toggles
/// [startTalking]/[stopTalking] on hold/release. Does not play audio-cue
/// beeps itself — that's `live_ride_screen.dart`'s job, listening for the
/// real `ptt:started`/`ptt:ended` WebSocket events (a separate relay, see
/// `docs/technical/systems/ptt-audio.md`'s "Audio Cue Playback" section;
/// this class only owns the actual Agora audio channel, still
/// **unvalidated end-to-end** — see that doc's status line).
class AgoraPttService {
  RtcEngine? _engine;
  bool _initialized = false;

  final ValueNotifier<PttState> state = ValueNotifier(PttState.idle);
  final ValueNotifier<String?> lastError = ValueNotifier(null);

  Future<bool> requestMicPermission() async {
    final status = await Permission.microphone.request();
    return status.isGranted;
  }

  /// Sets up the engine. Safe to call even without a real App ID configured
  /// yet — failures are caught and surfaced via [lastError] rather than
  /// thrown, since this is expected before an Agora account exists (see
  /// docs/process/build-status.md).
  Future<void> init() async {
    if (AgoraConfig.appId.isEmpty) {
      lastError.value = 'No Agora App ID configured yet — see lib/config/agora_config.example.dart';
      return;
    }

    // PTT is unvalidated everywhere in this app (see
    // docs/technical/decisions/ptt-sdk-choice.md — no real highway test has
    // happened even on iOS/Android). The web platform is a further step
    // down: agora_rtc_engine's web implementation needs its own Agora Web
    // SDK <script> tag wired into web/index.html (same shape of problem as
    // Google Maps' JS API key), which this app deliberately does not do —
    // adding it would let PTT silently "half-work" in the browser and
    // misrepresent an unvalidated feature as further along than it is.
    // Without that script, engine.initialize() throws a raw
    // "Null check operator used on a null value" from the plugin's JS
    // interop — technically caught by the try/catch below either way (so
    // this guard isn't needed to prevent a crash), but this early, explicit
    // check gives a clear, honest message instead of a confusing runtime
    // error string, matching the empty-appId guard above.
    if (kIsWeb) {
      lastError.value = 'PTT voice chat isn\'t available in this web preview — try the iOS or Android app.';
      return;
    }

    final engine = createAgoraRtcEngine();
    _engine = engine;

    try {
      await engine.initialize(
        const RtcEngineContext(
          appId: AgoraConfig.appId,
          channelProfile: ChannelProfileType.channelProfileCommunication,
        ),
      );

      engine.registerEventHandler(
        RtcEngineEventHandler(
          onJoinChannelSuccess: (RtcConnection connection, int elapsed) {
            debugPrint(
              'Agora: joined channel ${connection.channelId} as uid ${connection.localUid}',
            );
          },
          onError: (ErrorCodeType err, String msg) {
            debugPrint('Agora: onError $err ($msg)');
            lastError.value = 'Agora error: $msg';
          },
          onConnectionStateChanged: (
            RtcConnection connection,
            ConnectionStateType state,
            ConnectionChangedReasonType reason,
          ) {
            debugPrint('Agora: connection state -> $state (reason: $reason)');
            if (state == ConnectionStateType.connectionStateFailed) {
              lastError.value = 'Lost connection to the PTT channel';
            }
          },
          onLeaveChannel: (RtcConnection connection, RtcStats stats) {
            debugPrint('Agora: left channel ${connection.channelId}');
          },
        ),
      );

      await engine.enableAudio();
      await engine.muteLocalAudioStream(true);
      _initialized = true;
    } catch (e) {
      lastError.value = 'Could not initialize PTT audio: $e';
    }
  }

  /// Joins the real party's PTT channel. [partyId] is the party's real,
  /// stable identifier (`live_ride_screen.dart`'s `widget.partyId`) — used
  /// to fetch a channel-scoped Agora token from the backend
  /// (`PartyService.fetchAgoraToken`, `POST /parties/:id/agora-token`)
  /// before ever calling `joinChannel`.
  ///
  /// **Why this fetches a token at all**: found live 2026-09-16 (see
  /// `docs/technical/systems/ptt-audio.md`'s "channel-join failure
  /// root-caused" entry) — this Agora project has App Certificate enabled,
  /// so the empty-string token this method used to send
  /// (`AgoraConfig.tempToken`) was rejected outright by Agora's own servers
  /// (`errInvalidToken`, 110). **User decision**: keep App Certificate ON
  /// (the secure, production-appropriate setting — an open channel would let
  /// anyone holding this app's App ID, which is not really secret, listen
  /// into any ride's live PTT audio) rather than disable it, which means a
  /// real signed token is now required for every join, minted server-side
  /// per `services/agoraToken.ts`'s design (channel name = the party's real
  /// room code, uid = 0, a few hours' expiry).
  ///
  /// The returned `channelName` (the party's real room code, resolved
  /// server-side from [partyId] — never client-supplied) is used as the
  /// Agora `channelId` here, replacing the old hardcoded
  /// `AgoraConfig.channelName` mock-party-code constant.
  ///
  /// A token-fetch failure (network down, this rider genuinely isn't a
  /// member of the party, the backend's Agora App Certificate isn't
  /// configured yet) is caught and surfaced via [lastError] — same "don't
  /// crash, tell the rider" pattern as every other failure path in this
  /// class — rather than ever calling `joinChannel` with a missing/garbage
  /// token.
  Future<void> join(String partyId) async {
    final engine = _engine;
    if (engine == null || !_initialized) return;

    final AgoraTokenResult tokenResult;
    try {
      tokenResult = await PartyService.fetchAgoraToken(partyId);
    } on ApiException catch (e) {
      lastError.value = 'Could not get permission to join the PTT channel: ${e.message}';
      return;
    } catch (e) {
      lastError.value = 'Could not get permission to join the PTT channel: $e';
      return;
    }

    try {
      await engine.joinChannel(
        token: tokenResult.token,
        channelId: tokenResult.channelName,
        uid: tokenResult.uid,
        options: const ChannelMediaOptions(
          clientRoleType: ClientRoleType.clientRoleBroadcaster,
          channelProfile: ChannelProfileType.channelProfileCommunication,
          autoSubscribeAudio: true,
          publishMicrophoneTrack: true,
        ),
      );
    } catch (e) {
      lastError.value = 'Could not join PTT channel: $e';
    }
  }

  Future<void> startTalking() async {
    final engine = _engine;
    if (engine == null || !_initialized) return;
    await engine.muteLocalAudioStream(false);
    state.value = PttState.transmitting;
  }

  Future<void> stopTalking() async {
    final engine = _engine;
    if (engine == null || !_initialized) return;
    await engine.muteLocalAudioStream(true);
    state.value = PttState.idle;
  }

  Future<void> dispose() async {
    if (_initialized) {
      await _engine?.leaveChannel();
      await _engine?.release();
    }
    _engine = null;
    _initialized = false;
    state.dispose();
    lastError.dispose();
  }
}
