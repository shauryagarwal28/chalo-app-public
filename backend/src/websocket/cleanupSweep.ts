import { redisClient } from '../lib/redis';
import {
  CLEANUP_SWEEP_INTERVAL_MS,
  CLEANUP_SWEEP_PARTY_WARNING_THRESHOLD,
} from '../constants/cleanupSweep';

/**
 * Periodic Redis `party:*` key-set sanity sweep, per
 * docs/technical/architecture/backend-mvp-plan.md Task 9: "Add a periodic
 * Redis TTL sanity sweep (e.g. an interval that logs/alerts if any
 * `party:*` key set has grown unboundedly — a stuck party that never gets
 * cleaned up would slowly leak memory in a single-process MVP deployment)."
 *
 * **Observability only, per the plan's own framing** ("logs/alerts", not
 * "deletes"/"fixes") — this module never mutates Redis. It exists to give a
 * human running `redis-cli`/reading logs a signal that something has drifted
 * (an abandoned party nobody ever called `/end` on, or a structurally
 * inconsistent key set), not to auto-remediate it — auto-deleting a party's
 * keys based on a heuristic risks destroying a real, still-in-progress ride's
 * state on a false positive, which is a much worse failure mode than a
 * human occasionally needing to investigate a warning log.
 *
 * Two checks, both directly from the plan doc's own example:
 *  1. **Structural inconsistency**: a `party:{id}:members` hash with no
 *     matching `party:{id}:state` key, or vice versa — per
 *     `services/party.ts`'s doc comment, every party write path
 *     (`createParty`/`joinParty`) writes both keys, and `endParty`'s
 *     wildcard delete removes every `party:{id}:*` key together, so in
 *     steady state these two should always co-exist or both be gone. A
 *     mismatch is a real signal worth a human's attention (e.g. a partial
 *     write, or a bug in the wildcard-delete path), not expected/benign
 *     churn.
 *  2. **Unbounded growth**: the total number of distinct party IDs
 *     represented among any `party:*` key crossing
 *     CLEANUP_SWEEP_PARTY_WARNING_THRESHOLD — a proxy for "parties aren't
 *     being cleaned up via their normal /end lifecycle."
 *
 * **Known, deliberately out-of-scope residual gap** (flagged, not fixed,
 * per this task's own scope — see build-status.md's Task 9 write-up):
 * `services/party.ts`'s `endParty()` does a `KEYS 'party:{id}:*'` scan
 * followed by a separate `DEL` of exactly the keys that scan returned — not
 * atomic. A `location:update` (or, pre-this-task's-fix, an emergency
 * confirmation resolving) landing between the scan and the delete could
 * write a new `party:{id}:location:{userId}` (or similar) key that the
 * `DEL` call never enumerated, orphaning it until its own TTL expires (30s
 * for location, harmless) — but a party's `:state`/`:members` keys have no
 * TTL at all, so if either of *those* specifically were ever recreated in
 * that same narrow race (not currently possible — nothing writes `:state`/
 * `:members` after `/end` in the current codebase), it would persist
 * indefinitely. This sweep's structural-inconsistency check (1 above) would
 * surface exactly that shape of orphan if it ever happened, which is why
 * it's a useful check to have even though this specific race isn't
 * separately fixed here — fixing the race itself (e.g. a Lua script /
 * `WATCH`-based transaction for the scan+delete) is a bigger structural
 * change than this hardening pass's scope, and no live evidence of it
 * actually happening was found during this task's verification.
 */

const PARTY_STATE_SUFFIX = ':state';
const PARTY_MEMBERS_SUFFIX = ':members';

export interface CleanupSweepResult {
  totalPartyKeys: number;
  partyCount: number;
  orphanedStateKeys: string[]; // :state with no matching :members
  orphanedMembersKeys: string[]; // :members with no matching :state
}

