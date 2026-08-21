import type { AuthenticatedWebSocket } from './types';

/**
 * In-memory connection registry, per backend-mvp-plan.md Task 3.
 *
 * `userConnections`: every currently-connected user's live socket. Task 5+
 * uses this to push events to a specific user (e.g. "send party:started to
 * every member").
 *
 * `partyRooms`: partyId -> set of userIds currently in that party's "room".
 * Deliberately NOT populated by this task — no party state exists until
 * Task 4, and party membership (who's actually in a room) is Task 5's job.
 * This task only builds the structure so Task 5 has something to call into.
 *
 * Both are process-local (single Node process for MVP, per plan §4 Task 3
 * and §5's hosting recommendation) — not backed by Redis. A process
 * restart drops all live connections, which is fine at MVP scale (clients
 * reconnect, per real-time-location.md's reconnect window).
 */

export const userConnections = new Map<string, AuthenticatedWebSocket>();

export const partyRooms = new Map<string, Set<string>>();

export function registerConnection(userId: string, ws: AuthenticatedWebSocket): void {
  // A user opening a second connection (e.g. app relaunch before the old
  // socket timed out) replaces the old registry entry rather than being
  // rejected — the old socket, if still technically open, simply stops
  // being reachable via the registry. Not closing it explicitly here is a
  // deliberate simplification for Task 3; revisit if Task 9's reconnect
  // hardening pass finds this causes a real duplicate-connection problem.
  userConnections.set(userId, ws);
}

export function removeConnection(userId: string, ws: AuthenticatedWebSocket): void {
  // Only remove if the registry still points at *this* socket — guards
  // against a stale/older connection's close event clobbering a newer
  // connection's registry entry for the same user (see registerConnection's
  // note above).
  if (userConnections.get(userId) === ws) {
    userConnections.delete(userId);
  }
}

// Convenience helpers for Task 4/5 to build on — not exercised by any real
// party data yet, just the structural piece this task promises.
export function addToPartyRoom(partyId: string, userId: string): void {
  const members = partyRooms.get(partyId) ?? new Set<string>();
  members.add(userId);
  partyRooms.set(partyId, members);
}

export function removeFromPartyRoom(partyId: string, userId: string): void {
  const members = partyRooms.get(partyId);
  if (!members) return;
  members.delete(userId);
  if (members.size === 0) {
    partyRooms.delete(partyId);
  }
}
