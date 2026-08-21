/**
 * Numeric parameters for the emergency detection engine, per
 * docs/technical/architecture/backend-mvp-plan.md Task 7 and
 * docs/technical/systems/emergency-detection.md's "Tunable parameters"
 * table. Centralized here so no handler/service hardcodes a magic number,
 * matching the pattern set by constants/location.ts and constants/party.ts.
 *
 * All five are sourced from config/env.ts (not hardcoded here) precisely
 * because emergency-detection.md is explicit that these are reasoned
 * defaults, not validated values, and are expected to be re-tuned after real
 * highway-test false-positive data — without needing an app or server
 * release, just an env change.
 */

import { env } from '../config/env';

// Above this, a rider is "moving". Below EMERGENCY_LOWER_SPEED_KMPH, a rider
// is "stopped". Both in kmph, matching location:update's speed unit.
export const UPPER_SPEED_KMPH = env.EMERGENCY_UPPER_SPEED_KMPH;
export const LOWER_SPEED_KMPH = env.EMERGENCY_LOWER_SPEED_KMPH;

// Time window the upper->lower speed drop must happen within to count as a
// trigger, per emergency-detection.md step 2.
export const DETECTION_WINDOW_MS = env.EMERGENCY_DETECTION_WINDOW_MS;

// Stage 2 response window (emergency:confirm's countdown), per
// emergency-detection.md step 4.
export const CONFIRMATION_WINDOW_MS = env.EMERGENCY_CONFIRMATION_WINDOW_MS;
export const CONFIRMATION_WINDOW_SECONDS = Math.round(CONFIRMATION_WINDOW_MS / 1000);

// Number of most-recent raw GPS readings averaged into a rider's "rolling
// speed", per emergency-detection.md step 1 (glitch smoothing).
export const ROLLING_READINGS = env.EMERGENCY_ROLLING_READINGS;

// How stale another party member's last-known rolling speed is allowed to be
// before it stops counting as evidence they're "still moving" for the
// false-positive guard (emergency-detection.md's "at least one other member
// ... at the same timestamp" clause). Not one of the doc's five named
// tunables — deliberately *not* a separate env var so this doesn't become an
// extra untracked knob; derived from DETECTION_WINDOW_MS instead (2x, so it
// naturally follows the same window if that's re-tuned later). See
// websocket/emergency.ts's top-of-file note for the full reasoning.
export const OTHER_MEMBER_STALE_MS = DETECTION_WINDOW_MS * 2;
