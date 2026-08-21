import type { WsContext, WsHandler, OutgoingMessage, IncomingMessage } from './types';

/**
 * The typed event-dispatch pattern Tasks 5-8 all plug into (per
 * backend-mvp-plan.md Task 3). Deliberately minimal: parse -> validate
 * envelope shape -> look up handler by `type` -> call it. No middleware
 * chain, no per-type schema validation beyond the envelope itself — each
 * handler is responsible for validating its own `payload`, same way each
 * REST route validates its own `req.body` today (see routes/auth.ts's
 * requirePhoneNumber for the existing pattern this mirrors).
 *
 * The handler map is intentionally empty in Task 3 — no real events exist
 * yet (party/location/emergency/PTT are Tasks 4-8). This still needs to be
 * exercised end-to-end (an unrecognized `type` must be handled gracefully,
 * per Task 3's done-criteria), which it is: dispatchMessage falls through
 * to the "no handler" branch below for every `type` until Task 5+ registers
 * real ones.
 */
export const handlers: Record<string, WsHandler> = {};

// This project has a documented recurring pattern of unhandled-exception
// bugs surfacing only at runtime (see agora_ptt_service.dart's init()
// history, referenced directly in backend-mvp-plan.md Task 3). Every
// failure path below is a typed error event or a caught exception —
// nothing here should ever be able to throw back into the caller
// (websocket/server.ts's 'message' listener), which is what would crash
// the whole process per Node's default unhandled-exception behavior.

export function sendError(ctx: WsContext, code: string, message: string): void {
  const outgoing: OutgoingMessage = { type: 'error', payload: { code, message } };
  try {
    if (ctx.ws.readyState === ctx.ws.OPEN) {
      ctx.ws.send(JSON.stringify(outgoing));
    }
  } catch (err) {
    // Sending itself failing (e.g. socket already closing) shouldn't crash
    // the server either — log and move on.
    // eslint-disable-next-line no-console
    console.error('[ws] failed to send error event', ctx.userId, err);
  }
}

function isIncomingMessage(value: unknown): value is IncomingMessage {
  return (
    typeof value === 'object' &&
    value !== null &&
    typeof (value as Record<string, unknown>).type === 'string'
  );
}

/**
 * Parses and routes one raw incoming WS message. Never throws — every
 * failure mode (invalid JSON, wrong envelope shape, unknown `type`, a
 * handler itself throwing/rejecting) is caught here and turned into a typed
 * `error` event sent back to that one client. Other connections and the
 * server process are never affected by a single client's bad message.
 */
export function dispatchMessage(ctx: WsContext, raw: unknown): void {
  let text: string;
  try {
    text = typeof raw === 'string' ? raw : (raw as { toString(): string }).toString();
  } catch {
    sendError(ctx, 'MALFORMED_MESSAGE', 'Could not read message.');
    return;
  }

  let parsed: unknown;
  try {
    parsed = JSON.parse(text);
  } catch {
    sendError(ctx, 'MALFORMED_MESSAGE', 'Message must be valid JSON.');
    return;
  }

  if (!isIncomingMessage(parsed)) {
    sendError(
      ctx,
      'MALFORMED_MESSAGE',
      'Message must be a JSON object of the form { "type": string, "payload": ... }.',
    );
    return;
  }

  const handler = handlers[parsed.type];
  if (!handler) {
    sendError(ctx, 'UNKNOWN_EVENT_TYPE', `No handler registered for type "${parsed.type}".`);
    return;
  }

  try {
    const result = handler(ctx, parsed.payload);
    if (result instanceof Promise) {
      result.catch((err: unknown) => {
        // eslint-disable-next-line no-console
        console.error('[ws] handler rejected', parsed.type, ctx.userId, err);
        sendError(ctx, 'INTERNAL_ERROR', 'Something went wrong handling that message.');
      });
    }
  } catch (err) {
    // eslint-disable-next-line no-console
    console.error('[ws] handler threw synchronously', parsed.type, ctx.userId, err);
    sendError(ctx, 'INTERNAL_ERROR', 'Something went wrong handling that message.');
  }
}
