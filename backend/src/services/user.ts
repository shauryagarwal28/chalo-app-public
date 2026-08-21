import { randomUUID } from 'node:crypto';
import { redisClient } from '../lib/redis';

/**
 * Minimal MVP-scoped user identity — NOT the full `users` table from
 * data-models.md (no photoUrl/bikeMake/bikeModel/rating; those need
 * Postgres/KYC, both out of MVP scope per backend-mvp-plan.md §1).
 *
 * Stored at `user:{phoneNumber}` with NO TTL — this is the one piece of
 * real persistence MVP has, confirmed by the user 2026-07-14 (see
 * backend-mvp-plan.md §6 item 3): a rider's identity needs to survive
 * across parties/app restarts within the MVP test window even without
 * Postgres.
 */
export interface MinimalUser {
  userId: string;
  name: string;
  createdAt: string;
}

function userKey(phoneNumber: string): string {
  return `user:${phoneNumber}`;
}

export async function getUserByPhone(phoneNumber: string): Promise<MinimalUser | null> {
  const raw = await redisClient.get(userKey(phoneNumber));
  return raw ? (JSON.parse(raw) as MinimalUser) : null;
}

/**
 * Looks up the user record for phoneNumber, creating a minimal one (empty
 * name — there's no profile-creation endpoint in MVP scope, the Flutter app
 * collects a name client-side today) if this is the first successful OTP
 * verify for this number. Returns isNewUser so the caller (verify-otp route)
 * can pass it straight through in the response, per api-design.md's shape.
 */
export async function getOrCreateUser(
  phoneNumber: string,
): Promise<{ user: MinimalUser; isNewUser: boolean }> {
  const existing = await getUserByPhone(phoneNumber);
  if (existing) {
    return { user: existing, isNewUser: false };
  }

  const user: MinimalUser = {
    userId: randomUUID(),
    name: '',
    createdAt: new Date().toISOString(),
  };
  // Deliberately no EX/TTL — see file-level doc comment above.
  await redisClient.set(userKey(phoneNumber), JSON.stringify(user));
  return { user, isNewUser: true };
}

/**
 * Persists a new display name onto an already-loaded user record and writes
 * it back to `user:{phoneNumber}`. Callers are expected to have already
 * fetched `existing` via getUserByPhone and handled the "no record" case
 * themselves (same defensive-404 pattern GET /users/me uses) — this
 * function assumes existence rather than re-checking it, so it can't drift
 * into a second, differently-shaped "user not found" behaviour.
 */
export async function updateUserName(
  phoneNumber: string,
  existing: MinimalUser,
  name: string,
): Promise<MinimalUser> {
  const updated: MinimalUser = { ...existing, name };
  // Same no-EX/TTL persistence as getOrCreateUser — see file-level doc comment.
  await redisClient.set(userKey(phoneNumber), JSON.stringify(updated));
  return updated;
}
