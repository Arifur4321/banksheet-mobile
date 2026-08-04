/// Every path the app calls, in one place.
///
/// These mirror `routes/mobile.php` exactly. Keeping them as constants rather
/// than string literals scattered through repositories means a server-side
/// rename is a one-file change here, and a typo is a compile error rather than
/// a 404 at runtime.
library;

abstract final class Endpoints {
  // ------------------------------------------------------------------ public
  static const String config = '/config';
  static const String health = '/health';

  static const String register = '/auth/register';
  static const String login = '/auth/login';
  static const String refresh = '/auth/refresh';
  static const String forgotPassword = '/auth/forgot-password';
  static const String logout = '/auth/logout';

  // ----------------------------------------------------------------- account
  static const String me = '/me';
  static const String password = '/me/password';
  static const String devices = '/devices';
  static const String currentDevice = '/devices/current';

  // --------------------------------------------------------------- dashboard
  static const String dashboard = '/dashboard';

  // --------------------------------------------------------------- documents
  static const String documents = '/documents';
  static String document(int id) => '/documents/$id';
  static String documentStatus(int id) => '/documents/$id/status';
  static String documentReprocess(int id) => '/documents/$id/reprocess';
  static String documentFile(int id) => '/documents/$id/file';
  static String documentExport(int id) => '/documents/$id/export';
  static String documentApproveAll(int id) =>
      '/documents/$id/transactions/approve-all';

  // ------------------------------------------------------------ transactions
  static const String transactions = '/transactions';
  static String transaction(int id) => '/transactions/$id';

  // -------------------------------------------------------------- profiles
  static const String extractionProfiles = '/extraction-profiles';
  static String extractionProfile(int id) => '/extraction-profiles/$id';
  static String extractionProfileToggle(int id) =>
      '/extraction-profiles/$id/toggle';

  // ---------------------------------------------------------------- exports
  static const String exports = '/exports';
  static String exportDownload(int id) => '/exports/$id/download';

  // ------------------------------------------------------------------ tools
  static const String tools = '/tools';
  static String toolConvert(String tool) => '/tools/$tool/convert';
  static const String conversions = '/tools/conversions';
  static String conversion(int id) => '/tools/conversions/$id';
  static String conversionStatus(int id) => '/tools/conversions/$id/status';
  static String conversionDownload(int id) => '/tools/conversions/$id/download';
  static String conversionRetry(int id) => '/tools/conversions/$id/retry';

  // ---------------------------------------------------------------- barcode
  static const String barcodeSymbologies = '/barcode/symbologies';
  static const String barcodePreview = '/barcode/preview';
  static const String barcode = '/barcode';
  static String barcodeDownload(int id, String format) =>
      '/barcode/$id/download/$format';

  // --------------------------------------------------------- web extraction
  static const String webExtractions = '/web-extractions';
  static String webExtraction(int id) => '/web-extractions/$id';
  static String webExtractionResults(int id) => '/web-extractions/$id/results';
  static String webExtractionRetry(int id) => '/web-extractions/$id/retry';
  static String webExtractionCancel(int id) => '/web-extractions/$id/cancel';
  static String webExtractionExport(int id, String format) =>
      '/web-extractions/$id/export/$format';

  // -------------------------------------------------------------- templates
  static const String templates = '/templates';
  static String template(int id) => '/templates/$id';
  static String templateGenerate(int id) => '/templates/$id/generate';

  static const String generatedPdfs = '/generated-pdfs';
  static String generatedPdf(int id) => '/generated-pdfs/$id';
  static String generatedPdfDownload(int id) => '/generated-pdfs/$id/download';

  // ------------------------------------------------------------- signatures
  static const String signatures = '/signatures';
  static String signature(int id) => '/signatures/$id';
  static String signatureDownload(int id) => '/signatures/$id/download';

  // --------------------------------------------------------------- api keys
  static const String apiKeys = '/api-keys';
  static String apiKey(int id) => '/api-keys/$id';

  // ---------------------------------------------------------------- billing
  static const String billing = '/billing';
  static const String purchaseApple = '/billing/purchases/apple';
  static const String purchaseGoogle = '/billing/purchases/google';
  static const String restorePurchases = '/billing/purchases/restore';
}
