/**
 * Numeric/format parameters for party creation and room codes, per
 * docs/technical/architecture/backend-mvp-plan.md Task 4 and
 * docs/technical/architecture/api-design.md's `parties` section.
 * Centralized here so no route/service hardcodes a magic number, matching
 * the pattern set by constants/auth.ts.
 */

import { env } from '../config/env';

// 6-character uppercase alphanumeric room code, per api-design.md's
// POST /parties response shape.
export const ROOM_CODE_LENGTH = 6;
export const ROOM_CODE_CHARSET = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';

// Retry-on-collision loop bound, per backend-mvp-plan.md Task 4 ("a simple
// retry-on-collision loop is sufficient, no need for anything fancier at
// MVP scale"). Collisions are astronomically unlikely at this volume
// (36^6 possible codes) — this bound just guards against an infinite loop
// if something is badly wrong, not a realistic collision count.
export const ROOM_CODE_MAX_GENERATION_ATTEMPTS = 20;

// maxRiders bounds, per api-design.md's POST /parties request shape
// ("maxRiders: number (2-15)").
export const MIN_MAX_RIDERS = 2;
export const MAX_MAX_RIDERS = 15;

// Task 5 (party WS events): grace period between a party member's WS
// disconnect and party:member_left actually broadcasting/removing them from
// the room registry. Sourced from config/env.ts (not hardcoded here) so a
// test run can override it via PARTY_MEMBER_LEFT_GRACE_PERIOD_MS without
// touching the 3-minute production default — see backend-mvp-plan.md Task 5
// and real-time-location.md's reconnect window, which this reuses as-is.
export const PARTY_MEMBER_LEFT_GRACE_PERIOD_MS = env.PARTY_MEMBER_LEFT_GRACE_PERIOD_MS;
