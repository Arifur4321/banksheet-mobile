/// Route paths and names in one place.
///
/// Screens navigate with `context.goNamed(AppRoute.documentDetail, ...)` rather
/// than raw strings, so renaming a path is a single edit and a typo is a
/// compile error.
library;

abstract final class AppRoute {
  // ------------------------------------------------------------------- auth
  static const String splash = 'splash';
  static const String splashPath = '/';

  static const String welcome = 'welcome';
  static const String welcomePath = '/welcome';

  static const String login = 'login';
  static const String loginPath = '/login';

  static const String register = 'register';
  static const String registerPath = '/register';

  static const String forgotPassword = 'forgot-password';
  static const String forgotPasswordPath = '/forgot-password';

  // ------------------------------------------------------------- main shell
  static const String dashboard = 'dashboard';
  static const String dashboardPath = '/dashboard';

  static const String documents = 'documents';
  static const String documentsPath = '/documents';

  static const String review = 'review';
  static const String reviewPath = '/review';

  static const String tools = 'tools';
  static const String toolsPath = '/tools';

  static const String more = 'more';
  static const String morePath = '/more';

  // -------------------------------------------------------------- documents
  static const String documentUpload = 'document-upload';
  static const String documentUploadPath = '/documents/upload';

  static const String documentDetail = 'document-detail';
  static const String documentDetailPath = '/documents/:id';

  // ------------------------------------------------------------------ tools
  static const String toolRun = 'tool-run';
  static const String toolRunPath = '/tools/run/:tool';

  static const String conversions = 'conversions';
  static const String conversionsPath = '/tools/conversions';

  static const String barcode = 'barcode';
  static const String barcodePath = '/tools/barcode';

  // --------------------------------------------------------- web extraction
  static const String webExtractions = 'web-extractions';
  static const String webExtractionsPath = '/web-extractions';

  static const String webExtractionCreate = 'web-extraction-create';
  static const String webExtractionCreatePath = '/web-extractions/create';

  static const String webExtractionDetail = 'web-extraction-detail';
  static const String webExtractionDetailPath = '/web-extractions/:id';

  static const String webExtractionResults = 'web-extraction-results';
  static const String webExtractionResultsPath = '/web-extractions/:id/results';

  // -------------------------------------------------------------- templates
  static const String templates = 'templates';
  static const String templatesPath = '/templates';

  static const String templateDetail = 'template-detail';
  static const String templateDetailPath = '/templates/:id';

  static const String generatedPdfs = 'generated-pdfs';
  static const String generatedPdfsPath = '/generated-pdfs';

  // ------------------------------------------------------------- signatures
  static const String signatures = 'signatures';
  static const String signaturesPath = '/signatures';

  static const String signatureDetail = 'signature-detail';
  static const String signatureDetailPath = '/signatures/:id';

  // ---------------------------------------------------------------- exports
  static const String exports = 'exports';
  static const String exportsPath = '/exports';

  // --------------------------------------------------------------- profiles
  static const String profiles = 'profiles';
  static const String profilesPath = '/profiles';

  static const String profileDetail = 'profile-detail';
  static const String profileDetailPath = '/profiles/:id';

  // ---------------------------------------------------------------- billing
  static const String billing = 'billing';
  static const String billingPath = '/billing';

  // --------------------------------------------------------------- settings
  static const String settings = 'settings';
  static const String settingsPath = '/settings';

  static const String editProfile = 'edit-profile';
  static const String editProfilePath = '/settings/profile';

  static const String changePassword = 'change-password';
  static const String changePasswordPath = '/settings/password';

  static const String language = 'language';
  static const String languagePath = '/settings/language';

  static const String apiKeys = 'api-keys';
  static const String apiKeysPath = '/settings/api-keys';

  static const String about = 'about';
  static const String aboutPath = '/settings/about';

  // ----------------------------------------------------------------- viewer
  /// The reader tab, and the landing screen for a signed-out user.
  static const String viewer = 'viewer';
  static const String viewerPath = '/viewer';

  /// The reader itself. Takes `?path=` and `?title=` as query parameters
  /// rather than path segments, because a filesystem path contains slashes and
  /// would otherwise be parsed as extra route segments.
  static const String pdfView = 'pdf-view';
  static const String pdfViewPath = '/viewer/read';
}
