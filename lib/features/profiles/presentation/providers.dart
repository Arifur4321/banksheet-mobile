/// State for extraction profiles: the list with its active-only filter and its
/// optimistic toggle, and one profile's detail.
///
/// The toggle is the only write in this feature, and it is deliberately
/// optimistic: flipping a switch has to feel instant, the request is one field,
/// and the failure path is a rollback plus a message rather than anything the
/// user has to redo. The server's own copy of the row is adopted on success, so
/// a value the app guessed wrong is corrected within the same tap.
library;

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/providers.dart';
import '../../../core/utils/json.dart';
import '../data/profile_repository.dart';
import '../domain/extraction_profile.dart';

@immutable
class ProfileListState {
  const ProfileListState({
    required this.page,
    required this.activeOnly,
    required this.isLoadingMore,
    required this.pendingIds,
    this.loadMoreError,
  });

  const ProfileListState.initial()
      : page = const AsyncValue<Paged<ExtractionProfile>>.loading(),
        activeOnly = false,
        isLoadingMore = false,
        pendingIds = const <int>{},
        loadMoreError = null;

  final AsyncValue<Paged<ExtractionProfile>> page;

  /// Hides profiles that are switched off. Applied server-side, so pagination
  /// keeps working.
  final bool activeOnly;

  final bool isLoadingMore;

  /// Profiles with a toggle in flight. Their switches are disabled until the
  /// server answers, so a double tap cannot leave the row inverted.
  final Set<int> pendingIds;

  final Object? loadMoreError;

  List<ExtractionProfile> get items =>
      page.valueOrNull?.items ?? const <ExtractionProfile>[];

  bool get hasMore => page.valueOrNull?.meta.hasMore ?? false;

  int get total => page.valueOrNull?.meta.total ?? 0;

  ProfileListState copyWith({
    AsyncValue<Paged<ExtractionProfile>>? page,
    bool? activeOnly,
    bool? isLoadingMore,
    Set<int>? pendingIds,
    Object? loadMoreError,
    bool clearLoadMoreError = false,
  }) {
    return ProfileListState(
      page: page ?? this.page,
      activeOnly: activeOnly ?? this.activeOnly,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      pendingIds: pendingIds ?? this.pendingIds,
      loadMoreError:
          clearLoadMoreError ? null : (loadMoreError ?? this.loadMoreError),
    );
  }
}

class ProfileListController extends StateNotifier<ProfileListState> {
  ProfileListController(this._repository)
      : super(const ProfileListState.initial()) {
    unawaited(refresh());
  }

  final ProfileRepository _repository;
  final CancelToken _cancelToken = CancelToken();

  int _generation = 0;

  Future<void> refresh({bool showLoading = false}) async {
    final int generation = ++_generation;

    if (showLoading || !state.page.hasValue) {
      state = state.copyWith(
        page: const AsyncValue<Paged<ExtractionProfile>>.loading(),
        isLoadingMore: false,
        clearLoadMoreError: true,
      );
    }

    try {
      final Paged<ExtractionProfile> first = await _repository.list(
        activeOnly: state.activeOnly,
        cancelToken: _cancelToken,
      );
      if (!mounted || generation != _generation) {
        return;
      }
      state = state.copyWith(
        page: AsyncValue<Paged<ExtractionProfile>>.data(first),
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
        page: AsyncValue<Paged<ExtractionProfile>>.error(error, stackTrace),
        isLoadingMore: false,
      );
    }
  }

  Future<void> loadMore() async {
    final Paged<ExtractionProfile>? current = state.page.valueOrNull;
    if (current == null || !current.meta.hasMore || state.isLoadingMore) {
      return;
    }

    final int generation = _generation;
    state = state.copyWith(isLoadingMore: true, clearLoadMoreError: true);

    try {
      final Paged<ExtractionProfile> next = await _repository.list(
        page: current.meta.currentPage + 1,
        activeOnly: state.activeOnly,
        cancelToken: _cancelToken,
      );
      if (!mounted || generation != _generation) {
        return;
      }
      state = state.copyWith(
        page: AsyncValue<Paged<ExtractionProfile>>.data(current.merge(next)),
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

  void setActiveOnly({required bool value}) {
    if (value == state.activeOnly) {
      return;
    }
    state = state.copyWith(activeOnly: value);
    unawaited(refresh(showLoading: true));
  }

  /// Flips a profile, showing the new state immediately.
  ///
  /// Returns the state the profile ended up in, or null when the call failed
  /// and the row was rolled back — which is what the screen reports.
  Future<bool?> toggle(int id) async {
    final ExtractionProfile? current = _find(id);
    if (current == null || state.pendingIds.contains(id)) {
      return null;
    }

    final int generation = _generation;
    final bool optimistic = !current.isActive;

    _replace(current.withActive(active: optimistic));
    state = state.copyWith(pendingIds: <int>{...state.pendingIds, id});

    try {
      final ExtractionProfile updated =
          await _repository.toggle(id, cancelToken: _cancelToken);
      if (!mounted || generation != _generation) {
        return null;
      }
      // The server's answer wins over the optimistic guess. Only `is_active`
      // is adopted: the toggle endpoint answers with the *detail* shape, and
      // dropping a rules-carrying row into the list would make `isDetail` true
      // for one row and false for the rest.
      _replace(current.withActive(active: updated.isActive));
      return updated.isActive;
    } catch (error) {
      if (!mounted || generation != _generation) {
        return null;
      }
      _replace(current);
      if (ApiException.from(error).isCancelled) {
        return null;
      }
      rethrow;
    } finally {
      if (mounted) {
        state = state.copyWith(
          pendingIds: <int>{...state.pendingIds}..remove(id),
        );
      }
    }
  }

  ExtractionProfile? _find(int id) {
    for (final ExtractionProfile profile in state.items) {
      if (profile.id == id) {
        return profile;
      }
    }
    return null;
  }

  void _replace(ExtractionProfile profile) {
    final Paged<ExtractionProfile>? current = state.page.valueOrNull;
    if (current == null) {
      return;
    }
    state = state.copyWith(
      page: AsyncValue<Paged<ExtractionProfile>>.data(
        Paged<ExtractionProfile>(
          items: current.items
              .map((ExtractionProfile p) => p.id == profile.id ? profile : p)
              .toList(growable: false),
          meta: current.meta,
        ),
      ),
    );
  }

  void reset() {
    _generation++;
    state = const ProfileListState.initial();
    unawaited(refresh(showLoading: true));
  }

  @override
  void dispose() {
    _generation++;
    _cancelToken.cancel();
    super.dispose();
  }
}

final StateNotifierProvider<ProfileListController, ProfileListState>
    profileListProvider =
    StateNotifierProvider<ProfileListController, ProfileListState>(
  (Ref ref) {
    final ProfileListController controller =
        ProfileListController(ref.watch(profileRepositoryProvider));
    ref.listen<int>(
      sessionSignalProvider,
      (int? _, int __) => controller.reset(),
    );
    return controller;
  },
);

/// One profile, with its rules.
final AutoDisposeFutureProviderFamily<ExtractionProfile, int>
    profileDetailProvider =
    FutureProvider.autoDispose.family<ExtractionProfile, int>(
  (Ref ref, int id) {
    final CancelToken cancelToken = CancelToken();
    ref.onDispose(cancelToken.cancel);
    return ref
        .watch(profileRepositoryProvider)
        .detail(id, cancelToken: cancelToken);
  },
);
