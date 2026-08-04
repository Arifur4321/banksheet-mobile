/// The home screen.
///
/// Everything here answers one of two questions a returning user has: "what
/// happened while I was away" (the counters and the recent list) and "what do I
/// do next" (the upload button, the quick actions). It is built from a single
/// `GET /dashboard`, so the whole screen has one loading state, one error state
/// and one pull-to-refresh rather than six independent spinners.
///
/// The usage card reads the session rather than the dashboard payload, because
/// `GET /me` publishes every metered bucket while `/dashboard` only carries
/// pages — and warning someone before they hit a wall is worth more than the
/// one metric that happens to be in both.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../core/i18n/strings.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/theme/typography.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/logger.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/hero_scenes.dart';
import '../../../core/widgets/page_scaffold.dart';
import '../../../core/widgets/scene_3d.dart';
import '../../../core/widgets/states.dart';
import '../../auth/domain/session.dart';
import '../../auth/presentation/auth_controller.dart';
import '../domain/dashboard_data.dart';
import 'providers.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<DashboardData> state = ref.watch(dashboardProvider);
    final Session? session = ref.watch(sessionProvider);

    return HeroPageScaffold(
      onRefresh: () => _refresh(ref),
      slivers: <Widget>[
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.page,
            AppSpacing.md,
            AppSpacing.page,
            AppSpacing.lg,
          ),
          sliver: SliverToBoxAdapter(
            child: _GreetingRow(
              user: session?.user,
              workspaceName: session?.workspace.name,
            ),
          ),
        ),
        const SliverPadding(
          padding: EdgeInsets.symmetric(horizontal: AppSpacing.page),
          sliver: SliverToBoxAdapter(
            child: HeroPanel(
              eyebrow: S.dashboard,
              title: S.dashboardHeroTitle,
              scene: DashboardScene(),
              trailing: _UploadButton(),
            ),
          ),
        ),
        state.when(
          loading: () => const SliverPadding(
            padding: EdgeInsets.fromLTRB(
              AppSpacing.page,
              AppSpacing.xl,
              AppSpacing.page,
              AppSpacing.section,
            ),
            sliver: SliverToBoxAdapter(child: _DashboardSkeleton()),
          ),
          error: (Object error, StackTrace _) => SliverFillRemaining(
            hasScrollBody: false,
            child: ErrorState(
              error: error,
              onRetry: () => ref.invalidate(dashboardProvider),
              onUpgrade: () => context.pushNamed(AppRoute.billing),
            ),
          ),
          data: (DashboardData data) => SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.page,
              AppSpacing.xl,
              AppSpacing.page,
              AppSpacing.section,
            ),
            sliver: SliverToBoxAdapter(
              child: _Body(
                data: data,
                // Falls back to the one bucket `/dashboard` carries, so the
                // meter still appears in the moment before `/me` lands.
                limits: session?.limits ??
                    PlanLimits(
                      pagesUsed: data.usedPages,
                      pagesLimit: data.monthlyPageLimit,
                    ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Pull to refresh reloads the counters and the plan together — a refresh
  /// right after an upgrade should move the meters, not just the tiles.
  Future<void> _refresh(WidgetRef ref) async {
    try {
      await Future.wait<void>(<Future<void>>[
        ref.refresh(dashboardProvider.future),
        ref.read(authControllerProvider.notifier).refreshSession(),
      ]);
    } catch (error) {
      // The provider already holds the failure and ErrorState renders it;
      // rethrowing here would only surface an unhandled async error.
      Log.warn('Dashboard refresh failed: $error');
    }
  }
}

// ---------------------------------------------------------------------------
// Header
// ---------------------------------------------------------------------------

class _GreetingRow extends StatelessWidget {
  const _GreetingRow({this.user, this.workspaceName});

  final AppUser? user;
  final String? workspaceName;

  @override
  Widget build(BuildContext context) {
    final String name = user?.firstName ?? S.greetingFallback;
    final String? workspace = workspaceName;

    return Row(
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                '${S.greeting(DateTime.now())}, $name',
                style: AppText.h1,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (workspace != null && workspace.isNotEmpty)
                Text(
                  workspace,
                  style: AppText.bodySm,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        _AvatarButton(user: user),
      ],
    );
  }
}

class _AvatarButton extends StatelessWidget {
  const _AvatarButton({this.user});

  final AppUser? user;

  @override
  Widget build(BuildContext context) {
    final String? avatar = user?.avatarUrl;

    // Tooltip rather than a bare Semantics wrapper: it labels the control for
    // a screen reader and merges with the InkWell's own button semantics
    // instead of announcing two nodes for one avatar.
    return Tooltip(
      message: S.openAccount,
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => context.pushNamed(AppRoute.settings),
          child: Container(
            width: 46,
            height: 46,
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
                      width: 46,
                      height: 46,
                      fit: BoxFit.cover,
                      // A profile picture that will not load is not worth an
                      // error box on the home screen.
                      errorBuilder: (_, __, ___) => _initials(),
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  Widget _initials() => Text(
        user?.initials ?? '·',
        style: AppText.bodyStrong.copyWith(color: AppColors.brandDeep),
      );
}

class _UploadButton extends StatelessWidget {
  const _UploadButton();

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: () => context.pushNamed(AppRoute.documentUpload),
      style: FilledButton.styleFrom(
        // The theme's buttons are full width by default; inside the hero panel
        // this one has to sit beside the 3D stage rather than under it.
        minimumSize: const Size(0, 44),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      ),
      icon: const Icon(Icons.file_upload_outlined, size: 18),
      label: const Text(S.uploadStatement),
    );
  }
}

// ---------------------------------------------------------------------------
// Body
// ---------------------------------------------------------------------------

class _Body extends StatelessWidget {
  const _Body({required this.data, required this.limits});

  final DashboardData data;
  final PlanLimits limits;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _StatGrid(data: data),
        const SizedBox(height: AppSpacing.xxl),
        _UsageCard(limits: limits),
        const SizedBox(height: AppSpacing.xxl),
        DarkActionCard(
          eyebrow: S.webExtraction,
          title: S.webExtractionSubtitle,
          body: '${S.emailsFound}: ${Fmt.number(data.webEmailsFound)}',
          onTap: () => context.pushNamed(AppRoute.webExtractions),
        ),
        const SizedBox(height: AppSpacing.xxl),
        const SectionHeader(title: S.quickActions),
        const _QuickActions(),
        const SizedBox(height: AppSpacing.xxl),
        SectionHeader(
          title: S.recentDocuments,
          actionLabel: data.latestDocuments.isEmpty ? null : S.viewAll,
          onAction: data.latestDocuments.isEmpty
              ? null
              : () => context.goNamed(AppRoute.documents),
        ),
        _RecentDocuments(documents: data.latestDocuments),
      ],
    );
  }
}

