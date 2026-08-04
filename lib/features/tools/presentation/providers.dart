/// State for the tools feature: the catalogue, the history, the status poller
/// and the one controller that drives a conversion from file picker to result.
///
/// Hand-written Riverpod, no codegen. The catalogue is a plain [FutureProvider]
/// — it is small, it changes only when the plan does, and every screen wants the
/// same copy of it. The history is a [StateNotifier] because an infinite scroll
/// needs pages appended to what is already on screen and an `isLoadingMore` flag
/// distinct from "the whole list is loading".
///
/// [ToolRunController] deliberately reads the catalogue with `ref.read` rather
/// than `ref.watch`: a background refresh of the tool list must not rebuild the
/// provider and throw away a form the user is halfway through filling in.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../core/i18n/strings.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/providers.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/json.dart';
import '../../../core/utils/logger.dart';
import '../data/tool_repository.dart';
import '../domain/conversion.dart';
import '../domain/tool.dart';

// ---------------------------------------------------------------------------
// Catalogue
// ---------------------------------------------------------------------------

/// `GET /tools`. Refetched when the session changes, because the plan ceilings
/// and the remaining allowance it carries belong to a workspace.
final FutureProvider<ToolCatalogue> toolsProvider =
    FutureProvider<ToolCatalogue>((Ref ref) {
  ref.watch(sessionSignalProvider);
  return ref.watch(toolRepositoryProvider).tools();
});

// ---------------------------------------------------------------------------
// History
// ---------------------------------------------------------------------------

@immutable
class ConversionListState {
  const ConversionListState({
    required this.page,
    required this.isLoadingMore,
    this.loadMoreError,
  });

  const ConversionListState.initial()
      : page = const AsyncValue<Paged<Conversion>>.loading(),
        isLoadingMore = false,
        loadMoreError = null;

  /// Every page fetched so far, merged.
  final AsyncValue<Paged<Conversion>> page;

  final bool isLoadingMore;

  /// A failed "load more", kept separate so one bad page does not throw away
  /// the rows the user is already reading.
  final Object? loadMoreError;

  List<Conversion> get items =>
      page.valueOrNull?.items ?? const <Conversion>[];

  bool get hasMore => page.valueOrNull?.meta.hasMore ?? false;

  int get total => page.valueOrNull?.meta.total ?? 0;

  ConversionListState copyWith({
    AsyncValue<Paged<Conversion>>? page,
    bool? isLoadingMore,
    Object? loadMoreError,
    bool clearLoadMoreError = false,
  }) {
    return ConversionListState(
      page: page ?? this.page,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      loadMoreError:
          clearLoadMoreError ? null : (loadMoreError ?? this.loadMoreError),
    );
  }
}

class ConversionListController extends StateNotifier<ConversionListState> {
  ConversionListController(this._repository)
      : super(const ConversionListState.initial()) {
    unawaited(refresh());
  }

  final ToolRepository _repository;
  final CancelToken _cancelToken = CancelToken();

  /// Bumped on every reset so a slow in-flight page cannot land on top of a
  /// list that now belongs to a different account.
  int _generation = 0;

  Future<void> refresh({bool showLoading = false}) async {
    final int generation = ++_generation;

    if (showLoading || !state.page.hasValue) {
      state = state.copyWith(
        page: const AsyncValue<Paged<Conversion>>.loading(),
        isLoadingMore: false,
        clearLoadMoreError: true,
      );
    }

    try {
      final Paged<Conversion> first =
          await _repository.conversions(cancelToken: _cancelToken);
      if (!mounted || generation != _generation) {
        return;
      }
      state = state.copyWith(
        page: AsyncValue<Paged<Conversion>>.data(first),
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
        page: AsyncValue<Paged<Conversion>>.error(error, stackTrace),
        isLoadingMore: false,
      );
    }
  }

