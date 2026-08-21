import jwt from 'jsonwebtoken';
import { randomUUID } from 'node:crypto';
import { redisClient } from '../lib/redis';
import { ApiError } from '../errors/ApiError';
import { env } from '../config/env';
import { ACCESS_TOKEN_TTL_SECONDS, REFRESH_TOKEN_TTL_SECONDS } from '../constants/auth';

/**
 * JWT issuance/verification/rotation, per
 * docs/technical/systems/authentication.md's "JWT Token Design".
 *
 * Both access and refresh tokens are signed with the same JWT_SECRET
 * (Task 2's "first auth pattern in the codebase" — a single secret keeps
 * secrets handling simple for MVP) and distinguished by a `type` claim, so
 * an access token can never be presented where a refresh token is expected
 * or vice versa.
 *
 * Refresh rotation: every successful `POST /auth/refresh` call invalidates
 * the refresh token it was called with and issues a brand new access+refresh
 * pair. Validity is tracked in Redis at `refresh:{tokenId}` -> userId — the
 * JWT signature alone isn't enough to know a refresh token hasn't already
 * been used, since a stolen-but-already-rotated token would otherwise still
 * verify successfully right up until its 30-day expiry.
 */

export interface AccessTokenPayload {
  userId: string;
  phoneNumber: string;
  kycStatus: string;
  type: 'access';
}

interface RefreshTokenPayload {
  userId: string;
  phoneNumber: string;
  tokenId: string;
  type: 'refresh';
}

function refreshKey(tokenId: string): string {
  return `refresh:${tokenId}`;
}

function signAccessToken(userId: string, phoneNumber: string, kycStatus: string): string {
  const payload: AccessTokenPayload = { userId, phoneNumber, kycStatus, type: 'access' };
  return jwt.sign(payload, env.JWT_SECRET, { expiresIn: ACCESS_TOKEN_TTL_SECONDS });
}

async function signRefreshToken(userId: string, phoneNumber: string): Promise<string> {
  const tokenId = randomUUID();
  const payload: RefreshTokenPayload = { userId, phoneNumber, tokenId, type: 'refresh' };
  const token = jwt.sign(payload, env.JWT_SECRET, { expiresIn: REFRESH_TOKEN_TTL_SECONDS });
  await redisClient.set(refreshKey(tokenId), userId, { EX: REFRESH_TOKEN_TTL_SECONDS });
  return token;
}

/** Issues a fresh access+refresh pair for a user (verify-otp success, or refresh rotation). */
export async function issueTokenPair(
  userId: string,
  phoneNumber: string,
  kycStatus: string,
): Promise<{ accessToken: string; refreshToken: string }> {
  const accessToken = signAccessToken(userId, phoneNumber, kycStatus);
  const refreshToken = await signRefreshToken(userId, phoneNumber);
  return { accessToken, refreshToken };
}

/** Verifies an access token's signature, expiry, and `type` claim. Throws ApiError(401) on any failure. */
export function verifyAccessToken(token: string): AccessTokenPayload {
  let decoded: unknown;
  try {
    decoded = jwt.verify(token, env.JWT_SECRET);
  } catch {
    throw new ApiError(401, 'UNAUTHORIZED', 'Invalid or expired access token.');
  }

  const payload = decoded as Partial<AccessTokenPayload>;
  if (payload.type !== 'access' || !payload.userId || !payload.phoneNumber) {
    throw new ApiError(401, 'UNAUTHORIZED', 'Invalid or expired access token.');
  }
  return payload as AccessTokenPayload;
}

/**
 * Verifies a refresh token, confirms it hasn't already been rotated/revoked
 * (via the Redis `refresh:{tokenId}` lookup), invalidates it, and issues a
 * brand new access+refresh pair. A second call with the same (now-consumed)
 * refresh token fails with INVALID_REFRESH_TOKEN, same as a fabricated one.
 */
export async function rotateRefreshToken(
  token: string,
): Promise<{ accessToken: string; refreshToken: string }> {
  let decoded: unknown;
  try {
    decoded = jwt.verify(token, env.JWT_SECRET);
  } catch {
    throw new ApiError(401, 'INVALID_REFRESH_TOKEN', 'Invalid or expired refresh token.');
  }

  const payload = decoded as Partial<RefreshTokenPayload>;
  if (
    payload.type !== 'refresh' ||
    !payload.tokenId ||
    !payload.userId ||
    !payload.phoneNumber
  ) {
    throw new ApiError(401, 'INVALID_REFRESH_TOKEN', 'Invalid or expired refresh token.');
  }

  const storedUserId = await redisClient.get(refreshKey(payload.tokenId));
  if (!storedUserId || storedUserId !== payload.userId) {
    throw new ApiError(
      401,
      'INVALID_REFRESH_TOKEN',
      'This refresh token has already been used or revoked.',
    );
  }

  // Rotate: invalidate the old token before issuing the new pair, so a
  // concurrent/replayed use of the same old token can't also succeed.
  await redisClient.del(refreshKey(payload.tokenId));

  // kycStatus is hardcoded 'unverified' everywhere for now — no KYC pipeline
  // exists yet, see api-design.md's users section / build-status.md.
  const accessToken = signAccessToken(payload.userId, payload.phoneNumber, 'unverified');
  const refreshToken = await signRefreshToken(payload.userId, payload.phoneNumber);
  return { accessToken, refreshToken };
}
