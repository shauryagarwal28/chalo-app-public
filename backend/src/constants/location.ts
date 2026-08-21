/**
 * Numeric parameters for the location relay, per
 * docs/technical/architecture/backend-mvp-plan.md Task 6,
 * docs/technical/systems/real-time-location.md, and
 * docs/technical/architecture/data-models.md's Redis key structure.
 * Centralized here so no service/handler hardcodes a magic number, matching
 * the pattern set by constants/auth.ts and constants/party.ts.
 */

import { env } from '../config/env';

// party:{partyId}:location:{userId} TTL, refreshed (not extended
// additively) on every location:update. Sourced from config/env.ts so a
// test run can override it via LOCATION_TTL_SECONDS without touching the
// shipped 30s default — same pattern as
// constants/party.ts's PARTY_MEMBER_LEFT_GRACE_PERIOD_MS.
export const LOCATION_TTL_SECONDS = env.LOCATION_TTL_SECONDS;
