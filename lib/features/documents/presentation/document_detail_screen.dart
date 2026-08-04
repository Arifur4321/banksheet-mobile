/// One document, end to end: what was extracted, whether it balances, and every
/// row a reviewer has to decide on.
///
/// While the document is working the screen is driven by the status poller and
/// says so honestly — the extraction runs on the server's queue and does not
/// need this screen open. When it finishes, the poll settles and the full detail
/// is re-fetched once, rather than the app polling the large payload the whole
/// time.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../app/routes.dart';
import '../../../core/i18n/strings.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/theme/typography.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/page_scaffold.dart';
import '../../../core/widgets/states.dart';
import '../data/document_repository.dart';
import '../data/transaction_repository.dart';
import '../domain/document.dart';
import '../domain/transaction.dart';
import 'providers.dart';
import 'widgets/export_sheet.dart';
import 'widgets/processing_card.dart';
import 'widgets/reconciliation_card.dart';
import 'widgets/statement_summary_card.dart';
import 'widgets/transaction_edit_sheet.dart';
import 'widgets/transaction_row.dart';

/// What the reprocess sheet resolved to. A class rather than a bare `int?`,
/// because "auto-match" *is* null and has to be distinguishable from "the user
/// backed out".
class _ReprocessChoice {
  const _ReprocessChoice(this.profileId);

  final int? profileId;
}

enum _MenuAction { reprocess, downloadOriginal, delete }

class DocumentDetailScreen extends ConsumerStatefulWidget {
  const DocumentDetailScreen({required this.documentId, super.key});

  final int documentId;

  @override
  ConsumerState<DocumentDetailScreen> createState() =>
      _DocumentDetailScreenState();
}

