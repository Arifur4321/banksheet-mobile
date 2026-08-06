/// The settings list.
///
/// Five destinations, a sign-out, and a deletion that is visually and
/// physically separated from everything above it. Nothing here manages a team:
/// members, invitations and roles stay on the website, where the consequences
/// of a mis-tap are visible on a screen big enough to show them.
///
/// The change-password row is hidden for an account that signs in with Google.
/// `UserResource` publishes `auth_provider` precisely so the app can do this —
/// such an account has a password row in the database, but it is random and
/// changing it would accomplish nothing.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../core/config/feature_flags.dart';
import '../../../core/i18n/strings.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/hero_scenes.dart';
import '../../../core/widgets/page_scaffold.dart';
import '../../../core/widgets/states.dart';
import '../../auth/domain/session.dart';
import '../../auth/presentation/auth_controller.dart';
import '../domain/server_config.dart';
import 'delete_account_sheet.dart';
import 'providers.dart';
import 'widgets/nav_row.dart';
import 'widgets/settings_group.dart';
import 'widgets/settings_row.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppUser? user = ref.watch(currentUserProvider);

    // The bundled catalogue is the same list the server reads from, so the row
    // can name the current language even when `/config` has not landed yet.
    final ServerConfig config =
        ref.watch(serverConfigProvider).valueOrNull ?? ServerConfig.fallback;
    final String localeCode = ref.watch(localeControllerProvider).code;
    final AppLocale? locale = config.locale(localeCode);

    return HeroPageScaffold(
      onRefresh: () async {
        ref.invalidate(serverConfigProvider);
        await ref.read(authControllerProvider.notifier).refreshSession();
      },
      slivers: <Widget>[
        const SliverAppBar(
          floating: true,
          toolbarHeight: 52,
          titleSpacing: AppSpacing.lg,
          title: Text(S.settings),
        ),
        const SliverPadding(
          padding: EdgeInsets.fromLTRB(
            AppSpacing.page,
            0,
            AppSpacing.page,
            AppSpacing.lg,
          ),
          sliver: SliverToBoxAdapter(
            child: HeroPanel(
              eyebrow: S.settings,
              title: S.settingsHeroTitle,
              scene: AccountScene(),
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.page,
            0,
            AppSpacing.page,
            AppSpacing.section,
          ),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                SettingsGroup(
                  title: S.sectionAccount,
                  children: <Widget>[
                    NavRow(
                      icon: Icons.person_outline_rounded,
                      label: S.profile,
                      description: S.profileSubtitle,
                      trailingLabel: user?.name,
                      onTap: () => context.pushNamed(AppRoute.editProfile),
                    ),
                    if (user == null || user.canChangePassword)
                      NavRow(
                        icon: Icons.lock_outline_rounded,
                        label: S.changePassword,
                        description: S.changePasswordSubtitle,
                        onTap: () => context.pushNamed(AppRoute.changePassword),
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xxl),
                SettingsGroup(
                  title: S.sectionPreferences,
                  children: <Widget>[
                    NavRow(
                      icon: Icons.translate_rounded,
                      label: S.language,
                      description: S.languageSubtitle,
                      trailingLabel: locale?.native ?? localeCode.toUpperCase(),
                      onTap: () => context.pushNamed(AppRoute.language),
                    ),
                  ],
                ),
                // The whole group, not just the row: with Features.apiKeys off
                // the route is not registered, so the only thing in here is a
                // tap that throws — and an empty "Developer" heading would be
                // worse than no heading.
                if (Features.apiKeys) ...<Widget>[
                  const SizedBox(height: AppSpacing.xxl),
                  SettingsGroup(
                    title: S.sectionDeveloper,
                    children: <Widget>[
                      NavRow(
                        icon: Icons.vpn_key_outlined,
                        label: S.apiKeys,
                        description: S.apiKeysSubtitle,
                        onTap: () => context.pushNamed(AppRoute.apiKeys),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: AppSpacing.xxl),
                SettingsGroup(
                  title: S.sectionSupport,
                  children: <Widget>[
                    NavRow(
                      icon: Icons.info_outline_rounded,
                      label: S.about,
                      description: S.aboutSubtitle,
                      onTap: () => context.pushNamed(AppRoute.about),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xxl),
                SettingsGroup(
                  children: <Widget>[
                    SettingsRow(
                      icon: Icons.logout_rounded,
                      label: S.signOut,
                      showChevron: false,
                      onTap: () => _signOut(context, ref),
                    ),
                  ],
                ),

                // The destructive section is deliberately far down, under its
                // own heading, in its own red-ringed card: it must never be the
                // thing a thumb finds by accident on the way to sign out.
                const SizedBox(height: AppSpacing.section),
                SettingsGroup(
                  title: S.dangerZone,
                  borderColor: AppColors.danger.withValues(alpha: 0.24),
                  footnote: S.deleteAccountBody,
                  children: <Widget>[
                    SettingsRow(
                      icon: Icons.delete_forever_rounded,
                      label: S.deleteAccount,
                      tone: SettingsRowTone.destructive,
                      showChevron: false,
                      onTap: () => _deleteAccount(context, ref),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _signOut(BuildContext context, WidgetRef ref) async {
    final bool confirmed = await confirmAction(
      context,
      title: S.signOutConfirm,
      message: S.signOutConfirmBody,
      confirmLabel: S.signOut,
      destructive: true,
    );

    if (!confirmed) {
      return;
    }

    // No navigation afterwards: clearing the tokens moves the router on its
    // own, and a second push would race it.
    await ref.read(authControllerProvider.notifier).signOut();
  }

  Future<void> _deleteAccount(BuildContext context, WidgetRef ref) async {
    final bool deleted = await showDeleteAccountSheet(context);

    if (!deleted || !context.mounted) {
      return;
    }

    // The sheet has already ended the session; this only confirms it. The
    // snackbar lives on the root messenger, so it survives the route change to
    // the welcome screen.
    Toast.success(context, S.accountDeleted);
  }
}
