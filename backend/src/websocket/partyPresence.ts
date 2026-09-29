import * as partyService from '../services/party';
import { PARTY_MEMBER_LEFT_GRACE_PERIOD_MS } from '../constants/party';
import { addToPartyRoom, removeFromPartyRoom, partyRooms, userConnections } from './registry';
import { broadcastToParty } from './broadcast';
import type { AuthenticatedWebSocket, WsContext } from './types';

/**
 * Drives party presence, per backend-mvp-plan.md Task 5.
 *
 * `party:member_joined` and `party:ready` are NOT triggered from here as of
 * the 2026-07-15 senior review — see `websocket/broadcast.ts`'s top-of-file
 * note and `docs/process/build-status.md`'s Task 5 "Senior review outcome"
 * for the full reasoning. They're now fired directly from `POST
 * /parties/join` (routes/parties.ts) once the REST call durably updates
 * Redis, mirroring how `POST /parties/:id/start` already triggers
 * `party:started`. This module still owns:
 *   - Populating `partyRooms` when a party member's WS connection
 *     authenticates (`handlePartyConnect`) — still needed so
 *     `broadcastToParty` has a live, accurate recipient set for
 *     `party:member_joined`/`party:started`/`party:member_left`, and so a
 *     reconnect within the grace window is recognised as a reconnect, not a
 *     new join.
 *   - `party:member_left`'s grace-period timer (`handlePartyDisconnect`) —
 *     this genuinely has no REST equivalent to trigger from (there's no
 *     `POST /parties/leave`), so WS disconnect remains the only signal
 *     available for "this member might have left."
 *   - Cleaning up both of the above when a party ends (`clearPartyOnEnd`) —
 *     see that function's own doc comment for the bug this fixes.
 */

interface PendingRemoval {
  partyId: string;
  timeout: ReturnType<typeof setTimeout>;
}

// userId -> pending party:member_left removal, started on disconnect,
// cancelled if the same user reconnects within the grace window. Process-
// local, same "single Node process for MVP" scope as registry.ts's maps.
const pendingRemovals = new Map<string, PendingRemoval>();

// Exposed for tests only, so a verification script can confirm a timer is
// (or isn't) pending without reaching into module internals another way.
export function hasPendingRemoval(userId: string): boolean {
  return pendingRemovals.has(userId);
}

/**
 * Called from websocket/server.ts right after a connection passes handshake
 * auth. Never throws back into the caller — any failure is logged, not
 * fatal to the connection itself (matches dispatch.ts's "nothing here should
 * crash the process" discipline).
 *
 * Only reconciles the in-memory room registry against Redis membership —
 * does NOT broadcast party:member_joined or send party:ready (see this
 * file's top-of-file note; those are REST-triggered from
 * routes/parties.ts's join handler now).
 *
 * **Fixed 2026-09-17 (process/build-status.md's "Organiser's own roster
 * doesn't update" entry)**: this used to call `partyService.
 * findActivePartyIdForUser(ctx.userId)` — an unscoped `KEYS party:*:members`
 * scan that returns whichever active party this user happens to be a member
 * of, discovered by Redis key iteration order, **not necessarily the party
 * this connection is actually for**. Flagged as a real, not-yet-biting
 * ambiguity on 2026-08-18 ("a user who's organiser of two simultaneously-open
 * parties would get ambiguous WS room registration") and confirmed live
 * 2026-09-17: a user who creates a second party without ending the first
 * (an easy thing to do in normal repeated testing, and not something the
 * product actually prevents — nothing requires an organiser to end a party
 * before starting another) gets their **new** party's `party_ready_screen`
 * WS connection silently registered into the **old** party's `partyRooms`
 * entry instead. `broadcastToParty` for the real, current party then finds
 * this user is not in the room and skips them — no error, no crash, the
 * roster on their own screen just never updates, exactly the reported bug.
 * The rider's own screen isn't affected only because `waiting_room_screen.dart`
 * (the rider-side screen) shows the REST join response directly and never
 * opens a live WS connection of its own at all — a separate, pre-existing
 * gap, not something this fix touches.
 *
 * Fix: the WS handshake now carries the specific `partyId` the client is
 * connecting for (see websocket/server.ts's handshake parsing and
 * location_ws_service.dart's `connect()`), the same way every
 * `location:update` message already carries its own `partyId` rather than
 * having the server guess it (websocket/location.ts). The claim is never
 * trusted blindly — `isPartyMember` (a direct, unambiguous single-key Redis
 * check, already used by location.ts for the same reason) confirms it before
 * this connection is added to that party's room. A connection with no
 * `partyId` on the handshake, or one that fails the membership check, is
 * treated exactly like "not a member of any active party" always was — no
 * room registration, connection still works for everything else.
 * `findActivePartyIdForUser` itself is untouched and still exists
 * (services/party.ts) but is no longer used anywhere in this file, or
 * anywhere in the backend as of this fix — see its own doc comment for why
 * it's unsafe for this specific purpose.
 */