class _DocumentDetailScreenState
    extends ConsumerState<DocumentDetailScreen> {
  /// Guards every action that hits the network, so a double tap cannot start
  /// two exports or two deletes.
  bool _busy = false;

  DocumentDetailController get _controller =>
      ref.read(documentDetailProvider(widget.documentId).notifier);

  DocumentRepository get _documents => ref.read(documentRepositoryProvider);

  // ------------------------------------------------------------- actions

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) {
      return;
    }
    setState(() => _busy = true);
    try {
      await action();
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      Toast.error(context, error);
      if (ApiException.from(error).isQuota) {
        context.pushNamed(AppRoute.billing);
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _reprocess(DocumentDetail detail) async {
    if (!detail.isPdf) {
      Toast.info(context, S.onlyPdfsReprocess);
      return;
    }

    final _ReprocessChoice? choice = await _showReprocessSheet(detail);
    if (!context.mounted || choice == null) {
      return;
    }

    await _run(() async {
      await _documents.reprocess(
        widget.documentId,
        profileId: choice.profileId,
      );
      if (!context.mounted) {
        return;
      }
      Toast.success(context, S.reprocessStarted);
      await _controller.load(showLoading: true);
    });
  }

  Future<_ReprocessChoice?> _showReprocessSheet(DocumentDetail detail) {
    return showModalBottomSheet<_ReprocessChoice>(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext sheetContext) => _ReprocessSheet(
        currentProfileId: detail.summary.extractionProfile?.id,
      ),
    );
  }

  Future<void> _approveAll(DocumentDetail detail) async {
    final bool confirmed = await confirmAction(
      context,
      title: S.approveAll,
      message: S.approveAllConfirm,
      confirmLabel: S.approve,
    );
    if (!context.mounted || !confirmed) {
      return;
    }

    await _run(() async {
      final ApproveAllResult result =
          await _documents.approveAll(widget.documentId);
      if (!context.mounted) {
        return;
      }
      Toast.success(context, S.approvedRows(result.approvedCount));
      await _controller.load();
    });
  }

  Future<void> _export(DocumentDetail detail) async {
    final ExportChoice? choice = await showExportSheet(
      context,
      recent: detail.exports,
    );
    if (!context.mounted || choice == null) {
      return;
    }

    await _run(() async {
      // `late` rather than plain finals: the switch below is exhaustive over a
      // sealed type, and this keeps that fact from being load-bearing for
      // definite-assignment analysis.
      late final int exportId;
      late final String filename;

      switch (choice) {
        case NewExportChoice(:final String format):
          final ExportResult created =
              await _documents.export(widget.documentId, format);
          exportId = created.exportId;
          filename = created.filename;
        case ExistingExportChoice(:final DocumentExport export):
          exportId = export.id;
          filename = export.filename;
      }

      final File file = await _documents.downloadExport(
        exportId,
        await _tempPath(filename),
      );
      if (!context.mounted) {
        return;
      }
      await _share(file, filename);
      if (!context.mounted) {
        return;
      }
      Toast.success(context, S.exportReady);
      // A new export changes the archive shown in the sheet next time.
      await _controller.load();
    });
  }

  Future<void> _downloadOriginal(DocumentDetail detail) async {
    await _run(() async {
      final File file = await _documents.downloadOriginal(
        widget.documentId,
        await _tempPath(detail.displayName),
      );
      if (!context.mounted) {
        return;
      }
      await _share(file, detail.displayName);
    });
  }

  Future<void> _delete() async {
    final bool confirmed = await confirmAction(
      context,
      title: S.deleteDocument,
      message: S.deleteDocumentBody,
      confirmLabel: S.delete,
      destructive: true,
    );
    if (!context.mounted || !confirmed) {
      return;
    }

    await _run(() async {
      await _documents.delete(widget.documentId);
      if (!context.mounted) {
        return;
      }
      ref.read(documentListProvider.notifier).remove(widget.documentId);
      Toast.success(context, S.documentDeleted);
      context.pop();
    });
  }

  Future<void> _editRow(ExtractedTransaction row) async {
    final TransactionRepository transactions =
        ref.read(transactionRepositoryProvider);

    final ExtractedTransaction? updated = await showTransactionEditSheet(
      context,
      transaction: row,
      onSave: (TransactionEdit edit) => transactions.update(row.id, edit),
    );

    if (!context.mounted || updated == null) {
      return;
    }
    _controller.replaceTransaction(updated);
    Toast.success(context, S.transactionUpdated);
  }

  Future<String> _tempPath(String filename) async {
    final Directory directory = await getTemporaryDirectory();
    // Sanitised: a filename from the server is data, and a path separator in it
    // would write outside the temp directory.
    final String safe = p.basename(filename).replaceAll(
          RegExp(r'[^A-Za-z0-9._-]'),
          '_',
        );
    return p.join(directory.path, safe.isEmpty ? 'download' : safe);
  }

  Future<void> _share(File file, String filename) {
    final RenderObject? box = context.findRenderObject();
    return Share.shareXFiles(
      <XFile>[XFile(file.path, name: filename)],
      subject: filename,
      // Required on iPad: without an anchor the share sheet has nowhere to
      // attach and the call throws.
      sharePositionOrigin: box is RenderBox
          ? box.localToGlobal(Offset.zero) & box.size
          : null,
    );
  }

  bool _onScroll(ScrollNotification notification) {
    if (notification.metrics.extentAfter < 600) {
      _controller.loadMore();
    }
    return false;
  }

  // --------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    // When a run finishes here, the row in the list behind this screen is
    // stale — same document, old status. Pushing the summary across is cheaper
    // and less jarring than invalidating the whole list and losing the user's
    // scroll position and search term.
    ref.listen<DocumentDetailState>(
      documentDetailProvider(widget.documentId),
      (DocumentDetailState? previous, DocumentDetailState next) {
        final DocumentSummary? updated = next.detail.valueOrNull?.summary;
        if (updated != null &&
            updated != previous?.detail.valueOrNull?.summary) {
          ref.read(documentListProvider.notifier).replace(updated);
        }
      },
    );

    final DocumentDetailState state =
        ref.watch(documentDetailProvider(widget.documentId));
    final DocumentDetail? detail = state.detail.valueOrNull;
    final bool working = detail?.state.isWorking ?? false;

    // The poller is only subscribed to while there is something to poll, which
    // is what stops it and disposes the provider the moment the run settles.
    AsyncValue<DocumentStatusInfo> poll =
        const AsyncValue<DocumentStatusInfo>.loading();
    if (working) {
      poll = ref.watch(documentStatusPollProvider(widget.documentId));
      ref.listen<AsyncValue<DocumentStatusInfo>>(
        documentStatusPollProvider(widget.documentId),
        (AsyncValue<DocumentStatusInfo>? previous,
            AsyncValue<DocumentStatusInfo> next) {
          final DocumentStatusInfo? info = next.valueOrNull;
          if (info != null &&
              info.isSettled &&
              previous?.valueOrNull?.isSettled != true) {
            _controller.load();
          }
        },
      );
    }

    return PageScaffold(
      title: detail == null
          ? S.documents
          : Fmt.middleEllipsis(detail.displayName, max: 26),
      subtitle: detail == null
          ? null
          : '${detail.kind.label} · ${Fmt.relative(detail.summary.createdAt)}',
      showBack: true,
      padding: EdgeInsets.zero,
      onRefresh: () => _controller.load(),
      actions: <Widget>[
        if (detail != null)
          PopupMenuButton<_MenuAction>(
            enabled: !_busy,
            icon: const Icon(Icons.more_vert_rounded),
            onSelected: (_MenuAction action) {
              switch (action) {
                case _MenuAction.reprocess:
                  _reprocess(detail);
                case _MenuAction.downloadOriginal:
                  _downloadOriginal(detail);
                case _MenuAction.delete:
                  _delete();
              }
            },
            itemBuilder: (BuildContext context) => <PopupMenuEntry<_MenuAction>>[
              PopupMenuItem<_MenuAction>(
                value: _MenuAction.reprocess,
                enabled: detail.isPdf,
                child: const _MenuRow(
                  icon: Icons.refresh_rounded,
                  label: S.reprocess,
                ),
              ),
              const PopupMenuItem<_MenuAction>(
                value: _MenuAction.downloadOriginal,
                child: _MenuRow(
                  icon: Icons.file_download_outlined,
                  label: S.downloadOriginal,
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem<_MenuAction>(
                value: _MenuAction.delete,
                child: _MenuRow(
                  icon: Icons.delete_outline_rounded,
                  label: S.delete,
                  danger: true,
                ),
              ),
            ],
          ),
      ],
      child: NotificationListener<ScrollNotification>(
        onNotification: _onScroll,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: _slivers(state, detail, poll, working),
        ),
      ),
    );
  }

  List<Widget> _slivers(
    DocumentDetailState state,
    DocumentDetail? detail,
    AsyncValue<DocumentStatusInfo> poll,
    bool working,
  ) {
    if (detail == null) {
      if (state.detail.hasError) {
        return <Widget>[
          SliverFillRemaining(
            hasScrollBody: false,
            child: ErrorState(
              error: state.detail.error!,
              onRetry: () => _controller.load(showLoading: true),
            ),
          ),
        ];
      }
      return const <Widget>[SliverToBoxAdapter(child: SkeletonList())];
    }

    final StatementSummary? summary = detail.statementSummary;
    final List<ExtractedTransaction> rows = state.transactions;
    final double extent =
        TransactionRow.extentFor(context) + AppSpacing.sm;

    return <Widget>[
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.page,
          AppSpacing.lg,
          AppSpacing.page,
          0,
        ),
        sliver: SliverList.list(
          children: <Widget>[
            _FileCard(detail: detail),
            if (detail.state.isFailed) ...<Widget>[
              const SizedBox(height: AppSpacing.lg),
              InlineNotice(
                message: detail.errorMessage ?? S.documentFailed,
                tone: NoticeTone.danger,
                actionLabel: detail.isPdf ? S.retry : null,
                onAction: detail.isPdf ? () => _reprocess(detail) : null,
              ),
            ],
            if (working) ...<Widget>[
              const SizedBox(height: AppSpacing.lg),
              ProcessingCard(poll: poll, fallbackStatus: detail.state),
            ],
            if (summary != null) ...<Widget>[
              const SizedBox(height: AppSpacing.lg),
              StatementSummaryCard(summary: summary),
              const SizedBox(height: AppSpacing.lg),
              ReconciliationCard(
                info: summary.reconciliation,
                currency: summary.currency,
              ),
            ],
            if (detail.state.isProcessed) ...<Widget>[
              const SizedBox(height: AppSpacing.lg),
              _ReviewCard(
                counts: detail.reviewCounts,
                busy: _busy,
                onApproveAll: () => _approveAll(detail),
                onExport: () => _export(detail),
              ),
            ],
            if (detail.state.isProcessed &&
                !detail.isBankStatement &&
                summary == null) ...<Widget>[
              const SizedBox(height: AppSpacing.lg),
              const InlineNotice(
                message: S.notAStatementBody,
                tone: NoticeTone.info,
              ),
            ],
            const SizedBox(height: AppSpacing.section),
            if (rows.isNotEmpty)
              SectionHeader(
                title: S.transactions,
                subtitle: S.transactionCount(state.meta.total),
              ),
          ],
        ),
      ),
      // Only a bank statement is expected to have rows; for an invoice or a
      // generic PDF their absence is the normal case, not an empty state.
      if (rows.isEmpty && detail.state.isProcessed && detail.isBankStatement)
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.all(AppSpacing.page),
            child: EmptyState(
              icon: Icons.receipt_long_outlined,
              title: S.noTransactions,
              body: S.noTransactionsBody,
            ),
          ),
        )
      else if (rows.isNotEmpty)
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.page),
          sliver: SliverFixedExtentList.builder(
            itemExtent: extent,
            itemCount: rows.length,
            itemBuilder: (BuildContext context, int index) {
              final ExtractedTransaction row = rows[index];
              return Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: TransactionRow(
                  transaction: row,
                  onTap: () => _editRow(row),
                ),
              );
            },
          ),
        ),
      SliverToBoxAdapter(
        child: state.isLoadingMore
            ? const Padding(
                padding: EdgeInsets.symmetric(vertical: AppSpacing.xxl),
                child: Center(
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.4),
                  ),
                ),
              )
            : const SizedBox(height: AppSpacing.section),
      ),
    ];
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({
    required this.icon,
    required this.label,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final Color color = danger ? AppColors.danger : AppColors.ink;
    return Row(
      children: <Widget>[
        Icon(icon, size: 19, color: color),
        const SizedBox(width: AppSpacing.md),
        Text(label, style: AppText.body.copyWith(color: color)),
      ],
    );
  }
}

