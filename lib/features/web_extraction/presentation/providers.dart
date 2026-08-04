/// State for company-data extraction: the job list, one job with its targets
/// and its poller, one job's results, and the create form.
///
/// The detail controller polls on the interval the server publishes rather than
/// one the app hard-codes, and merges each refresh into the targets already on
/// screen by id instead of replacing the list — a crawl takes minutes, and
/// throwing away the user's scroll position every five seconds would make the
/// screen unusable exactly while it is most interesting.
library;

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/providers.dart';
import '../../../core/utils/json.dart';
import '../../../core/utils/logger.dart';
import '../data/web_extraction_repository.dart';
import '../domain/web_job.dart';

// ---------------------------------------------------------------------------
// Job list
// ---------------------------------------------------------------------------

@immutable
class WebJobListState {
  const WebJobListState({
    required this.page,
    required this.isLoadingMore,
    this.loadMoreError,
  });

  const WebJobListState.initial()
      : page = const AsyncValue<Paged<WebExtractionJob>>.loading(),
        isLoadingMore = false,
        loadMoreError = null;

  final AsyncValue<Paged<WebExtractionJob>> page;
  final bool isLoadingMore;
  final Object? loadMoreError;

  List<WebExtractionJob> get items =>
      page.valueOrNull?.items ?? const <WebExtractionJob>[];

  bool get hasMore => page.valueOrNull?.meta.hasMore ?? false;

  int get total => page.valueOrNull?.meta.total ?? 0;

  /// True while at least one job on screen is still crawling, which is what
  /// keeps the list refreshing itself.
  bool get hasRunning => items.any((WebExtractionJob j) => j.isRunning);

  WebJobListState copyWith({
    AsyncValue<Paged<WebExtractionJob>>? page,
    bool? isLoadingMore,
    Object? loadMoreError,
    bool clearLoadMoreError = false,
  }) {
    return WebJobListState(
      page: page ?? this.page,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      loadMoreError:
          clearLoadMoreError ? null : (loadMoreError ?? this.loadMoreError),
    );
  }
}

class WebJobListController extends StateNotifier<WebJobListState> {
  WebJobListController(this._repository)
      : super(const WebJobListState.initial()) {
    unawaited(refresh());
  }

  final WebExtractionRepository _repository;
  final CancelToken _cancelToken = CancelToken();

  int _generation = 0;

  Future<void> refresh({bool showLoading = false}) async {
    final int generation = ++_generation;

    if (showLoading || !state.page.hasValue) {
      state = state.copyWith(
        page: const AsyncValue<Paged<WebExtractionJob>>.loading(),
        isLoadingMore: false,
        clearLoadMoreError: true,
      );
    }

    try {
      final Paged<WebExtractionJob> first =
          await _repository.list(cancelToken: _cancelToken);
      if (!mounted || generation != _generation) {
        return;
      }
      state = state.copyWith(
        page: AsyncValue<Paged<WebExtractionJob>>.data(first),
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
        page: AsyncValue<Paged<WebExtractionJob>>.error(error, stackTrace),
        isLoadingMore: false,
      );
    }
  }

