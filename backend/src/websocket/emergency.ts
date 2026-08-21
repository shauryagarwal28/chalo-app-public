import { partyRooms } from './registry';
import { broadcastToParty, sendToUser } from './broadcast';
import { handlers, sendError } from './dispatch';
import * as partyService from '../services/party';
import * as locationService from '../services/location';
import * as emergencyService from '../services/emergency';
import { dispatchEmergencyPush } from '../services/fcm';
import {
  UPPER_SPEED_KMPH,
  LOWER_SPEED_KMPH,
  DETECTION_WINDOW_MS,
  CONFIRMATION_WINDOW_MS,
  CONFIRMATION_WINDOW_SECONDS,
  ROLLING_READINGS,
  OTHER_MEMBER_STALE_MS,
} from '../constants/emergency';
import type { WsContext } from './types';

/**
 * Emergency detection engine, per docs/technical/architecture/
 * backend-mvp-plan.md Task 7 and docs/technical/systems/
 * emergency-detection.md's algorithm (source of truth for the algorithm
 * itself — implemented as specified there, not redesigned here). Consumes
 * the same `location:update` stream Task 6's relay already handles — see
 * websocket/location.ts's `processEmergencyLocationUpdate` call site, added
 * alongside (not replacing) the existing cache+broadcast — and adds two new
 * WS events to the dispatch map: `emergency:respond` (in) alongside
 * `emergency:stage1`/`emergency:confirm`/`emergency:resolved`/
 * `emergency:full_alert` (out, per system-overview.md's Event Map).
 *
 * ---
 *
 * **Three open engineering questions from emergency-detection.md, resolved
 * per backend-mvp-plan.md Task 7's explicit defaults** (not re-derived here,
 * just implemented):
 *
 * 1. **Rolling-window storage**: in-memory per-process, `Map<userId, ...>`
 *    (`rollingState` below) — not Redis. A process restart silently drops
 *    all in-flight rolling windows; acceptable for MVP's single-process
 *    scope, per the plan doc.
 * 2. **60s confirmation timer**: a plain in-memory `setTimeout`
 *    (`pendingConfirmations` below), not a Redis-TTL-expiry hook. The
 *    `party:{P}:emergency:{R}` Redis key (services/emergency.ts) is written
 *    as a passive debugging record only — never read back to drive
 *    behavior.
 * 3. **Disconnection during the confirmation window is intentionally
 *    fail-safe** — confirmed by the user 2026-07-14 (backend-mvp-plan.md
 *    §6 item 4): a dead WS connection produces the same automatic
 *    `emergency:full_alert` as genuine 60s silence — same *outcome*, after
 *    the same *window*. **Task 9 audit fix (2026-07-19)**: the original
 *    implementation fired the alert the instant the WS closed, not after the
 *    window elapsed — a real bug that defeated reconnect entirely for this
 *    engine (a momentary drop = instant full alert, no chance to reconnect
 *    and tap "I Am Fine"). Fixed so the existing 60s timer is the only thing
 *    that ever resolves a disconnected/silent rider — see
 *    `handleEmergencyDisconnect` below for the full before/after reasoning,
 *    and `websocket/server.ts`'s `close` handler, which calls it.
 *
 * ---
 *
 * **Real ambiguities resolved here, flagged rather than silently picked**
 * (none of these are settled by any doc read for this task — see
 * build-status.md's Task 7 write-up for the full reasoning, this is a
 * summary):
 *
 * - **No doc defines the Client -> Server WS event/shape for "I Am Fine" /
 *   "I Need Help"** (emergency-detection.md describes the *behavior* only;
 *   system-overview.md's Event Map has no Client -> Server emergency-response
 *   row at all). Defined here as `emergency:respond { partyId, response:
 *   'fine' | 'help' }`, sent only by the stopped rider (matched against
 *   their own pending confirmation, not payload-trusted) — added to
 *   system-overview.md's Event Map as part of this task, not left
 *   undocumented.
 * - **Exact sampling semantics for "speed was >20 kmph at the start of a 5s
 *   window"** are underspecified for discrete ~3s-interval GPS readings
 *   (there's no reading that lands exactly 5s in the past). Implemented as:
 *   the rider's smoothed rolling speed is now below LOWER_SPEED_KMPH, AND at
 *   least one smoothed reading within the trailing DETECTION_WINDOW_MS was
 *   above UPPER_SPEED_KMPH. See `hasRecentDropTrigger` below.
 * - **"At least one other member ... at the same timestamp"** — implemented
 *   as: any other party member (per `partyRooms`, the same recipient-set
 *   source of truth `broadcastToParty` already uses) whose own most recent
 *   rolling-speed sample is both above UPPER_SPEED_KMPH and no older than
 *   OTHER_MEMBER_STALE_MS (derived from DETECTION_WINDOW_MS — see
 *   constants/emergency.ts). A member who's gone quiet (disconnected, GPS
 *   dead zone) stops counting as "still moving" after that window, rather
 *   than being treated as permanently moving from their last good reading.
 * - **`emergency:full_alert`'s `distanceBehind` field** (system-overview.md
 *   lists it in the payload shape but no doc says how to compute it — there
 *   is no "front of the group" concept anywhere in this codebase).
 *   Implemented as an MVP-scoped approximation: straight-line (haversine)
 *   distance in km from the stopped rider's last cached location
 *   (`services/location.ts`) to the *nearest* other party member's last
 *   cached location, rounded to 1 decimal place. Not distance along the
 *   planned route (no route-matching exists in this codebase), and `null`
 *   if no other member has a cached location to compare against.
 * - **`emergency:resolved` / `emergency:full_alert` recipient set**:
 *   emergency-detection.md/system-overview.md say "to P" / "to all members
 *   of P" for these two (unlike `emergency:stage1`'s explicit "except R").
 *   Implemented as broadcast to every party member with NO exclusion,
 *   including the stopped rider R themselves — read literally, since these
 *   two are explicitly not qualified with "except R" the way stage1 is.
 *
 * ---
 *
 * **A correctness fix made proactively (reasoned through during
 * implementation, then live-verified — not found via a bug report)**: on any
 * resolution (fine / help / auto-timeout / disconnect), this rider's rolling
 * state (`rollingState.delete(userId)`) is cleared entirely, not just the
 * pending-confirmation entry. Without this, a rider who resolves "I Am Fine"
 * while still genuinely stationary (e.g. pulled over to take a call) would
 * have their very next `location:update` immediately re-trigger Stage 1
 * again — the smoothed-history buffer would still contain the pre-stop >20
 * kmph reading inside the trailing detection window, and nothing about
 * resolving the *confirmation* clears that history. Clearing rolling state
 * on resolution means the next trigger evaluation starts cold and needs a
 * fresh, genuine drop to fire again. See build-status.md's Task 7
 * verification write-up for the live repro of this before the fix.
 */

