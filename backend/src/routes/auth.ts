import { Router } from 'express';
import { ApiError } from '../errors/ApiError';
import { isProduction } from '../config/env';
import * as otpService from '../services/otp';
import * as userService from '../services/user';
import * as tokenService from '../services/token';

export const authRouter = Router();

// E.164 format, e.g. "+919876543210" — matches api-design.md's example.
const PHONE_REGEX = /^\+[1-9]\d{7,14}$/;
const OTP_CODE_REGEX = /^\d{6}$/;

function requirePhoneNumber(body: unknown): string {
  const phoneNumber = (body as Record<string, unknown> | undefined)?.phoneNumber;
  if (typeof phoneNumber !== 'string' || !PHONE_REGEX.test(phoneNumber)) {
    throw new ApiError(
      400,
      'INVALID_PHONE_NUMBER',
      'phoneNumber must be in E.164 format, e.g. "+919876543210".',
    );
  }
  return phoneNumber;
}

// POST /auth/request-otp — { phoneNumber } -> { success, expiresInSeconds, debugOtp? }
// debugOtp only exists at all when NODE_ENV !== 'production' (omitted, not
// null, in production) — see backend-mvp-plan.md Task 2's dev-mode OTP spec.
authRouter.post('/auth/request-otp', async (req, res) => {
  const phoneNumber = requirePhoneNumber(req.body);

  const { code, expiresInSeconds } = await otpService.requestOtp(phoneNumber);

  if (!isProduction) {
    // eslint-disable-next-line no-console
    console.log(`[dev-otp] ${phoneNumber} -> ${code}`);
  }

  const response: { success: true; expiresInSeconds: number; debugOtp?: string } = {
    success: true,
    expiresInSeconds,
  };
  if (!isProduction) {
    response.debugOtp = code;
  }

  res.status(200).json(response);
});

// POST /auth/verify-otp — { phoneNumber, code } -> { accessToken, refreshToken, isNewUser }
authRouter.post('/auth/verify-otp', async (req, res) => {
  const phoneNumber = requirePhoneNumber(req.body);
  const code = (req.body as Record<string, unknown> | undefined)?.code;
  if (typeof code !== 'string' || !OTP_CODE_REGEX.test(code)) {
    throw new ApiError(400, 'INVALID_OTP_FORMAT', 'code must be a 6-digit string.');
  }

  await otpService.verifyOtp(phoneNumber, code);

  const { user, isNewUser } = await userService.getOrCreateUser(phoneNumber);
  // kycStatus is hardcoded 'unverified' for every user — no KYC pipeline
  // exists yet, this is correct-as-is per api-design.md's users section.
  const { accessToken, refreshToken } = await tokenService.issueTokenPair(
    user.userId,
    phoneNumber,
    'unverified',
  );

  res.status(200).json({ accessToken, refreshToken, isNewUser });
});

// POST /auth/refresh — { refreshToken } -> { accessToken, refreshToken }
//
// Note: api-design.md's documented response shape for this endpoint is
// `{ accessToken: string }` only. That shape predates the rotation decision
// this task implements (backend-mvp-plan.md §2: "issuing a new refresh
// token invalidates the old one") — a rotating refresh token that isn't
// returned to the caller would strand the client after exactly one refresh,
// with no way to refresh again. Extended the response to include the new
// refreshToken so rotation is actually usable; api-design.md has been
// updated to match (see that file's `auth` section) rather than silently
// diverging from it. Flagged in build-status.md's Task 2 write-up.
authRouter.post('/auth/refresh', async (req, res) => {
  const refreshToken = (req.body as Record<string, unknown> | undefined)?.refreshToken;
  if (typeof refreshToken !== 'string' || refreshToken.length === 0) {
    throw new ApiError(400, 'INVALID_REQUEST', 'refreshToken is required.');
  }

  const rotated = await tokenService.rotateRefreshToken(refreshToken);
  res.status(200).json(rotated);
});