class _StatGrid extends StatelessWidget {
  const _StatGrid({required this.data});

  final DashboardData data;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        _row(
          StatCard(
            label: S.statProcessedDocuments,
            value: Fmt.number(data.processedDocuments),
            icon: Icons.task_alt_rounded,
            tone: StatTone.brand,
            onTap: () => context.goNamed(AppRoute.documents),
          ),
          StatCard(
            label: S.statPendingReviews,
            value: Fmt.number(data.pendingReviews),
            icon: Icons.rate_review_outlined,
            tone: data.pendingReviews > 0 ? StatTone.warn : StatTone.neutral,
            onTap: () => context.goNamed(AppRoute.review),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        _row(
          StatCard(
            label: S.statSavedExports,
            value: Fmt.number(data.completedExports),
            icon: Icons.download_done_rounded,
            onTap: () => context.pushNamed(AppRoute.exports),
          ),
          StatCard(
            label: S.statFailedDocuments,
            value: Fmt.number(data.failedDocuments),
            icon: Icons.error_outline_rounded,
            tone: data.failedDocuments > 0 ? StatTone.danger : StatTone.neutral,
            onTap: () => context.goNamed(AppRoute.documents),
          ),
        ),
      ],
    );
  }

  /// Two tiles of equal height. [IntrinsicHeight] rather than a fixed aspect
  /// ratio so the pair still lines up at 200% text size.
  Widget _row(Widget left, Widget right) => IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Expanded(child: left),
            const SizedBox(width: AppSpacing.md),
            Expanded(child: right),
          ],
        ),
      );
}

class _UsageCard extends StatelessWidget {
  const _UsageCard({required this.limits});

  final PlanLimits limits;

  /// The three buckets that map to what the app actually spends.
  static const List<String> _keys = <String>[
    PlanLimits.keyDocuments,
    PlanLimits.keyPages,
    PlanLimits.keyConversions,
  ];

  @override
  Widget build(BuildContext context) {
    final List<UsageLine> lines = limits.linesFor(_keys);
    final bool nearLimit = lines.any((UsageLine line) => line.isNearLimit);
    final DateTime? resets = limits.periodEndsAt;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const Text(S.usageThisMonth, style: AppText.h3),
                    if (resets != null)
                      Text(
                        '${S.usageResets} ${Fmt.date(resets)}',
                        style: AppText.caption,
                      ),
                  ],
                ),
              ),
              // Offered only when it is actually useful — an upgrade prompt on
              // a workspace using 4% of its allowance is just noise.
              if (nearLimit)
                TextButton(
                  onPressed: () => context.pushNamed(AppRoute.billing),
                  child: const Text(S.upgrade),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          for (int i = 0; i < lines.length; i++) ...<Widget>[
            UsageMeter(
              label: lines[i].label,
              used: lines[i].used,
              limit: lines[i].limit,
            ),
            if (i < lines.length - 1) const SizedBox(height: AppSpacing.lg),
          ],
        ],
      ),
    );
  }
}

class _QuickActions extends StatelessWidget {
  const _QuickActions();

