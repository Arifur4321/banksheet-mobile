/// Build-time configuration.
///
/// Values come from `--dart-define` so a single codebase produces dev, staging
/// and production binaries without a code change and without secrets in git.
/// Nothing here is a secret: the mobile API is authenticated per user, and the
/// store product ids are public by definition.
library;

/// Which backend the binary talks to.
enum AppFlavor { dev, staging, prod }

abstract final class AppConfig {
  /// `flutter run --dart-define=BANKSHEET_ENV=dev`
  static const String _rawFlavor = String.fromEnvironment(
    'BANKSHEET_ENV',
    defaultValue: 'prod',
  );

  static AppFlavor get flavor => switch (_rawFlavor) {
        'dev' => AppFlavor.dev,
        'staging' => AppFlavor.staging,
        _ => AppFlavor.prod,
      };

  static bool get isProd => flavor == AppFlavor.prod;

  /// The live deployment the product owner already runs on their VPS.
  static const String _defaultBaseUrl = 'https://banksheet.pro';

  /// Origin only — [Endpoints] appends `/api/mobile/v1`.
  static const String baseUrl = String.fromEnvironment(
    'BANKSHEET_BASE_URL',
    defaultValue: _defaultBaseUrl,
  );

  static String get apiBase => '$baseUrl/api/mobile/v1';

  /// Public marketing/legal pages, served by the same Laravel app.
  static String get privacyUrl => '$baseUrl/privacy';
  static String get termsUrl => '$baseUrl/terms';
  static String get supportUrl => '$baseUrl/contact';
  static String get websiteUrl => baseUrl;

  // --------------------------------------------------------------- timeouts
  static const Duration connectTimeout = Duration(seconds: 20);
  static const Duration receiveTimeout = Duration(seconds: 60);

  /// Uploads and conversions legitimately take minutes on a slow connection.
  static const Duration uploadTimeout = Duration(minutes: 5);

  // ------------------------------------------------------------------- IAP
  /// Product identifiers. These must match App Store Connect and Play Console
  /// exactly, and they must match `config/mobile.php`'s `iap.products` map on
  /// the server — the server is what actually grants the plan.
  static const String starterMonthly = 'pro.banksheet.starter.monthly';
  static const String starterYearly = 'pro.banksheet.starter.yearly';
  static const String professionalMonthly =
      'pro.banksheet.professional.monthly';
  static const String professionalYearly = 'pro.banksheet.professional.yearly';

  /// Yearly plans are built but hidden until the store listings exist.
  static const bool yearlyEnabled = bool.fromEnvironment(
    'BANKSHEET_YEARLY',
  );

  static Set<String> get productIds => <String>{
        starterMonthly,
        professionalMonthly,
        if (yearlyEnabled) starterYearly,
        if (yearlyEnabled) professionalYearly,
      };

  /// Where the OS sends users to cancel or change a subscription. Required by
  /// App Store guideline 3.1.2 and by Play policy.
  static const String appleManageUrl =
      'https://apps.apple.com/account/subscriptions';
  static const String googleManageUrl =
      'https://play.google.com/store/account/subscriptions';

  // ----------------------------------------------------------------- launch
  /// The floor on how long the animated launch screen stays up.
  ///
  /// Restoring the keychain usually takes tens of milliseconds, so without a
  /// floor the launch animation would be replaced mid-first-loop and read as a
  /// flicker. One loop of `PdfLoaderScene` is 2.4s; 1.6s lands just after the
  /// pages have stacked and the badge has popped, which is the frame worth
  /// cutting on. See `SplashHold` in `core/providers.dart`.
  static const Duration minimumSplash = Duration(milliseconds: 1600);

  // ------------------------------------------------------------------- scan
  /// How many PDFs the scanner produces before asking for an account.
  ///
  /// Matches `GUEST_CONVERSION_LIMIT` on the website
  /// (`config/document-conversion.php`), so somebody who tried the web tool and
  /// then installed the app meets the same offer twice rather than two
  /// different ones.
  ///
  /// Counted per install and never reset — see `LocalDb.installUsed`.
  static const int freeScanPdfs = 3;

  // ----------------------------------------------------------------- limits
  /// Mirrors `DocumentController`'s `max:20480` rule on the server. Checked on
  /// device so an oversized file fails instantly instead of after a long upload.
  static const int maxDocumentUploadBytes = 20480 * 1024;

  /// How often a queued document is polled while the screen is open.
  static const Duration pollInterval = Duration(seconds: 3);

  /// Give up polling after this long and let the user pull to refresh.
  static const Duration pollCeiling = Duration(minutes: 10);
}
