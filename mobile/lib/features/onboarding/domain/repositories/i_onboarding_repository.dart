/// Contract for onboarding state persistence.
/// Keeps the presentation layer decoupled from SharedPreferences.
abstract class IOnboardingRepository {
  /// Returns true if the user has already completed onboarding.
  Future<bool> isOnboardingCompleted();

  /// Marks onboarding as completed.
  Future<void> markOnboardingCompleted();
}
