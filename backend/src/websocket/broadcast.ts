import { userConnections, partyRooms } from './registry';
import type { OutgoingMessage } from './types';

/**
 * Small, reusable send/broadcast helpers for the party WS events
 * (backend-mvp-plan.md Task 5) — and the integration points the REST
 * `parties` routes use to trigger WS side effects (routes/parties.ts imports
 * these rather than reaching into registry.ts directly, so the REST layer
 * only ever talks to small, purpose-built functions from the WS module, not
 * its internal registries).
 *
 * **party:member_joined / party:ready are REST-triggered, not WS-connect-
 * triggered** (senior review 2026-07-15, build-status.md's Task 5 "Senior
 * review outcome"): the junior engineer's original implementation fired
 * these from websocket/partyPresence.ts's `handlePartyConnect`, i.e. when
 * the *newly-joined* member's own WS connection authenticated — timing that
 * depends entirely on how quickly that member's client opens a WS after its
 * REST `/parties/join` call returns. Moved here instead, called directly
 * from `POST /parties/join` once the REST call itself succeeds, mirroring
 * how `POST /parties/:id/start` already triggers `party:started`. This
 * means existing (already WS-connected) party members are notified the
 * moment the join is durable in Redis, not whenever the joiner's own socket
 * happens to catch up — and it also fixes a case the WS-connect-driven
 * design couldn't handle at all: a client that opens one persistent WS
 * connection early (e.g. right after creating a party, before anyone else
 * has joined) would never get a *second* `connection` event to re-trigger
 * `handlePartyConnect` later, so it could never learn about subsequent
 * REST joins under the old design.
 */

function send(userId: string, message: OutgoingMessage): void {
  const ws = userConnections.get(userId);
  if (!ws || ws.readyState !== ws.OPEN) {
    return; // not connected right now — fine, nothing to relay to
  }
  try {
    ws.send(JSON.stringify(message));
  } catch (err) {
    // Same "sending itself failing shouldn't crash anything" discipline as
    // dispatch.ts's sendError.
    // eslint-disable-next-line no-console
    console.error('[ws] failed to send message', userId, message.type, err);
  }
}

/** Sends a message to one specific user, if they currently have a live socket. */
export function sendToUser(userId: string, message: OutgoingMessage): void {
  send(userId, message);
}

/**
 * Sends a message to every userId currently in a party's room registry,
 * optionally skipping one (e.g. don't echo party:member_joined back to the
 * member who just joined).
 */
export function broadcastToParty(
  partyId: string,
  message: OutgoingMessage,
  excludeUserId?: string,
): void {
  const members = partyRooms.get(partyId);
  if (!members) return;
  for (const userId of members) {
    if (userId === excludeUserId) continue;
    send(userId, message);
  }
}

/**
 * party:started { partyId, riderOrder } — per system-overview.md's event
 * map, broadcast to every room member when the organiser calls
 * POST /parties/:id/start. Called from routes/parties.ts after Task 4's
 * startParty() successfully updates Redis state — this is the REST-to-WS
 * integration point Task 5 explicitly asks for.
 */
export function broadcastPartyStarted(partyId: string, riderOrder: string[]): void {
  broadcastToParty(partyId, { type: 'party:started', payload: { partyId, riderOrder } });
}

function computeInitials(name: string): string {
  const trimmed = name.trim();
  if (!trimmed) return '';
  // Per docs/design/components.md: "1-2 character initials".
  return trimmed
    .split(/\s+/)
    .slice(0, 2)
    .map((part) => part[0]!.toUpperCase())
    .join('');
}

/**
 * party:member_joined { userId, name, initials } — per system-overview.md's
 * event map. Called from `POST /parties/join` (routes/parties.ts) once the
 * REST join itself has durably updated Redis — see this file's top-of-file
 * note for why this moved off the WS-connect-driven trigger. Recipients are
 * whichever existing room members currently have a live WS connection
 * (`send()` no-ops for anyone who doesn't); the newly-joined user is always
 * excluded, since they don't need to be told about their own join.
 */
export function broadcastPartyMemberJoined(
  partyId: string,
  userId: string,
  name: string,
  excludeUserId: string,
): void {
  broadcastToParty(
    partyId,
    { type: 'party:member_joined', payload: { userId, name, initials: computeInitials(name) } },
    excludeUserId,
  );
}

/**
 * party:ready { partyId } — sent to the organiser only, the first time a
 * party's actual Redis membership crosses from <2 to >=2 (the party-minimum
 * rule from product/features/active-ride-mode.md's "Party Minimums" —
 * organiser + at least 1 rider). Direction/trigger resolved on senior review
 * 2026-07-15: system-overview.md's WebSocket Event Map previously listed
 * `party:ready` as Client -> Server (a client "I'm ready" ping); corrected
 * to Server -> Client, since readiness is purely a server-observed fact
 * about party size — there's nothing for a client to meaningfully assert
 * here that the server doesn't already know from Redis membership, and this
 * keeps `party:ready` consistent with `party:member_joined`/`party:started`,
 * which are also both server-observed facts pushed to clients, not
 * client-initiated messages.
 */
export function sendPartyReady(organiserId: string, partyId: string): void {
  sendToUser(organiserId, { type: 'party:ready', payload: { partyId } });
}

/**
 * party:ended { partyId } — added 2026-08-17 (process/build-status.md Next
 * Steps item 30). `POST /parties/:id/end` (routes/parties.ts) previously
 * deleted the party's Redis state and cleared its in-memory WS room
 * registry without ever telling still-connected clients — Task 5's own
 * 2026-07-15 senior review considered and explicitly declined to add this
 * ("inventing one is a product/event-map decision beyond this review's
 * scope"), and it was confirmed live the same day this was finally added
 * that a member's screen just goes stale in place with no signal at all.
 *
 * Broadcast to every current room member with **no exclusion**, including
 * the organiser's own connection — they're still a `partyRooms` member at
 * the instant this fires (called from the route handler *before*
 * `clearPartyOnEnd` empties the room registry, same ordering constraint
 * `clearEmergencyStateForParty` already documents there). The Flutter
 * client is expected to ignore this echo on the organiser's own device
 * (see live_ride_screen.dart's `_onPartyEnded` doc comment) rather than
 * this function trying to exclude them server-side — excluding by
 * `endedByUserId` here would be one extra parameter purely to work around
 * a client-side no-op, not worth it for a broadcast this cheap.
 */
export function broadcastPartyEnded(partyId: string): void {
  broadcastToParty(partyId, { type: 'party:ended', payload: { partyId } });
}
