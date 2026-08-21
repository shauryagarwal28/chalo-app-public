import { redisClient } from '../lib/redis';
import { PTT_TTL_SECONDS } from '../constants/ptt';

/**
 * PTT channel-state cache, per docs/technical/architecture/backend-mvp-plan.md
 * Task 8 and docs/technical/architecture/data-models.md's Redis key
 * structure:
 *
 *   party:{partyId}:ptt → { speakerId, startedAt }  TTL: 60s
 *
 * Passive record only, per Task 8's own framing ("mainly for a possible
 * future 'who's currently speaking' UI indicator, not required for MVP
 * function") — nothing in this backend reads this key back to drive
 * behavior, same "write for observability, never read back" pattern as
 * services/emergency.ts's party:{partyId}:emergency:{userId} record.
 *
 * Written/cleared from websocket/ptt.ts's ptt:state handler. Also deleted
 * automatically, if the party ends first, by services/party.ts's endParty()
 * wildcard `party:{id}:*` delete (Task 4, unchanged by this task) — matches
 * real-time-location.md's Privacy Guarantee #4 pattern ("Redis cache is
 * deleted when the party ends"), which this key falls under too even though
 * it's not GPS location data.
 */

function pttKey(partyId: string): string {
  return `party:${partyId}:ptt`;
}

/**
 * Called on ptt:state: 'start'. Writes the current speaker + start time,
 * TTL 60s, matching data-models.md's documented shape exactly. `hSet` +
 * `expire` run as one Redis pipeline (`multi()...exec()`), same "don't leave
 * a written key with no TTL if the two calls somehow got split" discipline
 * as services/location.ts's `cacheLocation`.
 */
export async function writePttState(partyId: string, speakerId: string): Promise<void> {
  const key = pttKey(partyId);
  await redisClient
    .multi()
    .hSet(key, { speakerId, startedAt: new Date().toISOString() })
    .expire(key, PTT_TTL_SECONDS)
    .exec();
}

/**
 * Called on ptt:state: 'end'. Proactively deletes the key rather than
 * leaving it to the 60s TTL to lapse — see websocket/ptt.ts's top-of-file
 * note for the full reasoning (not silently picked either way): this key's
 * whole purpose is a "who's currently speaking right now" snapshot, and once
 * the speaker has explicitly ended their transmission there IS no current
 * speaker — leaving the key to expire naturally would mean up to 60s of a
 * stale "still speaking" read for anything that later consumes this key
 * (the "future who's-speaking indicator" data-models.md flags), which
 * defeats the point of the field existing at all. A missing key on delete
 * (already expired, or `end` sent without a preceding `start`) is a no-op,
 * not an error — `DEL` on a non-existent key is always safe.
 */
export async function clearPttState(partyId: string): Promise<void> {
  await redisClient.del(pttKey(partyId));
}
