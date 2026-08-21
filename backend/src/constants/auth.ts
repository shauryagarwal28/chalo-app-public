/**
 * Numeric parameters for OTP/JWT behaviour. Source of truth for all of these
 * values is docs/technical/systems/authentication.md — do not re-derive or
 * re-tune them here, this file just centralizes them so no route hardcodes a
 * magic number.
 */

// OTP is a 6-digit code (see generateCode() in services/otp.ts).
export const OTP_LENGTH = 6;

// How long a requested OTP stays valid before it must be re-requested.
export const OTP_TTL_SECONDS = 10 * 60; // 10 minutes

// Wrong-code attempts allowed against a single OTP before lockout.
export const OTP_MAX_VERIFY_ATTEMPTS = 3;

// How long a phone number is locked out of both request-otp and verify-otp
// after hitting OTP_MAX_VERIFY_ATTEMPTS.
export const OTP_LOCKOUT_SECONDS = 30 * 60; // 30 minutes

// Minimum gap between two OTP requests for the same phone number.
export const OTP_RESEND_COOLDOWN_SECONDS = 30;

// Max OTP requests allowed per phone number in a rolling hour.
export const OTP_RATE_LIMIT_MAX_PER_HOUR = 5;
export const OTP_RATE_LIMIT_WINDOW_SECONDS = 60 * 60; // 1 hour

// JWT TTLs.
export const ACCESS_TOKEN_TTL_SECONDS = 15 * 60; // 15 minutes
export const REFRESH_TOKEN_TTL_SECONDS = 30 * 24 * 60 * 60; // 30 days
