/// State for templates and generated PDFs.
///
/// The two list screens here are the same screen twice — a page of rows, appended
/// to as the user scrolls — so they share one [PagedController] rather than
/// carrying two copies of the same eighty lines. The generate form deliberately
/// does *not* live in a provider: it is a form with text controllers and per-field
/// errors, and Flutter already has a good answer for that inside the screen.
///
/// Every controller cancels its in-flight requests on dispose and drops its data
/// when the session ends, so the next account never sees the previous one's work.
library;

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/providers.dart';
import '../../../core/utils/json.dart';
import '../data/generated_pdf_repository.dart';
import '../data/template_repository.dart';
import '../domain/generated_pdf.dart';
import '../domain/template.dart';

/// Every page fetched so far, plus the two flags a paginated list needs that a
/// bare `AsyncValue` cannot express.
@immutable
class PagedState<T> {
  const PagedState({
    required this.page,
    required this.isLoadingMore,
    this.loadMoreError,
  });

  /// A static method rather than a named constructor: a loading [AsyncValue]
  /// for `Paged<T>` cannot be built as a constant while T is a type variable,
  /// and a non-const constructor on an immutable class is a smell.
  static PagedState<E> initial<E>() => PagedState<E>(
        page: AsyncValue<Paged<E>>.loading(),
        isLoadingMore: false,
      );

  final AsyncValue<Paged<T>> page;

  /// True while another page is on the way. Distinct from `page.isLoading`,
  /// which means the whole list is being replaced.
  final bool isLoadingMore;

  /// A failed "load more", kept apart so one bad page does not throw away the
  /// rows the user is already reading.
  final Object? loadMoreError;

  List<T> get items => page.valueOrNull?.items ?? <T>[];

  bool get hasMore => page.valueOrNull?.meta.hasMore ?? false;

  int get total => page.valueOrNull?.meta.total ?? 0;

  PagedState<T> copyWith({
    AsyncValue<Paged<T>>? page,
    bool? isLoadingMore,
    Object? loadMoreError,
    bool clearLoadMoreError = false,
  }) {
    return PagedState<T>(
      page: page ?? this.page,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      loadMoreError:
          clearLoadMoreError ? null : (loadMoreError ?? this.loadMoreError),
    );
  }
}

/// A list that pages. [_fetch] is the only thing that differs between the two
/// screens in this feature.
class PagedController<T> extends StateNotifier<PagedState<T>> {
  PagedController(this._fetch) : super(PagedState.initial<T>()) {
    unawaited(refresh());
  }

  final Future<Paged<T>> Function(int page, CancelToken cancelToken) _fetch;

  final CancelToken _cancelToken = CancelToken();

  /// Bumped on every reset so a slow in-flight page cannot land on top of a
  /// list that belongs to a different session.
  int _generation = 0;

  Future<void> refresh({bool showLoading = false}) async {
    final int generation = ++_generation;

    if (showLoading || !state.page.hasValue) {
      state = state.copyWith(
        page: AsyncValue<Paged<T>>.loading(),
        isLoadingMore: false,
        clearLoadMoreError: true,
      );
    }

    try {
      final Paged<T> first = await _fetch(1, _cancelToken);
      if (!mounted || generation != _generation) {
        return;
      }
      state = state.copyWith(
        page: AsyncValue<Paged<T>>.data(first),
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
        page: AsyncValue<Paged<T>>.error(error, stackTrace),
        isLoadingMore: false,
      );
    }
  }

  Future<void> loadMore() async {
    final Paged<T>? current = state.page.valueOrNull;
    if (current == null || !current.meta.hasMore || state.isLoadingMore) {
      return;
    }

    final int generation = _generation;
    state = state.copyWith(isLoadingMore: true, clearLoadMoreError: true);

    try {
      final Paged<T> next =
          await _fetch(current.meta.currentPage + 1, _cancelToken);
      if (!mounted || generation != _generation) {
        return;
      }
      state = state.copyWith(
        page: AsyncValue<Paged<T>>.data(current.merge(next)),
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

  void reset() {
    _generation++;
    state = PagedState.initial<T>();
    unawaited(refresh(showLoading: true));
  }

  @override
  void dispose() {
    _generation++;
    _cancelToken.cancel();
    super.dispose();
  }
}

// ---------------------------------------------------------------------------
// Templates
// ---------------------------------------------------------------------------

final StateNotifierProvider<PagedController<Template>, PagedState<Template>>
    templateListProvider =
    StateNotifierProvider<PagedController<Template>, PagedState<Template>>(
  (Ref ref) {
    final TemplateRepository repository = ref.watch(templateRepositoryProvider);
    final PagedController<Template> controller = PagedController<Template>(
      (int page, CancelToken cancelToken) =>
          repository.list(page: page, cancelToken: cancelToken),
    );
    ref.listen<int>(
      sessionSignalProvider,
      (int? _, int __) => controller.reset(),
    );
    return controller;
  },
);

/// One template, with its variable schema.
///
/// A plain future: the detail screen loads it once, and pull-to-refresh is
/// `ref.refresh(templateDetailProvider(id).future)`. Nothing on this screen
/// changes underneath the user.
final AutoDisposeFutureProviderFamily<Template, int> templateDetailProvider =
    FutureProvider.autoDispose.family<Template, int>(
  (Ref ref, int id) {
    final CancelToken cancelToken = CancelToken();
    ref.onDispose(cancelToken.cancel);
    return ref
        .watch(templateRepositoryProvider)
        .detail(id, cancelToken: cancelToken);
  },
);

// ---------------------------------------------------------------------------
// Generated PDFs
// ---------------------------------------------------------------------------

final StateNotifierProvider<PagedController<GeneratedPdf>,
        PagedState<GeneratedPdf>> generatedPdfListProvider =
    StateNotifierProvider<PagedController<GeneratedPdf>,
        PagedState<GeneratedPdf>>(
  (Ref ref) {
    final GeneratedPdfRepository repository =
        ref.watch(generatedPdfRepositoryProvider);
    final PagedController<GeneratedPdf> controller =
        PagedController<GeneratedPdf>(
      (int page, CancelToken cancelToken) =>
          repository.list(page: page, cancelToken: cancelToken),
    );
    ref.listen<int>(
      sessionSignalProvider,
      (int? _, int __) => controller.reset(),
    );
    return controller;
  },
);