  @override
  Widget build(BuildContext context) {
    // TiltCard measures itself with a LayoutBuilder, which cannot answer an
    // intrinsic-height query — so the pair is given a height that tracks the
    // user's text size instead of being stretched by IntrinsicHeight.
    final double scale =
        MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.7);

    return SizedBox(
      height: 168 * scale,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Expanded(
            child: TiltCard(
              onTap: () => context.goNamed(AppRoute.tools),
              semanticLabel: S.pdfTools,
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: const _QuickAction(
                icon: Icons.picture_as_pdf_rounded,
                title: S.pdfTools,
                body: S.pdfToolsSubtitle,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: TiltCard(
              onTap: () => context.pushNamed(AppRoute.barcode),
              semanticLabel: S.barcode,
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: const _QuickAction(
                icon: Icons.qr_code_2_rounded,
                title: S.barcode,
                body: S.barcodeSubtitle,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          width: 38,
          height: 38,
          decoration: const BoxDecoration(
            color: AppColors.brandTint,
            borderRadius: AppRadius.smallAll,
          ),
          child: Icon(icon, size: 21, color: AppColors.brandDeep),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          title,
          style: AppText.h3,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 2),
        Flexible(
          child: Text(
            body,
            style: AppText.bodySm,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _RecentDocuments extends StatelessWidget {
  const _RecentDocuments({required this.documents});

  final List<DashboardDocument> documents;

  @override
  Widget build(BuildContext context) {
    if (documents.isEmpty) {
      return EmptyState(
        title: S.noDocuments,
        body: S.noDocumentsBody,
        icon: Icons.description_outlined,
        actionLabel: S.uploadDocument,
        onAction: () => context.pushNamed(AppRoute.documentUpload),
      );
    }

    // The server already caps this at five; the take() is what guarantees the
    // home screen stays a summary if that ever changes.
    final List<DashboardDocument> rows =
        documents.take(5).toList(growable: false);

    return Column(
      children: <Widget>[
        for (int i = 0; i < rows.length; i++) ...<Widget>[
          _DocumentRow(document: rows[i]),
          if (i < rows.length - 1) const SizedBox(height: AppSpacing.md),
        ],
      ],
    );
  }
}

class _DocumentRow extends StatelessWidget {
  const _DocumentRow({required this.document});

  final DashboardDocument document;

  @override
  Widget build(BuildContext context) {
    final String name =
        Fmt.middleEllipsis(document.originalFilename ?? S.untitledDocument);
    final int? rows = document.rowCount;

    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.lg),
      semanticLabel: name,
      onTap: () => context.pushNamed(
        AppRoute.documentDetail,
        pathParameters: <String, String>{'id': '${document.id}'},
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: document.isFailed
                  ? AppColors.dangerTint
                  : AppColors.surfaceMuted,
              borderRadius: AppRadius.smallAll,
            ),
            child: Icon(
              document.isFailed
                  ? Icons.error_outline_rounded
                  : Icons.description_outlined,
              size: 20,
              color:
                  document.isFailed ? AppColors.danger : AppColors.inkMuted,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  name,
                  style: AppText.bodyStrong,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  rows == null
                      ? Fmt.relative(document.createdAt)
                      : '${Fmt.number(rows)} ${S.rowsExtracted} · '
                          '${Fmt.relative(document.createdAt)}',
                  style: AppText.caption,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (document.status != null) ...<Widget>[
            const SizedBox(width: AppSpacing.sm),
            StatusBadge(document.status!, compact: true),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Loading
// ---------------------------------------------------------------------------

class _DashboardSkeleton extends StatelessWidget {
  const _DashboardSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(child: _SkeletonCard(height: 104)),
            SizedBox(width: AppSpacing.md),
            Expanded(child: _SkeletonCard(height: 104)),
          ],
        ),
        SizedBox(height: AppSpacing.md),
        Row(
          children: <Widget>[
            Expanded(child: _SkeletonCard(height: 104)),
            SizedBox(width: AppSpacing.md),
            Expanded(child: _SkeletonCard(height: 104)),
          ],
        ),
        SizedBox(height: AppSpacing.xxl),
        _SkeletonCard(height: 186),
        SizedBox(height: AppSpacing.xxl),
        _SkeletonCard(height: 132),
        SizedBox(height: AppSpacing.xxl),
        Row(
          children: <Widget>[
            Expanded(child: _SkeletonCard(height: 148)),
            SizedBox(width: AppSpacing.md),
            Expanded(child: _SkeletonCard(height: 148)),
          ],
        ),
        SizedBox(height: AppSpacing.xxl),
        _SkeletonCard(height: 74),
        SizedBox(height: AppSpacing.md),
        _SkeletonCard(height: 74),
        SizedBox(height: AppSpacing.md),
        _SkeletonCard(height: 74),
      ],
    );
  }
}

class _SkeletonCard extends StatelessWidget {
  const _SkeletonCard({required this.height});

  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.cardAll,
        border: Border.all(color: AppColors.border),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Skeleton(width: 110, height: 12),
          SizedBox(height: 12),
          Skeleton(width: 72, height: 20),
        ],
      ),
    );
  }
}
