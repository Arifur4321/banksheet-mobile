/// Navigation graph.
///
/// Two things are decided here and nowhere else.
///
/// **The auth gate.** [GoRouter.redirect] reads the session and sends the user
/// where they belong. No screen ever pushes the login page imperatively, so
/// there is exactly one place that can get sign-in wrong.
///
/// **What a signed-out user may reach.** Two things, both in [_guestPaths]: the
/// reader and the scanner. Both operate entirely on files already on the user's
/// own phone and make no authenticated call, which is the test for being on
/// that list. Everything else still requires a session. The gate is a deny-list
/// turned inside out: a new route is private unless someone deliberately adds
/// it, which is the right default for a product holding other people's bank
/// statements.
///
/// **What exists at all.** Routes the v1 [Features] flags turn off are not
/// registered, so a stale deep link lands on the error page rather than on a
/// half-supported screen. Turning a flag back on restores its route with no
/// other edit.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/config/feature_flags.dart';
import '../core/network/token_store.dart';
import '../core/providers.dart';
import '../features/auth/presentation/forgot_password_screen.dart';
import '../features/auth/presentation/login_screen.dart';
import '../features/auth/presentation/register_screen.dart';
import '../features/auth/presentation/splash_screen.dart';
import '../features/auth/presentation/welcome_screen.dart';
import '../features/barcode/presentation/barcode_screen.dart';
import '../features/billing/presentation/billing_screen.dart';
import '../features/dashboard/presentation/dashboard_screen.dart';
import '../features/documents/presentation/document_detail_screen.dart';
import '../features/documents/presentation/document_upload_screen.dart';
import '../features/documents/presentation/documents_screen.dart';
import '../features/exports/presentation/exports_screen.dart';
import '../features/home/presentation/home_screen.dart';
import '../features/more/presentation/more_screen.dart';
import '../features/profiles/presentation/profile_detail_screen.dart';
import '../features/profiles/presentation/profiles_screen.dart';
import '../features/review/presentation/review_screen.dart';
import '../features/scan/domain/scan_page.dart';
import '../features/scan/presentation/scan_screen.dart';
import '../features/settings/presentation/about_screen.dart';
import '../features/settings/presentation/api_keys_screen.dart';
import '../features/settings/presentation/change_password_screen.dart';
import '../features/settings/presentation/edit_profile_screen.dart';
import '../features/settings/presentation/language_screen.dart';
import '../features/settings/presentation/settings_screen.dart';
import '../features/signatures/presentation/signature_detail_screen.dart';
import '../features/signatures/presentation/signatures_screen.dart';
import '../features/templates/presentation/generated_pdfs_screen.dart';
import '../features/templates/presentation/template_detail_screen.dart';
import '../features/templates/presentation/templates_screen.dart';
import '../features/tools/presentation/conversions_screen.dart';
import '../features/tools/presentation/tool_run_screen.dart';
import '../features/tools/presentation/tools_screen.dart';
import '../features/viewer/presentation/pdf_viewer_screen.dart';
import '../features/web_extraction/presentation/web_extraction_create_screen.dart';
import '../features/web_extraction/presentation/web_extraction_detail_screen.dart';
import '../features/web_extraction/presentation/web_extraction_results_screen.dart';
import '../features/web_extraction/presentation/web_extractions_screen.dart';
import 'routes.dart';
import 'shell.dart';

final GlobalKey<NavigatorState> _rootKey = GlobalKey<NavigatorState>(
  debugLabel: 'root',
);
final GlobalKey<NavigatorState> _shellKey = GlobalKey<NavigatorState>(
  debugLabel: 'shell',
);

/// Reachable with no session at all.
///
/// Keep this list short and justify every addition. Both entries operate
/// entirely on files the user already has on their own phone: they make no
/// authenticated call and read nothing from the workspace. The scanner is
/// metered on the device instead — see `AppConfig.freeScanPdfs`.
const Set<String> _guestPaths = <String>{
  AppRoute.pdfViewPath,
  AppRoute.scanPath,
};

/// The auth screens, which a signed-in user should never sit on.
const Set<String> _publicPaths = <String>{
  AppRoute.splashPath,
  AppRoute.welcomePath,
  AppRoute.loginPath,
  AppRoute.registerPath,
  AppRoute.forgotPasswordPath,
};

