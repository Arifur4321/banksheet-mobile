/// Every PDF this workspace has produced — from a template here, from the
/// contract editor on the website, or uploaded for signature.
///
/// Read-only, because two of those three creation paths need a canvas. What the
/// phone is genuinely good at is the last mile: find the PDF, open it, send it
/// to somebody.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../core/i18n/strings.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/hero_scenes.dart';
import '../../../core/widgets/page_scaffold.dart';
import '../../../core/widgets/states.dart';
import '../../exports/data/file_downloader.dart';
import '../data/generated_pdf_repository.dart';
import '../domain/generated_pdf.dart';
import 'providers.dart';
import 'widgets/generated_pdf_card.dart';

class GeneratedPdfsScreen extends ConsumerStatefulWidget {
  const GeneratedPdfsScreen({super.key});

  @override
  ConsumerState<GeneratedPdfsScreen> createState() =>
      _GeneratedPdfsScreenState();
}

class _GeneratedPdfsScreenState extends ConsumerState<GeneratedPdfsScreen> {
  /// The card currently downloading. One at a time.
  int? _busyId;

  bool _onScroll(ScrollNotification notification) {
    if (notification.metrics.extentAfter < 600) {
      ref.read(generatedPdfListProvider.notifier).loadMore();
    }
    return false;
  }

  Future<void> _run(
    GeneratedPdf pdf,
    FileAction action,
    Rect? origin,
  ) async {
    if (_busyId != null) {
      return;
    }
    setState(() => _busyId = pdf.id);

    try {
      final File file = await ref.read(generatedPdfRepositoryProvider).download(
            pdf.id,
            filename: pdf.filename,
          );
      if (!context.mounted) {
        return;
      }
      await FileDownloader.apply(
        action,
        file,
        subject: pdf.displayName,
        origin: origin,
      );
      if (!context.mounted) {
        return;
      }
      if (action == FileAction.save) {
        Toast.success(context, S.savedToDevice);
      }
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      Toast.error(context, error);
    } finally {
      if (mounted) {
        setState(() => _busyId = null);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final PagedState<GeneratedPdf> state = ref.watch(generatedPdfListProvider);
    final List<GeneratedPdf> rows = state.items;

    return NotificationListener<ScrollNotification>(
      onNotification: _onScroll,
      child: HeroPageScaffold(
        onRefresh: () => ref.read(generatedPdfListProvider.notifier).refresh(),
        slivers: <Widget>[
          const SliverAppBar(
            floating: true,
            toolbarHeight: 52,
            titleSpacing: AppSpacing.lg,
            title: Text(S.generatedPdfs),
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
                eyebrow: S.generatedPdfs,
                title: S.generatedPdfsSubtitle,
                scene: const DocumentsScene(),
                subtitle:
                    state.total > 0 ? S.generatedPdfCount(state.total) : null,
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
                onRetry: () => ref
                    .read(generatedPdfListProvider.notifier)
                    .refresh(showLoading: true),
                onUpgrade: () => context.pushNamed(AppRoute.billing),
              ),
            )
          else if (rows.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyState(
                icon: Icons.picture_as_pdf_outlined,
                title: S.noGeneratedPdfs,
                body: S.noGeneratedPdfsBody,
                actionLabel: S.templates,
                onAction: () => context.pushNamed(AppRoute.templates),
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
                  final GeneratedPdf pdf = rows[index];
                  return GeneratedPdfCard(
                    pdf: pdf,
                    isBusy: _busyId == pdf.id,
                    onAction: (FileAction action, Rect? origin) =>
                        _run(pdf, action, origin),
                  );
                },
              ),
            ),
          SliverToBoxAdapter(
            child: _ListFooter(
              isLoadingMore: state.isLoadingMore,
              error: state.loadMoreError,
              onRetry: () =>
                  ref.read(generatedPdfListProvider.notifier).loadMore(),
            ),
          ),
        ],
      ),
    );
  }
}

/// The bottom of the list: a spinner while another page loads, a retry when one
/// failed, breathing room otherwise.
class _ListFooter extends StatelessWidget {
  const _ListFooter({
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

    return const SizedBox(height: AppSpacing.section);
  }
}
