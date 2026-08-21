import 'dotenv/config';

// Central place to read process.env, so nothing else in the codebase touches
// `process.env` directly. Task 2 adds JWT_SECRET (signs both access and
// refresh tokens, distinguished by a `type` claim in the payload — see
// src/services/token.ts) — the first real secret this backend handles.
export const env = {
  PORT: Number(process.env.PORT) || 3000,
  NODE_ENV: process.env.NODE_ENV ?? 'development',
  REDIS_URL: process.env.REDIS_URL ?? 'redis://localhost:6379',
  JWT_SECRET: process.env.JWT_SECRET ?? 'dev-insecure-secret-change-me',
  // Task 5 (party WS events): grace period between a party member's WS
  // disconnect and the server broadcasting party:member_left / removing them
  // from the room registry, per backend-mvp-plan.md Task 5's explicit
  // decision to match real-time-location.md's 3-minute reconnect window
  // (a highway dead zone shouldn't look like someone left the party).
  // Overridable via env so a test run can shorten it without touching the
  // 3-minute production default — see constants/party.ts.
  PARTY_MEMBER_LEFT_GRACE_PERIOD_MS:
    Number(process.env.PARTY_MEMBER_LEFT_GRACE_PERIOD_MS) || 3 * 60 * 1000,
  // Task 6 (location relay): TTL on party:{id}:location:{userId}, per
  // data-models.md/real-time-location.md's explicit "TTL: 30s, refreshed on
  // each update". Overridable via env for faster test iteration, same
  // pattern as PARTY_MEMBER_LEFT_GRACE_PERIOD_MS above — the shipped default
  // is 30s.
  LOCATION_TTL_SECONDS: Number(process.env.LOCATION_TTL_SECONDS) || 30,
  // Task 7 (emergency detection engine): all five tunables from
  // technical/systems/emergency-detection.md's "Tunable parameters" table,
  // per that doc's explicit instruction that these are reasoned defaults —
  // NOT validated values — and must be re-tunable after real highway-test
  // false-positive data without an app/server release. Same
  // env-overridable-with-a-shipped-default pattern as
  // PARTY_MEMBER_LEFT_GRACE_PERIOD_MS/LOCATION_TTL_SECONDS above.
  EMERGENCY_UPPER_SPEED_KMPH: Number(process.env.EMERGENCY_UPPER_SPEED_KMPH) || 20,
  EMERGENCY_LOWER_SPEED_KMPH: Number(process.env.EMERGENCY_LOWER_SPEED_KMPH) || 5,
  EMERGENCY_DETECTION_WINDOW_MS: Number(process.env.EMERGENCY_DETECTION_WINDOW_MS) || 5000,
  EMERGENCY_CONFIRMATION_WINDOW_MS: Number(process.env.EMERGENCY_CONFIRMATION_WINDOW_MS) || 60_000,
  EMERGENCY_ROLLING_READINGS: Number(process.env.EMERGENCY_ROLLING_READINGS) || 3,
  // Task 9 (reconnect/cleanup hardening pass): how often the periodic
  // party:* Redis key-set sanity sweep (websocket/cleanupSweep.ts) runs, and
  // how many distinct party IDs represented among party:* keys should trip
  // its "this looks like it's grown unboundedly" warning. Same
  // env-overridable-with-a-shipped-default pattern as every other tunable
  // above — shipped defaults are 5 minutes / 200 parties. This is
  // observability only (logs a warning), never auto-remediation, per
  // backend-mvp-plan.md Task 9's explicit framing.
  CLEANUP_SWEEP_INTERVAL_MS: Number(process.env.CLEANUP_SWEEP_INTERVAL_MS) || 5 * 60 * 1000,
  CLEANUP_SWEEP_PARTY_WARNING_THRESHOLD:
    Number(process.env.CLEANUP_SWEEP_PARTY_WARNING_THRESHOLD) || 200,
  // Task 8 (PTT event relay): TTL on party:{id}:ptt, per data-models.md's
  // explicit "TTL: 60s". Overridable via env for faster test iteration, same
  // pattern as LOCATION_TTL_SECONDS above — the shipped default is 60s.
  PTT_TTL_SECONDS: Number(process.env.PTT_TTL_SECONDS) || 60,
};

export const isProduction = env.NODE_ENV === 'production';

// Fail loudly at startup rather than silently signing production tokens with
// a well-known dev default — same "don't let a placeholder look like it
// works" principle behind agora_ptt_service.dart's init() guard on the
// Flutter side.
if (isProduction && env.JWT_SECRET === 'dev-insecure-secret-change-me') {
  throw new Error('JWT_SECRET must be set via a real environment variable in production.');
}