/// The file's own facts, which is what a user checks first when a statement
/// parsed badly.
class _FileCard extends StatelessWidget {
  const _FileCard({required this.detail});

  final DocumentDetail detail;

  @override
  Widget build(BuildContext context) {
    final DocumentSummary document = detail.summary;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  document.displayName,
                  style: AppText.h3,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              StatusBadge(document.status),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.lg,
            runSpacing: AppSpacing.sm,
            children: <Widget>[
              _Fact(
                icon: Icons.description_outlined,
                label: S.pageCount(
                  detail.storedPageCount ?? document.pageCount,
                ),
              ),
              _Fact(
                icon: Icons.sd_storage_outlined,
                label: Fmt.bytes(document.fileSize),
              ),
              if (document.uploadedBy?.name != null)
                _Fact(
                  icon: Icons.person_outline_rounded,
                  label: document.uploadedBy!.name!,
                ),
              _Fact(
                icon: Icons.schedule_rounded,
                label: Fmt.relative(document.createdAt),
              ),
            ],
          ),
          if (document.extractionProfile != null) ...<Widget>[
            const SizedBox(height: AppSpacing.md),
            Text(
              '${S.extractionProfile}: '
              '${document.extractionProfile!.label}',
              style: AppText.caption,
            ),
          ],
          if (detail.latestJob?.engine != null) ...<Widget>[
            const SizedBox(height: 2),
            Text(
              detail.latestJob!.usedOcr
                  ? '${detail.latestJob!.engine} · OCR '
                      '${detail.latestJob!.ocrDriver ?? ''}'.trim()
                  : detail.latestJob!.engine!,
              style: AppText.caption,
            ),
          ],
        ],
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(icon, size: 15, color: AppColors.inkFaint),
        const SizedBox(width: 4),
        Text(label, style: AppText.caption),
      ],
    );
  }
}

