import { randomUUID, randomInt } from 'node:crypto';
import { redisClient } from '../lib/redis';
import { ApiError } from '../errors/ApiError';
import {
  ROOM_CODE_LENGTH,
  ROOM_CODE_CHARSET,
  ROOM_CODE_MAX_GENERATION_ATTEMPTS,
} from '../constants/party';

/**
 * Party REST endpoints + Redis party state, per
 * docs/technical/architecture/backend-mvp-plan.md Task 4,
 * docs/technical/architecture/api-design.md's `parties` section, and
 * docs/technical/architecture/data-models.md's Redis key structure.
 *
 * Redis keys used (both decisions below reviewed and finalized by the
 * senior engineer 2026-07-15 — see build-status.md's Task 4 write-up for the
 * full reasoning; data-models.md is updated to match):
 *   party:{partyId}:state    hash — per data-models.md: { organiserId,
 *                             status, startedAt, riderOrder }, PLUS the
 *                             ride-creation fields (roomCode, rideName,
 *                             meetPoint, date, time, maxRiders) that
 *                             api-design.md's POST /parties/join response
 *                             needs and that have nowhere else documented to
 *                             live. Kept as one key rather than a second
 *                             `:details` key — every field here is written
 *                             once at creation, read together on every
 *                             lookup, and deleted together on /end, so a
 *                             second key would only add a round trip with no
 *                             isolation benefit.
 *   party:{partyId}:members  hash, userId -> name. Originally built as a
 *                             Set of bare userIds (matching data-models.md's
 *                             original documented shape) plus a second
 *                             `:member_names` hash, since the Set alone
 *                             can't satisfy api-design.md's join response
 *                             shape (`members: [{ userId, name, isHost }]`).
 *                             Merged into a single hash on review: two keys
 *                             that must always be written together (sAdd +
 *                             hSet on every join) had no atomicity guarantee
 *                             and could drift if one write failed without
 *                             the other; a single hash makes "is a member"
 *                             and "what's their name" the same fact instead
 *                             of two facts that have to be kept in sync.
 *                             `isHost` is deliberately NOT stored per-member
 *                             here (would be redundant with, and could drift
 *                             from, `:state`'s `organiserId`) — computed at
 *                             read time in getMembers() instead.
 *
 * `POST /parties/:id/end` deletes every `party:{id}:*` key (this task's two
 * plus whatever Task 6/7/8 add later, e.g. location/ptt/emergency keys — the
 * wildcard delete covers those automatically once they exist).
 */

export interface PartyState {
  organiserId: string;
  status: 'waiting' | 'started';
  startedAt: string | null;
  riderOrder: string[];
  roomCode: string;
  rideName: string;
  meetPoint: string;
  date: string;
  time: string;
  maxRiders: number;
}

export interface PartyMember {
  userId: string;
  name: string;
  isHost: boolean;
}

function stateKey(partyId: string): string {
  return `party:${partyId}:state`;
}
function membersKey(partyId: string): string {
  return `party:${partyId}:members`;
}

function generateRoomCode(): string {
  let code = '';
  for (let i = 0; i < ROOM_CODE_LENGTH; i++) {
    code += ROOM_CODE_CHARSET[randomInt(ROOM_CODE_CHARSET.length)];
  }
  return code;
}

/**
 * Scans existing `party:*:state` keys for one whose roomCode field matches,
 * per Task 4's explicit instruction ("collision-checked against existing
 * party:*:state keys ... a simple retry-on-collision loop is sufficient").
 * Doubles as the join-by-roomCode lookup, since no separate roomCode index
 * key is documented anywhere and the task explicitly points at this
 * approach rather than a dedicated index.
 */
async function findPartyIdByRoomCode(roomCode: string): Promise<string | null> {
  const keys = await redisClient.keys('party:*:state');
  for (const key of keys) {
    const storedCode = await redisClient.hGet(key, 'roomCode');
    if (storedCode === roomCode) {
      // key format is party:{partyId}:state — partyId is a UUID (hyphens,
      // no colons), so splitting on ':' is safe.
      return key.split(':')[1] ?? null;
    }
  }
  return null;
}

async function generateUniqueRoomCode(): Promise<string> {
  for (let attempt = 0; attempt < ROOM_CODE_MAX_GENERATION_ATTEMPTS; attempt++) {
    const candidate = generateRoomCode();
    const existing = await findPartyIdByRoomCode(candidate);
    if (!existing) {
      return candidate;
    }
  }
  throw new ApiError(
    500,
    'ROOM_CODE_GENERATION_FAILED',
    'Could not generate a unique room code — try again.',
  );
}