  Future<void> loadMore() async {
    final Paged<Conversion>? current = state.page.valueOrNull;
    if (current == null || !current.meta.hasMore || state.isLoadingMore) {
      return;
    }

    final int generation = _generation;
    state = state.copyWith(isLoadingMore: true, clearLoadMoreError: true);

    try {
      final Paged<Conversion> next = await _repository.conversions(
        page: current.meta.currentPage + 1,
        cancelToken: _cancelToken,
      );
      if (!mounted || generation != _generation) {
        return;
      }
      state = state.copyWith(
        page: AsyncValue<Paged<Conversion>>.data(current.merge(next)),
        isLoadingMore: false,
      );
    } catch (error) {
      if (!mounted || generation != _generation) {
        return;
      }
      // Clearing the flag matters even on a cancel: leaving it set would jam
      // the sentinel and the list would never load another page.
      state = ApiException.from(error).isCancelled
          ? state.copyWith(isLoadingMore: false, clearLoadMoreError: true)
          : state.copyWith(isLoadingMore: false, loadMoreError: error);
    }
  }

  /// Drop a row the user just deleted, without re-fetching the whole list and
  /// losing their scroll position.
  void remove(int id) {
    final Paged<Conversion>? current = state.page.valueOrNull;
    if (current == null) {
      return;
    }
    state = state.copyWith(
      page: AsyncValue<Paged<Conversion>>.data(
        Paged<Conversion>(
          items: current.items
              .where((Conversion c) => c.id != id)
              .toList(growable: false),
          meta: current.meta,
        ),
      ),
    );
  }

  /// Swap in a row whose status changed elsewhere — a finished run, a retry.
  void replace(Conversion conversion) {
    final Paged<Conversion>? current = state.page.valueOrNull;
    if (current == null) {
      return;
    }
    state = state.copyWith(
      page: AsyncValue<Paged<Conversion>>.data(
        Paged<Conversion>(
          items: current.items
              .map((Conversion c) => c.id == conversion.id ? conversion : c)
              .toList(growable: false),
          meta: current.meta,
        ),
      ),
    );
  }

  void reset() {
    _generation++;
    state = const ConversionListState.initial();
    unawaited(refresh(showLoading: true));
  }

  @override
  void dispose() {
    _generation++;
    _cancelToken.cancel();
    super.dispose();
  }
}

final StateNotifierProvider<ConversionListController, ConversionListState>
    conversionListProvider =
    StateNotifierProvider<ConversionListController, ConversionListState>(
  (Ref ref) {
    final ConversionListController controller =
        ConversionListController(ref.watch(toolRepositoryProvider));
    ref.listen<int>(
      sessionSignalProvider,
      (int? _, int __) => controller.reset(),
    );
    return controller;
  },
);

// ---------------------------------------------------------------------------
// Status polling
// ---------------------------------------------------------------------------

/// How many consecutive transport failures the poller tolerates before it gives
/// up and surfaces the error.
const int _maxPollFailures = 3;

/// Polls `GET /tools/conversions/{id}/status` while the job is in flight.
///
/// Three stopping conditions, all necessary: the job settled (the server
/// withdraws `poll_after_seconds`, which is the signal the client honours
/// rather than matching status strings), [AppConfig.pollCeiling] elapsed, or the
/// screen went away. The interval is the larger of the app's floor and whatever
/// the server asked for, so the client can only ever be politer than requested.
final AutoDisposeStreamProviderFamily<ConversionStatusInfo, int>
    conversionStatusPollProvider =
    StreamProvider.autoDispose.family<ConversionStatusInfo, int>(
  (Ref ref, int conversionId) async* {
    final ToolRepository repository = ref.watch(toolRepositoryProvider);
    final CancelToken cancelToken = CancelToken();
    bool disposed = false;

    ref.onDispose(() {
      disposed = true;
      cancelToken.cancel();
    });

    final DateTime deadline = DateTime.now().add(AppConfig.pollCeiling);
    int failures = 0;

    while (!disposed && DateTime.now().isBefore(deadline)) {
      late final ConversionStatusInfo info;
      try {
        info = await repository.status(conversionId, cancelToken: cancelToken);
      } catch (error) {
        if (disposed) {
          return;
        }
        final ApiException failure = ApiException.from(error);
        if (failure.isCancelled) {
          return;
        }
        failures++;
        if (!failure.isRetryable || failures >= _maxPollFailures) {
          rethrow;
        }
        await Future<void>.delayed(AppConfig.pollInterval * failures);
        continue;
      }

      failures = 0;
      yield info;

      if (info.isSettled) {
        return;
      }

      await Future<void>.delayed(_pollDelay(info.pollAfterSeconds));
    }

    // The ceiling, not the job, ended this. Surfacing it as an error is what
    // puts "we stopped checking, pull to refresh" on the screen instead of a
    // spinner that never resolves.
    if (!disposed) {
      throw const ApiException(
        code: ApiException.codeTimeout,
        message: S.pollingStopped,
      );
    }
  },
);

