/// What a job found, one website at a time.
///
/// Grouped per website rather than as a flat contact list, because an email
/// only means something next to the domain it was published on. Every value is
/// one tap to copy and carries the page it came from.
///
/// Export downloads the spreadsheet the server builds — the same file the
/// website produces, deduplicated the same way — and hands it to the share
/// sheet, which is the only way a file leaves a phone usefully.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/routes.dart';
import '../../../core/i18n/strings.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/utils/logger.dart';
import '../../../core/widgets/page_scaffold.dart';
import '../../../core/widgets/states.dart';
import '../data/web_extraction_repository.dart';
import '../domain/web_job.dart';
import 'providers.dart';
import 'widgets/export_sheet.dart';
import 'widgets/result_card.dart';

class WebExtractionResultsScreen extends ConsumerStatefulWidget {
  const WebExtractionResultsScreen({required this.jobId, super.key});

  final int jobId;

  @override
  ConsumerState<WebExtractionResultsScreen> createState() =>
      _WebExtractionResultsScreenState();
}

class _WebExtractionResultsScreenState
    extends ConsumerState<WebExtractionResultsScreen> {
  bool _exporting = false;

  WebResultsController get _controller =>
      ref.read(webResultsProvider(widget.jobId).notifier);

  bool _onScroll(ScrollNotification notification) {
    if (notification.metrics.extentAfter < 600) {
      _controller.loadMore();
    }
    return false;
  }

  Future<void> _openSource(String url) async {
    final Uri? uri = Uri.tryParse(url);
    if (uri == null) {
      return;
    }

    bool opened = false;
    try {
      opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (error) {
      // A device with no browser, or a scheme the platform refuses. Neither is
      // worth an error dialog over a link the user can still copy.
      Log.warn('Web extraction: could not open $url — $error');
    }

    if (!context.mounted || opened) {
      return;
    }
    Toast.info(context, S.couldNotOpenLink);
  }

  Future<void> _export() async {
    final String? format = await showWebExportSheet(context);
    if (!context.mounted || format == null) {
      return;
    }

    setState(() => _exporting = true);

    try {
      final Directory directory = await getTemporaryDirectory();
      final String filename = 'web-extraction-${widget.jobId}.$format';
      final File file = await ref
          .read(webExtractionRepositoryProvider)
          .export(
            widget.jobId,
            format,
            p.join(directory.path, filename),
          );

      if (!context.mounted) {
        return;
      }

      final RenderObject? box = context.findRenderObject();
      await Share.shareXFiles(
        <XFile>[XFile(file.path, name: filename)],
        subject: filename,
        // Required on iPad: without an anchor the share sheet has nowhere to
        // attach and the call throws.
        sharePositionOrigin:
            box is RenderBox ? box.localToGlobal(Offset.zero) & box.size : null,
      );
    } catch (error) {
      Log.warn('Web extraction: export failed — $error');
      if (!context.mounted) {
        return;
      }
      Toast.error(context, error);
    } finally {
      if (mounted) {
        setState(() => _exporting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final WebResultsState state = ref.watch(webResultsProvider(widget.jobId));

    return NotificationListener<ScrollNotification>(
      onNotification: _onScroll,
      child: PageScaffold(
        title: S.results,
        subtitle: state.total > 0 ? S.websiteCount(state.total) : null,
        showBack: true,
        padding: EdgeInsets.zero,
        onRefresh: () => _controller.refresh(),
        actions: <Widget>[
          IconButton(
            onPressed: _exporting ? null : _export,
            icon: _exporting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2.2),
                  )
                : const Icon(Icons.file_download_outlined),
            tooltip: S.webExportTitle,
          ),
        ],
        child: Column(
          children: <Widget>[
            _FilterBar(
              emailsOnly: state.emailsOnly,
              onChanged: (bool value) =>
                  _controller.setEmailsOnly(enabled: value),
            ),
            Expanded(child: _body(state)),
          ],
        ),
      ),
    );
  }

  Widget _body(WebResultsState state) {
    if (state.page.isLoading && !state.page.hasValue) {
      return const SingleChildScrollView(
        physics: AlwaysScrollableScrollPhysics(),
        child: SkeletonList(height: 140),
      );
    }

    if (state.page.hasError && !state.page.hasValue) {
      return _fill(
        ErrorState(
          error: state.page.error!,
          onRetry: () => _controller.refresh(showLoading: true),
          onUpgrade: () => context.pushNamed(AppRoute.billing),
        ),
      );
    }

    final List<WebExtractionTarget> rows = state.items;

    if (rows.isEmpty) {
      return _fill(
        EmptyState(
          icon: Icons.person_search_rounded,
          title: S.noResultsYet,
          body: state.emailsOnly ? S.noResultsFiltered : S.noResultsYetBody,
          actionLabel: state.emailsOnly ? S.clearFilters : null,
          onAction: state.emailsOnly
              ? () => _controller.setEmailsOnly(enabled: false)
              : null,
        ),
      );
    }

    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.page,
        AppSpacing.md,
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
        return ResultCard(target: rows[index], onOpenSource: _openSource);
      },
    );
  }

  Widget _fill(Widget child) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) =>
          SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: child,
        ),
      ),
    );
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({required this.emailsOnly, required this.onChanged});

  final bool emailsOnly;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.page,
        AppSpacing.md,
        AppSpacing.page,
        0,
      ),
      child: Align(
        alignment: Alignment.centerLeft,
        child: FilterChip(
          label: const Text(S.filterWithEmail),
          selected: emailsOnly,
          showCheckmark: false,
          avatar: const Icon(Icons.alternate_email_rounded, size: 16),
          selectedColor: AppColors.brandTint,
          backgroundColor: AppColors.surface,
          side: BorderSide(
            color: emailsOnly ? AppColors.brandTintStrong : AppColors.border,
          ),
          onSelected: onChanged,
        ),
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
