import type { ErrorRequestHandler } from 'express';
import { ApiError } from '../errors/ApiError';

/**
 * Express's final error-handling middleware (must be mounted last, and must
 * keep all 4 params — (err, req, res, next) — for Express to recognize it as
 * an error handler at all). Every non-2xx response in this project goes
 * through here and comes out as:
 *   { "error": { "code": "SNAKE_CASE_STRING", "message": "human-readable" } }
 * paired with the correct HTTP status — see backend-mvp-plan.md §2. Never a
 * raw stack trace, never Express's default HTML error page.
 *
 * Express 5's routers automatically forward rejected promises from async
 * route handlers to `next(err)`, so this catches both sync throws and async
 * rejections without needing an extra wrapper (unlike Express 4).
 */
export const errorHandler: ErrorRequestHandler = (err, _req, res, _next) => {
  if (err instanceof ApiError) {
    res.status(err.statusCode).json({
      error: { code: err.code, message: err.message },
    });
    return;
  }

  // Anything else is an unexpected bug, not a modeled failure — log the full
  // detail server-side (stack included) but never leak it to the client.
  // eslint-disable-next-line no-console
  console.error('[unhandled error]', err);
  res.status(500).json({
    error: {
      code: 'INTERNAL_SERVER_ERROR',
      message: 'Something went wrong on our end. Please try again.',
    },
  });
};
