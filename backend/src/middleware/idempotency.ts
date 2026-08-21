import type { NextFunction, Request, Response } from 'express';
import { redisClient } from '../lib/redis';
import { IDEMPOTENCY_HEADER, IDEMPOTENCY_TTL_SECONDS } from '../constants/idempotency';

interface CachedResponse {
  statusCode: number;
  body: unknown;
}

function idempotencyRedisKey(key: string): string {
  return `idempotency:${key}`;
}

/**
 * Reusable Idempotency-Key middleware, per backend-mvp-plan.md §2. Applied
 * only to POST /parties and POST /parties/join (see routes/parties.ts) —
 * not mounted globally, since most endpoints don't have a meaningful
 * "duplicate" concept (see the plan doc's scoping rationale).
 *
 * Client sends a client-generated `Idempotency-Key` header (a UUID v4, one
 * per user tap of "Create"/"Join"). On first use, the route handler runs
 * normally and its JSON response is cached at `idempotency:{key}` for
 * IDEMPOTENCY_TTL_SECONDS; a repeat request with the same key within that
 * window gets the cached response replayed verbatim instead of the handler
 * re-executing.
 *
 * If the header is absent, this middleware is a no-op — the plan doc
 * specifies the header as something the client sends, but doesn't say what
 * the server should do if it's missing. Treating it as opt-in-per-request
 * (rather than rejecting the request outright) was chosen over inventing a
 * new required-header error code with no basis in api-design.md; flagged in
 * build-status.md's Task 4 write-up as an assumption, not a silent guess.
 *
 * Known limitation, not fixed here (matches the "no need for anything
 * fancier at this scale" scoping already used for room-code collision
 * checking): two concurrent requests with the same key, both arriving
 * before either has finished and cached its response, are not locked
 * against each other — both would execute the handler. Acceptable for MVP
 * traffic levels; would need a real lock (e.g. Redis SETNX-based) if this
 * ever needs to be airtight under concurrency.
 */
export async function idempotency(req: Request, res: Response, next: NextFunction): Promise<void> {
  const key = req.header(IDEMPOTENCY_HEADER);
  if (!key) {
    next();
    return;
  }

  const redisKey = idempotencyRedisKey(key);
  const cached = await redisClient.get(redisKey);
  if (cached) {
    const { statusCode, body } = JSON.parse(cached) as CachedResponse;
    res.status(statusCode).json(body);
    return;
  }

  // Intercept the eventual res.json() call (from the route handler on
  // success, or from the global errorHandler on failure — both call
  // res.json() on this same Response instance) so the cache write happens
  // regardless of which path produced the response.
  const originalJson = res.json.bind(res);
  res.json = ((body: unknown) => {
    void redisClient
      .set(redisKey, JSON.stringify({ statusCode: res.statusCode, body }), {
        EX: IDEMPOTENCY_TTL_SECONDS,
      })
      .catch((err) => {
        // eslint-disable-next-line no-console
        console.error('[idempotency] failed to cache response', err);
      });
    return originalJson(body);
  }) as Response['json'];

  next();
}