interface RawReading {
  speed: number;
  timestamp: number;
}

interface SmoothedPoint {
  avg: number;
  timestamp: number;
}

interface UserRollingState {
  raw: RawReading[];
  // Pruned to roughly the trailing 2x DETECTION_WINDOW_MS on every update —
  // see recordReading below. Bounded so a long-running rider's history can't
  // grow unboundedly for the life of the process.
  history: SmoothedPoint[];
}

// In-memory per-process rolling-window store, per backend-mvp-plan.md Task
// 7's explicit "Map<userId, ...>, not Redis" decision. Deliberately keyed by
// userId only (not partyId+userId) — a user is expected to be in at most one
// active party at a time in MVP (same assumption services/party.ts's
// findActivePartyIdForUser already makes), and this avoids a second
// composite-key scheme.
const rollingState = new Map<string, UserRollingState>();

interface PendingConfirmation {
  partyId: string;
  timeout: ReturnType<typeof setTimeout>;
  triggeredAtMs: number;
  // Task 9 audit fix (2026-07-19) — see handleEmergencyDisconnect's doc
  // comment below for the bug this closes. Set (not resolved) the moment
  // this rider's WS connection drops while this confirmation is pending;
  // read only by the setTimeout callback below to decide whether the
  // eventual auto-fired full_alert should be logged as 'auto_timeout' or
  // 'disconnect' in the passive Redis record. Never used to change *timing*.
  disconnectedAt?: number;
}