export async function handlePartyConnect(ctx: WsContext): Promise<void> {
  const partyId = ctx.partyId;
  if (!partyId) return; // handshake didn't specify a party — nothing to do

  const isMember = await partyService.isPartyMember(partyId, ctx.userId);
  if (!isMember) return; // claimed party, but Redis doesn't agree — ignore, don't trust the client

  ctx.ws.partyId = partyId;

  const pending = pendingRemovals.get(ctx.userId);
  if (pending && pending.partyId === partyId) {
    // Reconnect within the grace window: cancel the pending removal. The
    // user was never actually taken out of partyRooms (removal only happens
    // when the timer fires), so there's nothing to re-add here.
    clearTimeout(pending.timeout);
    pendingRemovals.delete(ctx.userId);
    return;
  }

  // Idempotent: a user already registered in the room (e.g. a second
  // simultaneous connection, or a socket that connected once already and is
  // just re-running this on some other path) is a no-op add.
  addToPartyRoom(partyId, ctx.userId);
}

/**
 * Called from websocket/server.ts's 'close' handler, after the connection
 * registry has already removed this socket (if it was still the
 * currently-registered one for this userId).
 */
export function handlePartyDisconnect(ws: AuthenticatedWebSocket): void {
  const partyId = ws.partyId;
  if (!partyId) return; // this connection was never in a party room

  if (userConnections.has(ws.userId)) {
    // A newer connection for this user already replaced the registry entry
    // before this 'close' event fired (race between reconnect and the old
    // socket's close) — this close is stale, the user is still genuinely
    // connected. Don't start a removal timer.
    return;
  }

  if (pendingRemovals.has(ws.userId)) {
    // Shouldn't normally happen (a user can only have one live connection
    // per the registry's replace-on-reconnect behaviour), but guard against
    // a duplicate timer rather than silently overwriting/leaking the first.
    return;
  }

  const timeout = setTimeout(() => {
    pendingRemovals.delete(ws.userId);
    removeFromPartyRoom(partyId, ws.userId);
    broadcastToParty(partyId, { type: 'party:member_left', payload: { userId: ws.userId } });
  }, PARTY_MEMBER_LEFT_GRACE_PERIOD_MS);

  // Don't let this pending timer alone keep the Node process alive (e.g.
  // during a graceful shutdown) — matches the "fine at MVP scale" ethos
  // elsewhere in this module, not load-bearing for correctness.
  timeout.unref?.();

  pendingRemovals.set(ws.userId, { partyId, timeout });
}

/**
 * Bug found on senior review 2026-07-15 (build-status.md's Task 5 "Senior
 * review outcome"): `POST /parties/:id/end` (services/party.ts's
 * `endParty`) only ever deleted the party's Redis keys — it never touched
 * this module's in-memory state. Two concrete consequences, both fixed by
 * calling this function from routes/parties.ts's `/end` handler:
 *
 *  1. **Leaked `partyRooms` entries.** Any party that ends while at least
 *     one member still has a live WS connection left its `partyRooms` Set
 *     (and those members' `ws.partyId` tags) sitting in memory forever —
 *     nothing ever deletes it, since `removeFromPartyRoom` only runs from
 *     the disconnect-grace-period timer, which may never fire if the member
 *     never disconnects. Unbounded growth over the life of the process.
 *  2. **Stale `party:member_left` after the party is already gone.** If a
 *     member disconnected shortly before `/end` was called, their grace-
 *     period timer (started by `handlePartyDisconnect`) is still pending.
 *     Nothing cancelled it, so it would fire minutes later, broadcast
 *     `party:member_left` to whichever members are still connected (from
 *     the now-orphaned `partyRooms` entry per bug 1), for a party that has
 *     already ended and whose Redis keys are long gone — a confusing,
 *     spurious event with no corresponding real-world meaning.
 *
 * Fix: cancel every pending removal timer scoped to this partyId, clear the
 * `partyId` tag off any still-connected sockets that belonged to this room
 * (so a later disconnect for the same user/socket doesn't start a new timer
 * referencing an ended party), and drop the `partyRooms` entry entirely.
 * Deliberately does NOT broadcast anything to clients — there's no
 * `party:ended`/similar event in system-overview.md's WebSocket Event Map,
 * and inventing one is a product/event-map decision beyond this review's
 * scope, not a bug fix; flagged in build-status.md as a follow-up instead.
 */
export function clearPartyOnEnd(partyId: string): void {
  for (const [userId, pending] of pendingRemovals) {
    if (pending.partyId === partyId) {
      clearTimeout(pending.timeout);
      pendingRemovals.delete(userId);
    }
  }

  const room = partyRooms.get(partyId);
  if (room) {
    for (const userId of room) {
      const ws = userConnections.get(userId);
      if (ws && ws.partyId === partyId) {
        ws.partyId = undefined;
      }
    }
  }

  partyRooms.delete(partyId);
}
