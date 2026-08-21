import type { NextFunction, Request, Response } from 'express';
import { ApiError } from '../errors/ApiError';

/**
 * Mounted after every real route. Anything that falls through to here is a
 * genuinely unmatched route — turn it into the same error envelope every
 * other error uses, rather than Express's default HTML 404 page.
 */
export function notFoundHandler(req: Request, _res: Response, next: NextFunction): void {
  next(new ApiError(404, 'NOT_FOUND', `No route found for ${req.method} ${req.originalUrl}`));
}
