/// The extraction job list.
///
/// A running job carries its own progress bar rather than a global spinner,
/// because a workspace usually has one crawl in flight and several finished
/// ones, and the finished rows must stay readable while the live one moves.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../core/i18n/strings.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/hero_scenes.dart';
import '../../../core/widgets/page_scaffold.dart';
import '../../../core/widgets/states.dart';
import '../domain/web_job.dart';
import 'providers.dart';
import 'widgets/job_card.dart';

class WebExtractionsScreen extends ConsumerStatefulWidget {
  const WebExtractionsScreen({super.key});

  @override
  ConsumerState<WebExtractionsScreen> createState() =>
      _WebExtractionsScreenState();
}

class _WebExtractionsScreenState extends ConsumerState<WebExtractionsScreen> {
  WebJobListController get _controller =>
      ref.read(webJobListProvider.notifier);

  bool _onScroll(ScrollNotification notification) {
    if (notification.metrics.extentAfter < 600) {
      _controller.loadMore();
    }
    return false;
  }

  void _open(int id) {
    context.pushNamed(
      AppRoute.webExtractionDetail,
      pathParameters: <String, String>{'id': '$id'},
    );
  }

  @override
  Widget build(BuildContext context) {
    final WebJobListState state = ref.watch(webJobListProvider);

    return NotificationListener<ScrollNotification>(
      onNotification: _onScroll,
      child: HeroPageScaffold(
        onRefresh: () => _controller.refresh(),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => context.pushNamed(AppRoute.webExtractionCreate),
          icon: const Icon(Icons.add_rounded),
          label: const Text(S.newExtraction),
        ),
        slivers: <Widget>[
          const SliverAppBar(
            backgroundColor: AppColors.canvas,
            surfaceTintColor: AppColors.canvas,
            elevation: 0,
            toolbarHeight: 48,
            floating: true,
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
                eyebrow: S.webExtraction,
                title: S.webExtractionSubtitle,
                scene: const WebScene(),
                subtitle: state.hasRunning
                    ? S.extractionRunning
                    : (state.total > 0 ? S.jobCount(state.total) : null),
              ),
            ),
          ),
          if (state.page.isLoading && !state.page.hasValue)
            const SliverToBoxAdapter(child: SkeletonList())
          else if (state.page.hasError && !state.page.hasValue)
            SliverFillRemaining(
              hasScrollBody: false,
              child: ErrorState(
                error: state.page.error!,
                onRetry: () => _controller.refresh(showLoading: true),
                onUpgrade: () => context.pushNamed(AppRoute.billing),
              ),
            )
          else if (state.items.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyState(
                icon: Icons.travel_explore_rounded,
                title: S.noExtractions,
                body: S.noExtractionsBody,
                actionLabel: S.newExtraction,
                onAction: () =>
                    context.pushNamed(AppRoute.webExtractionCreate),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.page),
              sliver: SliverList.separated(
                itemCount: state.items.length,
                separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.md),
                itemBuilder: (BuildContext context, int index) {
                  final WebExtractionJob job = state.items[index];
                  return WebJobCard(job: job, onTap: () => _open(job.id));
                },
              ),
            ),
          SliverToBoxAdapter(
            child: _Footer(
              isLoadingMore: state.isLoadingMore,
              error: state.loadMoreError,
              onRetry: _controller.loadMore,
            ),
          ),
        ],
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({
    required this.isLoadingMore,
    required this.error,
    required this.onRetry,
  });

  final bool isLoadingMore;
  final Object? error;
  final VoidCallback onRetry;

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

    return const SizedBox(height: 96);
  }
}
