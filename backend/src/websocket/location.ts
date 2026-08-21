import { partyRooms, addToPartyRoom } from './registry';
import { broadcastToParty } from './broadcast';
import { handlers, sendError } from './dispatch';
import { cacheLocation } from '../services/location';
import { isPartyMember } from '../services/party';
import { processEmergencyLocationUpdate } from './emergency';
import type { WsContext } from './types';

/**
 * location:update (Client -> Server) / location:broadcast (Server -> Client),
 * per docs/technical/architecture/backend-mvp-plan.md Task 6,
 * docs/technical/systems/real-time-location.md, and
 * docs/technical/architecture/system-overview.md's "Data Flow: Active Ride
 * Location" / WebSocket Event Map:
 *
 *   location:update    { partyId, lat, lng, speed, timestamp }  (in)
 *   location:broadcast { userId, lat, lng, speed, timestamp }   (out, all
 *                                                                 other party
 *                                                                 members)
 *
 * Plugs into Task 3's dispatch pattern (websocket/dispatch.ts's `handlers`
 * map) — the first task to actually register a Client -> Server handler
 * into it (Task 5 had none; party:member_joined/party:ready/party:started
 * are all REST-triggered or WS-lifecycle-triggered, not client-message-
 * triggered).
 *
 * **Membership enforcement reuses Task 3/5's existing `partyRooms:
 * Map<partyId, Set<userId>>` registry** (populated by
 * partyPresence.ts's handlePartyConnect once a WS connection authenticates
 * for a user who is a real Redis party member) rather than a second
 * membership-tracking mechanism, per this task's explicit instruction. This
 * is the same registry broadcastToParty already uses to pick recipients, so
 * "can this user push a location:update for this party" and "who receives
 * this party's broadcasts" are backed by the same fact, not two facts that
 * could drift.
 *
 * **Senior review 2026-07-15 — a real gap found and fixed, not just
 * flagged**: the junior engineer's own top-of-file note (previous revision)
 * argued a user who's a genuine Redis member but was never in `partyRooms`
 * "would also be rejected here, same as they'd be invisible to
 * broadcastToParty — consistent, not a new gap." That reasoning assumed
 * `partyRooms` membership and Redis membership only ever diverge in a way
 * that's symmetric with the broadcast side, which isn't true: `partyRooms`
 * is populated *only* at WS-connect time (partyPresence.ts's
 * handlePartyConnect), and system-overview.md's own Component Map documents
 * a single, persistent WS connection maintained by the client ("Shared
 * Infrastructure: WebSocket client (maintains single connection)") — not a
 * fresh connection per party. Two concretely reproduced failure modes
 * (verified live against a real server + Redis before this fix, see
 * build-status.md's Task 6 "Senior review outcome"):
 *   1. A client whose WS connection predates a party (e.g. connected at
 *      login, before ever creating/joining one) never gets a second
 *      `connection` event to re-run `handlePartyConnect` once it does create
 *      or join a party — its socket is never added to `partyRooms`, so its
 *      own genuinely-valid `location:update` calls are rejected forever.
 *   2. Even in the "REST join/create, then WS connect" ordering, sending
 *      `location:update` immediately on WS `open` races
 *      `handlePartyConnect`'s async Redis lookup (fire-and-forget from
 *      websocket/server.ts) — reproduced deterministically (3/3 runs), not a
 *      rare timing fluke.
 *
 * Fixed with a **self-healing fallback**, not by trying to enumerate and fix
 * every call site that could leave `partyRooms` stale: if the fast in-memory
 * check fails, `isMemberOfParty` falls back to a direct Redis `HEXISTS`
 * (`services/party.ts`'s `isPartyMember`, one extra round trip only on this
 * fallback path) and, if that confirms real membership, repairs the
 * registry on the spot (`addToPartyRoom` + tagging `ctx.ws.partyId`) so
 * every subsequent update from this connection takes the fast path again.
 * This treats Redis as the actual source of truth and `partyRooms` as a
 * cache that can lazily repair itself, which is robust to *any* ordering of
 * WS-connect vs. REST-join/create — not just the two cases reproduced above.
 */

interface LocationUpdatePayload {
  partyId: string;
  lat: number;
  lng: number;
  speed: number;
  timestamp: string | number;
}

