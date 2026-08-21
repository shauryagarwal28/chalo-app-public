import type { NextFunction, Request, Response } from 'express';
import { ApiError } from '../errors/ApiError';
import { verifyAccessToken } from '../services/token';

/**
 * Protects a route with the JWT access-token check. On success, sets
 * `req.user` (typed via src/types/express.d.ts) to the token's claims. On
 * any failure — missing header, malformed header, expired/invalid/wrong-type
 * token — forwards a 401 ApiError through the standard error envelope,
 * rather than letting Express's default behaviour leak anything.
 */
export function authenticate(req: Request, _res: Response, next: NextFunction): void {
  const header = req.headers.authorization;
  if (!header || !header.startsWith('Bearer ')) {
    next(new ApiError(401, 'UNAUTHORIZED', 'Missing or malformed Authorization header.'));
    return;
  }

  const token = header.slice('Bearer '.length).trim();
  try {
    const payload = verifyAccessToken(token);
    req.user = {
      userId: payload.userId,
      phoneNumber: payload.phoneNumber,
      kycStatus: payload.kycStatus,
    };
    next();
  } catch (err) {
    next(err instanceof ApiError ? err : new ApiError(401, 'UNAUTHORIZED', 'Invalid or expired access token.'));
  }
}