Duration _pollDelay(int? seconds) {
  final Duration requested = Duration(seconds: seconds ?? 0);
  return requested > AppConfig.pollInterval
      ? requested
      : AppConfig.pollInterval;
}

// ---------------------------------------------------------------------------
// Running one tool
// ---------------------------------------------------------------------------

enum ToolRunPhase {
  /// Filling in the form.
  editing,

  /// Bytes on the wire.
  uploading,

  /// Accepted; waiting for a worker.
  queued,

  /// Finished, with an output to open.
  finished,

  /// Finished badly, or refused.
  failed,
}

@immutable
class ToolRunState {
  const ToolRunState({
    required this.tool,
    required this.maxFiles,
    required this.files,
    required this.values,
    required this.errors,
    required this.phase,
    required this.sentBytes,
    required this.totalBytes,
    this.fileError,
    this.conversionId,
    this.status,
    this.result,
    this.error,
  });

  const ToolRunState.initial()
      : tool = const AsyncValue<ToolDefinition>.loading(),
        maxFiles = 1,
        files = const <ToolUpload>[],
        values = const <String, String>{},
        errors = const <String, String>{},
        phase = ToolRunPhase.editing,
        sentBytes = 0,
        totalBytes = 0,
        fileError = null,
        conversionId = null,
        status = null,
        result = null,
        error = null;

  final AsyncValue<ToolDefinition> tool;

  /// The lower of the validator's ceiling and this workspace's plan ceiling.
  final int maxFiles;

  final List<ToolUpload> files;

  /// Option name to raw string value, exactly as it will be posted.
  final Map<String, String> values;

  /// Option name to the message shown under its field.
  final Map<String, String> errors;

  final ToolRunPhase phase;
  final int sentBytes;
  final int totalBytes;

  /// A message about the chosen files rather than about one option.
  final String? fileError;

  final int? conversionId;
  final ConversionStatusInfo? status;
  final Conversion? result;
  final Object? error;

  double get progress =>
      totalBytes <= 0 ? 0 : (sentBytes / totalBytes).clamp(0.0, 1.0).toDouble();

  bool get isBusy =>
      phase == ToolRunPhase.uploading || phase == ToolRunPhase.queued;

  /// True while the app should be polling this job.
  bool get isPolling => phase == ToolRunPhase.queued && conversionId != null;

  int get totalBytesSelected =>
      files.fold<int>(0, (int sum, ToolUpload f) => sum + f.sizeBytes);

  bool get canSubmit {
    final ToolDefinition? definition = tool.valueOrNull;
    if (definition == null || !definition.supported || isBusy) {
      return false;
    }
    return !definition.needsFiles || files.length >= definition.minFiles;
  }

