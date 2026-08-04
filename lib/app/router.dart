/// Navigation graph.
///
/// The auth gate is declarative: [GoRouter.redirect] reads the session state and
/// sends the user where they belong. No screen ever pushes the login page
/// imperatively, so there is exactly one place that can get sign-in wrong.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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
import '../features/more/presentation/more_screen.dart';
import '../features/profiles/presentation/profile_detail_screen.dart';
import '../features/profiles/presentation/profiles_screen.dart';
import '../features/review/presentation/review_screen.dart';
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

final Provider<GoRouter> routerProvider = Provider<GoRouter>((Ref ref) {
  final TokenStore tokens = ref.watch(tokenStoreProvider);

  final GoRouter router = GoRouter(
    navigatorKey: _rootKey,
    initialLocation: AppRoute.splashPath,
    // TokenStore is a ChangeNotifier, so signing in or out re-evaluates the
    // redirect below without any screen having to navigate.
    refreshListenable: tokens,
    redirect: (BuildContext context, GoRouterState state) {
      final String location = state.matchedLocation;

      // Startup: hold on the splash until the refresh token has been read from
      // the keychain, otherwise the login screen flashes for one frame on every
      // cold start for a signed-in user.
      if (!tokens.isRestored) {
        return location == AppRoute.splashPath ? null : AppRoute.splashPath;
      }

      const Set<String> publicPaths = <String>{
        AppRoute.splashPath,
        AppRoute.welcomePath,
        AppRoute.loginPath,
        AppRoute.registerPath,
        AppRoute.forgotPasswordPath,
      };

      final bool onPublicPage = publicPaths.contains(location);

      if (!tokens.hasSession) {
        return onPublicPage && location != AppRoute.splashPath
            ? null
            : AppRoute.welcomePath;
      }

      // Signed in but sitting on an auth page — go to the app.
      if (onPublicPage) {
        return AppRoute.dashboardPath;
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

      // ---------------------------------------------------------- main shell
      ShellRoute(
        navigatorKey: _shellKey,
        builder: (BuildContext context, GoRouterState state, Widget child) =>
            AppShell(child: child),
        routes: <RouteBase>[
          GoRoute(
            path: AppRoute.dashboardPath,
            name: AppRoute.dashboard,
            pageBuilder: (_, GoRouterState s) =>
                const NoTransitionPage<void>(child: DashboardScreen()),
          ),
          GoRoute(
            path: AppRoute.documentsPath,
            name: AppRoute.documents,
            pageBuilder: (_, GoRouterState s) =>
                const NoTransitionPage<void>(child: DocumentsScreen()),
          ),
          GoRoute(
            path: AppRoute.reviewPath,
            name: AppRoute.review,
            pageBuilder: (_, GoRouterState s) =>
                const NoTransitionPage<void>(child: ReviewScreen()),
          ),
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
      GoRoute(
        parentNavigatorKey: _rootKey,
        path: AppRoute.barcodePath,
        name: AppRoute.barcode,
        builder: (_, __) => const BarcodeScreen(),
      ),
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
      GoRoute(
        parentNavigatorKey: _rootKey,
        path: AppRoute.exportsPath,
        name: AppRoute.exports,
        builder: (_, __) => const ExportsScreen(),
      ),
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
                onPressed: () => context.goNamed(AppRoute.dashboard),
                child: const Text('Go to dashboard'),
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
