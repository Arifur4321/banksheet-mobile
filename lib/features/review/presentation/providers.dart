/// The cross-document review queue.
///
/// Every decision here is optimistic: the row leaves the list the instant the
/// finger lifts, and only goes back if the server refuses. A reviewer working
/// through two hundred rows on a train cannot wait for a round trip per swipe,
/// and a queue that stutters is a queue nobody finishes.
///
/// Rollback restores the row to its sorted position rather than to wherever it
/// happened to be, because a failed swipe that puts a row back in the wrong
/// place looks like data corruption.
library;

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/strings.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/providers.dart';
import '../../../core/utils/json.dart';
import '../../documents/data/transaction_repository.dart';
import '../../documents/domain/transaction.dart';

/// The status chips above the queue.
enum ReviewFilter {
  pending,
  edited,
  approved,
  rejected,
  all;

  /// The `review_status` query value. `all` is the server's own escape hatch,
  /// not a client-side pass-through.
  String get wire => switch (this) {
        ReviewFilter.pending => ReviewStatus.pendingReview.wire,
        ReviewFilter.edited => ReviewStatus.edited.wire,
        ReviewFilter.approved => ReviewStatus.approved.wire,
        ReviewFilter.rejected => ReviewStatus.rejected.wire,
        ReviewFilter.all => 'all',
      };

  String get label => switch (this) {
        ReviewFilter.pending => S.pendingReview,
        ReviewFilter.edited => S.edited,
        ReviewFilter.approved => S.approved,
        ReviewFilter.rejected => S.rejected,
        ReviewFilter.all => S.all,
      };

  /// Whether a row with this status still belongs in the current view after it
  /// was changed.
  bool admits(ReviewStatus status) => switch (this) {
        ReviewFilter.all => true,
        ReviewFilter.pending => status == ReviewStatus.pendingReview,
        ReviewFilter.edited => status == ReviewStatus.edited,
        ReviewFilter.approved => status == ReviewStatus.approved,
        ReviewFilter.rejected => status == ReviewStatus.rejected,
      };
}

/// The outcome of "approve everything on screen".
class BulkApproveResult {
  const BulkApproveResult({required this.approved, this.error});

  final int approved;

  /// The failure that stopped the run, if one did. The rows before it were
  /// still approved — this is not a transaction.
  final Object? error;
}

@immutable
class ReviewQueueState {
  const ReviewQueueState({
    required this.page,
    required this.filter,
    required this.isLoadingMore,
    this.loadMoreError,
  });

  const ReviewQueueState.initial()
      : page = const AsyncValue<Paged<ExtractedTransaction>>.loading(),
        filter = ReviewFilter.pending,
        isLoadingMore = false,
        loadMoreError = null;

  final AsyncValue<Paged<ExtractedTransaction>> page;
  final ReviewFilter filter;
  final bool isLoadingMore;
  final Object? loadMoreError;

  List<ExtractedTransaction> get rows =>
      page.valueOrNull?.items ?? const <ExtractedTransaction>[];

  bool get hasMore => page.valueOrNull?.meta.hasMore ?? false;

  int get total => page.valueOrNull?.meta.total ?? 0;

  int get openCount =>
      rows.where((ExtractedTransaction t) => t.isOpen).length;

  ReviewQueueState copyWith({
    AsyncValue<Paged<ExtractedTransaction>>? page,
    ReviewFilter? filter,
    bool? isLoadingMore,
    Object? loadMoreError,
    bool clearLoadMoreError = false,
  }) {
    return ReviewQueueState(
      page: page ?? this.page,
      filter: filter ?? this.filter,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      loadMoreError:
          clearLoadMoreError ? null : (loadMoreError ?? this.loadMoreError),
    );
  }
}

class ReviewQueueController extends StateNotifier<ReviewQueueState> {
  ReviewQueueController(this._repository)
      : super(const ReviewQueueState.initial()) {
    unawaited(refresh());
  }

  final TransactionRepository _repository;

  final CancelToken _cancelToken = CancelToken();
  int _generation = 0;

