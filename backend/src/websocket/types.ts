import type { WebSocket } from 'ws';

/**
 * Shared types for the WebSocket layer. See backend-mvp-plan.md Task 3 and
 * docs/technical/architecture/system-overview.md's "WebSocket Event Map" for
 * the design this implements.
 */

// A `ws` socket that has passed the handshake auth check in
// websocket/server.ts and been tagged with the identity that check
// produced. Every message handler receives one of these via WsContext,
// never a raw un-authenticated WebSocket.
export interface AuthenticatedWebSocket extends WebSocket {
  userId: string;
  phoneNumber: string;
  // Task 5 addition: set once this connection has been added to a party's
  // room registry (websocket/partyPresence.ts), so the 'close' handler knows
  // which party's grace-period removal timer to start without having to
  // scan partyRooms. Undefined for a connection that never belonged to an
  // active party.
  partyId?: string;
}

// Every incoming client->server message must parse to this shape before
// being routed. `payload`'s real shape is handler-specific (Tasks 5-8
// define their own payload types and narrow it themselves) — kept `unknown`
// here deliberately, not `any`, so a handler can't accidentally skip
// validating it.
export interface IncomingMessage {
  type: string;
  payload: unknown;
}

// Every outgoing server->client message (including the typed error event
// this task defines) uses the same envelope shape, for symmetry with
// IncomingMessage and so a client only ever needs one parser.
export interface OutgoingMessage {
  type: string;
  payload: unknown;
}

export interface WsContext {
  ws: AuthenticatedWebSocket;
  userId: string;
  phoneNumber: string;
  // The partyId the client claimed on the WS handshake query string
  // (`?token=...&partyId=...`), added 2026-09-17 — see
  // partyPresence.ts's handlePartyConnect doc comment for the
  // ambiguous-room-registration bug this closes. Never trusted blindly:
  // handlePartyConnect verifies real Redis membership before using it for
  // anything. Null if the client didn't send one (e.g. a future connection
  // type that isn't party-scoped) — same "no active party" no-op as before
  // this field existed.
  partyId: string | null;
}

// The handler map every later task (5-8) plugs into: `handlers[type]` is
// looked up by dispatch.ts for each parsed incoming message. Handlers are
// deliberately synchronous-or-async (`void | Promise<void>`) and are
// expected to send their own responses via ctx.ws.send(...) — dispatch.ts
// only guarantees the handler gets called with a validated envelope, it
// doesn't prescribe a response shape beyond that.
export type WsHandler = (ctx: WsContext, payload: unknown) => void | Promise<void>;
