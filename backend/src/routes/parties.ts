import { Router } from 'express';
import { ApiError } from '../errors/ApiError';
import { authenticate } from '../middleware/authenticate';
import { idempotency } from '../middleware/idempotency';
import * as partyService from '../services/party';
import * as userService from '../services/user';
import { MIN_MAX_RIDERS, MAX_MAX_RIDERS } from '../constants/party';
import {
  broadcastPartyStarted,
  broadcastPartyMemberJoined,
  broadcastPartyEnded,
  sendPartyReady,
} from '../websocket/broadcast';
import { clearPartyOnEnd } from '../websocket/partyPresence';
import { clearEmergencyStateForParty } from '../websocket/emergency';

export const partiesRouter = Router();

const DATE_REGEX = /^\d{4}-\d{2}-\d{2}$/; // ISO8601 date, e.g. "2026-07-20"
const TIME_REGEX = /^([01]\d|2[0-3]):[0-5]\d$/; // HH:mm, e.g. "09:30"

function requireCreatePartyBody(body: unknown): {
  rideName: string;
  meetPoint: string;
  date: string;
  time: string;
  maxRiders: number;
} {
  const b = (body as Record<string, unknown> | undefined) ?? {};
  const { rideName, meetPoint, date, time, maxRiders } = b;

  if (typeof rideName !== 'string' || rideName.trim().length === 0) {
    throw new ApiError(400, 'INVALID_REQUEST', 'rideName is required.');
  }
  if (typeof meetPoint !== 'string' || meetPoint.trim().length === 0) {
    throw new ApiError(400, 'INVALID_REQUEST', 'meetPoint is required.');
  }
  if (typeof date !== 'string' || !DATE_REGEX.test(date)) {
    throw new ApiError(400, 'INVALID_REQUEST', 'date must be an ISO8601 date, e.g. "2026-07-20".');
  }
  if (typeof time !== 'string' || !TIME_REGEX.test(time)) {
    throw new ApiError(400, 'INVALID_REQUEST', 'time must be in HH:mm format, e.g. "09:30".');
  }
  if (
    typeof maxRiders !== 'number' ||
    !Number.isInteger(maxRiders) ||
    maxRiders < MIN_MAX_RIDERS ||
    maxRiders > MAX_MAX_RIDERS
  ) {
    throw new ApiError(
      400,
      'INVALID_REQUEST',
      `maxRiders must be an integer between ${MIN_MAX_RIDERS} and ${MAX_MAX_RIDERS}.`,
    );
  }

  return { rideName, meetPoint, date, time, maxRiders };
}

function requireRoomCode(body: unknown): string {
  const roomCode = (body as Record<string, unknown> | undefined)?.roomCode;
  if (typeof roomCode !== 'string' || roomCode.trim().length === 0) {
    throw new ApiError(400, 'INVALID_REQUEST', 'roomCode is required.');
  }
  return roomCode.trim().toUpperCase();
}

// POST /parties — protected + idempotent.
// { rideName, meetPoint, date, time, maxRiders } -> { partyId, roomCode }
partiesRouter.post('/parties', authenticate, idempotency, async (req, res) => {
  const input = requireCreatePartyBody(req.body);

  const organiser = await userService.getUserByPhone(req.user!.phoneNumber);
  const organiserName = organiser?.name ?? '';

  const { partyId, roomCode } = await partyService.createParty({
    ...input,
    organiserId: req.user!.userId,
    organiserName,
  });

  res.status(200).json({ partyId, roomCode });
});

// POST /parties/join — protected + idempotent.
// { roomCode } -> { partyId, rideName, meetPoint, date, time, maxRiders, members }
// 404 (error envelope) if roomCode doesn't match an open party.
//
// Task 5 integration point (senior review 2026-07-15): on a genuinely new
// member joining, broadcasts party:member_joined (and party:ready, if this
// join crosses the party-minimum threshold) directly from here, rather than
// waiting for the joining member's own WS connection to trigger it — see
// websocket/broadcast.ts's top-of-file note for why. `isNewMember` is
// stripped before the response is sent, since it's not part of
// api-design.md's documented response shape.
partiesRouter.post('/parties/join', authenticate, idempotency, async (req, res) => {
  const roomCode = requireRoomCode(req.body);

  const user = await userService.getUserByPhone(req.user!.phoneNumber);
  const name = user?.name ?? '';
  const userId = req.user!.userId;

  const { isNewMember, ...result } = await partyService.joinParty(roomCode, userId, name);

  if (isNewMember) {
    broadcastPartyMemberJoined(result.partyId, userId, name, userId);

    // party:ready fires once, to the organiser, the moment membership
    // crosses the party-minimum threshold (>=2, per active-ride-mode.md's
    // "Party Minimums"). A join can only ever move membership from N to
    // N+1, so "exactly 2 members after this join" is equivalent to
    // "just crossed the threshold" — it can't have crossed earlier and
    // won't fire again on a later join.
    if (result.members.length === 2) {
      const organiser = result.members.find((member) => member.isHost);
      if (organiser) {
        sendPartyReady(organiser.userId, result.partyId);
      }
    }
  }

  res.status(200).json(result);
});