/**
 * partyId is always a UUID (hyphens, no colons — see services/party.ts's
 * findPartyIdByRoomCode comment for the same assumption), so splitting a
 * `party:{partyId}:{suffix...}` key on ':' and taking index 1 is safe.
 */
function partyIdFromKey(key: string): string | null {
  return key.split(':')[1] ?? null;
}

/** Runs one sweep pass and returns what it found — exported separately from
 * the interval wiring so a verification script (or a future health-check
 * endpoint) can trigger a pass on demand without waiting for the interval.
 */
export async function runCleanupSweep(): Promise<CleanupSweepResult> {
  // Same KEYS-based "fine at MVP scale" pattern already used elsewhere in
  // this codebase (services/party.ts's findPartyIdByRoomCode/
  // findActivePartyIdForUser, services/party.ts's endParty) — not a new
  // scanning strategy invented for this task.
  const allKeys = await redisClient.keys('party:*');

  const partyIds = new Set<string>();
  const withState = new Set<string>();
  const withMembers = new Set<string>();

  for (const key of allKeys) {
    const partyId = partyIdFromKey(key);
    if (!partyId) continue;
    partyIds.add(partyId);
    if (key.endsWith(PARTY_STATE_SUFFIX)) withState.add(partyId);
    if (key.endsWith(PARTY_MEMBERS_SUFFIX)) withMembers.add(partyId);
  }

  const orphanedStateKeys: string[] = [];
  const orphanedMembersKeys: string[] = [];

  for (const partyId of partyIds) {
    const hasState = withState.has(partyId);
    const hasMembers = withMembers.has(partyId);
    if (hasState && !hasMembers) orphanedStateKeys.push(`party:${partyId}:state`);
    if (hasMembers && !hasState) orphanedMembersKeys.push(`party:${partyId}:members`);
  }

  const result: CleanupSweepResult = {
    totalPartyKeys: allKeys.length,
    partyCount: partyIds.size,
    orphanedStateKeys,
    orphanedMembersKeys,
  };

  if (orphanedStateKeys.length > 0 || orphanedMembersKeys.length > 0) {
    // eslint-disable-next-line no-console
    console.warn('[cleanup-sweep] inconsistent party:* key set(s) found', {
      orphanedStateKeys,
      orphanedMembersKeys,
    });
  }

  if (partyIds.size >= CLEANUP_SWEEP_PARTY_WARNING_THRESHOLD) {
    // eslint-disable-next-line no-console
    console.warn(
      '[cleanup-sweep] party:* key set has grown unboundedly — parties may not be getting cleaned up via /end',
      { partyCount: partyIds.size, totalPartyKeys: allKeys.length },
    );
  }

  return result;
}

let sweepTimer: ReturnType<typeof setInterval> | null = null;

/** Idempotent — calling this more than once (e.g. a future hot-reload) doesn't start a second interval. */
export function startCleanupSweep(): void {
  if (sweepTimer) return;
  sweepTimer = setInterval(() => {
    runCleanupSweep().catch((err: unknown) => {
      // A sweep failure (e.g. a transient Redis blip) must never crash the
      // process — same "never let a background task take the server down"
      // discipline as every other setTimeout/setInterval callback in this
      // codebase (partyPresence.ts's grace-period timer, emergency.ts's
      // confirmation timer).
      // eslint-disable-next-line no-console
      console.error('[cleanup-sweep] sweep failed', err);
    });
  }, CLEANUP_SWEEP_INTERVAL_MS);
  // Don't let this interval alone keep the Node process alive — matches
  // the "not load-bearing for correctness, just don't block shutdown"
  // discipline used by every other timer in this codebase.
  sweepTimer.unref?.();
}

/** Exposed for tests/graceful-shutdown use — not currently called from src/index.ts, which has no shutdown handler yet. */
export function stopCleanupSweep(): void {
  if (sweepTimer) {
    clearInterval(sweepTimer);
    sweepTimer = null;
  }
}