/**
 * Task 6 senior review addition (2026-07-15): a direct, single-key
 * Redis-truth check for "is userId really a member of partyId", used by
 * websocket/location.ts as a fallback when the in-memory `partyRooms`
 * registry (websocket/registry.ts) doesn't (yet) show this user as present.
 * See that file's comment for the registry-vs-Redis gap this closes — a
 * cheap `HEXISTS` on the `:members` hash rather than the
 * `findActivePartyIdForUser` scan above, since here the partyId is already
 * known from the incoming payload and doesn't need to be discovered.
 */
export async function isPartyMember(partyId: string, userId: string): Promise<boolean> {
  return Boolean(await redisClient.hExists(membersKey(partyId), userId));
}

/**
 * Task 7 (emergency detection engine) addition: looks up a single member's
 * display name directly from the `:members` hash, for
 * `emergency:stage1`/`emergency:full_alert`'s `stoppedUserName`/`name`
 * fields. A single `hGet` rather than routing through `getMembers` (which
 * needs `organiserId` to compute `isHost`, irrelevant here) — same
 * "cheap, single-key, source-of-truth-is-Redis" pattern as `isPartyMember`
 * above. Returns null if the party or member doesn't exist, rather than
 * throwing — callers decide how to degrade (e.g. an empty-string fallback in
 * the outgoing payload), consistent with how `getLocation` (services/
 * location.ts) also returns null on a miss instead of throwing.
 */
export async function getMemberName(partyId: string, userId: string): Promise<string | null> {
  const name = await redisClient.hGet(membersKey(partyId), userId);
  return name ?? null;
}

/**
 * Task 5 addition: finds *a* partyId an authenticated userId happens to be
 * a member of, by scanning `party:*:members` the same way
 * findPartyIdByRoomCode above scans `party:*:state` (same "fine at MVP
 * scale" justification the room-code lookup already relies on).
 *
 * **No longer used by the WS connect path, as of 2026-09-17 — confirmed
 * unsafe for that purpose, not just theoretically risky.** This was
 * originally `handlePartyConnect`'s (websocket/partyPresence.ts) only way to
 * decide which party's room registry a freshly authenticated connection
 * should join. The doc comment here always said "returns the first match if
 * a user were somehow in more than one (not expected, not guarded against
 * elsewhere either)" — flagged as a real, not-yet-biting gap on 2026-08-18
 * ("a user who's organiser of two simultaneously-open parties would get
 * ambiguous WS room registration"), and confirmed live 2026-09-17: a user
 * who creates a second party without ending the first (nothing in the
 * product stops this) gets a **new** party's WS connection silently
 * registered into the **wrong, older** party's room — this function has no
 * way to know which of a user's several memberships the *connection* is
 * actually for, because that was never asked of it. See
 * process/build-status.md's "Organiser's own roster doesn't update" entry
 * and partyPresence.ts's handlePartyConnect doc comment for the full story
 * and the fix (the client now says which party it's connecting for on the
 * handshake; the server verifies that specific claim via [isPartyMember]
 * rather than guessing).
 *
 * Left in place — still correct for what it actually does ("does this user
 * have *a* current party"), and still unused-but-harmless if a future
 * caller needs exactly that and is prepared for the same multi-membership
 * ambiguity this doc comment describes. Not currently called from
 * anywhere in this backend.
 */
export async function findActivePartyIdForUser(userId: string): Promise<string | null> {
  const keys = await redisClient.keys('party:*:members');
  for (const key of keys) {
    const isMember = await redisClient.hExists(key, userId);
    if (isMember) {
      // key format is party:{partyId}:members
      return key.split(':')[1] ?? null;
    }
  }
  return null;
}

export async function getPartyState(partyId: string): Promise<PartyState | null> {
  const raw = await redisClient.hGetAll(stateKey(partyId));
  if (!raw || Object.keys(raw).length === 0) {
    return null;
  }
  return {
    organiserId: raw.organiserId,
    status: raw.status === 'started' ? 'started' : 'waiting',
    startedAt: raw.startedAt ? raw.startedAt : null,
    riderOrder: raw.riderOrder ? (JSON.parse(raw.riderOrder) as string[]) : [],
    roomCode: raw.roomCode,
    rideName: raw.rideName,
    meetPoint: raw.meetPoint,
    date: raw.date,
    time: raw.time,
    maxRiders: Number(raw.maxRiders),
  };
}