// userId -> the one active Stage 2 confirmation window for that rider, if
// any. Presence in this map is also what suppresses re-evaluating a new
// trigger for the same rider while one is already pending (see
// processEmergencyLocationUpdate below).
const pendingConfirmations = new Map<string, PendingConfirmation>();

// Exposed for the verification/test scripts only (mirrors partyPresence.ts's
// hasPendingRemoval, same "expose the minimum needed to assert on internal
// state without reaching into module internals another way" rationale).
export function hasPendingConfirmation(userId: string): boolean {
  return pendingConfirmations.has(userId);
}

function recordReading(userId: string, speed: number, now: number): number {
  let state = rollingState.get(userId);
  if (!state) {
    state = { raw: [], history: [] };
    rollingState.set(userId, state);
  }

  state.raw.push({ speed, timestamp: now });
  if (state.raw.length > ROLLING_READINGS) {
    state.raw.shift();
  }

  const avg = state.raw.reduce((sum, r) => sum + r.speed, 0) / state.raw.length;
  state.history.push({ avg, timestamp: now });

  const cutoff = now - DETECTION_WINDOW_MS * 2;
  while (state.history.length > 1 && state.history[0]!.timestamp < cutoff) {
    state.history.shift();
  }

  return avg;
}

/**
 * emergency-detection.md step 2's trigger condition, minus the "at least one
 * other member moving" clause (checked separately by
 * isAnyOtherMemberMoving). See this file's top-of-file note for the exact
 * sampling-semantics resolution.
 */
function hasRecentDropTrigger(userId: string, currentAvg: number, now: number): boolean {
  if (currentAvg >= LOWER_SPEED_KMPH) return false;

  const state = rollingState.get(userId);
  if (!state) return false;

  const windowStart = now - DETECTION_WINDOW_MS;
  return state.history.some(
    (point) => point.timestamp >= windowStart && point.timestamp < now && point.avg > UPPER_SPEED_KMPH,
  );
}

/** emergency-detection.md's false-positive guard: a whole-group stop must NOT fire Stage 1. */
function isAnyOtherMemberMoving(partyId: string, excludeUserId: string, now: number): boolean {
  const members = partyRooms.get(partyId);
  if (!members) return false;

  for (const memberId of members) {
    if (memberId === excludeUserId) continue;
    const state = rollingState.get(memberId);
    if (!state || state.history.length === 0) continue;

    const latest = state.history[state.history.length - 1]!;
    if (now - latest.timestamp <= OTHER_MEMBER_STALE_MS && latest.avg > UPPER_SPEED_KMPH) {
      return true;
    }
  }

  return false;
}

const EARTH_RADIUS_KM = 6371;

function toRadians(deg: number): number {
  return (deg * Math.PI) / 180;
}

/** Straight-line (haversine) distance in km between two lat/lng points. */
function haversineKm(a: { lat: number; lng: number }, b: { lat: number; lng: number }): number {
  const dLat = toRadians(b.lat - a.lat);
  const dLng = toRadians(b.lng - a.lng);
  const lat1 = toRadians(a.lat);
  const lat2 = toRadians(b.lat);

  const h = Math.sin(dLat / 2) ** 2 + Math.cos(lat1) * Math.cos(lat2) * Math.sin(dLng / 2) ** 2;
  return 2 * EARTH_RADIUS_KM * Math.asin(Math.sqrt(h));
}

/**
 * MVP-scoped approximation of emergency:full_alert's `distanceBehind` — see
 * this file's top-of-file note. Returns null if the stopped rider or no
 * other member has a cached location to compare against.
 */
