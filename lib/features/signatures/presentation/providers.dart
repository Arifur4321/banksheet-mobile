/// State for the signatures feature: the filtered list, and one request's
/// detail.
///
/// The list is a [StateNotifier] because the status filter has to survive a
/// refresh and pages are appended to what is already on screen. The detail is a
/// plain future — nothing on that screen changes underneath the user, and
/// pull-to-refresh is one line.
library;

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/strings.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/providers.dart';
import '../../../core/utils/json.dart';
import '../data/signature_repository.dart';
import '../domain/signature.dart';

/// The four chips above the list.
///
/// "Awaiting" is not a status: `SignatureController::index()` matches one status
/// exactly, and awaiting means any of `sent`, `viewed` or `partially_signed`.
/// The server has a scope for that set, reached with `open_only`, so the filter
/// stays server-side and pagination keeps working.
enum SignatureFilter {
  all,
  awaiting,
  completed,
  declined;

  String get label => switch (this) {
        SignatureFilter.all => S.all,
        SignatureFilter.awaiting => S.filterAwaiting,
        SignatureFilter.completed => S.filterCompleted,
        SignatureFilter.declined => S.filterDeclined,
      };

  /// The value to send as `?status=`, when this filter maps onto one.
  String? get serverStatus => switch (this) {
        SignatureFilter.completed => SignatureStatus.completed.wire,
        SignatureFilter.declined => SignatureStatus.declined.wire,
        SignatureFilter.all || SignatureFilter.awaiting => null,
      };

  bool get openOnly => this == SignatureFilter.awaiting;
}

@immutable
class SignatureListState {
  const SignatureListState({
    required this.page,
    required this.filter,
    required this.isLoadingMore,
    this.loadMoreError,
  });

  const SignatureListState.initial()
      : page = const AsyncValue<Paged<SignatureRequest>>.loading(),
        filter = SignatureFilter.all,
        isLoadingMore = false,
        loadMoreError = null;

  final AsyncValue<Paged<SignatureRequest>> page;
  final SignatureFilter filter;
  final bool isLoadingMore;
  final Object? loadMoreError;

  List<SignatureRequest> get items =>
      page.valueOrNull?.items ?? const <SignatureRequest>[];

  bool get hasMore => page.valueOrNull?.meta.hasMore ?? false;

  int get total => page.valueOrNull?.meta.total ?? 0;

  bool get isFiltered => filter != SignatureFilter.all;

  SignatureListState copyWith({
    AsyncValue<Paged<SignatureRequest>>? page,
    SignatureFilter? filter,
    bool? isLoadingMore,
    Object? loadMoreError,
    bool clearLoadMoreError = false,
  }) {
    return SignatureListState(
      page: page ?? this.page,
      filter: filter ?? this.filter,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      loadMoreError:
          clearLoadMoreError ? null : (loadMoreError ?? this.loadMoreError),
    );
  }
}

class SignatureListController extends StateNotifier<SignatureListState> {
  SignatureListController(this._repository)
      : super(const SignatureListState.initial()) {
    unawaited(refresh());
  }

  final SignatureRepository _repository;
  final CancelToken _cancelToken = CancelToken();

  /// Bumped on every filter change so a slow in-flight page for the previous
  /// filter cannot land on top of the new one.
  int _generation = 0;

  Future<void> refresh({bool showLoading = false}) async {
    final int generation = ++_generation;

    if (showLoading || !state.page.hasValue) {
      state = state.copyWith(
        page: const AsyncValue<Paged<SignatureRequest>>.loading(),
        isLoadingMore: false,
        clearLoadMoreError: true,
      );
    }

    try {
      final Paged<SignatureRequest> first = await _repository.list(
        status: state.filter.serverStatus,
        openOnly: state.filter.openOnly,
        cancelToken: _cancelToken,
      );
      if (!mounted || generation != _generation) {
        return;
      }
      state = state.copyWith(
        page: AsyncValue<Paged<SignatureRequest>>.data(first),
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
        page: AsyncValue<Paged<SignatureRequest>>.error(error, stackTrace),
        isLoadingMore: false,
      );
    }
  }

  Future<void> loadMore() async {
    final Paged<SignatureRequest>? current = state.page.valueOrNull;
    if (current == null || !current.meta.hasMore || state.isLoadingMore) {
      return;
    }

    final int generation = _generation;
    state = state.copyWith(isLoadingMore: true, clearLoadMoreError: true);

    try {
      final Paged<SignatureRequest> next = await _repository.list(
        page: current.meta.currentPage + 1,
        status: state.filter.serverStatus,
        openOnly: state.filter.openOnly,
        cancelToken: _cancelToken,
      );
      if (!mounted || generation != _generation) {
        return;
      }
      state = state.copyWith(
        page: AsyncValue<Paged<SignatureRequest>>.data(current.merge(next)),
        isLoadingMore: false,
      );
    } catch (error) {
      if (!mounted || generation != _generation) {
        return;
      }
      // Cleared even on a cancel, or the scroll sentinel jams and the list
      // never loads another page.
      state = ApiException.from(error).isCancelled
          ? state.copyWith(isLoadingMore: false, clearLoadMoreError: true)
          : state.copyWith(isLoadingMore: false, loadMoreError: error);
    }
  }

  void setFilter(SignatureFilter filter) {
    if (filter == state.filter) {
      return;
    }
    state = state.copyWith(filter: filter);
    unawaited(refresh(showLoading: true));
  }

  void reset() {
    _generation++;
    state = const SignatureListState.initial();
    unawaited(refresh(showLoading: true));
  }

  @override
  void dispose() {
    _generation++;
    _cancelToken.cancel();
    super.dispose();
  }
}

final StateNotifierProvider<SignatureListController, SignatureListState>
    signatureListProvider =
    StateNotifierProvider<SignatureListController, SignatureListState>(
  (Ref ref) {
    final SignatureListController controller =
        SignatureListController(ref.watch(signatureRepositoryProvider));
    ref.listen<int>(
      sessionSignalProvider,
      (int? _, int __) => controller.reset(),
    );
    return controller;
  },
);

/// One request, with its signers and its audit trail.
final AutoDisposeFutureProviderFamily<SignatureRequest, int>
    signatureDetailProvider =
    FutureProvider.autoDispose.family<SignatureRequest, int>(
  (Ref ref, int id) {
    final CancelToken cancelToken = CancelToken();
    ref.onDispose(cancelToken.cancel);
    return ref
        .watch(signatureRepositoryProvider)
        .detail(id, cancelToken: cancelToken);
  },
);
