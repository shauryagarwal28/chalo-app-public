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

  app.use(express.json());

  app.use('/api/v1', healthRouter);
  app.use('/api/v1', authRouter);
  app.use('/api/v1', usersRouter);
  app.use('/api/v1', partiesRouter);

  app.use(notFoundHandler);
  app.use(errorHandler);

  return app;
}