async function computeDistanceBehindKm(
  partyId: string,
  stoppedUserId: string,
  stoppedLocation: { lat: number; lng: number } | null,
): Promise<number | null> {
  if (!stoppedLocation) return null;

  const members = partyRooms.get(partyId);
  if (!members) return null;

  let nearestKm: number | null = null;
  for (const memberId of members) {
    if (memberId === stoppedUserId) continue;
    const loc = await locationService.getLocation(partyId, memberId);
    if (!loc) continue;
    const km = haversineKm(stoppedLocation, loc);
    if (nearestKm === null || km < nearestKm) {
      nearestKm = km;
    }
  }

  return nearestKm === null ? null : Math.round(nearestKm * 10) / 10;
}

async function fireStage1(partyId: string, userId: string, now: number): Promise<void> {
  const name = (await partyService.getMemberName(partyId, userId)) ?? '';

  broadcastToParty(
    partyId,
    { type: 'emergency:stage1', payload: { stoppedUserId: userId, stoppedUserName: name } },
    userId,
  );
  sendToUser(userId, { type: 'emergency:confirm', payload: { countdown: CONFIRMATION_WINDOW_SECONDS } });

  const triggeredAt = new Date(now).toISOString();
  const confirmDeadline = new Date(now + CONFIRMATION_WINDOW_MS).toISOString();

  try {
    await emergencyService.writeEmergencyTriggerRecord(partyId, userId, triggeredAt, confirmDeadline);
  } catch (err) {
    // The passive Redis record is observability-only (see services/
    // emergency.ts's top-of-file note) — a failure to write it must never
    // stop the real, in-memory-timer-driven confirmation flow below.
    // eslint-disable-next-line no-console
    console.error('[emergency] failed to write passive Redis trigger record', partyId, userId, err);
  }

  const timeout = setTimeout(() => {
    // Task 9 audit fix (2026-07-19): the outcome logged here reflects
    // whether this rider's connection dropped at some point during the
    // window (handleEmergencyDisconnect below sets disconnectedAt, but no
    // longer resolves early) — purely for the passive Redis record's
    // `reason` field. The *timing* is identical either way: this callback
    // only ever fires after the full CONFIRMATION_WINDOW_MS has elapsed.
    const stillPending = pendingConfirmations.get(userId);
    const outcome: ResolutionOutcome = stillPending?.disconnectedAt ? 'disconnect' : 'auto_timeout';
    resolveEmergency(partyId, userId, outcome).catch((err: unknown) => {
      // eslint-disable-next-line no-console
      console.error('[emergency] auto-timeout resolution failed', partyId, userId, err);
    });
  }, CONFIRMATION_WINDOW_MS);
  timeout.unref?.();

  pendingConfirmations.set(userId, { partyId, timeout, triggeredAtMs: now });
}

type ResolutionOutcome = 'fine' | 'help' | 'auto_timeout' | 'disconnect';

/**
 * Resolves the one active confirmation window for `userId`, if any — the
 * "first of these [outcomes] wins" framing from emergency-detection.md step
 * 5, generalized to include the confirmed disconnect fail-safe as a fourth
 * outcome. A no-op (not an error) if there's no pending confirmation, so
 * this can safely be called from a race between the timer firing and a
 * client response arriving around the same moment — whichever reaches here
 * first wins, the other finds `pendingConfirmations` already empty.
 */
async function resolveEmergency(
  partyId: string,
  userId: string,
  outcome: ResolutionOutcome,
): Promise<void> {
  const pending = pendingConfirmations.get(userId);
  if (!pending) return;

  clearTimeout(pending.timeout);
  pendingConfirmations.delete(userId);
  // See this file's top-of-file note on why this is cleared on every
  // resolution outcome, not just some of them.
  rollingState.delete(userId);

  if (outcome === 'fine') {
    broadcastToParty(partyId, { type: 'emergency:resolved', payload: { userId } });
    try {
      await emergencyService.updateEmergencyRecordStage(partyId, userId, 'resolved', {
        resolvedAt: new Date().toISOString(),
      });
    } catch (err) {
      // eslint-disable-next-line no-console
      console.error('[emergency] failed to update passive Redis record on resolve', partyId, userId, err);
    }
    return;
  }

  await fireFullAlert(partyId, userId, pending.triggeredAtMs, outcome);
}

