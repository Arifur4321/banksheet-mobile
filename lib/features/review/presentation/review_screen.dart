/// The review queue: every extracted row that still needs a decision, across
/// every document in the workspace.
///
/// This is the screen the product exists for — an extraction nobody checks is
/// an extraction nobody can book — so it is built for speed rather than for
/// ceremony: swipe right to approve, left to reject, with an undo that is a real
/// round trip rather than a delayed commit. The row leaves the list immediately
/// and comes back if the server refuses.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../core/i18n/strings.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/hero_scenes.dart';
import '../../../core/widgets/page_scaffold.dart';
import '../../../core/widgets/states.dart';
import '../../documents/data/transaction_repository.dart';
import '../../documents/domain/transaction.dart';
import '../../documents/presentation/widgets/transaction_edit_sheet.dart';
import '../../documents/presentation/widgets/transaction_row.dart';
import 'providers.dart';

class ReviewScreen extends ConsumerStatefulWidget {
  const ReviewScreen({super.key});

  @override
  ConsumerState<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends ConsumerState<ReviewScreen> {
  bool _busy = false;

  ReviewQueueController get _controller =>
      ref.read(reviewQueueProvider.notifier);

  bool _onScroll(ScrollNotification notification) {
    if (notification.metrics.extentAfter < 600) {
      _controller.loadMore();
    }
    return false;
  }

  // ------------------------------------------------------------- actions

  Future<void> _decide(
    ExtractedTransaction row,
    ReviewStatus status,
  ) async {
    _showUndo(row, status);
    try {
      await _controller.decide(row, status);
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      Toast.error(context, error);
    }
  }

  void _showUndo(ExtractedTransaction row, ReviewStatus applied) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 5),
          content: Text(
            applied == ReviewStatus.approved ? S.rowApproved : S.rowRejected,
            style: AppText.bodySm.copyWith(color: AppColors.inkInverse),
          ),
          action: SnackBarAction(
            label: S.undo,
            textColor: AppColors.brandLight,
            onPressed: () => _undo(row),
          ),
        ),
      );
  }

  Future<void> _undo(ExtractedTransaction row) async {
    try {
      await _controller.undo(row);
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      Toast.error(context, error);
    }
  }

  Future<void> _approveVisible() async {
    final bool confirmed = await confirmAction(
      context,
      title: S.approveAllVisible,
      message: S.approveAllVisibleConfirm,
      confirmLabel: S.approve,
    );
    if (!context.mounted || !confirmed) {
      return;
    }

    setState(() => _busy = true);
    final BulkApproveResult result = await _controller.approveVisible();
    if (!mounted) {
      return;
    }
    setState(() => _busy = false);

    if (!context.mounted) {
      return;
    }
    if (result.error != null) {
      Toast.error(context, result.error!);
    } else {
      Toast.success(context, S.approvedRows(result.approved));
    }
  }

  Future<void> _edit(ExtractedTransaction row) async {
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
    _controller.applyEdit(updated);
    Toast.success(context, S.transactionUpdated);
  }

  void _openDocument(ExtractedTransaction row) {
    final int? documentId = row.documentId ?? row.document?.id;
    if (documentId == null) {
      return;
    }
    context.pushNamed(
      AppRoute.documentDetail,
      pathParameters: <String, String>{'id': '$documentId'},
    );
  }

  // --------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final ReviewQueueState state = ref.watch(reviewQueueProvider);
    final List<ExtractedTransaction> rows = state.rows;
    final double extent =
        TransactionRow.extentFor(context, showDocument: true) + AppSpacing.sm;

    return NotificationListener<ScrollNotification>(
      onNotification: _onScroll,
      child: HeroPageScaffold(
        onRefresh: () => _controller.refresh(),
        slivers: <Widget>[
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.page,
              AppSpacing.page,
              AppSpacing.page,
              AppSpacing.lg,
            ),
            sliver: SliverToBoxAdapter(
              child: HeroPanel(
                eyebrow: S.reviewQueue,
                title: S.reviewSubtitle,
                scene: const ReviewScene(),
                subtitle: state.total > 0 ? S.rowsWaiting(state.total) : null,
                trailing: state.openCount == 0
                    ? null
                    : TextButton.icon(
                        onPressed: _busy ? null : _approveVisible,
                        icon: const Icon(Icons.done_all_rounded, size: 17),
                        label: const Text(S.approveAllVisible),
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.brandLight,
                          padding: EdgeInsets.zero,
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: _FilterChips(
              selected: state.filter,
              onSelect: _controller.setFilter,
            ),
          ),
          if (state.page.isLoading && !state.page.hasValue)
            const SliverToBoxAdapter(child: SkeletonList(height: 84))
          else if (state.page.hasError && !state.page.hasValue)
            SliverFillRemaining(
              hasScrollBody: false,
              child: ErrorState(
                error: state.page.error!,
                onRetry: () => _controller.refresh(showLoading: true),
              ),
            )
          else if (rows.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyState(
                icon: Icons.verified_rounded,
                title: state.filter == ReviewFilter.pending
                    ? S.nothingToReview
                    : S.noRowsHere,
                body: state.filter == ReviewFilter.pending
                    ? S.nothingToReviewBody
                    : S.noRowsHereBody,
              ),
            )
          else ...<Widget>[
            const SliverToBoxAdapter(child: _SwipeHint()),
            SliverPadding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.page,
              ),
              sliver: SliverFixedExtentList.builder(
                itemExtent: extent,
                itemCount: rows.length,
                itemBuilder: (BuildContext context, int index) =>
                    _QueueRow(
                  row: rows[index],
                  onEdit: () => _edit(rows[index]),
                  onOpenDocument: () => _openDocument(rows[index]),
                  onDecide: (ReviewStatus status) =>
                      _decide(rows[index], status),
                ),
              ),
            ),
          ],
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
                : state.loadMoreError == null
                    ? const SizedBox(height: AppSpacing.section)
                    : Padding(
                        padding: const EdgeInsets.all(AppSpacing.page),
                        child: InlineNotice(
                          message: S.couldNotLoadMore,
                          tone: NoticeTone.warn,
                          actionLabel: S.tryAgain,
                          onAction: _controller.loadMore,
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}

/// One swipeable row.
class _QueueRow extends StatelessWidget {
  const _QueueRow({
    required this.row,
    required this.onEdit,
    required this.onOpenDocument,
    required this.onDecide,
  });

  final ExtractedTransaction row;
  final VoidCallback onEdit;
  final VoidCallback onOpenDocument;
  final ValueChanged<ReviewStatus> onDecide;

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: ValueKey<int>(row.id),
      // Only rows that are still open can be swiped: dismissing an already
      // approved row would remove it from a list it belongs in.
      direction:
          row.isOpen ? DismissDirection.horizontal : DismissDirection.none,
      // The list has a fixed item extent, so the shrink animation has nowhere
      // to run. Disabling it makes the dismissal end cleanly instead of
      // snapping.
      resizeDuration: null,
      background: const _SwipeAction(
        alignment: Alignment.centerLeft,
        color: AppColors.brand,
        icon: Icons.check_rounded,
        label: S.approve,
      ),
      secondaryBackground: const _SwipeAction(
        alignment: Alignment.centerRight,
        color: AppColors.danger,
        icon: Icons.close_rounded,
        label: S.reject,
      ),
      onDismissed: (DismissDirection direction) => onDecide(
        direction == DismissDirection.startToEnd
            ? ReviewStatus.approved
            : ReviewStatus.rejected,
      ),
      child: Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
        child: Semantics(
          customSemanticsActions: <CustomSemanticsAction, VoidCallback>{
            const CustomSemanticsAction(label: S.approve): () =>
                onDecide(ReviewStatus.approved),
            const CustomSemanticsAction(label: S.reject): () =>
                onDecide(ReviewStatus.rejected),
            const CustomSemanticsAction(label: S.editTransaction): onEdit,
          },
          // Tap opens the statement the row came from — the context a reviewer
          // needs when a row looks wrong. Long press edits it in place, which
          // is the same gesture the detail list offers on tap, one level down.
          child: GestureDetector(
            onLongPress: onEdit,
            child: TransactionRow(
              transaction: row,
              showDocument: true,
              onTap: onOpenDocument,
            ),
          ),
        ),
      ),
    );
  }
}

