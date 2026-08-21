import { Router } from 'express';
import { ApiError } from '../errors/ApiError';
import { authenticate } from '../middleware/authenticate';
import * as userService from '../services/user';

export const usersRouter = Router();

const MAX_NAME_LENGTH = 100; // matches data-models.md's `users.name VARCHAR(100)` bound

// Mirrors parties.ts's requireCreatePartyBody discipline: a small typed
// validator that throws the standard ApiError on any bad input, rather than
// leaving invalid data to fail unpredictably downstream.
function requireUpdateNameBody(body: unknown): { name: string } {
  const name = (body as Record<string, unknown> | undefined)?.name;
  if (typeof name !== 'string' || name.trim().length === 0) {
    throw new ApiError(400, 'INVALID_REQUEST', 'name is required and must be a non-empty string.');
  }
  if (name.length > MAX_NAME_LENGTH) {
    throw new ApiError(400, 'INVALID_REQUEST', `name must be ${MAX_NAME_LENGTH} characters or fewer.`);
  }
  return { name: name.trim() };
}

// GET /users/me — protected. Returns the MVP-minimal profile shape, NOT the
// full api-design.md shape (no photoUrl/bikeMake/bikeModel/rating — those
// need Postgres/KYC, out of MVP scope per backend-mvp-plan.md §1).
usersRouter.get('/users/me', authenticate, async (req, res) => {
  // req.user is guaranteed set here — `authenticate` calls next() with an
  // ApiError (short-circuiting this handler) on any auth failure.
  const { phoneNumber } = req.user!;

  const user = await userService.getUserByPhone(phoneNumber);
  if (!user) {
    // Shouldn't happen in practice (a valid access token implies a user
    // record was created on verify-otp), but defensive rather than assumed.
    throw new ApiError(404, 'USER_NOT_FOUND', 'No user record found for this token.');
  }

  res.status(200).json({
    id: user.userId,
    phoneNumber,
    name: user.name,
    kycStatus: 'unverified',
  });
});

// PUT /users/me — protected. Persists the rider's real display name, closing
// the gap flagged in the 2026-08-04 backend-integration writeup
// (build-status.md's "Real backend integration" section): every user record
// is created with `name: ''` on OTP verify and there was never an endpoint
// to set it. Request: { name: string }. Response: same minimal MVP shape as
// GET /users/me (no photoUrl/bikeMake/bikeModel — api-design.md's documented
// `PUT /users/me` also accepts those, but MinimalUser has nowhere to store
// them yet; same MVP-subset caveat GET /users/me's doc comment already
// carries, see that section's note in api-design.md).
usersRouter.put('/users/me', authenticate, async (req, res) => {
  const { phoneNumber } = req.user!;
  const { name } = requireUpdateNameBody(req.body);

  const existing = await userService.getUserByPhone(phoneNumber);
  if (!existing) {
    // Same defensive-404 as GET /users/me — shouldn't happen in practice for
    // a valid access token, but not assumed.
    throw new ApiError(404, 'USER_NOT_FOUND', 'No user record found for this token.');
  }

  const updated = await userService.updateUserName(phoneNumber, existing, name);

  res.status(200).json({
    id: updated.userId,
    phoneNumber,
    name: updated.name,
    kycStatus: 'unverified',
  });
});
