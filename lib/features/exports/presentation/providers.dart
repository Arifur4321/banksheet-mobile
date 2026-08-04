/// State for the export archive: one paginated list, grouped by day when it is
/// rendered.
///
/// A [StateNotifier] rather than a `FutureProvider` because the list appends
/// pages to what is already on screen and needs an `isLoadingMore` flag that is
/// distinct from "the whole screen is loading" — neither of which a future can
/// express. In-flight requests are cancelled on dispose, and the whole thing is
/// dropped when the session ends so the next account never sees the previous
/// one's spreadsheets.
library;

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/providers.dart';
import '../../../core/utils/json.dart';
import '../data/export_repository.dart';
import '../domain/export_archive.dart';

@immutable
class ExportListState {
  const ExportListState({
    required this.page,
    required this.isLoadingMore,
    this.loadMoreError,
  });

  const ExportListState.initial()
      : page = const AsyncValue<Paged<ExportArchive>>.loading(),
        isLoadingMore = false,
        loadMoreError = null;

  /// Every page fetched so far, merged.
  final AsyncValue<Paged<ExportArchive>> page;

  final bool isLoadingMore;

  /// A failed "load more", kept apart from [page] so one bad page does not
  /// throw away the rows the user is already reading.
  final Object? loadMoreError;

  List<ExportArchive> get items =>
      page.valueOrNull?.items ?? const <ExportArchive>[];

  bool get hasMore => page.valueOrNull?.meta.hasMore ?? false;

  int get total => page.valueOrNull?.meta.total ?? 0;

  ExportListState copyWith({
    AsyncValue<Paged<ExportArchive>>? page,
    bool? isLoadingMore,
    Object? loadMoreError,
    bool clearLoadMoreError = false,
  }) {
    return ExportListState(
      page: page ?? this.page,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      loadMoreError:
          clearLoadMoreError ? null : (loadMoreError ?? this.loadMoreError),
    );
  }
}

class ExportListController extends StateNotifier<ExportListState> {
  ExportListController(this._repository)
      : super(const ExportListState.initial()) {
    unawaited(refresh());
  }

  final ExportRepository _repository;
  final CancelToken _cancelToken = CancelToken();

  /// Bumped on every reset so a slow in-flight page cannot land on top of a
  /// list that belongs to a different session.
  int _generation = 0;

  Future<void> refresh({bool showLoading = false}) async {
    final int generation = ++_generation;

    if (showLoading || !state.page.hasValue) {
      state = state.copyWith(
        page: const AsyncValue<Paged<ExportArchive>>.loading(),
        isLoadingMore: false,
        clearLoadMoreError: true,
      );
    }

    try {
      final Paged<ExportArchive> first =
          await _repository.list(cancelToken: _cancelToken);
      if (!mounted || generation != _generation) {
        return;
      }
      state = state.copyWith(
        page: AsyncValue<Paged<ExportArchive>>.data(first),
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
        page: AsyncValue<Paged<ExportArchive>>.error(error, stackTrace),
        isLoadingMore: false,
      );
    }
  }

  Future<void> loadMore() async {
    final Paged<ExportArchive>? current = state.page.valueOrNull;
    if (current == null || !current.meta.hasMore || state.isLoadingMore) {
      return;
    }

    final int generation = _generation;
    state = state.copyWith(isLoadingMore: true, clearLoadMoreError: true);

    try {
      final Paged<ExportArchive> next = await _repository.list(
        page: current.meta.currentPage + 1,
        cancelToken: _cancelToken,
      );
      if (!mounted || generation != _generation) {
        return;
      }
      state = state.copyWith(
        page: AsyncValue<Paged<ExportArchive>>.data(current.merge(next)),
        isLoadingMore: false,
      );
    } catch (error) {
      if (!mounted || generation != _generation) {
        return;
      }
      // The flag has to be cleared even on a cancel, or the scroll sentinel
      // jams and the list never loads another page.
      state = ApiException.from(error).isCancelled
          ? state.copyWith(isLoadingMore: false, clearLoadMoreError: true)
          : state.copyWith(isLoadingMore: false, loadMoreError: error);
    }
  }

  /// Forget everything. Called when the session ends.
  void reset() {
    _generation++;
    state = const ExportListState.initial();
    unawaited(refresh(showLoading: true));
  }

  @override
  void dispose() {
    _generation++;
    _cancelToken.cancel();
    super.dispose();
  }
}

final StateNotifierProvider<ExportListController, ExportListState>
    exportListProvider =
    StateNotifierProvider<ExportListController, ExportListState>(
  (Ref ref) {
    final ExportListController controller =
        ExportListController(ref.watch(exportRepositoryProvider));
    ref.listen<int>(
      sessionSignalProvider,
      (int? _, int __) => controller.reset(),
    );
    return controller;
  },
);

/// The list split into calendar days, newest first, in the order the server
/// already sorted them.
///
/// Computed in a provider rather than in `build()` so scrolling a long archive
/// does not re-group it on every frame.
final Provider<List<ExportDayGroup>> exportDayGroupsProvider =
    Provider<List<ExportDayGroup>>((Ref ref) {
  final List<ExportArchive> items = ref.watch(exportListProvider).items;

  final List<ExportDayGroup> groups = <ExportDayGroup>[];

  for (final ExportArchive archive in items) {
    final DateTime? day = archive.day;

    if (groups.isNotEmpty && groups.last.day == day) {
      groups.last.exports.add(archive);
    } else {
      groups.add(ExportDayGroup(day: day, exports: <ExportArchive>[archive]));
    }
  }

  return List<ExportDayGroup>.unmodifiable(groups);
});

/// One day's worth of exports.
class ExportDayGroup {
  ExportDayGroup({required this.day, required this.exports});

  /// Null when the row carries no usable timestamp at all, which the header
  /// renders as "Undated" rather than silently dropping the row.
  final DateTime? day;

  final List<ExportArchive> exports;
}
