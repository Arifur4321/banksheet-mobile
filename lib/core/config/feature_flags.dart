/// What this build actually ships.
///
/// v1.0 is the Play closed-test build. Its story is "a PDF reader that also
/// converts, extracts, signs and barcodes" — so the reader, the tools, the
/// bank-statement pipeline, e-signature, barcode and billing are on, and the
/// long tail of the website is off.
///
/// Nothing here deletes code. Every screen listed below is written, wired and
/// tested; a flag only decides whether the router mounts it and whether the
/// navigation offers it. That matters for two reasons: every extra screen is
/// another surface a store reviewer can question, and twelve closed testers can
/// only walk so many paths before the 14-day clock runs out.
///
/// Each flag is a `bool.fromEnvironment`, so a feature comes back for one build
/// with no code edit at all:
///
/// ```
/// flutter run --dart-define=BANKSHEET_FEATURE_WEB_EXTRACTION=true
/// ```
///
/// When a flag is turned back on permanently, change the `defaultValue` here —
/// do not scatter the decision across screens.
library;

abstract final class Features {
  // ------------------------------------------------------------------ v1: on

  /// The bank-statement pipeline: upload, extraction, inline transaction
  /// review and XLSX / CSV / JSON export.
  ///
  /// Note this covers reviewing transactions *inside* a document; it is the
  /// standalone cross-document review queue that [reviewQueue] gates.
  static const bool documents = bool.fromEnvironment(
    'BANKSHEET_FEATURE_DOCUMENTS',
    defaultValue: true,
  );

  /// The 13 server-side conversion tools: PDF to DOCX, DOCX to PDF, image to
  /// PDF, merge, split, compress, rotate and the rest.
  static const bool tools = bool.fromEnvironment(
    'BANKSHEET_FEATURE_TOOLS',
    defaultValue: true,
  );

  /// Barcode generation, and stamping a barcode onto a PDF.
  static const bool barcode = bool.fromEnvironment(
    'BANKSHEET_FEATURE_BARCODE',
    defaultValue: true,
  );

  /// Internal e-signature: send for signing, track signers, download the
  /// signed PDF.
  static const bool signatures = bool.fromEnvironment(
    'BANKSHEET_FEATURE_SIGNATURES',
    defaultValue: true,
  );

  /// The export archive — every XLSX / CSV / JSON the workspace has produced.
  static const bool exports = bool.fromEnvironment(
    'BANKSHEET_FEATURE_EXPORTS',
    defaultValue: true,
  );

  /// Plans, in-app purchase and restore. Turning this off would leave the app
  /// with no way to raise a limit, so it is on in every build that has quotas.
  static const bool billing = bool.fromEnvironment(
    'BANKSHEET_FEATURE_BILLING',
    defaultValue: true,
  );

  // ----------------------------------------------------------- v1: off

  /// The standalone cross-document review queue with swipe approve / reject.
  ///
  /// Off for v1 because the same transactions are reviewable inside the
  /// document detail screen, and a second entry point to the same work is a
  /// tester's first "which one am I supposed to use?".
  static const bool reviewQueue = bool.fromEnvironment(
    'BANKSHEET_FEATURE_REVIEW_QUEUE',
    defaultValue: false,
  );

  /// Web-to-Excel contact crawling.
  ///
  /// On since the flag and the navigation disagreed: the Tools tab, the More
  /// tab and the dashboard all offered "Web extraction" unconditionally while
  /// this flag kept `lib/app/router.dart` from registering the route, so every
  /// one of those taps hit go_router with a name it had never heard of. The
  /// screens are now gated on the flag as well (so turning it off is safe), and
  /// the feature itself is wanted, so it ships.
  static const bool webExtraction = bool.fromEnvironment(
    'BANKSHEET_FEATURE_WEB_EXTRACTION',
    defaultValue: true,
  );

  /// HTML templates and the generated-PDF library. Authoring belongs on the
  /// website; the phone only ever consumed the output.
  static const bool templates = bool.fromEnvironment(
    'BANKSHEET_FEATURE_TEMPLATES',
    defaultValue: false,
  );

  /// Extraction profile management. Power-user configuration for recurring
  /// statement layouts — created once on the website, not tuned on a phone.
  static const bool extractionProfiles = bool.fromEnvironment(
    'BANKSHEET_FEATURE_EXTRACTION_PROFILES',
    defaultValue: false,
  );

  /// REST API key management. A developer surface; showing it in a consumer
  /// build invites "what is this for?" from reviewers and testers alike.
  static const bool apiKeys = bool.fromEnvironment(
    'BANKSHEET_FEATURE_API_KEYS',
    defaultValue: false,
  );

  /// The metrics dashboard. Genuinely useful, but it is the second screen a
  /// reader-first app should show, not the first — so for v1 it lives under
  /// More rather than owning a tab.
  static const bool dashboardTab = bool.fromEnvironment(
    'BANKSHEET_FEATURE_DASHBOARD_TAB',
    defaultValue: false,
  );

  /// Every flag in one place, for the diagnostics panel in Settings > About.
  /// Keep this in sync when adding a flag — a build whose behaviour cannot be
  /// read off a support screenshot is a build you debug by guessing.
  static Map<String, bool> get all => const <String, bool>{
        'documents': documents,
        'tools': tools,
        'barcode': barcode,
        'signatures': signatures,
        'exports': exports,
        'billing': billing,
        'review_queue': reviewQueue,
        'web_extraction': webExtraction,
        'templates': templates,
        'extraction_profiles': extractionProfiles,
        'api_keys': apiKeys,
        'dashboard_tab': dashboardTab,
      };
}