async function fireFullAlert(
  partyId: string,
  userId: string,
  triggeredAtMs: number,
  reason: ResolutionOutcome,
): Promise<void> {
  const [name, location] = await Promise.all([
    partyService.getMemberName(partyId, userId),
    locationService.getLocation(partyId, userId),
  ]);

  const distanceBehindKm = await computeDistanceBehindKm(partyId, userId, location);
  const elapsedSeconds = Math.max(0, Math.round((Date.now() - triggeredAtMs) / 1000));

  broadcastToParty(partyId, {
    type: 'emergency:full_alert',
    payload: {
      userId,
      name: name ?? '',
      lat: location?.lat ?? null,
      lng: location?.lng ?? null,
      stoppedAt: new Date(triggeredAtMs).toISOString(),
      elapsed: elapsedSeconds,
      distanceBehind: distanceBehindKm,
    },
  });

  try {
    await emergencyService.updateEmergencyRecordStage(partyId, userId, 'full_alert', {
      firedAt: new Date().toISOString(),
      reason,
    });
  } catch (err) {
    // eslint-disable-next-line no-console
    console.error('[emergency] failed to update passive Redis record on full_alert', partyId, userId, err);
  }

  const members = partyRooms.get(partyId);
  const targets = members ? [...members].map((memberId) => ({ userId: memberId })) : [];

  try {
    await dispatchEmergencyPush(targets, {
      partyId,
      stoppedUserId: userId,
      stoppedUserName: name ?? '',
      distanceBehindKm,
    });
  } catch (err) {
    // Per services/fcm.ts's own contract this shouldn't throw at all, but
    // guarded here too — an emergency push failure must never be allowed to
    // look like the rest of the engine failed, since the WS broadcast above
    // has already gone out to every connected member regardless.
    // eslint-disable-next-line no-console
    console.error('[emergency] FCM dispatch threw unexpectedly', partyId, userId, err);
  }
}

/**
 * Called from websocket/location.ts's handleLocationUpdate, after the
 * existing cache+broadcast — this is the "adding detection logic alongside
 * the existing relay, not replacing it" integration point Task 7's brief
 * asks for. Never throws back into the caller, same discipline as every
 * other WS-path function in this codebase (dispatch.ts's sendError,
 * partyPresence.ts's handlePartyConnect) — a bug in emergency detection must
 * never be able to break the location relay itself.
 */
export async function processEmergencyLocationUpdate(
  partyId: string,
  userId: string,
  speed: number,
): Promise<void> {
  try {
    const now = Date.now();
    const avg = recordReading(userId, speed, now);

    // Don't evaluate a new trigger while this rider already has an active
    // confirmation window open — emergency-detection.md's algorithm only
    // ever has one Stage 1/2 cycle in flight per rider at a time.
    if (pendingConfirmations.has(userId)) return;

    if (!hasRecentDropTrigger(userId, avg, now)) return;
    if (!isAnyOtherMemberMoving(partyId, userId, now)) return;

    await fireStage1(partyId, userId, now);
  } catch (err) {
    // eslint-disable-next-line no-console
    console.error('[emergency] failed to process location update for detection', partyId, userId, err);
  }
}

