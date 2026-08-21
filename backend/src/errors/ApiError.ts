/**
 * The one error type every route/middleware in this project should throw for
 * an expected, "this is the client's fault or a known failure mode" case.
 *
 * `errorHandler` (src/middleware/errorHandler.ts) knows how to turn this into
 * the project-wide error envelope:
 *   { "error": { "code": "SNAKE_CASE_STRING", "message": "human-readable" } }
 * paired with `statusCode`. See docs/technical/architecture/backend-mvp-plan.md
 * §2 for the decision this implements — do not invent a different shape
 * per-route, reuse this class.
 *
 * Anything thrown that is NOT an ApiError is treated by errorHandler as an
 * unexpected server bug: logged in full server-side, but only ever reported
 * to the client as a generic 500 INTERNAL_SERVER_ERROR — never a raw stack
 * trace or Express's default HTML error page.
 */
export class ApiError extends Error {
  public readonly statusCode: number;
  public readonly code: string;

  constructor(statusCode: number, code: string, message: string) {
    super(message);
    this.name = 'ApiError';
    this.statusCode = statusCode;
    this.code = code;

    // Needed because Error's prototype chain doesn't otherwise carry through
    // TypeScript's down-compiled `extends` on some target/module combos.
    Object.setPrototypeOf(this, ApiError.prototype);
  }
}
