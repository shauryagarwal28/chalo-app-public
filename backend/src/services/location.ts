import { redisClient } from '../lib/redis';
import { LOCATION_TTL_SECONDS } from '../constants/location';

/**
 * Location cache, per docs/technical/architecture/backend-mvp-plan.md
 * Task 6 and docs/technical/architecture/data-models.md's Redis key
 * structure:
 *
 *   party:{partyId}:location:{userId} → { lat, lng, speed, updatedAt }
 *   TTL: 30s (LOCATION_TTL_SECONDS), refreshed on each update.
 *
 * Written from websocket/location.ts's location:update handler. Deleted
 * automatically both by its own TTL expiring and, if the party ends first,
 * by services/party.ts's endParty() wildcard `party:{id}:*` delete (Task 4,
 * unchanged by this task) — matches real-time-location.md's Privacy
 * Guarantee #4 ("Redis cache is deleted when the party ends").
 */

export interface LocationInput {
  lat: number;
  lng: number;
  speed: number;
}

function locationKey(partyId: string, userId: string): string {
  return `party:${partyId}:location:${userId}`;
}

/**
 * Caches a rider's latest location. `EXPIRE` always sets a fresh, absolute
 * TTL from "now" — it does not add to whatever time was left on the
 * previous TTL — so calling this on every location:update naturally
 * resets (not additively extends) the 30s window, per data-models.md's
 * explicit "refreshed on each update" instruction.
 *
 * `updatedAt` is deliberately set to the server's own receive time, not the
 * client-supplied `timestamp` field from the location:update WS payload —
 * flagged as an ambiguity, since data-models.md doesn't say which. Reasoning:
 * `updatedAt` is what real-time-location.md's "Stale Location Handling"
 * section ("If a rider's location has not updated for 30 seconds...") needs
 * to reason about — a client clock could be skewed or wrong, and the TTL
 * itself is already reset relative to server "now", so measuring staleness
 * against anything but server time would be inconsistent with the TTL it's
 * paired with. The client's `timestamp` is still relayed as-is in the
 * outgoing location:broadcast payload (see websocket/location.ts) — it's
 * just not what's cached as `updatedAt` here.
 */
/**
 * Senior review 2026-07-15: the `hSet` then separate `expire` call below run
 * as one Redis pipeline (`multi()...exec()`), not two independent
 * round-trips. With two independent calls, a process crash/connection drop
 * between them would leave a `hSet`-written key with no TTL at all — it
 * would then only ever be cleaned up by the party's own `/end` wildcard
 * delete, not the documented 30s staleness window, which is exactly the
 * kind of orphaned-if-the-party-never-ends key `real-time-location.md`'s
 * Redis-only/no-persistence framing is trying to avoid. A pipeline sends
 * both commands in one round trip and the client library only reports
 * success once both have been acknowledged, closing that window.
 */
export async function cacheLocation(
  partyId: string,
  userId: string,
  input: LocationInput,
): Promise<void> {
  const key = locationKey(partyId, userId);
  await redisClient
    .multi()
    .hSet(key, {
      lat: String(input.lat),
      lng: String(input.lng),
      speed: String(input.speed),
      updatedAt: new Date().toISOString(),
    })
    .expire(key, LOCATION_TTL_SECONDS)
    .exec();
}

export interface CachedLocation {
  lat: number;
  lng: number;
  speed: number;
  updatedAt: string;
}

/**
 * Task 7 (emergency detection engine) addition: reads a rider's last cached
 * location back out, used to populate emergency:full_alert's `lat`/`lng`
 * fields — the rolling speed window Task 7 keeps in-memory has no lat/lng in
 * it (only speed), so the full_alert payload's position has to come from
 * here, the same Redis cache location:update already writes on every
 * update. Returns null if the key doesn't exist (never sent a location, or
 * the 30s TTL has already expired it) — callers must handle that, not assume
 * a position is always available.
 */
export async function getLocation(partyId: string, userId: string): Promise<CachedLocation | null> {
  const raw = await redisClient.hGetAll(locationKey(partyId, userId));
  if (!raw || Object.keys(raw).length === 0) {
    return null;
  }
  return {
    lat: Number(raw.lat),
    lng: Number(raw.lng),
    speed: Number(raw.speed),
    updatedAt: raw.updatedAt,
  };
}
