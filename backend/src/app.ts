import express, { type Express } from 'express';
import { healthRouter } from './routes/health';
import { authRouter } from './routes/auth';
import { usersRouter } from './routes/users';
import { partiesRouter } from './routes/parties';
import { notFoundHandler } from './middleware/notFoundHandler';
import { errorHandler } from './middleware/errorHandler';

/**
 * Builds the Express app without starting it listening — keeps app
 * construction separate from the process entrypoint (src/index.ts) so it can
 * be imported directly by a future test suite without binding a port.
 *
 * Route/middleware mount order matters: real routes first, then
 * notFoundHandler (catches anything unmatched), then errorHandler last
 * (Express only recognizes a 4-arg function as the error handler, and it
 * must be the final `app.use`).
 *
 * Caller (src/index.ts) is responsible for connecting Redis before this app
 * ever receives traffic — auth/users routes assume redisClient is already
 * connected, they don't connect it themselves.
 */
export function createApp(): Express {
  const app = express();

  // CORS: this backend was mobile-only (iOS/Android — no browser, no CORS
  // concept) until the 2026-09-05 Flutter-web build effort. Browsers block
  // cross-origin fetch()/XHR by default, and every real deployment of this
  // backend is cross-origin from the app that calls it (Flutter web served
  // from its own origin, e.g. a Vercel domain, hitting this API's own
  // origin). Wide open (`*`) rather than an allowlist: every response here
  // is either public (health) or gated by a Bearer token in the
  // `Authorization` header (never a cookie), so there's no ambient-auth /
  // CSRF risk a stricter origin allowlist would be defending against — see
  // technical/systems/authentication.md. Revisit if a future production
  // backend adds cookie-based auth or anything origin-sensitive.
  app.use((req, res, next) => {
    res.setHeader('Access-Control-Allow-Origin', '*');
    res.setHeader('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, OPTIONS');
    res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization, Idempotency-Key');
    if (req.method === 'OPTIONS') {
      res.sendStatus(204);
      return;
    }
    next();
  });

  app.use(express.json());

  app.use('/api/v1', healthRouter);
  app.use('/api/v1', authRouter);
  app.use('/api/v1', usersRouter);
  app.use('/api/v1', partiesRouter);

  app.use(notFoundHandler);
  app.use(errorHandler);

  return app;
}
