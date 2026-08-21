import bcrypt from 'bcryptjs';
import { redisClient } from '../lib/redis';
import { ApiError } from '../errors/ApiError';
import {
  OTP_TTL_SECONDS,
  OTP_MAX_VERIFY_ATTEMPTS,
  OTP_LOCKOUT_SECONDS,
  OTP_RESEND_COOLDOWN_SECONDS,
  OTP_RATE_LIMIT_MAX_PER_HOUR,
  OTP_RATE_LIMIT_WINDOW_SECONDS,
} from '../constants/auth';

/**
 * OTP request/verify logic, per docs/technical/systems/authentication.md and
 * docs/technical/architecture/data-models.md's `otp:{phoneNumber}` Redis key.
 * Numeric parameters all come from src/constants/auth.ts, not hardcoded here.
 *
 * Redis keys used (all per-phoneNumber):
 *   otp:{phoneNumber}            hash { codeHash, attempts, createdAt }, TTL 10m
 *   otp:lockout:{phoneNumber}    '1', TTL 30m — set after 3 failed verify attempts
 *   otp:cooldown:{phoneNumber}   '1', TTL 30s — resend cooldown
 *   otp:ratelimit:{phoneNumber}  counter, TTL 1h — max 5 requests/hour
 */

const BCRYPT_ROUNDS = 10;

function otpKey(phoneNumber: string): string {
  return `otp:${phoneNumber}`;
}
function lockoutKey(phoneNumber: string): string {
  return `otp:lockout:${phoneNumber}`;
}
function cooldownKey(phoneNumber: string): string {
  return `otp:cooldown:${phoneNumber}`;
}
function rateLimitKey(phoneNumber: string): string {
  return `otp:ratelimit:${phoneNumber}`;
}

function generateCode(): string {
  // 6-digit code, zero-padded, no leading-zero bias issue since we generate
  // directly in the 100000-999999 range (always 6 digits).
  return Math.floor(100000 + Math.random() * 900000).toString();
}

async function assertNotLockedOut(phoneNumber: string): Promise<void> {
  const locked = await redisClient.exists(lockoutKey(phoneNumber));
  if (locked) {
    const ttl = await redisClient.ttl(lockoutKey(phoneNumber));
    const minutes = Math.max(1, Math.ceil(ttl / 60));
    throw new ApiError(
      429,
      'OTP_LOCKED',
      `Too many failed attempts. Try again in ${minutes} minute(s).`,
    );
  }
}

/**
 * Generates and stores a new OTP for phoneNumber, enforcing lockout, resend
 * cooldown, and hourly rate limit. Returns the plaintext code (caller
 * decides whether to log/return it — dev-only, see routes/auth.ts) and how
 * long it stays valid.
 */
export async function requestOtp(
  phoneNumber: string,
): Promise<{ code: string; expiresInSeconds: number }> {
  await assertNotLockedOut(phoneNumber);

  const cooling = await redisClient.exists(cooldownKey(phoneNumber));
  if (cooling) {
    throw new ApiError(
      429,
      'OTP_RESEND_COOLDOWN',
      `Please wait ${OTP_RESEND_COOLDOWN_SECONDS} seconds before requesting another code.`,
    );
  }

  const requestCount = await redisClient.incr(rateLimitKey(phoneNumber));
  if (requestCount === 1) {
    await redisClient.expire(rateLimitKey(phoneNumber), OTP_RATE_LIMIT_WINDOW_SECONDS);
  }
  if (requestCount > OTP_RATE_LIMIT_MAX_PER_HOUR) {
    throw new ApiError(
      429,
      'OTP_RATE_LIMITED',
      'Too many OTP requests for this number. Try again in an hour.',
    );
  }

  const code = generateCode();
  const codeHash = await bcrypt.hash(code, BCRYPT_ROUNDS);

  await redisClient.hSet(otpKey(phoneNumber), {
    codeHash,
    attempts: '0',
    createdAt: new Date().toISOString(),
  });
  await redisClient.expire(otpKey(phoneNumber), OTP_TTL_SECONDS);
  await redisClient.set(cooldownKey(phoneNumber), '1', { EX: OTP_RESEND_COOLDOWN_SECONDS });

  return { code, expiresInSeconds: OTP_TTL_SECONDS };
}

/**
 * Verifies submittedCode against the stored OTP for phoneNumber. Throws an
 * ApiError (never returns false) on any failure — INVALID_OTP for a wrong
 * code with attempts remaining, OTP_LOCKED once the 3rd wrong attempt is
 * hit, OTP_NOT_FOUND if no OTP is on record (expired or never requested).
 * Resolves (no return value) only on a correct code.
 */
export async function verifyOtp(phoneNumber: string, submittedCode: string): Promise<void> {
  await assertNotLockedOut(phoneNumber);

  const record = await redisClient.hGetAll(otpKey(phoneNumber));
  if (!record || !record.codeHash) {
    throw new ApiError(
      400,
      'OTP_NOT_FOUND',
      'No active OTP for this phone number — request a new one.',
    );
  }

  const matches = await bcrypt.compare(submittedCode, record.codeHash);
  if (matches) {
    await redisClient.del(otpKey(phoneNumber));
    await redisClient.del(cooldownKey(phoneNumber));
    return;
  }

  const attempts = await redisClient.hIncrBy(otpKey(phoneNumber), 'attempts', 1);
  if (attempts >= OTP_MAX_VERIFY_ATTEMPTS) {
    await redisClient.set(lockoutKey(phoneNumber), '1', { EX: OTP_LOCKOUT_SECONDS });
    await redisClient.del(otpKey(phoneNumber));
    throw new ApiError(
      429,
      'OTP_LOCKED',
      `Too many failed attempts. Locked for ${OTP_LOCKOUT_SECONDS / 60} minutes.`,
    );
  }

  const remaining = OTP_MAX_VERIFY_ATTEMPTS - attempts;
  throw new ApiError(400, 'INVALID_OTP', `Incorrect code. ${remaining} attempt(s) remaining.`);
}
