import { redisClient } from '../lib/redis';

/**
 * Passive Redis debugging record for the emergency detection engine, per
 * docs/technical/architecture/data-models.md's Redis key structure:
 *
 *   party:{partyId}:emergency:{userId} -> { triggeredAt, stage, confirmDeadline }
 *   TTL: 120s (fixed, set once at trigger time — see below).
 *
 * Per backend-mvp-plan.md Task 7's explicit resolution of "not yet decided"
 * item 2 (emergency-detection.md): this key is a passive, best-effort
 * observability record only. The REAL 60s countdown/resolution logic lives
 * entirely in the in-memory setTimeout timer (websocket/emergency.ts) — this
 * key is never read back to drive behavior, only written for a human running
 * `redis-cli` to be able to see "is there an active/recent emergency for
 * this rider" during development or a live highway test. Its 120s TTL is
 * fixed at creation (never re-EXPIRE'd on update) so it naturally disappears
 * shortly after even the slowest resolution path (60s confirmation + some
 * margin), without this module needing to know when that happens.
 */

export type EmergencyStage = 'stage1' | 'resolved' | 'full_alert';

function emergencyKey(partyId: string, userId: string): string {
  return `party:${partyId}:emergency:${userId}`;
}

const RECORD_TTL_SECONDS = 120;

/** Called once, when a Stage 1 trigger fires and the 60s confirmation window starts. */
export async function writeEmergencyTriggerRecord(
  partyId: string,
  userId: string,
  triggeredAt: string,
  confirmDeadline: string,
): Promise<void> {
  const key = emergencyKey(partyId, userId);
  const stage: EmergencyStage = 'stage1';
  await redisClient
    .multi()
    .hSet(key, { triggeredAt, stage, confirmDeadline })
    .expire(key, RECORD_TTL_SECONDS)
    .exec();
}

/**
 * Called once resolution happens (any of the three/four outcomes), purely to
 * update the passive record's `stage` field for observability. Deliberately
 * does NOT touch the key's TTL (no EXPIRE call) — see this file's top-of-file
 * note on why the 120s window is fixed from trigger time, not extended.
 * Best-effort: if the key already expired (a resolution arriving very late
 * relative to the 120s TTL, e.g. a slow disconnect fail-safe), `hSet` on a
 * missing key just recreates it with no TTL, which is a harmless, rare
 * edge case, not worth guarding against with an extra existence check here.
 */
export async function updateEmergencyRecordStage(
  partyId: string,
  userId: string,
  stage: EmergencyStage,
  extra: Record<string, string> = {},
): Promise<void> {
  await redisClient.hSet(emergencyKey(partyId, userId), { stage, ...extra });
}
