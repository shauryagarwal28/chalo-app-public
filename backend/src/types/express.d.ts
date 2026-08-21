// Augments Express's own Request type with the `user` field set by
// middleware/authenticate.ts, so every protected route handler can read
// `req.user` with real types instead of `any`/a locally-redeclared interface.
import type { AccessTokenPayload } from '../services/token';

declare global {
  namespace Express {
    interface Request {
      user?: Pick<AccessTokenPayload, 'userId' | 'phoneNumber' | 'kycStatus'>;
    }
  }
}

export {};