async function getMembers(partyId: string, organiserId: string): Promise<PartyMember[]> {
  const names = await redisClient.hGetAll(membersKey(partyId));
  return Object.entries(names).map(([userId, name]) => ({
    userId,
    name,
    isHost: userId === organiserId,
  }));
}

/**
 * Creates a new party. Per api-design.md's POST /parties, request fields
 * match create_party_screen.dart's mock form exactly.
 */
export async function createParty(input: {
  rideName: string;
  meetPoint: string;
  date: string;
  time: string;
  maxRiders: number;
  organiserId: string;
  organiserName: string;
}): Promise<{ partyId: string; roomCode: string }> {
  const partyId = randomUUID();
  const roomCode = await generateUniqueRoomCode();

  await redisClient.hSet(stateKey(partyId), {
    organiserId: input.organiserId,
    status: 'waiting',
    startedAt: '',
    riderOrder: JSON.stringify([input.organiserId]),
    roomCode,
    rideName: input.rideName,
    meetPoint: input.meetPoint,
    date: input.date,
    time: input.time,
    maxRiders: String(input.maxRiders),
  });
  await redisClient.hSet(membersKey(partyId), input.organiserId, input.organiserName);

  return { partyId, roomCode };
}

/**
 * Joins an existing party by room code. Throws 404 (via ApiError) if the
 * room code doesn't match any open party, per api-design.md's explicit
 * "Errors: 404 if roomCode doesn't match an open party". Throws 409
 * PARTY_FULL if the party is already at `maxRiders` capacity and the caller
 * isn't already a member (a re-join by an existing member — e.g. a
 * reconnect — never counts as exceeding capacity).
 *
 * Capacity enforcement added on senior review 2026-07-15 — see
 * build-status.md's Task 4 write-up: `maxRiders` is a real field the client
 * collects and the create-party request bounds to 2-15, so leaving it
 * completely unenforced meant the cap was cosmetic. `PARTY_FULL`/409 is a
 * new error code with no prior doc reference, but follows the same
 * envelope shape as every other ApiError in this codebase and 409 is
 * exactly the "conflict" status class backend-mvp-plan.md §2 already
 * reserves for this kind of case.
 */
export async function joinParty(
  roomCode: string,
  userId: string,
  name: string,
): Promise<{
  partyId: string;
  rideName: string;
  meetPoint: string;
  date: string;
  time: string;
  maxRiders: number;
  members: PartyMember[];
  // Senior review 2026-07-15 (Task 5): true only when this call actually
  // added a brand-new member; false for a re-join by an existing member
  // (e.g. a retried request without an Idempotency-Key). Consumed by
  // routes/parties.ts to decide whether to fire party:member_joined /
  // party:ready — deliberately NOT part of api-design.md's documented
  // response shape; the route strips it before sending the JSON response,
  // so the public API contract is unchanged.
  isNewMember: boolean;
}> {
  const partyId = await findPartyIdByRoomCode(roomCode);
  if (!partyId) {
    throw new ApiError(404, 'PARTY_NOT_FOUND', 'No open party found for this room code.');
  }

  const state = await getPartyState(partyId);
  if (!state) {
    throw new ApiError(404, 'PARTY_NOT_FOUND', 'No open party found for this room code.');
  }

  const alreadyMember = await redisClient.hExists(membersKey(partyId), userId);
  if (!alreadyMember) {
    const memberCount = await redisClient.hLen(membersKey(partyId));
    if (memberCount >= state.maxRiders) {
      throw new ApiError(
        409,
        'PARTY_FULL',
        `This party is full (max ${state.maxRiders} riders).`,
      );
    }
  }

  await redisClient.hSet(membersKey(partyId), userId, name);

  if (!state.riderOrder.includes(userId)) {
    const updatedOrder = [...state.riderOrder, userId];
    await redisClient.hSet(stateKey(partyId), 'riderOrder', JSON.stringify(updatedOrder));
  }

  const members = await getMembers(partyId, state.organiserId);

  return {
    partyId,
    rideName: state.rideName,
    meetPoint: state.meetPoint,
    date: state.date,
    time: state.time,
    maxRiders: state.maxRiders,
    members,
    isNewMember: !alreadyMember,
  };
}

