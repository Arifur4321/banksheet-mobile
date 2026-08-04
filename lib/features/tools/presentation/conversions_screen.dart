/// The conversion history.
///
/// Everything the workspace has run through PDF Tools, newest first, barcodes
/// included — they are the same rows on the server and hiding them here would
/// mean a barcode a user generated on the phone had nowhere to be found again.
///
/// The three destructive-ish actions follow the server's own rules: only a
/// failed job (or a finished one whose file has been swept) can be retried,
/// nothing that is mid-processing can be deleted, and deletion is confirmed
/// because it also removes the private source files behind the row.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../core/i18n/strings.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/page_scaffold.dart';
import '../../../core/widgets/states.dart';
import '../data/tool_repository.dart';
import '../domain/conversion.dart';
import 'conversion_files.dart';
import 'providers.dart';
import 'widgets/conversion_card.dart';

class ConversionsScreen extends ConsumerStatefulWidget {
  const ConversionsScreen({super.key});

  @override
  ConsumerState<ConversionsScreen> createState() => _ConversionsScreenState();
}

class _ConversionsScreenState extends ConsumerState<ConversionsScreen> {
  /// The row with an action in flight, so only that card shows a bar.
  int? _busyId;

  ConversionListController get _controller =>
      ref.read(conversionListProvider.notifier);

  ToolRepository get _repository => ref.read(toolRepositoryProvider);

  bool _onScroll(ScrollNotification notification) {
    // 600 px of runway: far enough that the next page has usually landed before
    // the user reaches the bottom, close enough not to prefetch the archive.
    if (notification.metrics.extentAfter < 600) {
      _controller.loadMore();
    }
    return false;
  }

  Future<void> _run(int id, Future<void> Function() action) async {
    if (_busyId != null) {
      return;
    }
    setState(() => _busyId = id);
    try {
      await action();
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      final ApiException failure = ApiException.from(error);
      if (failure.isQuota) {
        Toast.error(context, failure);
        context.pushNamed(AppRoute.billing);
        return;
      }
      Toast.error(context, failure);
    } finally {
      if (mounted) {
        setState(() => _busyId = null);
      }
    }
  }

  Future<void> _retry(Conversion conversion) => _run(conversion.id, () async {
        await _repository.retry(conversion.id);
        if (!context.mounted) {
          return;
        }
        Toast.success(context, S.conversionRequeued);
        await _controller.refresh();
      });

  Future<void> _delete(Conversion conversion) async {
    final bool confirmed = await confirmAction(
      context,
      title: S.deleteConversion,
      message: S.deleteConversionBody,
      confirmLabel: S.delete,
      destructive: true,
    );
    if (!context.mounted || !confirmed) {
      return;
    }

    await _run(conversion.id, () async {
      await _repository.delete(conversion.id);
      if (!context.mounted) {
        return;
      }
      _controller.remove(conversion.id);
      Toast.success(context, S.conversionDeleted);
    });
  }

  @override
  Widget build(BuildContext context) {
    final ConversionListState state = ref.watch(conversionListProvider);
    final ConversionFiles files = ConversionFiles(_repository);

    return NotificationListener<ScrollNotification>(
      onNotification: _onScroll,
      child: PageScaffold(
        title: S.conversions,
        subtitle: state.total > 0 ? S.conversionCount(state.total) : null,
        showBack: true,
        padding: EdgeInsets.zero,
        onRefresh: () => _controller.refresh(),
        child: _body(state, files),
      ),
    );
  }

  Widget _body(ConversionListState state, ConversionFiles files) {
    if (state.page.isLoading && !state.page.hasValue) {
      return const SingleChildScrollView(
        physics: AlwaysScrollableScrollPhysics(),
        child: SkeletonList(),
      );
    }

    if (state.page.hasError && !state.page.hasValue) {
      return LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) =>
            SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: ErrorState(
              error: state.page.error!,
              onRetry: () => _controller.refresh(showLoading: true),
              onUpgrade: () => context.pushNamed(AppRoute.billing),
            ),
          ),
        ),
      );
    }

    final List<Conversion> rows = state.items;

    if (rows.isEmpty) {
      return LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) =>
            SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: EmptyState(
              icon: Icons.history_rounded,
              title: S.noConversions,
              body: S.noConversionsBody,
              actionLabel: S.pdfTools,
              onAction: () => context.pop(),
            ),
          ),
        ),
      );
    }

    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.page,
        AppSpacing.page,
        AppSpacing.page,
        AppSpacing.section,
      ),
      itemCount: rows.length + 1,
      separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.md),
      itemBuilder: (BuildContext context, int index) {
        if (index == rows.length) {
          return _Footer(
            isLoadingMore: state.isLoadingMore,
            error: state.loadMoreError,
            onRetry: _controller.loadMore,
          );
        }

        final Conversion conversion = rows[index];
        final bool downloadable = conversion.isDownloadable;

        return ConversionCard(
          conversion: conversion,
          busy: _busyId == conversion.id,
          onOpen: downloadable
              ? () => _run(
                    conversion.id,
                    () => files.open(context, conversion),
                  )
              : null,
          onDownload: downloadable
              ? () => _run(
                    conversion.id,
                    () => files.save(context, conversion),
                  )
              : null,
          onShare: downloadable
              ? () => _run(
                    conversion.id,
                    () => files.share(context, conversion),
                  )
              : null,
          onRetry: () => _retry(conversion),
          onDelete: () => _delete(conversion),
        );
      },
    );
  }
}

/// The bottom of the list: a spinner while another page loads, a retry when one
/// failed, and breathing room otherwise.
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
        padding: const EdgeInsets.only(top: AppSpacing.md),
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

    return const SizedBox(height: AppSpacing.lg);
  }
}
