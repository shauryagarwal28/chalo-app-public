/**
 * Numeric parameters for the periodic Redis party:* key-set sanity sweep,
 * per docs/technical/architecture/backend-mvp-plan.md Task 9 ("Add a
 * periodic Redis TTL sanity sweep ... an interval that logs/alerts if any
 * party:* key set has grown unboundedly"). Centralized here so nothing
 * hardcodes a magic number, matching the pattern set by constants/party.ts,
 * constants/location.ts, and constants/emergency.ts.
 *
 * Both values are sourced from config/env.ts (not hardcoded here) so a test
 * run can shorten the interval / lower the warning threshold without
 * touching the shipped defaults — same pattern as every other tunable in
 * this codebase.
 */

import { env } from '../config/env';

// How often the sweep runs. 5 minutes by default: frequent enough to catch
// a real leak (e.g. abandoned parties nobody ever calls /end on) well before
// it matters at MVP scale, infrequent enough that a Redis KEYS scan (O(n),
// same "fine at MVP scale" pattern already used by
// findPartyIdByRoomCode/findActivePartyIdForUser in services/party.ts) isn't
// run needlessly often.
export const CLEANUP_SWEEP_INTERVAL_MS = env.CLEANUP_SWEEP_INTERVAL_MS;

// If the number of distinct party IDs represented among party:* keys reaches
// this, log a warning — a signal that parties aren't being cleaned up via
// their normal /end lifecycle. Arbitrary, not derived from any doc — worth
// revisiting once real usage data exists for how many concurrent/abandoned
// parties are actually normal for this deployment.
export const CLEANUP_SWEEP_PARTY_WARNING_THRESHOLD = env.CLEANUP_SWEEP_PARTY_WARNING_THRESHOLD;
