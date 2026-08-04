/// One extraction job, while it runs and after.
///
/// The progress card polls on the interval the server publishes and stops the
/// moment the job reports itself finished — the client never matches status
/// strings to decide that, so a state a future server adds ends the poll rather
/// than spinning a phone for the rest of the day.
///
/// Cancel, retry and delete each carry the server's own rule in their enabled
/// state: a finished job cannot be cancelled, an unfinished one cannot be
/// deleted, and retry only exists when there is something failed to retry.
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
import '../../../core/widgets/page_scaffold.dart';
import '../../../core/widgets/states.dart';
import '../domain/web_job.dart';
import 'providers.dart';
import 'widgets/target_row.dart';

class WebExtractionDetailScreen extends ConsumerStatefulWidget {
  const WebExtractionDetailScreen({required this.jobId, super.key});

  final int jobId;

  @override
  ConsumerState<WebExtractionDetailScreen> createState() =>
      _WebExtractionDetailScreenState();
}

class _WebExtractionDetailScreenState
    extends ConsumerState<WebExtractionDetailScreen> {
  WebJobDetailController get _controller =>
      ref.read(webJobDetailProvider(widget.jobId).notifier);

  Future<void> _cancel() async {
    final bool confirmed = await confirmAction(
      context,
      title: S.cancelJob,
      message: S.cancelJobBody,
      confirmLabel: S.cancelJob,
      destructive: true,
    );
    if (!context.mounted || !confirmed) {
      return;
    }

    try {
      final WebExtractionJob job = await _controller.cancel();
      if (!context.mounted) {
        return;
      }
      ref.read(webJobListProvider.notifier).replace(job);
      Toast.success(context, S.jobCancelled);
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      Toast.error(context, error);
    }
  }

  Future<void> _retry() async {
    try {
      final WebExtractionJob job = await _controller.retry();
      if (!context.mounted) {
        return;
      }
      ref.read(webJobListProvider.notifier).replace(job);
      Toast.success(context, S.jobRetried);
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      Toast.error(context, error);
    }
  }

  Future<void> _delete() async {
    final bool confirmed = await confirmAction(
      context,
      title: S.deleteJob,
      message: S.deleteJobBody,
      confirmLabel: S.delete,
      destructive: true,
    );
    if (!context.mounted || !confirmed) {
      return;
    }

    try {
      await _controller.delete();
      if (!context.mounted) {
        return;
      }
      ref.read(webJobListProvider.notifier).remove(widget.jobId);
      Toast.success(context, S.jobDeleted);
      context.pop();
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      Toast.error(context, error);
    }
  }

  void _openResults() {
    context.pushNamed(
      AppRoute.webExtractionResults,
      pathParameters: <String, String>{'id': '${widget.jobId}'},
    );
  }

  @override
  Widget build(BuildContext context) {
    final WebJobDetailState state = ref.watch(webJobDetailProvider(widget.jobId));
    final WebExtractionJob? job = state.job;

    return PageScaffold(
      title: job?.title ?? S.webExtraction,
      subtitle: job == null ? null : Fmt.relative(job.createdAt),
      showBack: true,
      scrollable: true,
      onRefresh: () => _controller.load(),
      actions: <Widget>[
        if (job != null && job.canDelete)
          IconButton(
            onPressed: state.isBusy ? null : _delete,
            icon: const Icon(Icons.delete_outline_rounded),
            tooltip: S.delete,
          ),
      ],
      child: state.detail.when(
        loading: () => const Padding(
          padding: EdgeInsets.only(top: AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Skeleton(height: 150, radius: AppRadius.card),
              SizedBox(height: AppSpacing.lg),
              Skeleton(height: 220, radius: AppRadius.card),
            ],
          ),
        ),
        error: (Object error, StackTrace _) => Padding(
          padding: const EdgeInsets.only(top: AppSpacing.section),
          child: ErrorState(
            error: error,
            onRetry: () => _controller.load(showLoading: true),
            onUpgrade: () => context.pushNamed(AppRoute.billing),
          ),
        ),
        data: (WebExtractionJob loaded) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _ProgressCard(job: loaded, busy: state.isBusy),
            if (loaded.warning != null) ...<Widget>[
              const SizedBox(height: AppSpacing.md),
              InlineNotice(message: loaded.warning!, tone: NoticeTone.warn),
            ],
            if (loaded.error != null) ...<Widget>[
              const SizedBox(height: AppSpacing.md),
              InlineNotice(message: loaded.error!, tone: NoticeTone.danger),
            ],
            const SizedBox(height: AppSpacing.lg),
            Row(
              children: <Widget>[
                if (loaded.canCancel)
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: state.isBusy ? null : _cancel,
                      icon: const Icon(Icons.stop_circle_outlined, size: 18),
                      label: const Text(S.cancelJob),
                    ),
                  ),
                if (loaded.canCancel && _hasRetryable(state))
                  const SizedBox(width: AppSpacing.sm),
                if (_hasRetryable(state))
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: state.isBusy ? null : _retry,
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                      label: const Text(S.retryFailed),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            FilledButton.icon(
              onPressed: _openResults,
              icon: const Icon(Icons.list_alt_rounded, size: 19),
              label: const Text(S.viewResults),
            ),
            const SizedBox(height: AppSpacing.xl),
            SectionHeader(
              title: S.websites,
              subtitle: S.websiteCount(loaded.totalTargets),
            ),
            AppCard(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.sm,
              ),
              child: Column(
                children: <Widget>[
                  for (final WebExtractionTarget target in state.targets)
                    TargetRow(target: target),
                  if (state.targets.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      child: Text(S.noWebsitesYet, style: AppText.bodySm),
                    ),
                ],
              ),
            ),
            if (state.hasMoreTargets) ...<Widget>[
              const SizedBox(height: AppSpacing.sm),
              TextButton(
                onPressed:
                    state.isLoadingMore ? null : _controller.loadMoreTargets,
                child: Text(
                  state.isLoadingMore ? S.loading : S.showMoreWebsites,
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.section),
          ],
        ),
      ),
    );
  }

  /// Only the first page of websites is loaded, so a job with a failure on page
  /// three would otherwise hide the button entirely. The job's own rollup is
  /// trusted for that case; if none of them turn out to be retryable the server
  /// answers 409 and the toast says so, which beats an invisible action.
  static bool _hasRetryable(WebJobDetailState state) =>
      state.targets.any((WebExtractionTarget t) => t.isRetryable) ||
      (state.job?.failedTargets ?? 0) > 0;
}

class _ProgressCard extends StatelessWidget {
  const _ProgressCard({required this.job, required this.busy});

  final WebExtractionJob job;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  job.isRunning ? S.extractionRunning : S.extractionFinished,
                  style: AppText.h3,
                ),
              ),
              StatusBadge(job.status),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: job.progress,
              minHeight: 8,
              backgroundColor: AppColors.border,
              valueColor: const AlwaysStoppedAnimation<Color>(AppColors.brand),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            S.websitesProcessed(job.processedTargets, job.totalTargets),
            style: AppText.caption,
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: <Widget>[
              Expanded(
                child: _Stat(
                  label: S.emailsFound,
                  value: '${job.emailsFoundCount}',
                ),
              ),
              Expanded(
                child: _Stat(
                  label: S.careerPagesFound,
                  value: '${job.careerPagesFoundCount}',
                ),
              ),
              Expanded(
                child: _Stat(
                  label: S.websitesFailed,
                  value: '${job.failedTargets}',
                ),
              ),
            ],
          ),
          if (busy) ...<Widget>[
            const SizedBox(height: AppSpacing.lg),
            const LinearProgressIndicator(minHeight: 3),
          ],
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(value, style: AppText.statValue),
        Text(
          label,
          style: AppText.caption,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}
