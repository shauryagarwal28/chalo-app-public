/**
 * Numeric parameters for the PTT event relay, per
 * docs/technical/architecture/backend-mvp-plan.md Task 8 and
 * docs/technical/architecture/data-models.md's Redis key structure.
 * Centralized here so no service/handler hardcodes a magic number, matching
 * the pattern set by constants/location.ts and constants/emergency.ts.
 */

import { env } from '../config/env';

// party:{partyId}:ptt TTL, set on every ptt:state: 'start'. Sourced from
// config/env.ts so a test run can override it without touching the shipped
// 60s default — same pattern as constants/location.ts's
// LOCATION_TTL_SECONDS.
export const PTT_TTL_SECONDS = env.PTT_TTL_SECONDS;