/**
 * GET /parties/:id — added 2026-08-17 (build-status.md Next Steps item 29)
 * as a REST backstop for party_ready_screen.dart's roster-listener race
 * condition: `party:member_joined` is only ever broadcast once, live, to
 * whoever is registered in the party's WS room at that instant
 * (websocket/broadcast.ts) — a connection that hasn't finished its
 * handshake yet (or reconnects later) has no way to replay a missed event.
 * This gives a client a way to ask "what's the real membership right now,"
 * independent of whatever the WS stream has or hasn't delivered.
 *
 * Member-only (403 NOT_PARTY_MEMBER otherwise) — deliberately not
 * organiser-only like start/end, since a member's own client could just as
 * validly need this backstop (this pass only wires it into the organiser's
 * party_ready_screen.dart, but there's no reason to bake in an
 * organiser-only restriction here that the next caller would just have to
 * undo). Reuses the same NOT_PARTY_MEMBER code the WS layer's
 * location.ts/ptt.ts handlers already use for the equivalent check, for
 * consistency across REST and WS.
 */
export async function getPartyDetail(
  partyId: string,
  userId: string,
): Promise<{
  partyId: string;
  rideName: string;
  meetPoint: string;
  date: string;
  time: string;
  maxRiders: number;
  members: PartyMember[];
}> {
  const state = await getPartyState(partyId);
  assertPartyExists(state, partyId);

  const isMember = await redisClient.hExists(membersKey(partyId), userId);
  if (!isMember) {
    throw new ApiError(403, 'NOT_PARTY_MEMBER', 'You are not a member of this party.');
  }

  const members = await getMembers(partyId, state.organiserId);

  return {
    partyId,
    rideName: state.rideName,
    meetPoint: state.meetPoint,
    date: state.date,
    time: state.time,
    maxRiders: state.maxRiders,
    members,
  };
}

/**
 * Resolves the caller's party membership and the party's `roomCode` in one
 * call, for `POST /parties/:id/agora-token` (routes/parties.ts, added
 * 2026-09-16). The Agora *channel name* this app uses is the party's
 * `roomCode` (e.g. `"RD7K2X"`), not `partyId` — see
 * `services/agoraToken.ts`'s file-level doc comment for why — but the
 * *membership* check still has to run against the real, stable `partyId`,
 * same as every other party-scoped check in this file. Deliberately reuses
 * `getPartyDetail`'s exact 404 PARTY_NOT_FOUND / 403 NOT_PARTY_MEMBER
 * shape and mechanics (same `assertPartyExists` + `membersKey` hExists
 * check) rather than inventing a third variant of "is this user a member of
 * this party" — see that function's doc comment and
 * `websocket/location.ts`'s `isMemberOfParty` for the other two places this
 * same question is already answered.
 */
export async function getPartyRoomCodeForMember(partyId: string, userId: string): Promise<string> {
  const state = await getPartyState(partyId);
  assertPartyExists(state, partyId);

  const isMember = await redisClient.hExists(membersKey(partyId), userId);
  if (!isMember) {
    throw new ApiError(403, 'NOT_PARTY_MEMBER', 'You are not a member of this party.');
  }

  return state.roomCode;
}

function assertPartyExists(state: PartyState | null, partyId: string): asserts state is PartyState {
  if (!state) {
    throw new ApiError(404, 'PARTY_NOT_FOUND', `No party found with id "${partyId}".`);
  }
}

function assertIsOrganiser(state: PartyState, userId: string): void {
  if (state.organiserId !== userId) {
    throw new ApiError(403, 'FORBIDDEN', 'Only the organiser can perform this action.');
  }
}

/** POST /parties/:id/start — organiser-only, per api-design.md. */
export async function startParty(
  partyId: string,
  userId: string,
): Promise<{ started: true; startedAt: string }> {
  const state = await getPartyState(partyId);
  assertPartyExists(state, partyId);
  assertIsOrganiser(state, userId);

  const startedAt = new Date().toISOString();
  await redisClient.hSet(stateKey(partyId), { status: 'started', startedAt });

  return { started: true, startedAt };
}

/**
 * POST /parties/:id/end — organiser-only. Deletes every `party:{id}:*`
 * Redis key, per data-models.md/api-design.md's explicit instruction — not
 * just `:state` and `:members`, so any Task 6/7/8 keys for this party
 * (location/ptt/emergency) are cleaned up too, once those exist.
 */
export async function endParty(
  partyId: string,
  userId: string,
): Promise<{ ended: true; endedAt: string }> {
  const state = await getPartyState(partyId);
  assertPartyExists(state, partyId);
  assertIsOrganiser(state, userId);

  const endedAt = new Date().toISOString();

  const keysToDelete = await redisClient.keys(`party:${partyId}:*`);
  if (keysToDelete.length > 0) {
    await redisClient.del(keysToDelete);
  }

  return { ended: true, endedAt };
}
