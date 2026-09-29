import { RtcTokenBuilder, RtcRole } from 'agora-token';
import { ApiError } from '../errors/ApiError';
import { env } from '../config/env';
import { AGORA_TOKEN_EXPIRY_SECONDS } from '../constants/ptt';

/**
 * Agora RTC channel-join token generation, added 2026-09-16 — new scope,
 * not part of the original backend-mvp-plan.md Task list (that plan's
 * explicit stance, §1, is that PTT *audio* is Agora's problem, never this
 * backend's — see that file's exclusion note). This is the one narrow
 * exception: minting the *token* Agora's own client SDK needs to join a
 * channel, which has to happen server-side because the secret it's signed
 * with (the Agora App Certificate) can never ship in the client.
 *
 * **Why this exists at all**: `docs/technical/systems/ptt-audio.md`'s
 * 2026-09-16 "Android PTT/Agora channel-join failure root-caused" entry —
 * this Agora project has App Certificate enabled in the Agora Console, so
 * `agora_ptt_service.dart`'s old empty-string token (`AgoraConfig.tempToken`)
 * was rejected outright with Agora's own `errInvalidToken` (110) /
 * `connectionChangedInvalidToken` (8). Two fixes existed: disable App
 * Certificate (fast, but leaves every ride's PTT channel joinable by anyone
 * holding the App ID — not really secret, ships in the client binary), or
 * keep it on and mint a real signed token per join, scoped to the caller's
 * actual party. **The user decided to keep App Certificate ON** — this file
 * is the "mint a real token" half of that decision; `routes/parties.ts`'s
 * `POST /parties/:id/agora-token` is the other half.
 *
 * **What the token is scoped to — channel name**: the party's `roomCode`
 * (e.g. `"RD7K2X"`), NOT `partyId`. This matches, exactly, what
 * `agora_ptt_service.dart`/`agora_config.dart` already treat as the Agora
 * channel name (`AgoraConfig.channelName`, a hardcoded room-code-shaped
 * constant, per that file's own comment: "must match party_ready_screen.dart's
 * mock party code") — reusing that identifier rather than introducing a
 * second one (e.g. `partyId`) for the same channel. The caller's party
 * membership is still checked against `partyId` (the real, stable identifier
 * — room codes are meant to be shared/typed by humans and aren't guaranteed
 * unique forever, per `services/party.ts`'s room-code generation), and the
 * server — not the client — looks up that party's `roomCode` to build the
 * token, so a caller can't request a token for an arbitrary channel name by
 * just passing one in.
 *
 * **What uid the token is scoped to**: 0 (Agora's documented "wildcard uid"
 * convention — a token minted for uid 0 can be presented by a join call
 * using any uid, not just uid 0 literally, but this app's join call always
 * literally passes `uid: 0` — see `agora_ptt_service.dart`'s `join()`).
 * This app has no concept of a stable per-rider *numeric* Agora uid (Chalo's
 * own userId is a UUID string, not a uint32) — inventing one would be new,
 * unscoped work, and Agora's own wildcard-uid mechanism exists precisely for
 * clients like this that don't need per-uid binding. The token is still
 * fully channel-scoped (a token minted for room code A cannot join room code
 * B), which is the actual security property this task needs — per-ride
 * isolation from strangers, not per-rider isolation from other verified
 * members of the same ride. **Known tradeoff, not swept under the rug**:
 * Agora's own guidance for wildcard-uid tokens is to prefer a
 * subscriber/audience role to limit blast radius if the token leaks: this
 * app instead grants `RtcRole.PUBLISHER` (every rider can transmit, which is
 * the whole point of PTT), matching the client's existing
 * `clientRoleType: ClientRoleType.clientRoleBroadcaster` in `join()`. A
 * leaked token is still bounded by party membership (only ever issued to a
 * confirmed member) and by its expiry (see below), not by uid-role
 * narrowing.
 *
 * **Expiry**: `AGORA_TOKEN_EXPIRY_SECONDS`, default 4 hours (14400s) — see
 * `constants/ptt.ts`. The Flutter client fetches this token once, when
 * `LiveRideScreen` mounts (`agora_ptt_service.dart`'s `init()`/`join()`
 * sequence) — there is no token-refresh-mid-ride flow built. The token must
 * therefore outlive the whole ride, not just Agora's own 3600s sample
 * default from their docs. `ptt-audio.md`'s highway-test pass criteria call
 * for a minimum 2-hour continuous run; real group rides
 * (`product/features/active-ride-mode.md`) can run longer than that. 4 hours
 * gives real headroom over the 2-hour minimum without leaving a
 * leaked/logged token exploitable for an unreasonable stretch. Both
 * `tokenExpire` and `privilegeExpire` (Agora's two independent expiry knobs
 * — see `RtcTokenBuilder.buildTokenWithUid`'s own doc comment in
 * `node_modules/agora-token/index.d.ts`) are set to the same value; this app
 * has no use for a token that outlives its own privileges.
 */

/** True once both real Agora config values this endpoint needs are present. */
export function isAgoraTokenGenerationConfigured(): boolean {
  return env.AGORA_APP_ID.length > 0 && env.AGORA_APP_CERTIFICATE.length > 0;
}

export interface PttTokenResult {
  token: string;
  channelName: string;
  uid: number;
  expiresAt: string; // ISO8601
}

/**
 * Mints a channel-scoped Agora RTC token for [channelName] (expected to be
 * the caller's party's `roomCode` — callers, i.e. `routes/parties.ts`, are
 * responsible for resolving that from a real party membership check before
 * calling this; this function itself does no membership check, matching
 * `services/token.ts`'s split of concerns between the route/service
 * membership logic and the pure token-signing logic).
 *
 * Throws `ApiError(503, 'AGORA_NOT_CONFIGURED', ...)` — not a raw exception,
 * and not a silent empty token — if `AGORA_APP_CERTIFICATE` isn't set yet.
 * This is the expected, honest state until the user's real Agora Console
 * value lands; see `config/env.ts`'s startup warning for the same gap
 * surfaced at boot.
 */
export function generatePttToken(channelName: string): PttTokenResult {
  if (!isAgoraTokenGenerationConfigured()) {
    throw new ApiError(
      503,
      'AGORA_NOT_CONFIGURED',
      'PTT voice channel tokens are not available yet — the server is missing its real Agora App Certificate.',
    );
  }

  const uid = 0;
  const token = RtcTokenBuilder.buildTokenWithUid(
    env.AGORA_APP_ID,
    env.AGORA_APP_CERTIFICATE,
    channelName,
    uid,
    RtcRole.PUBLISHER,
    AGORA_TOKEN_EXPIRY_SECONDS,
    AGORA_TOKEN_EXPIRY_SECONDS,
  );

  const expiresAt = new Date(Date.now() + AGORA_TOKEN_EXPIRY_SECONDS * 1000).toISOString();

  return { token, channelName, uid, expiresAt };
}