final Provider<GoRouter> routerProvider = Provider<GoRouter>((Ref ref) {
  final TokenStore tokens = ref.watch(tokenStoreProvider);
  final SplashHold splash = ref.watch(splashHoldProvider);

  final GoRouter router = GoRouter(
    navigatorKey: _rootKey,
    initialLocation: AppRoute.splashPath,
    // TokenStore is a ChangeNotifier, so signing in or out re-evaluates the
    // redirect below without any screen having to navigate. SplashHold is the
    // second notifier: it fires once the launch animation's minimum has
    // elapsed, which is the other thing that can unblock the splash.
    refreshListenable: Listenable.merge(<Listenable>[tokens, splash]),
    redirect: (BuildContext context, GoRouterState state) {
      final String location = state.matchedLocation;

      // Startup: hold on the splash until the refresh token has been read from
      // the keychain — otherwise the welcome screen flashes for one frame on
      // every cold start for a signed-in user — and until the launch animation
      // has had its minimum beat, so it reads as a launch rather than a blink.
      if (!tokens.isRestored || !splash.elapsed) {
        return location == AppRoute.splashPath ? null : AppRoute.splashPath;
      }

      final bool onPublicPage = _publicPaths.contains(location);
      final bool onGuestPage = _guestPaths.any(
        (String p) => location == p || location.startsWith('$p/'),
      );

      if (!tokens.hasSession) {
        // The reader and the scanner are open to everyone.
        if (onGuestPage) {
          return null;
        }
        // Signing in, registering or recovering a password.
        if (onPublicPage && location != AppRoute.splashPath) {
          return null;
        }
        // Cold start, or a deep link into the workspace with no session.
        // The welcome screen carries both the pitch and the two actions a
        // signed-out user can take, so it is the only landing place — there is
        // no separate guest home to fall through to any more, which is also
        // why `hasOnboarded` no longer changes the destination.
        return AppRoute.welcomePath;
      }

      // Signed in but sitting on an auth page — go to the app.
      if (onPublicPage) {
        return AppRoute.homePath;
      }

      return null;
    },
    routes: <RouteBase>[
      GoRoute(
        path: AppRoute.splashPath,
        name: AppRoute.splash,
        builder: (_, __) => const SplashScreen(),
      ),
      GoRoute(
        path: AppRoute.welcomePath,
        name: AppRoute.welcome,
        builder: (_, __) => const WelcomeScreen(),
      ),
      GoRoute(
        path: AppRoute.loginPath,
        name: AppRoute.login,
        builder: (_, __) => const LoginScreen(),
      ),
      GoRoute(
        path: AppRoute.registerPath,
        name: AppRoute.register,
        builder: (_, __) => const RegisterScreen(),
      ),
      GoRoute(
        path: AppRoute.forgotPasswordPath,
        name: AppRoute.forgotPassword,
        builder: (_, __) => const ForgotPasswordScreen(),
      ),

      // The reader, full screen and outside the shell: reading a document
      // should not carry a navigation bar competing for the page.
      GoRoute(
        parentNavigatorKey: _rootKey,
        path: AppRoute.pdfViewPath,
        name: AppRoute.pdfView,
        builder: (_, GoRouterState s) => PdfViewerScreen(
          path: s.uri.queryParameters['path'] ?? '',
          title: s.uri.queryParameters['title'] ?? 'Document',
        ),
      ),

      // The scanner, likewise full screen. It owns a camera, a page list and
      // its own bottom action bar; a navigation bar underneath all of that
      // would offer the user a way to walk away from unsaved captures with one
      // mis-tap.
      GoRoute(
        parentNavigatorKey: _rootKey,
        path: AppRoute.scanPath,
        name: AppRoute.scan,
        builder: (_, GoRouterState s) => ScanScreen(
          startWith: switch (s.uri.queryParameters['source']) {
            'camera' => ScanSource.camera,
            'gallery' => ScanSource.gallery,
            _ => null,
          },
        ),
      ),

      // ---------------------------------------------------------- main shell
      ShellRoute(
        navigatorKey: _shellKey,
        builder: (BuildContext context, GoRouterState state, Widget child) =>
            AppShell(child: child),
        routes: <RouteBase>[
          GoRoute(
            path: AppRoute.homePath,
            name: AppRoute.home,
            pageBuilder: (_, GoRouterState s) =>
                const NoTransitionPage<void>(child: HomeScreen()),
          ),
          GoRoute(
            path: AppRoute.dashboardPath,
            name: AppRoute.dashboard,
            pageBuilder: (_, GoRouterState s) =>
                const NoTransitionPage<void>(child: DashboardScreen()),
          ),
          if (Features.documents)
            GoRoute(
              path: AppRoute.documentsPath,
              name: AppRoute.documents,
              pageBuilder: (_, GoRouterState s) =>
                  const NoTransitionPage<void>(child: DocumentsScreen()),
            ),
          if (Features.reviewQueue)
            GoRoute(
              path: AppRoute.reviewPath,
              name: AppRoute.review,
              pageBuilder: (_, GoRouterState s) =>
                  const NoTransitionPage<void>(child: ReviewScreen()),
            ),
          if (Features.tools)
            GoRoute(
              path: AppRoute.toolsPath,
              name: AppRoute.tools,
              pageBuilder: (_, GoRouterState s) =>
                  const NoTransitionPage<void>(child: ToolsScreen()),
            ),
          GoRoute(
            path: AppRoute.morePath,
            name: AppRoute.more,
            pageBuilder: (_, GoRouterState s) =>
                const NoTransitionPage<void>(child: MoreScreen()),
          ),
        ],
      ),

      // ------------------------------------------------- full-screen routes
      if (Features.documents) ...<RouteBase>[
        GoRoute(
          parentNavigatorKey: _rootKey,
          path: AppRoute.documentUploadPath,
          name: AppRoute.documentUpload,
          builder: (_, __) => const DocumentUploadScreen(),
        ),
        GoRoute(
          parentNavigatorKey: _rootKey,
          path: AppRoute.documentDetailPath,
          name: AppRoute.documentDetail,
          builder: (_, GoRouterState s) =>
              DocumentDetailScreen(documentId: _id(s)),
        ),
      ],
      if (Features.tools) ...<RouteBase>[
        GoRoute(
          parentNavigatorKey: _rootKey,
          path: AppRoute.toolRunPath,
          name: AppRoute.toolRun,
          builder: (_, GoRouterState s) =>
              ToolRunScreen(toolKey: s.pathParameters['tool'] ?? ''),
        ),
        GoRoute(
          parentNavigatorKey: _rootKey,
          path: AppRoute.conversionsPath,
          name: AppRoute.conversions,
          builder: (_, __) => const ConversionsScreen(),
        ),
      ],
      if (Features.barcode)
        GoRoute(
          parentNavigatorKey: _rootKey,
          path: AppRoute.barcodePath,
          name: AppRoute.barcode,
          builder: (_, __) => const BarcodeScreen(),
        ),
      if (Features.webExtraction)
        GoRoute(
          parentNavigatorKey: _rootKey,
          path: AppRoute.webExtractionsPath,
          name: AppRoute.webExtractions,
          builder: (_, __) => const WebExtractionsScreen(),
          routes: <RouteBase>[
            GoRoute(
              parentNavigatorKey: _rootKey,
              path: 'create',
              name: AppRoute.webExtractionCreate,
              builder: (_, __) => const WebExtractionCreateScreen(),
            ),
            GoRoute(
              parentNavigatorKey: _rootKey,
              path: ':id',
              name: AppRoute.webExtractionDetail,
              builder: (_, GoRouterState s) =>
                  WebExtractionDetailScreen(jobId: _id(s)),
              routes: <RouteBase>[
                GoRoute(
                  parentNavigatorKey: _rootKey,
                  path: 'results',
                  name: AppRoute.webExtractionResults,
                  builder: (_, GoRouterState s) =>
                      WebExtractionResultsScreen(jobId: _id(s)),
                ),
              ],
            ),
          ],
        ),
      if (Features.templates) ...<RouteBase>[
        GoRoute(
          parentNavigatorKey: _rootKey,
          path: AppRoute.templatesPath,
          name: AppRoute.templates,
          builder: (_, __) => const TemplatesScreen(),
          routes: <RouteBase>[
            GoRoute(
              parentNavigatorKey: _rootKey,
              path: ':id',
              name: AppRoute.templateDetail,
              builder: (_, GoRouterState s) =>
                  TemplateDetailScreen(templateId: _id(s)),
            ),
          ],
        ),
        GoRoute(
          parentNavigatorKey: _rootKey,
          path: AppRoute.generatedPdfsPath,
          name: AppRoute.generatedPdfs,
          builder: (_, __) => const GeneratedPdfsScreen(),
        ),
      ],
      if (Features.signatures)
        GoRoute(
          parentNavigatorKey: _rootKey,
          path: AppRoute.signaturesPath,
          name: AppRoute.signatures,
          builder: (_, __) => const SignaturesScreen(),
          routes: <RouteBase>[
            GoRoute(
              parentNavigatorKey: _rootKey,
              path: ':id',
              name: AppRoute.signatureDetail,
              builder: (_, GoRouterState s) =>
                  SignatureDetailScreen(signatureId: _id(s)),
            ),
          ],
        ),
      if (Features.exports)
        GoRoute(
          parentNavigatorKey: _rootKey,
          path: AppRoute.exportsPath,
          name: AppRoute.exports,
          builder: (_, __) => const ExportsScreen(),
        ),
      if (Features.extractionProfiles)
        GoRoute(
          parentNavigatorKey: _rootKey,
          path: AppRoute.profilesPath,
          name: AppRoute.profiles,
          builder: (_, __) => const ProfilesScreen(),
          routes: <RouteBase>[
            GoRoute(
              parentNavigatorKey: _rootKey,
              path: ':id',
              name: AppRoute.profileDetail,
              builder: (_, GoRouterState s) =>
                  ProfileDetailScreen(profileId: _id(s)),
            ),
          ],
        ),
      if (Features.billing)
        GoRoute(
          parentNavigatorKey: _rootKey,
          path: AppRoute.billingPath,
          name: AppRoute.billing,
          builder: (_, __) => const BillingScreen(),
        ),
      GoRoute(
        parentNavigatorKey: _rootKey,
        path: AppRoute.settingsPath,
        name: AppRoute.settings,
        builder: (_, __) => const SettingsScreen(),
        routes: <RouteBase>[
          GoRoute(
            parentNavigatorKey: _rootKey,
            path: 'profile',
            name: AppRoute.editProfile,
            builder: (_, __) => const EditProfileScreen(),
          ),
          GoRoute(
            parentNavigatorKey: _rootKey,
            path: 'password',
            name: AppRoute.changePassword,
            builder: (_, __) => const ChangePasswordScreen(),
          ),
          GoRoute(
            parentNavigatorKey: _rootKey,
            path: 'language',
            name: AppRoute.language,
            builder: (_, __) => const LanguageScreen(),
          ),
          if (Features.apiKeys)
            GoRoute(
              parentNavigatorKey: _rootKey,
              path: 'api-keys',
              name: AppRoute.apiKeys,
              builder: (_, __) => const ApiKeysScreen(),
            ),
          GoRoute(
            parentNavigatorKey: _rootKey,
            path: 'about',
            name: AppRoute.about,
            builder: (_, __) => const AboutScreen(),
          ),
        ],
      ),
    ],
    errorBuilder: (BuildContext context, GoRouterState state) => Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(Icons.explore_off_rounded, size: 48),
              const SizedBox(height: 16),
              const Text('That screen does not exist.'),
              const SizedBox(height: 16),
              FilledButton(
                // `go` on a path rather than `goNamed`: the home route only
                // exists behind the auth gate, and a signed-out user landing
                // here needs the redirect to send them to welcome instead of
                // the router throwing on an unreachable name.
                onPressed: () => context.go(AppRoute.homePath),
                child: const Text('Go to the start'),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  ref.onDispose(router.dispose);
  return router;
});

/// Parses an `:id` path parameter, falling back to 0 so a malformed deep link
/// lands on a "not found" state inside the screen rather than crashing here.
int _id(GoRouterState state) => int.tryParse(state.pathParameters['id'] ?? '') ?? 0;