class _SwipeAction extends StatelessWidget {
  const _SwipeAction({
    required this.alignment,
    required this.color,
    required this.icon,
    required this.label,
  });

  final Alignment alignment;
  final Color color;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Container(
        alignment: alignment,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
        decoration: BoxDecoration(
          color: color,
          borderRadius: AppRadius.cardAll,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 19, color: AppColors.inkInverse),
            const SizedBox(width: 6),
            Text(
              label,
              style: AppText.button.copyWith(color: AppColors.inkInverse),
            ),
          ],
        ),
      ),
    );
  }
}

class _SwipeHint extends StatelessWidget {
  const _SwipeHint();

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
          const Icon(
            Icons.swipe_rounded,
            size: 15,
            color: AppColors.inkFaint,
          ),
          const SizedBox(width: 6),
          Expanded(child: Text(S.swipeHint, style: AppText.caption)),
        ],
      ),
    );
  }
}

class _FilterChips extends StatelessWidget {
  const _FilterChips({required this.selected, required this.onSelect});

  final ReviewFilter selected;
  final ValueChanged<ReviewFilter> onSelect;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 54,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.page,
          AppSpacing.sm,
          AppSpacing.page,
          AppSpacing.md,
        ),
        itemCount: ReviewFilter.values.length,
        separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.sm),
        itemBuilder: (BuildContext context, int index) {
          final ReviewFilter filter = ReviewFilter.values[index];
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