  Future<void> loadMore() async {
    final Paged<WebExtractionJob>? current = state.page.valueOrNull;
    if (current == null || !current.meta.hasMore || state.isLoadingMore) {
      return;
    }

    final int generation = _generation;
    state = state.copyWith(isLoadingMore: true, clearLoadMoreError: true);

    try {
      final Paged<WebExtractionJob> next = await _repository.list(
        page: current.meta.currentPage + 1,
        cancelToken: _cancelToken,
      );
      if (!mounted || generation != _generation) {
        return;
      }
      state = state.copyWith(
        page: AsyncValue<Paged<WebExtractionJob>>.data(current.merge(next)),
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

  void remove(int id) {
    final Paged<WebExtractionJob>? current = state.page.valueOrNull;
    if (current == null) {
      return;
    }
    state = state.copyWith(
      page: AsyncValue<Paged<WebExtractionJob>>.data(
        Paged<WebExtractionJob>(
          items: current.items
              .where((WebExtractionJob j) => j.id != id)
              .toList(growable: false),
          meta: current.meta,
        ),
      ),
    );
  }

  void replace(WebExtractionJob job) {
    final Paged<WebExtractionJob>? current = state.page.valueOrNull;
    if (current == null) {
      return;
    }
    state = state.copyWith(
      page: AsyncValue<Paged<WebExtractionJob>>.data(
        Paged<WebExtractionJob>(
          items: current.items
              .map((WebExtractionJob j) => j.id == job.id ? job : j)
              .toList(growable: false),
          meta: current.meta,
        ),
      ),
    );
  }

  void reset() {
    _generation++;
    state = const WebJobListState.initial();
    unawaited(refresh(showLoading: true));
  }

  @override
  void dispose() {
    _generation++;
    _cancelToken.cancel();
    super.dispose();
  }
}

final StateNotifierProvider<WebJobListController, WebJobListState>
    webJobListProvider =
    StateNotifierProvider<WebJobListController, WebJobListState>(
  (Ref ref) {
    final WebJobListController controller =
        WebJobListController(ref.watch(webExtractionRepositoryProvider));
    ref.listen<int>(
      sessionSignalProvider,
      (int? _, int __) => controller.reset(),
    );
    return controller;
  },
);

// ---------------------------------------------------------------------------
// One job
// ---------------------------------------------------------------------------

@immutable
class WebJobDetailState {
  const WebJobDetailState({
    required this.detail,
    required this.targets,
    required this.targetsMeta,
    required this.isLoadingMore,
    required this.isBusy,
  });

  const WebJobDetailState.initial()
      : detail = const AsyncValue<WebExtractionJob>.loading(),
        targets = const <WebExtractionTarget>[],
        targetsMeta = PageMeta.empty,
        isLoadingMore = false,
        isBusy = false;

  final AsyncValue<WebExtractionJob> detail;

  /// Accumulated across pages and refreshed in place by the poller.
  final List<WebExtractionTarget> targets;

  final PageMeta targetsMeta;
  final bool isLoadingMore;

  /// True while cancel, retry or delete is in flight.
  final bool isBusy;

  WebExtractionJob? get job => detail.valueOrNull;

  bool get hasMoreTargets => targetsMeta.hasMore;

  WebJobDetailState copyWith({
    AsyncValue<WebExtractionJob>? detail,
    List<WebExtractionTarget>? targets,
    PageMeta? targetsMeta,
    bool? isLoadingMore,
    bool? isBusy,
  }) {
    return WebJobDetailState(
      detail: detail ?? this.detail,
      targets: targets ?? this.targets,
      targetsMeta: targetsMeta ?? this.targetsMeta,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      isBusy: isBusy ?? this.isBusy,
    );
  }
}

class WebJobDetailController extends StateNotifier<WebJobDetailState> {
  WebJobDetailController(this._repository, this._jobId)
      : super(const WebJobDetailState.initial()) {
    unawaited(load());
  }

  final WebExtractionRepository _repository;
  final int _jobId;

  final CancelToken _cancelToken = CancelToken();
  Timer? _poll;
  int _generation = 0;

  Future<void> load({bool showLoading = false}) async {
    final int generation = ++_generation;

    if (showLoading || !state.detail.hasValue) {
      state = state.copyWith(
        detail: const AsyncValue<WebExtractionJob>.loading(),
      );
    }

    try {
      final WebExtractionJobDetail detail = await _repository.detail(
        _jobId,
        cancelToken: _cancelToken,
      );
      if (!mounted || generation != _generation) {
        return;
      }
      state = state.copyWith(
        detail: AsyncValue<WebExtractionJob>.data(detail.job),
        targets: _merge(detail.targets),
        targetsMeta: detail.targetsMeta,
        isLoadingMore: false,
      );
      _schedulePoll(detail.job);
    } catch (error, stackTrace) {
      if (!mounted || generation != _generation) {
        return;
      }
      if (ApiException.from(error).isCancelled) {
        return;
      }
      state = state.copyWith(
        detail: AsyncValue<WebExtractionJob>.error(error, stackTrace),
        isLoadingMore: false,
      );
    }
  }

  /// Next page of websites, appended.
  Future<void> loadMoreTargets() async {
    if (state.isLoadingMore || !state.targetsMeta.hasMore) {
      return;
    }

    final int generation = _generation;
    state = state.copyWith(isLoadingMore: true);

    try {
      final WebExtractionJobDetail next = await _repository.detail(
        _jobId,
        targetsPage: state.targetsMeta.currentPage + 1,
        cancelToken: _cancelToken,
      );
      if (!mounted || generation != _generation) {
        return;
      }
      state = state.copyWith(
        detail: AsyncValue<WebExtractionJob>.data(next.job),
        targets: <WebExtractionTarget>[...state.targets, ...next.targets],
        targetsMeta: next.targetsMeta,
        isLoadingMore: false,
      );
    } catch (error) {
      if (!mounted || generation != _generation) {
        return;
      }
      state = state.copyWith(isLoadingMore: false);
      if (!ApiException.from(error).isCancelled) {
        Log.warn('Web extraction: could not load more websites — $error');
      }
    }
  }

  // ----------------------------------------------------------------- actions

  Future<WebExtractionJob> retry() => _act(() => _repository.retry(_jobId));

  Future<WebExtractionJob> cancel() => _act(() => _repository.cancel(_jobId));

  Future<void> delete() async {
    // Stop the poller first: a refresh landing after the row is gone would put
    // a 404 on a screen the user has already left.
    _poll?.cancel();
    _generation++;
    state = state.copyWith(isBusy: true);
    try {
      await _repository.delete(_jobId);
    } finally {
      if (mounted) {
        state = state.copyWith(isBusy: false);
      }
    }
  }

  Future<WebExtractionJob> _act(Future<WebExtractionJob> Function() action) async {
    state = state.copyWith(isBusy: true);
    try {
      final WebExtractionJob job = await action();
      if (mounted) {
        state = state.copyWith(
          detail: AsyncValue<WebExtractionJob>.data(job),
          isBusy: false,
        );
        // The per-target statuses changed too, and only a reload has them.
        unawaited(load());
      }
      return job;
    } catch (error) {
      if (mounted) {
        state = state.copyWith(isBusy: false);
      }
      rethrow;
    }
  }

  // ----------------------------------------------------------------- polling

  /// Refresh in place, keeping the rows already on screen where they are.
  List<WebExtractionTarget> _merge(List<WebExtractionTarget> fresh) {
    if (state.targets.isEmpty) {
      return fresh;
    }

    final Map<int, WebExtractionTarget> byId = <int, WebExtractionTarget>{
      for (final WebExtractionTarget target in fresh) target.id: target,
    };
    final Set<int> known =
        state.targets.map((WebExtractionTarget t) => t.id).toSet();

    return <WebExtractionTarget>[
      for (final WebExtractionTarget target in state.targets)
        byId[target.id] ?? target,
      for (final WebExtractionTarget target in fresh)
        if (!known.contains(target.id)) target,
    ];
  }

  void _schedulePoll(WebExtractionJob job) {
    _poll?.cancel();
    if (job.isFinished) {
      return;
    }
    // The server's own interval, floored by the app's, so the client can only
    // ever be politer than asked.
    final Duration requested = Duration(seconds: job.pollAfterSeconds ?? 5);
    final Duration delay =
        requested > AppConfig.pollInterval ? requested : AppConfig.pollInterval;

    _poll = Timer(delay, () {
      if (!mounted) {
        return;
      }
      unawaited(load());
    });
  }

  void reset() {
    _generation++;
    _poll?.cancel();
    state = const WebJobDetailState.initial();
    unawaited(load(showLoading: true));
  }

  @override
  void dispose() {
    _generation++;
    _poll?.cancel();
    _cancelToken.cancel();
    super.dispose();
  }
}

final AutoDisposeStateNotifierProviderFamily<WebJobDetailController,
    WebJobDetailState, int> webJobDetailProvider = StateNotifierProvider
    .autoDispose
    .family<WebJobDetailController, WebJobDetailState, int>(
  (Ref ref, int jobId) {
    final WebJobDetailController controller = WebJobDetailController(
      ref.watch(webExtractionRepositoryProvider),
      jobId,
    );
    ref.listen<int>(
      sessionSignalProvider,
      (int? _, int __) => controller.reset(),
    );
    return controller;
  },
);

// ---------------------------------------------------------------------------
// Results
// ---------------------------------------------------------------------------

@immutable
class WebResultsState {
  const WebResultsState({
    required this.page,
    required this.isLoadingMore,
    required this.emailsOnly,
    this.loadMoreError,
  });

  const WebResultsState.initial()
      : page = const AsyncValue<Paged<WebExtractionTarget>>.loading(),
        isLoadingMore = false,
        emailsOnly = false,
        loadMoreError = null;

  final AsyncValue<Paged<WebExtractionTarget>> page;
  final bool isLoadingMore;

  /// The one filter worth a chip on a phone: websites that yielded an address.
  final bool emailsOnly;

  final Object? loadMoreError;

  List<WebExtractionTarget> get items =>
      page.valueOrNull?.items ?? const <WebExtractionTarget>[];

  bool get hasMore => page.valueOrNull?.meta.hasMore ?? false;

  int get total => page.valueOrNull?.meta.total ?? 0;

  WebResultsState copyWith({
    AsyncValue<Paged<WebExtractionTarget>>? page,
    bool? isLoadingMore,
    bool? emailsOnly,
    Object? loadMoreError,
    bool clearLoadMoreError = false,
  }) {
    return WebResultsState(
      page: page ?? this.page,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      emailsOnly: emailsOnly ?? this.emailsOnly,
      loadMoreError:
          clearLoadMoreError ? null : (loadMoreError ?? this.loadMoreError),
    );
  }
}

class WebResultsController extends StateNotifier<WebResultsState> {
  WebResultsController(this._repository, this._jobId)
      : super(const WebResultsState.initial()) {
    unawaited(refresh());
  }

  final WebExtractionRepository _repository;
  final int _jobId;

  final CancelToken _cancelToken = CancelToken();
  int _generation = 0;

  Future<void> refresh({bool showLoading = false}) async {
    final int generation = ++_generation;

    if (showLoading || !state.page.hasValue) {
      state = state.copyWith(
        page: const AsyncValue<Paged<WebExtractionTarget>>.loading(),
        isLoadingMore: false,
        clearLoadMoreError: true,
      );
    }

    try {
      final Paged<WebExtractionTarget> first = await _repository.results(
        _jobId,
        hasEmail: state.emailsOnly ? true : null,
        cancelToken: _cancelToken,
      );
      if (!mounted || generation != _generation) {
        return;
      }
      state = state.copyWith(
        page: AsyncValue<Paged<WebExtractionTarget>>.data(first),
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
        page: AsyncValue<Paged<WebExtractionTarget>>.error(error, stackTrace),
        isLoadingMore: false,
      );
    }
  }

  Future<void> loadMore() async {
    final Paged<WebExtractionTarget>? current = state.page.valueOrNull;
    if (current == null || !current.meta.hasMore || state.isLoadingMore) {
      return;
    }

    final int generation = _generation;
    state = state.copyWith(isLoadingMore: true, clearLoadMoreError: true);

    try {
      final Paged<WebExtractionTarget> next = await _repository.results(
        _jobId,
        page: current.meta.currentPage + 1,
        hasEmail: state.emailsOnly ? true : null,
        cancelToken: _cancelToken,
      );
      if (!mounted || generation != _generation) {
        return;
      }
      state = state.copyWith(
        page: AsyncValue<Paged<WebExtractionTarget>>.data(current.merge(next)),
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

  void setEmailsOnly({required bool enabled}) {
    if (enabled == state.emailsOnly) {
      return;
    }
    state = state.copyWith(emailsOnly: enabled);
    unawaited(refresh(showLoading: true));
  }

  @override
  void dispose() {
    _generation++;
    _cancelToken.cancel();
    super.dispose();
  }
}

final AutoDisposeStateNotifierProviderFamily<WebResultsController,
    WebResultsState, int> webResultsProvider = StateNotifierProvider.autoDispose
    .family<WebResultsController, WebResultsState, int>(
  (Ref ref, int jobId) => WebResultsController(
    ref.watch(webExtractionRepositoryProvider),
    jobId,
  ),
);

// ---------------------------------------------------------------------------
// Create
// ---------------------------------------------------------------------------

@immutable
class WebCreateState {
  const WebCreateState({
    required this.raw,
    required this.parsed,
    required this.title,
    required this.isSubmitting,
    this.error,
  });

  const WebCreateState.initial()
      : raw = '',
        parsed = DomainListParse.empty,
        title = '',
        isSubmitting = false,
        error = null;

  /// Exactly what is in the text field.
  final String raw;

  /// What that text means: the websites that will be scanned, and the lines
  /// that will not be.
  final DomainListParse parsed;

  final String title;
  final bool isSubmitting;
  final Object? error;

  bool get isTooLong => raw.length > DomainList.maxInputLength;

  bool get canSubmit =>
      parsed.domains.isNotEmpty && !isSubmitting && !isTooLong;

  WebCreateState copyWith({
    String? raw,
    DomainListParse? parsed,
    String? title,
    bool? isSubmitting,
    Object? error,
    bool clearError = false,
  }) {
    return WebCreateState(
      raw: raw ?? this.raw,
      parsed: parsed ?? this.parsed,
      title: title ?? this.title,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class WebCreateController extends StateNotifier<WebCreateState> {
  WebCreateController(this._repository) : super(const WebCreateState.initial());

  final WebExtractionRepository _repository;

  void setDomains(String raw) {
    state = state.copyWith(
      raw: raw,
      parsed: DomainList.parse(raw),
      clearError: true,
    );
  }

  void setTitle(String title) {
    state = state.copyWith(title: title, clearError: true);
  }

  /// Queues the job. Returns null when the server refused, leaving the reason
  /// in `state.error` for the screen to route on.
  Future<WebExtractionCreated?> submit() async {
    if (!state.canSubmit) {
      return null;
    }

    state = state.copyWith(isSubmitting: true, clearError: true);

    try {
      final String title = state.title.trim();
      final WebExtractionCreated created = await _repository.create(
        domains: state.parsed.domains,
        title: title.isEmpty ? null : title,
      );
      if (mounted) {
        state = state.copyWith(isSubmitting: false);
      }
      return created;
    } catch (error) {
      if (mounted) {
        state = state.copyWith(isSubmitting: false, error: error);
      }
      return null;
    }
  }
}

final AutoDisposeStateNotifierProvider<WebCreateController, WebCreateState>
    webCreateProvider =
    StateNotifierProvider.autoDispose<WebCreateController, WebCreateState>(
  (Ref ref) => WebCreateController(ref.watch(webExtractionRepositoryProvider)),
);