/**
 * Confirmed fail-safe (backend-mvp-plan.md §6 item 4): a dropped WS
 * connection during the confirmation window produces the same automatic
 * emergency:full_alert as genuine 60s silence — but "same as silence" means
 * the same *outcome after the same window*, not "immediately." Called from
 * websocket/server.ts's 'close' handler, alongside partyPresence.ts's
 * handlePartyDisconnect — a no-op if this user has no pending confirmation.
 *
 * **Task 9 audit fix (2026-07-19)**: the original implementation called
 * `resolveEmergency(pending.partyId, userId, 'disconnect')` directly here —
 * i.e. it fired `emergency:full_alert` the instant the WS `close` event
 * fired, regardless of how much of the confirmation window was still
 * remaining. That's a real bug, not a faithful reading of the confirmed
 * fail-safe: `close` fires on *every* disconnect, including a momentary
 * highway dead-zone drop that reconnects a few seconds later — exactly the
 * class of transient disconnect `real-time-location.md`'s 3-minute reconnect
 * window (and, for this specific engine, the rider's own remaining
 * confirmation window) exists to tolerate. Firing immediately meant a rider
 * who ducked through a tunnel mid-confirmation-window would get an automatic
 * full alert sent to their whole party before they'd even had a chance to
 * reconnect and tap "I Am Fine" — defeating the entire point of giving them
 * a confirmation window in the first place. Verified live before this fix
 * (see build-status.md's Task 9 write-up): a `ws.terminate()` 2s into a
 * 60s-equivalent window produced `emergency:full_alert` within ~100ms, not
 * anywhere near the window's actual end.
 *
 * **Fixed by decoupling "a disconnect happened" from "resolve now"**: this
 * function no longer resolves anything. It only marks
 * `pending.disconnectedAt` (read by fireStage1's already-running setTimeout
 * callback, purely to label the eventual outcome 'disconnect' vs
 * 'auto_timeout' for the passive Redis record — see that callback's own
 * comment). The confirmation's *actual* resolution still only ever happens
 * one of three ways, exactly as designed: (1) the rider reconnects and sends
 * `emergency:respond` before the window elapses — resolves normally, timer
 * cancelled, no alert; (2) the rider reconnects but never responds — the
 * original timer (untouched by the disconnect) fires at the end of the full
 * window, same as case (3); (3) the rider never reconnects at all — same
 * timer, same result. All three converge on "the existing 60s timer is the
 * only thing that ever resolves a silent/dropped rider" — which is exactly
 * "the same outcome as genuine silence," just no longer short-circuited to
 * fire early. A different party member's disconnect during someone else's
 * confirmation window is unaffected either way — this function only ever
 * touches `pendingConfirmations.get(userId)` for the userId that actually
 * disconnected, never another rider's entry, so there's no cross-rider
 * interference to guard against (confirmed, not just assumed — see
 * build-status.md's Task 9 write-up for the live check).
 */
export function handleEmergencyDisconnect(userId: string): void {
  const pending = pendingConfirmations.get(userId);
  if (!pending) return;

  if (pending.disconnectedAt === undefined) {
    pending.disconnectedAt = Date.now();
    // eslint-disable-next-line no-console
    console.warn(
      '[emergency] connection dropped during an active confirmation window — fail-safe timer still running, not resolving early',
      pending.partyId,
      userId,
    );
  }
}

/**
 * Task 9 audit fix (2026-07-19): the second gap this task was explicitly
 * asked to close — "what happens if a party ends mid-confirmation-window",
 * flagged but deferred by Task 7 (see build-status.md's Task 7 "Not built"
 * note). Before this fix, `POST /parties/:id/end` never touched this
 * module's state at all: `services/party.ts`'s `endParty()` only deletes
 * Redis keys, and `partyPresence.ts`'s `clearPartyOnEnd()` only touches its
 * own party-membership registries. Two concrete, unfixed consequences,
 * reproduced live before this fix (see build-status.md's Task 9 write-up):
 *
 *  1. **An orphaned confirmation timer kept running for an ended party.**
 *     60s (or whatever the confirmation window was) after the party ended,
 *     the timer would still fire, call `resolveEmergency(...,
 *     'auto_timeout')`, and attempt `broadcastToParty` for a partyId whose
 *     `partyRooms` entry may or may not still exist depending on exactly
 *     when `clearPartyOnEnd` ran relative to this — an unreliable "it
 *     happens to be harmless right now" state, not a guarantee. It also
 *     re-wrote `party:{partyId}:emergency:{userId}` in Redis via
 *     `updateEmergencyRecordStage` — recreating a key for an already-ended
 *     party whose `party:{id}:*` keys `endParty()` had just wildcard-deleted,
 *     directly contradicting `real-time-location.md`'s "Redis cache is
 *     deleted when the party ends" privacy guarantee (which this same
 *     ephemeral-state framing applies to the emergency record too).
 *  2. **`rollingState` leaked indefinitely.** Nothing ever cleared a party
 *     member's rolling-average history when their party ended — `rollingState`
 *     is keyed by userId only (not partyId+userId, a deliberate MVP
 *     simplification — see this file's top-of-file note), so a member who
 *     later joined a *different* party would carry stale pre-drop readings
 *     from the ended party into the new one's detection window, risking a
 *     spurious trigger seeded by data from a ride that's already over. This
 *     is the same class of staleness Task 6's senior review found and fixed
 *     for `partyRooms` (build-status.md's Task 6 write-up) — reused here,
 *     not reinvented.
 *
 * Fix: called from `routes/parties.ts`'s `/end` handler, **before**
 * `partyPresence.ts`'s `clearPartyOnEnd(partyId)` (which deletes the
 * `partyRooms` entry this function still needs to read the party's member
 * list from). Cancels every pending confirmation timer scoped to this
 * partyId (no Redis write on cancellation — the party's Redis keys are
 * already gone by the time this runs, so writing to
 * `party:{partyId}:emergency:{userId}` here would just recreate exactly the
 * orphaned key described in point 1 above) and clears `rollingState` for
 * every member who was in the party's room registry. Deliberately does NOT
 * broadcast anything to clients — mirrors `clearPartyOnEnd`'s own explicit
 * choice (no `party:ended` event exists in `system-overview.md`'s Event Map;
 * inventing one is a product/event-map decision, not a bug fix).
 */
