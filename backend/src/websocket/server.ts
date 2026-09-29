import type { Server as HttpServer } from 'node:http';
import { WebSocketServer, type WebSocket } from 'ws';
import { verifyAccessToken } from '../services/token';
import { registerConnection, removeConnection } from './registry';
import { dispatchMessage } from './dispatch';
import { handlePartyConnect, handlePartyDisconnect } from './partyPresence';
import { registerLocationHandlers } from './location';
import { registerEmergencyHandlers, handleEmergencyDisconnect } from './emergency';
import { registerPttHandlers } from './ptt';
import type { AuthenticatedWebSocket, WsContext } from './types';

// Task 6/7/8: plug location:update / emergency:respond / ptt:state into
// Task 3's dispatch handler map. Called once at module load —
// createWebSocketServer itself is only ever called once per process
// (src/index.ts), so there's no real risk of double registration in
// practice, but all three functions are idempotent either way (a plain
// object-key reassignment).
registerLocationHandlers();
registerEmergencyHandlers();
registerPttHandlers();

/**
 * WebSocket server skeleton + connection auth, per backend-mvp-plan.md
 * Task 3. Mounted on the same HTTP server/Node process as the Express app
 * (src/index.ts) — no separate WS process, per the plan's explicit "no
 * unnecessary complexity at this scale" decision.
 *
 * Handshake auth: the client passes its access token as a query param —
 * `ws://host/ws?token=<accessToken>` — chosen over a custom header because
 * it needs no special client-side support beyond a plain URL (works with
 * `web_socket_channel` on the Flutter side with zero extra config, and with
 * plain `wscat`/browser WebSocket for testing). Documented in
 * docs/technical/architecture/api-design.md's WebSocket section.
 *
 * The WS handshake itself is always allowed to complete (so a distinguishable
 * *close code* is available to the client, not just an HTTP-level rejection
 * that some WS client libraries surface poorly) — the token is checked
 * immediately after, in the 'connection' handler, and a bad/missing/expired
 * token closes the connection right away with code 4001 (a private-use close
 * code per RFC 6455 §7.4.2 — the 4000-4999 range is reserved for
 * application use, distinguishing this from any standard close reason).
 */
export const CLOSE_CODE_UNAUTHORIZED = 4001;

export function createWebSocketServer(httpServer: HttpServer): WebSocketServer {
  const wss = new WebSocketServer({ server: httpServer });

  wss.on('connection', (ws: WebSocket, req) => {
    let token: string | null = null;
    // partyId (added 2026-09-17): which party's room this connection should
    // be registered into — see websocket/types.ts's WsContext.partyId and
    // partyPresence.ts's handlePartyConnect doc comment for the ambiguous
    // room-registration bug this closes. Parsed the same permissive way as
    // token below — a malformed/missing value just means "not party-scoped",
    // not a connection failure (unlike a bad token, which does close the
    // connection).
    let partyId: string | null = null;
    try {
      // req.url is only the path+query (no scheme/host) on the underlying
      // http.IncomingMessage — the base below is a throwaway, only needed
      // because the URL constructor requires an absolute URL to parse from.
      const url = new URL(req.url ?? '', 'http://internal');
      token = url.searchParams.get('token');
      partyId = url.searchParams.get('partyId');
    } catch {
      // Deliberately fall through to the "no token" branch below rather
      // than let a malformed req.url throw and crash the connection
      // handler — same "never let handshake-time parsing crash the
      // process" discipline as dispatchMessage.
      token = null;
      partyId = null;
    }

    if (!token) {
      ws.close(CLOSE_CODE_UNAUTHORIZED, 'Missing access token.');
      return;
    }

    let payload;
    try {
      payload = verifyAccessToken(token);
    } catch {
      // Covers invalid signature, malformed token, wrong `type` claim, and
      // expired tokens alike — verifyAccessToken (reused from Task 2,
      // src/services/token.ts) already throws a single ApiError(401) for
      // all of these, so there's nothing token-shape-specific to branch on
      // here.
      ws.close(CLOSE_CODE_UNAUTHORIZED, 'Invalid or expired access token.');
      return;
    }

    const authedWs = ws as AuthenticatedWebSocket;
    authedWs.userId = payload.userId;
    authedWs.phoneNumber = payload.phoneNumber;

    registerConnection(payload.userId, authedWs);

    const ctx: WsContext = {
      ws: authedWs,
      userId: payload.userId,
      phoneNumber: payload.phoneNumber,
      partyId,
    };

    // Task 5: if this user is a member of an active party, join its room
    // registry (and cancel any pending party:member_left removal timer if
    // this is a reconnect within the grace window) — see partyPresence.ts's
    // top-of-file note for why this no longer broadcasts party:member_joined
    // /party:ready itself (moved to routes/parties.ts's join handler on
    // senior review 2026-07-15). Fire-and-forget (async Redis lookups) — a
    // failure here shouldn't ever prevent the connection itself from
    // working, same "never crash the connection over a side effect"
    // discipline as dispatchMessage.
    handlePartyConnect(ctx).catch((err) => {
      // eslint-disable-next-line no-console
      console.error('[ws] failed to process party presence on connect', payload.userId, err);
    });

    ws.on('message', (raw) => {
      // dispatchMessage never throws (see websocket/dispatch.ts's own
      // doc comment) — this try/catch is deliberate defense-in-depth, not
      // load-bearing, so a future bug in dispatch.ts still can't take the
      // process down from here.
      try {
        dispatchMessage(ctx, raw);
      } catch (err) {
        // eslint-disable-next-line no-console
        console.error('[ws] unexpected error reached the connection handler', payload.userId, err);
      }
    });

    ws.on('close', () => {
      removeConnection(payload.userId, authedWs);
      // Task 5: starts the party:member_left grace-period timer if this
      // connection was in a party room (no-op otherwise).
      handlePartyDisconnect(authedWs);
      // Task 7: confirmed fail-safe — a dropped connection during an active
      // emergency confirmation window fires emergency:full_alert
      // automatically, same as genuine 60s silence (no-op if this user has
      // no pending confirmation).
      handleEmergencyDisconnect(payload.userId);
    });

    ws.on('error', (err) => {
      // eslint-disable-next-line no-console
      console.error('[ws] connection-level error', payload.userId, err);
    });
  });

  wss.on('error', (err) => {
    // Server-level errors (e.g. the underlying HTTP server erroring) —
    // logged, not fatal. Individual connection errors are handled per-socket
    // above.
    // eslint-disable-next-line no-console
    console.error('[ws] server-level error', err);
  });

  return wss;
}
