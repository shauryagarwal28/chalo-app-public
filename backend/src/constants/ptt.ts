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

// How long a minted Agora PTT *audio* channel-join token stays valid, added
// 2026-09-16 (see services/agoraToken.ts). Distinct from PTT_TTL_SECONDS
// above, which is Task 8's *event relay* Redis key TTL (who's currently
// speaking, for a possible future UI indicator) — this is the actual Agora
// RTC channel join credential's lifetime, an unrelated concept that just
// happens to also be PTT-adjacent. Sourced from config/env.ts, same
// env-overridable-with-a-shipped-default pattern as every other tunable in
// this file.
export const AGORA_TOKEN_EXPIRY_SECONDS = env.AGORA_TOKEN_EXPIRY_SECONDS;