  // ----------------------------------------------------------------- read

  Future<void> refresh({bool showLoading = false}) async {
    final int generation = ++_generation;

    if (showLoading || !state.page.hasValue) {
      state = state.copyWith(
        page: const AsyncValue<Paged<ExtractedTransaction>>.loading(),
        isLoadingMore: false,
        clearLoadMoreError: true,
      );
    }

    try {
      final Paged<ExtractedTransaction> first = await _repository.list(
        reviewStatus: state.filter.wire,
        cancelToken: _cancelToken,
      );
      if (!mounted || generation != _generation) {
        return;
      }
      state = state.copyWith(
        page: AsyncValue<Paged<ExtractedTransaction>>.data(first),
        isLoadingMore: false,
        clearLoadMoreError: true,
      );
    } catch (error, stackTrace) {
      if (!mounted || generation != _generation) {
        return;
      }
      if (ApiException.from(error).isCancelled) {
        return;
      }
      state = state.copyWith(
        page: AsyncValue<Paged<ExtractedTransaction>>.error(error, stackTrace),
        isLoadingMore: false,
      );
    }
  }

  Future<void> loadMore() async {
    final Paged<ExtractedTransaction>? current = state.page.valueOrNull;
    if (current == null || !current.meta.hasMore || state.isLoadingMore) {
      return;
    }

    final int generation = _generation;
    state = state.copyWith(isLoadingMore: true, clearLoadMoreError: true);

    try {
      final Paged<ExtractedTransaction> next = await _repository.list(
        page: current.meta.currentPage + 1,
        reviewStatus: state.filter.wire,
        cancelToken: _cancelToken,
      );
      if (!mounted || generation != _generation) {
        return;
      }
      state = state.copyWith(
        page: AsyncValue<Paged<ExtractedTransaction>>.data(
          // Rows decided since page 1 loaded are gone from the local list but
          // still shift the server's offsets; merging by id keeps a row that
          // straddles the page boundary from appearing twice.
          _merge(state.page.valueOrNull ?? current, next),
        ),
        isLoadingMore: false,
      );
    } catch (error) {
      if (!mounted || generation != _generation) {
        return;
      }
      state = ApiException.from(error).isCancelled
          ? state.copyWith(isLoadingMore: false, clearLoadMoreError: true)
          : state.copyWith(isLoadingMore: false, loadMoreError: error);
    }
  }

  void setFilter(ReviewFilter filter) {
    if (filter == state.filter) {
      return;
    }
    state = state.copyWith(filter: filter);
    unawaited(refresh(showLoading: true));
  }

  // ---------------------------------------------------------------- write

  /// Approve or reject one row.
  ///
  /// The removal happens synchronously — before the first `await` — because a
  /// `Dismissible` asserts if the item it just dismissed is still in the list on
  /// the next build.
  Future<void> decide(ExtractedTransaction row, ReviewStatus status) async {
    _remove(row.id);

    try {
      final ExtractedTransaction updated = await _repository.update(
        row.id,
        TransactionEdit.statusOnly(status),
        cancelToken: _cancelToken,
      );
      if (!mounted) {
        return;
      }
      if (state.filter.admits(updated.reviewStatus)) {
        _insert(updated);
      }
    } catch (error) {
      if (!mounted || ApiException.from(error).isCancelled) {
        return;
      }
      // Put it back exactly where the server would sort it, then let the screen
      // report the failure.
      _insert(row);
      rethrow;
    }
  }

  /// Fold an edit made in the sheet back into the queue: keep the row where the
  /// server would sort it if the current filter still admits it, drop it if the
  /// new status moved it out of this view.
  void applyEdit(ExtractedTransaction updated) {
    if (!mounted) {
      return;
    }
    if (state.filter.admits(updated.reviewStatus)) {
      _insert(updated);
    } else {
      _remove(updated.id);
    }
  }

