/// The extraction profiles list.
///
/// The one thing this screen can change is whether a profile is considered at
/// all, so that switch sits on the row rather than two taps away — and it moves
/// the instant it is tapped, rolling back if the server disagrees. Everything
/// else is read-only, and the note at the bottom says where the editing lives
/// instead of leaving the user hunting for it.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../core/i18n/strings.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/theme/typography.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/hero_scenes.dart';
import '../../../core/widgets/page_scaffold.dart';
import '../../../core/widgets/states.dart';
import '../domain/extraction_profile.dart';
import 'providers.dart';

class ProfilesScreen extends ConsumerStatefulWidget {
  const ProfilesScreen({super.key});

  @override
  ConsumerState<ProfilesScreen> createState() => _ProfilesScreenState();
}

class _ProfilesScreenState extends ConsumerState<ProfilesScreen> {
  bool _onScroll(ScrollNotification notification) {
    if (notification.metrics.extentAfter < 600) {
      ref.read(profileListProvider.notifier).loadMore();
    }
    return false;
  }

  void _open(int id) {
    context.pushNamed(
      AppRoute.profileDetail,
      pathParameters: <String, String>{'id': '$id'},
    );
  }

  Future<void> _toggle(ExtractionProfile profile) async {
    try {
      final bool? active =
          await ref.read(profileListProvider.notifier).toggle(profile.id);
      if (!context.mounted || active == null) {
        return;
      }
      Toast.success(
        context,
        active ? S.profileActivated : S.profileDeactivated,
      );
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      // The row has already rolled itself back; this says why.
      Toast.error(context, error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ProfileListState state = ref.watch(profileListProvider);
    final List<ExtractionProfile> rows = state.items;

    return NotificationListener<ScrollNotification>(
      onNotification: _onScroll,
      child: HeroPageScaffold(
        onRefresh: () => ref.read(profileListProvider.notifier).refresh(),
        slivers: <Widget>[
          const SliverAppBar(
            floating: true,
            toolbarHeight: 52,
            titleSpacing: AppSpacing.lg,
            title: Text(S.profiles),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.page,
              0,
              AppSpacing.page,
              AppSpacing.lg,
            ),
            sliver: SliverToBoxAdapter(
              child: HeroPanel(
                eyebrow: S.profiles,
                title: S.profilesSubtitle,
                scene: const ToolsScene(),
                subtitle:
                    state.total > 0 ? S.profileCount(state.total) : null,
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: _ActiveOnlyToggle(
              value: state.activeOnly,
              onChanged: (bool value) => ref
                  .read(profileListProvider.notifier)
                  .setActiveOnly(value: value),
            ),
          ),
          if (state.page.isLoading && !state.page.hasValue)
            const SliverToBoxAdapter(child: SkeletonList())
          else if (state.page.hasError && !state.page.hasValue)
            SliverFillRemaining(
              hasScrollBody: false,
              child: ErrorState(
                error: state.page.error!,
                onRetry: () => ref
                    .read(profileListProvider.notifier)
                    .refresh(showLoading: true),
                onUpgrade: () => context.pushNamed(AppRoute.billing),
              ),
            )
          else if (rows.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: state.activeOnly
                  ? EmptyState(
                      icon: Icons.filter_alt_off_rounded,
                      title: S.noResults,
                      body: S.noResultsBody,
                      actionLabel: S.clearFilters,
                      onAction: () => ref
                          .read(profileListProvider.notifier)
                          .setActiveOnly(value: false),
                    )
                  : const EmptyState(
                      icon: Icons.tune_rounded,
                      title: S.noProfiles,
                      body: S.noProfilesBody,
                    ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.page),
              sliver: SliverList.separated(
                itemCount: rows.length,
                separatorBuilder: (_, __) =>
                    const SizedBox(height: AppSpacing.md),
                itemBuilder: (BuildContext context, int index) {
                  final ExtractionProfile profile = rows[index];
                  return _ProfileCard(
                    profile: profile,
                    isPending: state.pendingIds.contains(profile.id),
                    onTap: () => _open(profile.id),
                    onToggle: () => _toggle(profile),
                  );
                },
              ),
            ),
          SliverToBoxAdapter(
            child: _ListFooter(
              isLoadingMore: state.isLoadingMore,
              error: state.loadMoreError,
              onRetry: () => ref.read(profileListProvider.notifier).loadMore(),
              note: rows.isEmpty ? null : S.profilesAuthoredOnWeb,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActiveOnlyToggle extends StatelessWidget {
  const _ActiveOnlyToggle({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.page,
        0,
        AppSpacing.page,
        AppSpacing.md,
      ),
      child: Row(
        children: <Widget>[
          const Expanded(
            child: Text(S.activeOnly, style: AppText.bodySm),
          ),
          Switch.adaptive(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({
    required this.profile,
    required this.isPending,
    required this.onTap,
    required this.onToggle,
  });

  final ExtractionProfile profile;

  /// True while this row's toggle is in flight.
  final bool isPending;

  final VoidCallback onTap;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.all(AppSpacing.lg),
      semanticLabel: '${profile.displayName}, '
          '${profile.isActive ? S.profileActive : S.profileInactive}',
      child: Row(
        children: <Widget>[
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: profile.isActive
                  ? AppColors.brandTint
                  : AppColors.surfaceMuted,
              borderRadius: AppRadius.smallAll,
            ),
            child: Icon(
              Icons.account_balance_rounded,
              size: 21,
              color:
                  profile.isActive ? AppColors.brandDeep : AppColors.inkFaint,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  Fmt.middleEllipsis(profile.displayName),
                  style: AppText.bodyStrong,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Text(
                  _meta,
                  style: AppText.caption,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          // Disabled rather than hidden while in flight: a switch that vanishes
          // mid-tap is worse than one that will not move for half a second.
          Semantics(
            label: profile.displayName,
            child: Switch.adaptive(
              value: profile.isActive,
              onChanged: isPending ? null : (_) => onToggle(),
            ),
          ),
        ],
      ),
    );
  }

  String get _meta {
    final List<String> parts = <String>[
      if (profile.bankName != null && profile.bankName != profile.name)
        profile.bankName!,
      if (profile.documentType != null) Fmt.humanise(profile.documentType),
      if (profile.documentsCount != null)
        S.documentCount(profile.documentsCount!),
      profile.lastMatchedAt == null
          ? S.neverMatched
          : '${S.lastMatched} ${Fmt.relative(profile.lastMatchedAt)}',
    ];
    return parts.join(' · ');
  }
}

/// The bottom of the list: a spinner while another page loads, a retry when one
/// failed, and the "profiles are built on the website" note otherwise.
class _ListFooter extends StatelessWidget {
  const _ListFooter({
    required this.isLoadingMore,
    required this.error,
    required this.onRetry,
    required this.note,
  });

  final bool isLoadingMore;
  final Object? error;
  final VoidCallback onRetry;
  final String? note;

  @override
  Widget build(BuildContext context) {
    if (error != null) {
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.page),
        child: InlineNotice(
          message: S.couldNotLoadMore,
          tone: NoticeTone.warn,
          actionLabel: S.tryAgain,
          onAction: onRetry,
        ),
      );
    }

    if (isLoadingMore) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.xxl),
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2.4),
          ),
        ),
      );
    }

    if (note == null) {
      return const SizedBox(height: AppSpacing.section);
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.page,
        AppSpacing.lg,
        AppSpacing.page,
        AppSpacing.section,
      ),
      child: Text(note!, style: AppText.caption, textAlign: TextAlign.center),
    );
  }
}