/// How much of this document has been checked, and the two things to do next.
class _ReviewCard extends StatelessWidget {
  const _ReviewCard({
    required this.counts,
    required this.busy,
    required this.onApproveAll,
    required this.onExport,
  });

  final ReviewCounts counts;
  final bool busy;
  final VoidCallback onApproveAll;
  final VoidCallback onExport;

  @override
  Widget build(BuildContext context) {
    final int total = counts.total ?? 0;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(child: Text(S.reviewProgress, style: AppText.h3)),
              Text(
                S.approvedOf(counts.approved ?? 0, total),
                style: AppText.numeric.copyWith(fontSize: 14),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: counts.approvedRatio,
              minHeight: 6,
              backgroundColor: AppColors.border,
              valueColor: const AlwaysStoppedAnimation<Color>(
                AppColors.brand,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: <Widget>[
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: busy || !counts.hasPending ? null : onApproveAll,
                  icon: const Icon(Icons.done_all_rounded, size: 18),
                  label: const Text(S.approveAll),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: FilledButton.icon(
                  onPressed: busy ? null : onExport,
                  icon: const Icon(Icons.ios_share_rounded, size: 18),
                  label: const Text(S.exportData),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Choose the profile to parse with before queueing another run.
///
/// "Auto-match" is a real choice, not an absence of one: submitting it clears
/// the document's stored profile, which is exactly what the web form does.
class _ReprocessSheet extends ConsumerWidget {
  const _ReprocessSheet({required this.currentProfileId});

  final int? currentProfileId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<ProfileRef>> options = ref.watch(
      extractionProfileOptionsProvider(DocumentKind.bankStatement.wire),
    );

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.xl,
          AppSpacing.sm,
          AppSpacing.xl,
          AppSpacing.xl,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(S.reprocessTitle, style: AppText.h3),
            const SizedBox(height: AppSpacing.xs),
            Text(S.reprocessBody, style: AppText.bodySm),
            const SizedBox(height: AppSpacing.lg),
            _ProfileTile(
              title: S.autoMatchProfile,
              selected: currentProfileId == null,
              onTap: () => Navigator.of(context).pop(
                const _ReprocessChoice(null),
              ),
            ),
            options.when(
              loading: () => const Padding(
                padding: EdgeInsets.only(top: AppSpacing.sm),
                child: Skeleton(height: 52, radius: AppRadius.control),
              ),
              error: (Object error, _) => const Padding(
                padding: EdgeInsets.only(top: AppSpacing.sm),
                child: InlineNotice(
                  message: S.profilesUnavailable,
                  tone: NoticeTone.info,
                ),
              ),
              data: (List<ProfileRef> profiles) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  for (final ProfileRef profile in profiles)
                    _ProfileTile(
                      title: profile.label,
                      subtitle: profile.bankName,
                      selected: profile.id == currentProfileId,
                      onTap: () => Navigator.of(context).pop(
                        _ReprocessChoice(profile.id),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text(S.cancel),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileTile extends StatelessWidget {
  const _ProfileTile({
    required this.title,
    required this.selected,
    required this.onTap,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Material(
        color: selected ? AppColors.brandTint : AppColors.surfaceMuted,
        borderRadius: AppRadius.controlAll,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppRadius.controlAll,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Row(
              children: <Widget>[
                Icon(
                  selected
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_unchecked_rounded,
                  size: 19,
                  color: selected ? AppColors.brandDeep : AppColors.inkFaint,
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        title,
                        style: AppText.bodyStrong,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (subtitle != null) ...<Widget>[
                        const SizedBox(height: 2),
                        Text(subtitle!, style: AppText.caption, maxLines: 1),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