  /// Restore a row to the status it had before a swipe.
  Future<void> undo(ExtractedTransaction original) async {
    final ExtractedTransaction updated = await _repository.update(
      original.id,
      TransactionEdit.statusOnly(original.reviewStatus),
      cancelToken: _cancelToken,
    );
    if (!mounted) {
      return;
    }
    if (state.filter.admits(updated.reviewStatus)) {
      _insert(updated);
    }
  }

  /// Approve every open row currently loaded.
  ///
  /// One request per row: the server's only bulk endpoint is scoped to a single
  /// document, and this queue spans all of them. It stops at the first failure
  /// and reports how far it got, because silently approving 12 of 30 rows and
  /// saying nothing is how a reviewer loses trust in the screen.
  Future<BulkApproveResult> approveVisible() async {
    final List<ExtractedTransaction> targets = state.rows
        .where((ExtractedTransaction t) => t.isOpen)
        .toList(growable: false);

    int approved = 0;
    for (final ExtractedTransaction row in targets) {
      if (!mounted) {
        break;
      }
      try {
        await decide(row, ReviewStatus.approved);
        approved++;
      } catch (error) {
        return BulkApproveResult(approved: approved, error: error);
      }
    }
    return BulkApproveResult(approved: approved);
  }

  void reset() {
    _generation++;
    state = const ReviewQueueState.initial();
    unawaited(refresh(showLoading: true));
  }

  // ------------------------------------------------------------ internals

  void _remove(int id) {
    final Paged<ExtractedTransaction>? current = state.page.valueOrNull;
    if (current == null) {
      return;
    }
    state = state.copyWith(
      page: AsyncValue<Paged<ExtractedTransaction>>.data(
        Paged<ExtractedTransaction>(
          items: current.items
              .where((ExtractedTransaction t) => t.id != id)
              .toList(growable: false),
          meta: current.meta,
        ),
      ),
    );
  }

  void _insert(ExtractedTransaction row) {
    final Paged<ExtractedTransaction>? current = state.page.valueOrNull;
    if (current == null) {
      return;
    }
    final List<ExtractedTransaction> items = <ExtractedTransaction>[
      ...current.items.where((ExtractedTransaction t) => t.id != row.id),
    ];

    int index = 0;
    while (index < items.length && _compare(items[index], row) < 0) {
      index++;
    }
    items.insert(index, row);

    state = state.copyWith(
      page: AsyncValue<Paged<ExtractedTransaction>>.data(
        Paged<ExtractedTransaction>(items: items, meta: current.meta),
      ),
    );
  }

  static Paged<ExtractedTransaction> _merge(
    Paged<ExtractedTransaction> current,
    Paged<ExtractedTransaction> next,
  ) {
    final Set<int> seen =
        current.items.map((ExtractedTransaction t) => t.id).toSet();
    return Paged<ExtractedTransaction>(
      items: <ExtractedTransaction>[
        ...current.items,
        ...next.items.where((ExtractedTransaction t) => !seen.contains(t.id)),
      ],
      meta: next.meta,
    );
  }

  /// The server's ordering: `document_id`, then `position`, then `id`.
  static int _compare(ExtractedTransaction a, ExtractedTransaction b) {
    final int byDocument =
        (a.documentId ?? 0).compareTo(b.documentId ?? 0);
    if (byDocument != 0) {
      return byDocument;
    }
    final int byPosition = (a.position ?? 0).compareTo(b.position ?? 0);
    if (byPosition != 0) {
      return byPosition;
    }
    return a.id.compareTo(b.id);
  }

  @override
  void dispose() {
    _generation++;
    _cancelToken.cancel();
    super.dispose();
  }
}

final StateNotifierProvider<ReviewQueueController, ReviewQueueState>
    reviewQueueProvider =
    StateNotifierProvider<ReviewQueueController, ReviewQueueState>(
  (Ref ref) {
    final ReviewQueueController controller =
        ReviewQueueController(ref.watch(transactionRepositoryProvider));
    ref.listen<int>(
      sessionSignalProvider,
      (int? _, int __) => controller.reset(),
    );
    return controller;
  },
);
