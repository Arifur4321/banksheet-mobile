/// What is out for signature.
///
/// The screen exists to answer one question from a phone — is it signed yet —
/// so every row leads with the progress and the chips default to the set that
/// still needs chasing. Creating a request is not offered: that needs signature
/// boxes placed on a page, and the note at the top says so rather than leaving
/// a "+" that does nothing.
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
import '../../auth/domain/session.dart';
import '../../auth/presentation/auth_controller.dart';
import '../domain/signature.dart';
import 'providers.dart';
import 'widgets/signature_status_header.dart';

class SignaturesScreen extends ConsumerStatefulWidget {
  const SignaturesScreen({super.key});

  @override
  ConsumerState<SignaturesScreen> createState() => _SignaturesScreenState();
}

class _SignaturesScreenState extends ConsumerState<SignaturesScreen> {
  bool _onScroll(ScrollNotification notification) {
    if (notification.metrics.extentAfter < 600) {
      ref.read(signatureListProvider.notifier).loadMore();
    }
    return false;
  }

  void _open(int id) {
    context.pushNamed(
      AppRoute.signatureDetail,
      pathParameters: <String, String>{'id': '$id'},
    );
  }

  @override
  Widget build(BuildContext context) {
    final SignatureListState state = ref.watch(signatureListProvider);
    final List<SignatureRequest> rows = state.items;

    // E-signature is the one metered thing in this corner of the app, and the
    // allowance is the usual reason a request cannot be sent from the website
    // — so it is worth stating here rather than only on the billing screen.
    final PlanLimits? limits = ref.watch(sessionProvider)?.limits;
    final bool showUsage = limits != null && limits.esignLimit != null;

    return NotificationListener<ScrollNotification>(
      onNotification: _onScroll,
      child: HeroPageScaffold(
        onRefresh: () => ref.read(signatureListProvider.notifier).refresh(),
        slivers: <Widget>[
          const SliverAppBar(
            floating: true,
            toolbarHeight: 52,
            titleSpacing: AppSpacing.lg,
            title: Text(S.signatures),
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
                eyebrow: S.signatures,
                title: S.signaturesSubtitle,
                scene: const SignatureScene(),
                subtitle: state.total > 0
                    ? S.signatureRequestCount(state.total)
                    : null,
              ),
            ),
          ),
          if (showUsage)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.page,
                0,
                AppSpacing.page,
                AppSpacing.lg,
              ),
              sliver: SliverToBoxAdapter(
                child: AppCard(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: UsageMeter(
                    label: S.usageEsign,
                    used: limits?.esignUsed,
                    limit: limits?.esignLimit,
                  ),
                ),
              ),
            ),
          SliverToBoxAdapter(
            child: _FilterChips(
              selected: state.filter,
              onSelect: ref.read(signatureListProvider.notifier).setFilter,
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
                    .read(signatureListProvider.notifier)
                    .refresh(showLoading: true),
                onUpgrade: () => context.pushNamed(AppRoute.billing),
              ),
            )
          else if (rows.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: state.isFiltered
                  ? EmptyState(
                      icon: Icons.filter_alt_off_rounded,
                      title: S.noResults,
                      body: S.noResultsBody,
                      actionLabel: S.clearFilters,
                      onAction: () => ref
                          .read(signatureListProvider.notifier)
                          .setFilter(SignatureFilter.all),
                    )
                  : const EmptyState(
                      icon: Icons.draw_outlined,
                      title: S.noSignatureRequests,
                      body: S.noSignatureRequestsBody,
                    ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.page),
              sliver: SliverList.separated(
                itemCount: rows.length,
                separatorBuilder: (_, __) =>
                    const SizedBox(height: AppSpacing.md),
                itemBuilder: (BuildContext context, int index) =>
                    _SignatureRow(
                  request: rows[index],
                  onTap: () => _open(rows[index].id),
                ),
              ),
            ),
          SliverToBoxAdapter(
            child: _ListFooter(
              isLoadingMore: state.isLoadingMore,
              error: state.loadMoreError,
              onRetry: () =>
                  ref.read(signatureListProvider.notifier).loadMore(),
              // The one-line explanation of why there is no "new request"
              // button, at the end of the list where it answers the question
              // rather than at the top where it is in the way.
              note: state.items.isEmpty ? null : S.signaturesReadOnly,
            ),
          ),
        ],
      ),
    );
  }
}

class _SignatureRow extends StatelessWidget {
  const _SignatureRow({required this.request, required this.onTap});

  final SignatureRequest request;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final SignatureProgress progress = request.progress;
    final ({Color fg, Color bg, IconData icon}) tone =
        signatureTone(request.state);

    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.all(AppSpacing.lg),
      semanticLabel: '${request.displayName}, '
          '${Fmt.humanise(request.status)}, ${progress.label}',
      child: Row(
        children: <Widget>[
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: tone.bg,
              borderRadius: AppRadius.smallAll,
            ),
            child: Icon(tone.icon, size: 21, color: tone.fg),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  Fmt.middleEllipsis(request.displayName),
                  style: AppText.bodyStrong,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 5),
                Row(
                  children: <Widget>[
                    StatusBadge(request.status, compact: true),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        progress.label,
                        style: AppText.caption.copyWith(
                          color: tone.fg,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  _meta,
                  style: AppText.caption,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          const Icon(
            Icons.chevron_right_rounded,
            size: 22,
            color: AppColors.inkFaint,
          ),
        ],
      ),
    );
  }

  String get _meta {
    final List<String> parts = <String>[
      if (request.source.label != null)
        Fmt.middleEllipsis(request.source.label!, max: 26),
      Fmt.relative(request.lastEventAt ?? request.sentAt ?? request.createdAt),
    ];
    return parts.join(' · ');
  }
}

class _FilterChips extends StatelessWidget {
  const _FilterChips({required this.selected, required this.onSelect});

  final SignatureFilter selected;
  final ValueChanged<SignatureFilter> onSelect;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 54,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.page,
          0,
          AppSpacing.page,
          AppSpacing.md,
        ),
        itemCount: SignatureFilter.values.length,
        separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.sm),
        itemBuilder: (BuildContext context, int index) {
          final SignatureFilter filter = SignatureFilter.values[index];
          final bool active = filter == selected;

          return ChoiceChip(
            label: Text(filter.label),
            selected: active,
            showCheckmark: false,
            onSelected: (_) => onSelect(filter),
            labelStyle: AppText.bodySm.copyWith(
              fontWeight: FontWeight.w600,
              color: active ? AppColors.brandDeep : AppColors.inkBody,
            ),
            selectedColor: AppColors.brandTint,
            backgroundColor: AppColors.surface,
            side: BorderSide(
              color: active ? AppColors.brandTintStrong : AppColors.border,
            ),
          );
        },
      ),
    );
  }
}

/// The bottom of the list: a spinner while another page loads, a retry when one
/// failed, and the "requests are created on the website" note otherwise.
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