export function clearEmergencyStateForParty(partyId: string): void {
  for (const [userId, pending] of pendingConfirmations) {
    if (pending.partyId !== partyId) continue;
    clearTimeout(pending.timeout);
    pendingConfirmations.delete(userId);
  }

  const members = partyRooms.get(partyId);
  if (members) {
    for (const userId of members) {
      rollingState.delete(userId);
    }
  }
}

interface RespondPayload {
  partyId: string;
  response: 'fine' | 'help';
}

function isValidRespondPayload(payload: unknown): payload is RespondPayload {
  if (typeof payload !== 'object' || payload === null) return false;
  const p = payload as Record<string, unknown>;
  return (
    typeof p.partyId === 'string' &&
    p.partyId.trim().length > 0 &&
    (p.response === 'fine' || p.response === 'help')
  );
}

/**
 * emergency:respond (Client -> Server) — see this file's top-of-file note
 * for why this event/shape doesn't come from any existing doc. Only the
 * rider who actually has a pending confirmation for the given partyId can
 * resolve it — matched against `ctx.userId`'s own entry in
 * `pendingConfirmations`, never trusted from the payload alone (a malicious
 * or buggy client can't resolve someone else's emergency by guessing their
 * partyId).
 */
export async function handleEmergencyRespond(ctx: WsContext, rawPayload: unknown): Promise<void> {
  if (!isValidRespondPayload(rawPayload)) {
    sendError(
      ctx,
      'INVALID_PAYLOAD',
      'emergency:respond payload must be { partyId: string, response: "fine" | "help" }.',
    );
    return;
  }

  const { partyId, response } = rawPayload;
  const pending = pendingConfirmations.get(ctx.userId);

  if (!pending || pending.partyId !== partyId) {
    // Per this file's top-of-file note on emergency-detection.md's "R sends
    // 'I Need Help' (any time, including after 60s)": once a confirmation
    // has already resolved (fine / auto_timeout / disconnect all clear
    // pendingConfirmations), a late "help" naturally lands here rather than
    // silently re-firing a second full_alert for an already-resolved
    // emergency — see build-status.md's Task 7 write-up for the full
    // reasoning on this race.
    sendError(ctx, 'NO_PENDING_EMERGENCY', 'No active emergency confirmation for this party.');
    return;
  }

  await resolveEmergency(partyId, ctx.userId, response);
}

/** Called once from websocket/server.ts to plug this task's handler into
 * Task 3's dispatch map — same explicit-registration pattern as
 * registerLocationHandlers (websocket/location.ts).
 */
export function registerEmergencyHandlers(): void {
  handlers['emergency:respond'] = handleEmergencyRespond;
}