// POST /parties/:id/start — protected, organiser-only (403 otherwise).
// -> { started: true, startedAt }
// Task 5 integration point: on success, broadcasts party:started to every
// member currently in the party's WS room registry — this is the one place
// a REST route reaches into the websocket module, via the single shared
// broadcastPartyStarted() function rather than touching the room registry
// directly.
partiesRouter.post('/parties/:id/start', authenticate, async (req, res) => {
  const partyId = String(req.params.id);
  const result = await partyService.startParty(partyId, req.user!.userId);

  const state = await partyService.getPartyState(partyId);
  broadcastPartyStarted(partyId, state?.riderOrder ?? []);

  res.status(200).json(result);
});

// POST /parties/:id/end — protected, organiser-only (403 otherwise).
// Deletes all party:{id}:* Redis keys. -> { ended: true, endedAt }
//
// Task 5 senior-review fix (2026-07-15): also clears this party's in-memory
// WS room state (pending party:member_left timers + partyRooms entry) —
// endParty() only ever touched Redis, leaving both to leak/fire stale
// events for an already-ended party. See partyPresence.ts's
// clearPartyOnEnd() doc comment for the full bug description.
//
// Task 9 audit fix (2026-07-19): also clears any in-flight emergency
// confirmation state for this party (pending 60s timers + rolling-average
// history) — the gap Task 7 explicitly flagged and deferred ("what happens
// if a party ends mid-confirmation-window", build-status.md's Task 7 "Not
// built" note). Ordering matters: clearEmergencyStateForParty must run
// BEFORE clearPartyOnEnd, since it reads the party's member list from the
// same partyRooms registry clearPartyOnEnd is about to delete — see
// websocket/emergency.ts's clearEmergencyStateForParty doc comment for the
// full bug this closes.
//
// Task 8 (PTT event relay): deliberately NOT given a clearXOnEnd() call of
// its own — verified, not assumed, that it doesn't need one. ptt:state is
// stateless request/response (no in-memory timers or per-user rolling
// history like emergency detection keeps); its only Redis footprint,
// party:{partyId}:ptt, already matches partyService.endParty()'s existing
// `party:{id}:*` wildcard delete above, same as Task 6's location keys.
//
// 2026-08-17 (build-status.md Next Steps item 30): broadcastPartyEnded()
// now fires here, right after the Redis delete succeeds and BEFORE either
// cleanup call below — ordering matters the same way it already does for
// clearEmergencyStateForParty vs clearPartyOnEnd (see that comment above):
// broadcastToParty reads the live `partyRooms` registry, which
// clearPartyOnEnd is about to delete, so the broadcast has to happen while
// that registry still reflects who was actually in the room.
partiesRouter.post('/parties/:id/end', authenticate, async (req, res) => {
  const partyId = String(req.params.id);
  const result = await partyService.endParty(partyId, req.user!.userId);
  broadcastPartyEnded(partyId);
  clearEmergencyStateForParty(partyId);
  clearPartyOnEnd(partyId);
  res.status(200).json(result);
});

// GET /parties/:id — protected, member-only (403 NOT_PARTY_MEMBER
// otherwise, 404 PARTY_NOT_FOUND if the party doesn't exist at all).
// -> { partyId, rideName, meetPoint, date, time, maxRiders, members }
//
// Added 2026-08-17 as a REST backstop for a live-reproduced race condition
// in party_ready_screen.dart (build-status.md Next Steps item 29):
// party:member_joined is broadcast the moment a REST join durably updates
// Redis (websocket/broadcast.ts), but a client's own WS connect() is
// genuinely asynchronous — if a join lands before that connection is fully
// registered server-side, the broadcast never reaches it, and there is no
// replay for a missed WS event by design. Same response shape as
// POST /parties/join (minus isNewMember, which only makes sense for that
// call) so the Flutter client can reuse its existing JoinPartyResult
// parsing rather than a new model. See services/party.ts's
// getPartyDetail() doc comment for the full reasoning.
partiesRouter.get('/parties/:id', authenticate, async (req, res) => {
  const partyId = String(req.params.id);
  const result = await partyService.getPartyDetail(partyId, req.user!.userId);
  res.status(200).json(result);
});