  ToolRunState copyWith({
    AsyncValue<ToolDefinition>? tool,
    int? maxFiles,
    List<ToolUpload>? files,
    Map<String, String>? values,
    Map<String, String>? errors,
    ToolRunPhase? phase,
    int? sentBytes,
    int? totalBytes,
    String? fileError,
    int? conversionId,
    ConversionStatusInfo? status,
    Conversion? result,
    Object? error,
    bool clearFileError = false,
    bool clearError = false,
    bool clearJob = false,
  }) {
    return ToolRunState(
      tool: tool ?? this.tool,
      maxFiles: maxFiles ?? this.maxFiles,
      files: files ?? this.files,
      values: values ?? this.values,
      errors: errors ?? this.errors,
      phase: phase ?? this.phase,
      sentBytes: sentBytes ?? this.sentBytes,
      totalBytes: totalBytes ?? this.totalBytes,
      fileError: clearFileError ? null : (fileError ?? this.fileError),
      conversionId: clearJob ? null : (conversionId ?? this.conversionId),
      status: clearJob ? null : (status ?? this.status),
      result: clearJob ? null : (result ?? this.result),
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class ToolRunController extends StateNotifier<ToolRunState> {
  ToolRunController({
    required ToolRepository repository,
    required Future<ToolCatalogue> catalogue,
    required String toolKey,
  })  : _repository = repository,
        _toolKey = toolKey,
        super(const ToolRunState.initial()) {
    unawaited(_load(catalogue));
  }

  final ToolRepository _repository;
  final String _toolKey;

  CancelToken? _cancelToken;
  ToolLimits _limits = ToolLimits.fallback;

  /// The last percentage pushed into state. dio reports progress per chunk —
  /// thousands of times on a large file — and rebuilding the screen for a
  /// change nobody can see is the definition of jank.
  int _lastPercent = -1;

  Future<void> _load(Future<ToolCatalogue> catalogue) async {
    try {
      final ToolCatalogue resolved = await catalogue;
      if (!mounted) {
        return;
      }
      final ToolDefinition? tool = resolved.byKey(_toolKey);
      if (tool == null) {
        state = state.copyWith(
          tool: AsyncValue<ToolDefinition>.error(
            ApiException(code: 'not_found', message: S.toolNotFound(_toolKey)),
            StackTrace.current,
          ),
        );
        return;
      }
      _limits = resolved.limits;
      state = state.copyWith(
        tool: AsyncValue<ToolDefinition>.data(tool),
        maxFiles: resolved.maxFilesFor(tool),
        values: tool.defaults,
      );
    } catch (error, stackTrace) {
      if (!mounted) {
        return;
      }
      state = state.copyWith(
        tool: AsyncValue<ToolDefinition>.error(error, stackTrace),
      );
    }
  }

  // ------------------------------------------------------------------ form

  void setValue(String name, String? value) {
    final Map<String, String> values = <String, String>{...state.values};
    final String trimmed = (value ?? '').trim();
    if (trimmed.isEmpty) {
      values.remove(name);
    } else {
      values[name] = value!;
    }

    final Map<String, String> errors = <String, String>{...state.errors}
      ..remove(name);

    state = state.copyWith(values: values, errors: errors, clearError: true);
  }

  // ----------------------------------------------------------------- files

  /// Opens the system picker, restricted to the extensions the server accepts
  /// for this tool. Offering anything wider only moves the rejection from a tap
  /// to a failed upload.
  Future<void> pickFiles() async {
    final ToolDefinition? tool = state.tool.valueOrNull;
    if (tool == null || !tool.needsFiles || state.isBusy) {
      return;
    }

    try {
      final FilePickerResult? picked = await FilePicker.platform.pickFiles(
        type: tool.acceptedExtensions.isEmpty
            ? FileType.any
            : FileType.custom,
        allowedExtensions:
            tool.acceptedExtensions.isEmpty ? null : tool.acceptedExtensions,
        allowMultiple: tool.multiple,
      );
      if (!mounted || picked == null || picked.files.isEmpty) {
        return;
      }

      final List<ToolUpload> chosen = <ToolUpload>[
        if (tool.multiple) ...state.files,
      ];
      bool unreadable = false;

      for (final PlatformFile file in picked.files) {
        final String? path = file.path;
        if (path == null) {
          unreadable = true;
          continue;
        }
        chosen.add(
          ToolUpload(path: path, filename: file.name, sizeBytes: file.size),
        );
      }

      _applySelection(tool, chosen, unreadable: unreadable);
    } catch (error) {
      if (!mounted) {
        return;
      }
      Log.error('Tools: the file picker failed', error);
      state = state.copyWith(fileError: S.filePickFailed);
    }
  }

  void removeFile(int index) {
    if (index < 0 || index >= state.files.length || state.isBusy) {
      return;
    }
    final ToolDefinition? tool = state.tool.valueOrNull;
    final List<ToolUpload> files = <ToolUpload>[...state.files]
      ..removeAt(index);
    if (tool == null) {
      state = state.copyWith(files: files, clearFileError: true);
      return;
    }
    _applySelection(tool, files, unreadable: false);
  }

  void clearFiles() {
    if (state.isBusy) {
      return;
    }
    state = state.copyWith(
      files: const <ToolUpload>[],
      clearFileError: true,
      clearError: true,
    );
  }

  /// Trim to the ceiling, reject anything too big, and report why.
  void _applySelection(
    ToolDefinition tool,
    List<ToolUpload> chosen, {
    required bool unreadable,
  }) {
    final int ceiling = math.max(1, state.maxFiles);
    final List<ToolUpload> kept =
        chosen.length > ceiling ? chosen.sublist(0, ceiling) : chosen;

    String? message;
    if (unreadable) {
      message = S.filePickFailed;
    } else if (chosen.length > ceiling) {
      message = S.tooManyFiles(ceiling);
    }

    final int perFileLimit = tool.maxFileBytes > 0
        ? tool.maxFileBytes
        : _limits.maxFileBytes;
    final int totalBytes =
        kept.fold<int>(0, (int sum, ToolUpload f) => sum + f.sizeBytes);

    if (message == null && perFileLimit > 0) {
      for (final ToolUpload file in kept) {
        if (file.sizeBytes > perFileLimit) {
          message = S.fileTooLarge(
            Fmt.bytes(file.sizeBytes),
            Fmt.bytes(perFileLimit),
          );
          break;
        }
      }
    }

    if (message == null &&
        _limits.maxTotalUploadBytes > 0 &&
        totalBytes > _limits.maxTotalUploadBytes) {
      message = S.totalTooLarge(Fmt.bytes(_limits.maxTotalUploadBytes));
    }

    state = state.copyWith(
      files: kept,
      fileError: message,
      clearFileError: message == null,
      clearError: true,
      phase: ToolRunPhase.editing,
    );
  }

  // ---------------------------------------------------------------- submit

  /// Validates, uploads and queues. Returns true when the server accepted it.
  ///
  /// A false answer leaves the reason in `state.error`, which the screen reads
  /// to decide between a toast and a trip to the billing screen.
  Future<bool> submit() async {
    final ToolDefinition? tool = state.tool.valueOrNull;
    if (tool == null || !tool.supported || state.isBusy) {
      return false;
    }

    final Map<String, String> errors = <String, String>{};
    for (final ToolOption option in tool.options) {
      final String? failure =
          option.validate(state.values[option.name], form: state.values);
      if (failure != null) {
        errors[option.name] = failure;
      }
    }

    String? fileError = state.fileError;
    if (tool.needsFiles && state.files.length < tool.minFiles) {
      fileError = S.needAtLeastFiles(tool.minFiles);
    }

    if (errors.isNotEmpty || fileError != null) {
      state = state.copyWith(errors: errors, fileError: fileError);
      return false;
    }

    final CancelToken cancelToken = CancelToken();
    _cancelToken = cancelToken;
    _lastPercent = -1;

    final int totalBytes = state.totalBytesSelected;

    state = state.copyWith(
      phase: ToolRunPhase.uploading,
      errors: const <String, String>{},
      sentBytes: 0,
      totalBytes: totalBytes,
      clearError: true,
      clearFileError: true,
      clearJob: true,
    );

    try {
      final QueuedConversion queued = await _repository.convert(
        tool: tool,
        fields: state.values,
        files: state.files,
        onProgress: (int sent, int total) {
          if (!mounted) {
            return;
          }
          final int resolved = total > 0 ? total : totalBytes;
          final int percent =
              resolved <= 0 ? 100 : ((sent / resolved) * 100).floor();
          if (percent == _lastPercent && sent < resolved) {
            return;
          }
          _lastPercent = percent;
          state = state.copyWith(sentBytes: sent, totalBytes: resolved);
        },
        cancelToken: cancelToken,
      );

      if (!mounted) {
        return false;
      }
      state = state.copyWith(
        phase: ToolRunPhase.queued,
        conversionId: queued.id,
      );
      return true;
    } catch (error) {
      if (!mounted) {
        return false;
      }
      final ApiException failure = ApiException.from(error);
      if (failure.isCancelled) {
        state = state.copyWith(phase: ToolRunPhase.editing, sentBytes: 0);
        return false;
      }
      // A 422 comes back with the server's own per-field messages, which are
      // more specific than anything the client could have said — so the form
      // stays on screen with those messages under the fields they belong to,
      // rather than being replaced by a failure card that hides both the
      // messages and the files the user already chose.
      final bool isValidation = failure.fieldErrors.isNotEmpty ||
          failure.code == 'validation_failed';

      state = state.copyWith(
        phase: isValidation ? ToolRunPhase.editing : ToolRunPhase.failed,
        error: failure,
        errors: <String, String>{
          for (final MapEntry<String, List<String>> entry
              in failure.fieldErrors.entries)
            if (entry.value.isNotEmpty) entry.key: entry.value.first,
        },
        fileError: failure.fieldError('file') ?? failure.fieldError('files'),
      );
      return false;
    } finally {
      _cancelToken = null;
    }
  }

  void cancel() {
    _cancelToken?.cancel();
    _cancelToken = null;
  }

  // ----------------------------------------------------------------- result

  /// Fed by `conversionStatusPollProvider`.
  Future<void> onStatus(ConversionStatusInfo info) async {
    if (!mounted || info.id != state.conversionId) {
      return;
    }

    state = state.copyWith(status: info);

    if (!info.isSettled) {
      return;
    }

    if (info.status.isFailed) {
      state = state.copyWith(
        phase: ToolRunPhase.failed,
        error: ApiException(
          code: 'conversion_failed',
          message: info.error ?? S.conversionFailed,
        ),
      );
      return;
    }

    await loadResult();
  }

  /// The poller only ever reports the four small fields; the result card needs
  /// the filename and the size too.
  Future<void> loadResult() async {
    final int? id = state.conversionId;
    if (id == null) {
      return;
    }
    try {
      final Conversion conversion = await _repository.conversion(id);
      if (!mounted) {
        return;
      }
      state = conversion.isFailed
          ? state.copyWith(
              result: conversion,
              phase: ToolRunPhase.failed,
              error: ApiException(
                code: 'conversion_failed',
                message: conversion.error ?? S.conversionFailed,
              ),
            )
          : state.copyWith(
              result: conversion,
              phase: ToolRunPhase.finished,
              clearError: true,
            );
    } catch (error) {
      if (!mounted) {
        return;
      }
      if (ApiException.from(error).isCancelled) {
        return;
      }
      Log.warn('Tools: could not load the finished conversion — $error');
      state = state.copyWith(phase: ToolRunPhase.failed, error: error);
    }
  }

  /// A polling failure the stream surfaced. The job may still be running, so
  /// this is not a conversion failure — it is a "we stopped watching".
  void onPollFailure(Object error) {
    if (!mounted || state.phase != ToolRunPhase.queued) {
      return;
    }
    state = state.copyWith(phase: ToolRunPhase.failed, error: error);
  }

  /// Back to the form for a fresh run, keeping the options the user picked.
  /// The files go, because the ones just converted are done with.
  void reset() {
    cancel();
    state = state.copyWith(
      phase: ToolRunPhase.editing,
      files: const <ToolUpload>[],
      sentBytes: 0,
      totalBytes: 0,
      errors: const <String, String>{},
      clearFileError: true,
      clearError: true,
      clearJob: true,
    );
  }

  /// Back to the form after a failure, keeping the files. A conversion that
  /// failed because the workspace ran out of quota should be one tap away from
  /// succeeding once the plan changes — not a re-pick of five PDFs.
  void dismissFailure() {
    cancel();
    state = state.copyWith(
      phase: ToolRunPhase.editing,
      sentBytes: 0,
      totalBytes: 0,
      clearError: true,
      clearJob: true,
    );
  }

  @override
  void dispose() {
    cancel();
    super.dispose();
  }
}

/// One controller per tool key, disposed with its screen.
final AutoDisposeStateNotifierProviderFamily<ToolRunController, ToolRunState,
    String> conversionRunProvider = StateNotifierProvider.autoDispose
    .family<ToolRunController, ToolRunState, String>(
  (Ref ref, String toolKey) => ToolRunController(
    repository: ref.watch(toolRepositoryProvider),
    // read, not watch: refreshing the catalogue elsewhere must not rebuild
    // this provider and discard a half-filled form.
    catalogue: ref.read(toolsProvider.future),
    toolKey: toolKey,
  ),
);
