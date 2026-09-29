// Copy this file to agora_config.dart (gitignored) and fill in real values.
//
// appId: Agora Console > your project > App ID. Not a secret (it ships
// inside the client binary regardless) — restricting a stranger from
// joining a ride's channel is the App Certificate's job, not this value's.
//
// There used to be a `tempToken`/`channelName` pair here too, for a
// Certificate-disabled ("testing mode") Agora project — removed 2026-09-16.
// This project's Agora App Certificate is enabled (the secure,
// production-appropriate setting, kept ON rather than disabled — see
// docs/technical/systems/ptt-audio.md's "channel-join failure root-caused"
// entry for why an empty/static token doesn't work here), so the real,
// per-join, channel-scoped token now comes from the backend
// (`PartyService.fetchAgoraToken`, `POST /parties/:id/agora-token` —
// backend/src/services/agoraToken.ts), never from a client-side constant.
// The backend needs its own copy of the App Certificate (a real secret,
// server-side only — backend/.env.example's `AGORA_APP_CERTIFICATE`), not
// this file.
class AgoraConfig {
  static const String appId = 'YOUR_AGORA_APP_ID';
}