// Senior review 2026-07-15: `isFiniteNumber` alone accepted any finite
// number, including out-of-range lat/lng (e.g. lat: 999) and negative speed
// — confirmed live (both cached in Redis and would have been relayed to
// every other party member's map with no complaint). Bounds below match
// GPS's own physical limits, not an arbitrary product choice: latitude is
// always in [-90, 90], longitude in [-180, 180], and speed (kmph, per
// real-time-location.md's "67m in 3s at 80 kmph" framing) can't be negative
// — a negative reading is a malformed/malicious payload, not a real GPS
// value, unlike e.g. 0 (stationary) which is valid. No upper bound on speed
// is enforced deliberately — a genuinely fast highway rider or a noisy GPS
// spike are both plausible and this handler isn't the layer responsible for
// judging "too fast" (emergency-detection.md's Task 7 thresholds are about
// sudden *drops*, not raw speed ceilings).
const LAT_MIN = -90;
const LAT_MAX = 90;
const LNG_MIN = -180;
const LNG_MAX = 180;

function isFiniteNumber(value: unknown): value is number {
  return typeof value === 'number' && Number.isFinite(value);
}

function isValidPayload(payload: unknown): payload is LocationUpdatePayload {
  if (typeof payload !== 'object' || payload === null) return false;
  const p = payload as Record<string, unknown>;
  return (
    typeof p.partyId === 'string' &&
    p.partyId.trim().length > 0 &&
    isFiniteNumber(p.lat) &&
    p.lat >= LAT_MIN &&
    p.lat <= LAT_MAX &&
    isFiniteNumber(p.lng) &&
    p.lng >= LNG_MIN &&
    p.lng <= LNG_MAX &&
    isFiniteNumber(p.speed) &&
    p.speed >= 0 &&
    (typeof p.timestamp === 'string' || typeof p.timestamp === 'number')
  );
}

/**
 * Fast path: is this user already tracked as present in this party's
 * in-memory room? If not, falls back to a direct Redis membership check and
 * self-heals the registry on a true positive — see this file's top-of-file
 * note ("Senior review 2026-07-15") for the two live-reproduced bugs this
 * closes.
 *
 * **Exported as of Task 8 (PTT event relay)**: `websocket/ptt.ts`'s
 * `ptt:state` handler needs the exact same "is this user really a member of
 * this party" check as `location:update` does — reused verbatim rather than
 * duplicated, per Task 8's explicit instruction not to invent a second
 * membership-checking mechanism. Nothing about this function is
 * location-specific (it only takes a `WsContext` + `partyId`), so exporting
 * it is a smaller change than moving it to a new shared module.
 */
export async function isMemberOfParty(ctx: WsContext, partyId: string): Promise<boolean> {
  if (partyRooms.get(partyId)?.has(ctx.userId)) {
    return true;
  }

  const realMember = await isPartyMember(partyId, ctx.userId);
  if (realMember) {
    addToPartyRoom(partyId, ctx.userId);
    ctx.ws.partyId = partyId;
  }
  return realMember;
}

export async function handleLocationUpdate(ctx: WsContext, rawPayload: unknown): Promise<void> {
  if (!isValidPayload(rawPayload)) {
    sendError(
      ctx,
      'INVALID_PAYLOAD',
      'location:update payload must be { partyId: string, lat: number, lng: number, speed: number, timestamp: string | number }.',
    );
    return;
  }

  const { partyId, lat, lng, speed, timestamp } = rawPayload;

  // Privacy Guarantee #1 (real-time-location.md): "Location is broadcast
  // only to active party members — the server enforces party membership
  // before relaying." Enforced here, not assumed — a real, typed rejection,
  // not a silent drop.
  if (!(await isMemberOfParty(ctx, partyId))) {
    sendError(ctx, 'NOT_PARTY_MEMBER', 'You are not a member of this party.');
    return;
  }

  await cacheLocation(partyId, ctx.userId, { lat, lng, speed });

  broadcastToParty(
    partyId,
    { type: 'location:broadcast', payload: { userId: ctx.userId, lat, lng, speed, timestamp } },
    ctx.userId, // don't echo the update back to its own sender
  );

  // Task 7 (emergency detection engine): adds detection logic alongside the
  // relay above, doesn't replace it. Never throws (see its own top-of-file
  // note) — awaited here anyway so a test/verification run has a
  // deterministic point at which detection for this update has finished,
  // not because a failure here could affect the relay above (it can't).
  await processEmergencyLocationUpdate(partyId, ctx.userId, speed);
}

/** Called once from websocket/server.ts to plug this task's handler into
 * Task 3's dispatch map — kept as an explicit call (not an import-time side
 * effect) so registration is visible at the call site, matching this
 * codebase's existing preference for explicit wiring over implicit
 * module-load magic (e.g. partyPresence.ts's handlePartyConnect/
 * handlePartyDisconnect are both explicitly called from server.ts, not
 * self-registering).
 */
export function registerLocationHandlers(): void {
  handlers['location:update'] = handleLocationUpdate;
}
