/**
 * Idempotency-Key middleware parameters, per
 * docs/technical/architecture/backend-mvp-plan.md §2's decision — applied
 * only to POST /parties and POST /parties/join (see middleware/idempotency.ts
 * and routes/parties.ts), not globally.
 */
export const IDEMPOTENCY_HEADER = 'Idempotency-Key';
export const IDEMPOTENCY_TTL_SECONDS = 60;
