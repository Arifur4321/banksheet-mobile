/// The fifth tab: everything the four other tabs could not hold.
///
/// The website's sidebar has nineteen entries. A phone can carry five tabs, so
/// the four that matter daily are tabs and the rest live here, grouped the way
/// the work is actually shaped: what you produce (Work), what you keep
/// (Documents), what you convert (Tools), and who you are (Account).
///
/// There is deliberately nothing about the team on this screen. Inviting,
/// removing and re-roling people has consequences that are hard to see on a
/// phone, so it stays on the web — `CompanyResource` publishes a member count
/// and nothing else, and this screen does not even show that.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../core/i18n/strings.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/hero_scenes.dart';
import '../../../core/widgets/page_scaffold.dart';
import '../../../core/widgets/states.dart';
import '../../auth/domain/session.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../settings/presentation/widgets/nav_row.dart';
import '../../settings/presentation/widgets/settings_group.dart';

class MoreScreen extends ConsumerWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Session? session = ref.watch(sessionProvider);

    return HeroPageScaffold(
      onRefresh: () =>
          ref.read(authControllerProvider.notifier).refreshSession(),
      slivers: <Widget>[
        const SliverPadding(
          padding: EdgeInsets.fromLTRB(
            AppSpacing.page,
            AppSpacing.md,
            AppSpacing.page,
            AppSpacing.lg,
          ),
          sliver: SliverToBoxAdapter(
            child: HeroPanel(
              eyebrow: S.more,
              title: S.moreHeroTitle,
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
                _AccountHeader(session: session),
                const SizedBox(height: AppSpacing.xxl),
                SettingsGroup(
                  title: S.sectionWork,
                  children: <Widget>[
                    NavRow(
                      icon: Icons.travel_explore_rounded,
                      label: S.webExtraction,
                      description: S.webExtractionSubtitle,
                      onTap: () => context.pushNamed(AppRoute.webExtractions),
                    ),
                    NavRow(
                      icon: Icons.tune_rounded,
                      label: S.profiles,
                      description: S.profilesSubtitle,
                      onTap: () => context.pushNamed(AppRoute.profiles),
                    ),
                    NavRow(
                      icon: Icons.inventory_2_outlined,
                      label: S.exports,
                      description: S.exportsSubtitle,
                      onTap: () => context.pushNamed(AppRoute.exports),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xxl),
                SettingsGroup(
                  title: S.documents,
                  children: <Widget>[
                    NavRow(
                      icon: Icons.article_outlined,
                      label: S.templates,
                      description: S.templatesSubtitle,
                      onTap: () => context.pushNamed(AppRoute.templates),
                    ),
                    NavRow(
                      icon: Icons.picture_as_pdf_outlined,
                      label: S.generatedPdfs,
                      description: S.generatedPdfsSubtitle,
                      onTap: () => context.pushNamed(AppRoute.generatedPdfs),
                    ),
                    NavRow(
                      icon: Icons.draw_outlined,
                      label: S.signatures,
                      description: S.signaturesSubtitle,
                      onTap: () => context.pushNamed(AppRoute.signatures),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xxl),
                SettingsGroup(
                  title: S.sectionTools,
                  children: <Widget>[
                    NavRow(
                      icon: Icons.qr_code_2_rounded,
                      label: S.barcode,
                      description: S.barcodeSubtitle,
                      onTap: () => context.pushNamed(AppRoute.barcode),
                    ),
                    NavRow(
                      icon: Icons.history_rounded,
                      label: S.conversionHistory,
                      description: S.conversionsSubtitle,
                      onTap: () => context.pushNamed(AppRoute.conversions),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xxl),
                SettingsGroup(
                  title: S.sectionAccount,
                  children: <Widget>[
                    NavRow(
                      icon: Icons.credit_card_rounded,
                      label: S.billing,
                      description: S.billingSubtitle,
                      trailingLabel: session?.workspace.planLabel,
                      // A nudge, not a sales pitch: only when there is nothing
                      // to manage yet.
                      badgeLabel: _canUpgrade(session) ? S.upgrade : null,
                      onTap: () => context.pushNamed(AppRoute.billing),
                    ),
                    NavRow(
                      icon: Icons.settings_rounded,
                      label: S.settings,
                      description: S.settingsSubtitle,
                      onTap: () => context.pushNamed(AppRoute.settings),
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

  static bool _canUpgrade(Session? session) =>
      session != null && !session.workspace.onPaidPlan;
}

/// Who is signed in and where they are working.
///
/// Both facts belong together: an accountant with a workspace per client needs
/// to know which one they are about to change the settings of.
class _AccountHeader extends StatelessWidget {
  const _AccountHeader({this.session});

  final Session? session;

  @override
  Widget build(BuildContext context) {
    final Session? current = session;

    if (current == null) {
      return const AppCard(
        child: Row(
          children: <Widget>[
            Skeleton(width: 52, height: 52, radius: 26),
            SizedBox(width: AppSpacing.lg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Skeleton(width: 140, height: 15),
                  SizedBox(height: 8),
                  Skeleton(width: 190, height: 11),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final AppUser user = current.user;
    final Workspace workspace = current.workspace;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              _Avatar(user: user),
              const SizedBox(width: AppSpacing.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      user.name.isEmpty ? user.firstName : user.name,
                      style: AppText.h3,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      user.email,
                      style: AppText.bodySm,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (workspace.name.isNotEmpty) ...<Widget>[
            const SizedBox(height: AppSpacing.lg),
            const SizedBox(height: 1, child: ColoredBox(color: AppColors.border)),
            const SizedBox(height: AppSpacing.lg),
            Row(
              children: <Widget>[
                const Icon(
                  Icons.business_rounded,
                  size: 17,
                  color: AppColors.inkMuted,
                ),
                const SizedBox(width: AppSpacing.sm),
                Text(S.workspaceLabel, style: AppText.bodySm),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    workspace.name,
                    style: AppText.bodySm.copyWith(color: AppColors.ink),
                    textAlign: TextAlign.end,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.user});

  final AppUser user;

  @override
  Widget build(BuildContext context) {
    final String? avatar = user.avatarUrl;

    return ExcludeSemantics(
      child: Container(
        width: 52,
        height: 52,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.brandTint,
          border: Border.all(color: AppColors.brandTintStrong),
        ),
        child: avatar == null
            ? _initials()
            : ClipOval(
                child: Image.network(
                  avatar,
                  width: 52,
                  height: 52,
                  fit: BoxFit.cover,
                  // A profile picture that will not load is not worth an error
                  // box at the top of the account screen.
                  errorBuilder: (_, __, ___) => _initials(),
                ),
              ),
      ),
    );
  }

  Widget _initials() => Text(
        user.initials,
        style: AppText.bodyStrong.copyWith(color: AppColors.brandDeep),
      );
}
