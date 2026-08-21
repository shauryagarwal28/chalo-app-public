import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import '../config/agora_config.dart';

/// Mirrors the PTT state machine in docs/technical/systems/ptt-audio.md.
enum PttState { idle, transmitting, sendingEnd }

/// Owns the Agora RtcEngine lifecycle for one live-ride PTT channel.
///
/// This is a prototype: it joins the channel muted on [init]/[join] and
/// toggles [startTalking]/[stopTalking] on hold/release. It does not emit
/// ptt:started/ptt:ended events or play beeps — both depend on a WebSocket
/// that doesn't exist yet (see docs/product/features/ptt-radio.md).
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
            lastError.value = 'Agora error: $msg';
          },
          onConnectionStateChanged: (
            RtcConnection connection,
            ConnectionStateType state,
            ConnectionChangedReasonType reason,
          ) {
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

  Future<void> join() async {
    final engine = _engine;
    if (engine == null || !_initialized) return;
    try {
      await engine.joinChannel(
        token: AgoraConfig.tempToken,
        channelId: AgoraConfig.channelName,
        uid: 0,
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
