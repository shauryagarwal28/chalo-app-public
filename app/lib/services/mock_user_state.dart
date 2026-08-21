/// Prototype-only stand-in for the current user's verification status.
///
/// No auth/backend exists yet, so this is a process-lifetime flag rather
/// than anything persisted. Set true when the KYC demo flow reaches
/// [KycApprovedScreen] (via kyc_pending_screen.dart's "Simulate: Approved"
/// button); checked at the two real KYC gate points per
/// docs/product/features/kyc-verification.md: joining a ride (S12) and
/// posting a ride (S11's Post a Ride entry).
class MockUserState {
  static bool isVerified = false;

  /// Set from `profile_creation_screen.dart`'s "Let's Ride" continue button
  /// (the real signup path: Phone → OTP → Create Profile → Home). Left
  /// `null` if the name field is ever empty/skipped, so `home_screen.dart`'s
  /// greeting can fall back to the generic "Rider" text — same
  /// process-lifetime-only pattern as [isVerified] above, no persistence.
  static String? riderName;
}
