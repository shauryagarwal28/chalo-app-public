import { broadcastToParty } from './broadcast';
import { handlers, sendError } from './dispatch';
import { isMemberOfParty } from './location';
import { writePttState, clearPttState } from '../services/ptt';
import type { WsContext } from './types';

/**
 * ptt:state (Client -> Server) / ptt:started, ptt:ended (Server -> Client),
 * per docs/technical/architecture/backend-mvp-plan.md Task 8,
 * docs/technical/systems/ptt-audio.md's "Audio Cue Playback" section, and
 * docs/technical/architecture/system-overview.md's WebSocket Event Map
 * (`ptt:state` row, previously marked "if server-relayed" — this task is
 * what makes it "if").
 *
 *   ptt:state   { partyId, state: 'start' | 'end' }  (in)
 *   ptt:started { userId }                            (out, all other party
 *   ptt:ended   { userId }                             members, per Task 8's
 *                                                       "Done means")
 *
 * This is purely a relay for the local audio-cue beeps described in
 * ptt-audio.md's "Audio Cue Playback" section — NOT the actual PTT audio,
 * which Agora handles peer-to-peer whether or not this handler exists (see
 * backend-mvp-plan.md §1's explicit "PTT audio itself" exclusion).
 *
 * Deliberately a near-exact structural mirror of websocket/location.ts's
 * `location:update` handler, per Task 8's own "if you find yourself
 * inventing a new pattern, stop and check whether Task 6's location handler
 * already solved the same problem" instruction: validate payload -> check
 * party membership (via location.ts's exported `isMemberOfParty`, reused
 * as-is rather than duplicated — see that function's own doc comment) ->
 * act (write/clear the passive Redis record) -> broadcast to the rest of
 * the party, excluding the sender.
 *
 * **`end`'s Redis-key handling — a real ambiguity, resolved and stated
 * here, not silently picked**: on `ptt:state: 'end'`, this handler
 * proactively `DEL`s `party:{partyId}:ptt` rather than leaving it to its
 * own 60s TTL. Reasoning: the key represents "who is currently speaking"
 * (data-models.md's shape, `{ speakerId, startedAt }`) for a possible
 * future speaking-indicator UI — once the speaker has explicitly ended
 * their transmission, there genuinely is no current speaker, so leaving a
 * stale `speakerId` readable for up to 60 more seconds would be actively
 * wrong for that future consumer, not just imprecise. See
 * services/ptt.ts's `clearPttState` for the same reasoning inline at the
 * write site.
 */

interface PttStatePayload {
  partyId: string;
  state: 'start' | 'end';
}

// Mirrors location.ts's isValidPayload discipline (Task 6's own lesson,
// called out explicitly in this task's brief): validate `state` is exactly
// one of the two allowed literal strings, not just "is a string" — a typo'd
// or malicious `state` value gets a typed rejection here, not silently
// treated as one of the two real states or forwarded as-is.
function isValidPayload(payload: unknown): payload is PttStatePayload {
  if (typeof payload !== 'object' || payload === null) return false;
  const p = payload as Record<string, unknown>;
  return (
    typeof p.partyId === 'string' &&
    p.partyId.trim().length > 0 &&
    (p.state === 'start' || p.state === 'end')
  );
}

export async function handlePttState(ctx: WsContext, rawPayload: unknown): Promise<void> {
  if (!isValidPayload(rawPayload)) {
    sendError(
      ctx,
      'INVALID_PAYLOAD',
      'ptt:state payload must be { partyId: string, state: "start" | "end" }.',
    );
    return;
  }

  const { partyId, state } = rawPayload;

  // Same membership discipline as location:update — a real, typed
  // rejection for a non-member (or someone who's left), not a silent drop.
  if (!(await isMemberOfParty(ctx, partyId))) {
    sendError(ctx, 'NOT_PARTY_MEMBER', 'You are not a member of this party.');
    return;
  }

  if (state === 'start') {
    await writePttState(partyId, ctx.userId);
    broadcastToParty(
      partyId,
      { type: 'ptt:started', payload: { userId: ctx.userId } },
      ctx.userId, // don't echo back to the sender — they already know they started
    );
  } else {
    await clearPttState(partyId);
    broadcastToParty(
      partyId,
      { type: 'ptt:ended', payload: { userId: ctx.userId } },
      ctx.userId,
    );
  }
}

/** Called once from websocket/server.ts to plug this task's handler into
 * Task 3's dispatch map — same explicit-registration pattern as
 * registerLocationHandlers (websocket/location.ts) and
 * registerEmergencyHandlers (websocket/emergency.ts).
 */
export function registerPttHandlers(): void {
  handlers['ptt:state'] = handlePttState;
}
