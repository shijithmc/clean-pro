/// Application-wide constants. All values that change per environment
/// are loaded via environment variables injected at build time.
class AppConstants {
  AppConstants._();

  // Sentry
  // FA-004: Sentry DSN must be injected at build time via --dart-define.
  static const String sentryDsn = String.fromEnvironment(
    'SENTRY_DSN',
    defaultValue: '',
  );

  /// FA-004: Fail fast at startup when required build-time config is absent.
  /// Catches the common mistake of running a release build without --dart-define
  /// before it surfaces as a silent runtime failure (no crash reports, no purchases).
  static void assertConfigured() {
    assert(
      revenueCatAppleApiKey.isNotEmpty || revenueCatGoogleApiKey.isNotEmpty,
      'Missing build-time config: RC_APPLE_API_KEY or RC_GOOGLE_API_KEY must '
      'be provided via --dart-define.',
    );
    assert(
      sentryDsn.isNotEmpty,
      'Missing build-time config: SENTRY_DSN must be provided via --dart-define.',
    );
  }

  // RevenueCat
  static const String revenueCatAppleApiKey = String.fromEnvironment(
    'RC_APPLE_API_KEY',
    defaultValue: '',
  );
  static const String revenueCatGoogleApiKey = String.fromEnvironment(
    'RC_GOOGLE_API_KEY',
    defaultValue: '',
  );
  static const String revenueCatEntitlementId = 'pro_access';

  // Product IDs (must match App Store Connect / Google Play Console)
  static const String monthlyProductId = 'cleanpro_monthly';
  static const String annualProductId = 'cleanpro_annual';

  // Backend API
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://api.cleanpro.app/v1',
  );

  // AWS Cognito
  static const String cognitoUserPoolId = String.fromEnvironment(
    'COGNITO_USER_POOL_ID',
    defaultValue: '',
  );
  static const String cognitoClientId = String.fromEnvironment(
    'COGNITO_CLIENT_ID',
    defaultValue: '',
  );
  static const String cognitoRegion = 'ap-southeast-1';

  // Trial
  static const int trialDurationDays = 7;

  // Scan
  static const int scanBatchSize = 100;
  static const int maxPhotosForScan = 50000;
  static const int pHashSimilarityThreshold = 10; // Hamming distance ≤ 10 = near-duplicate

  // AI model asset paths
  static const String mobileNetModelPath = 'assets/models/mobilenet_v3_small_quant.tflite';
  static const int embeddingDimensions = 128;

  // Storage keys
  static const String trialStartDateKey = 'trial_start_date';
  static const String lastScanDateKey = 'last_scan_date';
  static const String onboardingCompleteKey = 'onboarding_complete';
}
