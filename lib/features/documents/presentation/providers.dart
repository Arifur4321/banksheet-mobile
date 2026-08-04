/// State for the documents feature: the list, one document's detail, the status
/// poller, and the upload.
///
/// All hand-written Riverpod — no codegen anywhere in this project. The two
/// list-shaped screens use a [StateNotifier] rather than a `FutureProvider`
/// because both need three things a future cannot express: a filter and a search
/// term that survive a refresh, pages appended to what is already on screen, and
/// an `isLoadingMore` flag that is distinct from "the whole screen is loading".
///
/// Every controller cancels its in-flight requests on dispose and drops its data
/// when the session ends, so the next account never sees the previous one's
/// statements.
library;

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../core/config/app_config.dart';
import '../../../core/i18n/strings.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/providers.dart';
import '../../../core/storage/prefs.dart';
import '../../../core/utils/json.dart';
import '../../../core/utils/logger.dart';
import '../data/document_repository.dart';
import '../data/image_pdf_builder.dart';
import '../domain/document.dart';
import '../domain/transaction.dart';

// ---------------------------------------------------------------------------
// List
// ---------------------------------------------------------------------------

/// The five chips above the documents list.
///
/// Three of them map straight onto the server's `status` filter. "Working"
/// cannot: `DocumentController::index()` matches a single status exactly, and
/// working means any of `uploaded`, `queued` or `processing`. "Needs review" is
/// narrowed to processed documents server-side and then refined here, because
/// the index has no notion of unapproved rows at all. Both are therefore
/// applied to the pages that come back — see [matches].
enum DocumentFilter {
  all,
  working,
  needsReview,
  done,
  failed;

  String get label => switch (this) {
        DocumentFilter.all => S.all,
        DocumentFilter.working => S.filterWorking,
        DocumentFilter.needsReview => S.needsReview,
        DocumentFilter.done => S.filterDone,
        DocumentFilter.failed => S.filterFailed,
      };

  /// The value to send as `?status=`, when this filter maps onto one.
  String? get serverStatus => switch (this) {
        DocumentFilter.needsReview => DocumentStatus.processed.wire,
        DocumentFilter.done => DocumentStatus.processed.wire,
        DocumentFilter.failed => DocumentStatus.failed.wire,
        DocumentFilter.all || DocumentFilter.working => null,
      };

  /// The client-side refinement applied on top of [serverStatus].
  bool matches(DocumentSummary document) => switch (this) {
        DocumentFilter.all => true,
        DocumentFilter.working => document.state.isWorking,
        DocumentFilter.needsReview => document.needsReview,
        DocumentFilter.done => document.state.isProcessed,
        DocumentFilter.failed => document.state.isFailed,
      };

  /// True when rows the server returned may still be hidden by [matches], and
  /// the list therefore has to keep pulling pages to fill the screen.
  bool get refinesLocally =>
      this == DocumentFilter.working || this == DocumentFilter.needsReview;
}

@immutable
class DocumentListState {
  const DocumentListState({
    required this.page,
    required this.filter,
    required this.query,
    required this.isLoadingMore,
    this.loadMoreError,
  });

  const DocumentListState.initial()
      : page = const AsyncValue<Paged<DocumentSummary>>.loading(),
        filter = DocumentFilter.all,
        query = '',
        isLoadingMore = false,
        loadMoreError = null;

  /// Every page fetched so far, merged.
  final AsyncValue<Paged<DocumentSummary>> page;

  final DocumentFilter filter;
  final String query;

  /// True while another page is on the way. Distinct from `page.isLoading`,
  /// which means the whole list is being replaced.
  final bool isLoadingMore;

  /// A failed "load more". Kept separate so one bad page does not throw away
  /// the rows the user is already reading.
  final Object? loadMoreError;

  List<DocumentSummary> get visible {
    final Paged<DocumentSummary>? loaded = page.valueOrNull;
    if (loaded == null) {
      return const <DocumentSummary>[];
    }
    return loaded.items.where(filter.matches).toList(growable: false);
  }

  bool get hasMore => page.valueOrNull?.meta.hasMore ?? false;

  int get total => page.valueOrNull?.meta.total ?? 0;

  bool get isFiltered => filter != DocumentFilter.all || query.isNotEmpty;

  DocumentListState copyWith({
    AsyncValue<Paged<DocumentSummary>>? page,
    DocumentFilter? filter,
    String? query,
    bool? isLoadingMore,
    Object? loadMoreError,
    bool clearLoadMoreError = false,
  }) {
    return DocumentListState(
      page: page ?? this.page,
      filter: filter ?? this.filter,
      query: query ?? this.query,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      loadMoreError:
          clearLoadMoreError ? null : (loadMoreError ?? this.loadMoreError),
    );
  }
}

class DocumentListController extends StateNotifier<DocumentListState> {
  DocumentListController(this._repository)
      : super(const DocumentListState.initial()) {
    unawaited(refresh());
  }

  /// Rows worth showing before the list stops chasing pages for a filter that
  /// is refined on the device.
  static const int _minVisibleRows = 8;

  /// The ceiling on that chase, per user action.
  static const int _maxAutoPages = 4;

  final DocumentRepository _repository;

  final CancelToken _cancelToken = CancelToken();

  /// Bumped on every filter or query change so a slow in-flight page for the
  /// previous term cannot land on top of the new one.
  int _generation = 0;

  Future<void> refresh({bool showLoading = false}) async {
    final int generation = ++_generation;

    if (showLoading || !state.page.hasValue) {
      state = state.copyWith(
        page: const AsyncValue<Paged<DocumentSummary>>.loading(),
        isLoadingMore: false,
        clearLoadMoreError: true,
      );
    }

    try {
      final Paged<DocumentSummary> first = await _repository.list(
        status: state.filter.serverStatus,
        query: state.query,
        cancelToken: _cancelToken,
      );
      if (!mounted || generation != _generation) {
        return;
      }
      state = state.copyWith(
        page: AsyncValue<Paged<DocumentSummary>>.data(first),
        isLoadingMore: false,
        clearLoadMoreError: true,
      );
      await _autoFill(generation);
    } catch (error, stackTrace) {
      if (!mounted || generation != _generation) {
        return;
      }
      if (ApiException.from(error).isCancelled) {
        return;
      }
      state = state.copyWith(
        page: AsyncValue<Paged<DocumentSummary>>.error(error, stackTrace),
        isLoadingMore: false,
      );
    }
  }

  Future<void> loadMore() async {
    final int generation = _generation;
    await _fetchNextPage(generation);
    await _autoFill(generation);
  }

  /// A filter that is refined on the device can hide every row the server just
  /// sent, which would leave the screen empty under a filter that does have
  /// matches two pages down. Keep pulling until there is something to read —
  /// bounded, so a workspace with ten thousand processed documents and no
  /// working ones cannot turn one tap into an unbounded crawl.
  Future<void> _autoFill(int generation) async {
    if (!state.filter.refinesLocally) {
      return;
    }
    int pages = 0;
    while (mounted &&
        generation == _generation &&
        pages < _maxAutoPages &&
        state.hasMore &&
        state.visible.length < _minVisibleRows) {
      pages++;
      await _fetchNextPage(generation);
    }
  }

  Future<void> _fetchNextPage(int generation) async {
    final Paged<DocumentSummary>? current = state.page.valueOrNull;
    if (current == null ||
        !current.meta.hasMore ||
        state.isLoadingMore ||
        generation != _generation) {
      return;
    }

    state = state.copyWith(isLoadingMore: true, clearLoadMoreError: true);

    try {
      final Paged<DocumentSummary> next = await _repository.list(
        page: current.meta.currentPage + 1,
        status: state.filter.serverStatus,
        query: state.query,
        cancelToken: _cancelToken,
      );
      if (!mounted || generation != _generation) {
        return;
      }
      state = state.copyWith(
        page: AsyncValue<Paged<DocumentSummary>>.data(current.merge(next)),
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

  void setFilter(DocumentFilter filter) {
    if (filter == state.filter) {
      return;
    }
    state = state.copyWith(filter: filter);
    unawaited(refresh(showLoading: true));
  }

  void setQuery(String query) {
    final String trimmed = query.trim();
    if (trimmed == state.query) {
      return;
    }
    state = state.copyWith(query: trimmed);
    unawaited(refresh(showLoading: true));
  }

  /// Drop a row the user just deleted, without re-fetching the whole list and
  /// losing their scroll position.
  void remove(int id) {
    final Paged<DocumentSummary>? current = state.page.valueOrNull;
    if (current == null) {
      return;
    }
    state = state.copyWith(
      page: AsyncValue<Paged<DocumentSummary>>.data(
        Paged<DocumentSummary>(
          items: current.items
              .where((DocumentSummary d) => d.id != id)
              .toList(growable: false),
          meta: current.meta,
        ),
      ),
    );
  }

  /// Swap in a document whose status changed elsewhere (a finished extraction,
  /// a reprocess), so the list agrees with the detail screen behind it.
  void replace(DocumentSummary document) {
    final Paged<DocumentSummary>? current = state.page.valueOrNull;
    if (current == null) {
      return;
    }
    state = state.copyWith(
      page: AsyncValue<Paged<DocumentSummary>>.data(
        Paged<DocumentSummary>(
          items: current.items
              .map((DocumentSummary d) => d.id == document.id ? document : d)
              .toList(growable: false),
          meta: current.meta,
        ),
      ),
    );
  }

  /// Forget everything. Called when the session ends.
  void reset() {
    _generation++;
    state = const DocumentListState.initial();
    unawaited(refresh(showLoading: true));
  }

  @override
  void dispose() {
    _generation++;
    _cancelToken.cancel();
    super.dispose();
  }
}

final StateNotifierProvider<DocumentListController, DocumentListState>
    documentListProvider =
    StateNotifierProvider<DocumentListController, DocumentListState>(
  (Ref ref) {
    final DocumentListController controller =
        DocumentListController(ref.watch(documentRepositoryProvider));
    ref.listen<int>(
      sessionSignalProvider,
      (int? _, int __) => controller.reset(),
    );
    return controller;
  },
);

// ---------------------------------------------------------------------------
// Detail
// ---------------------------------------------------------------------------

@immutable
class DocumentDetailState {
  const DocumentDetailState({
    required this.detail,
    required this.transactions,
    required this.meta,
    required this.isLoadingMore,
  });

  const DocumentDetailState.initial()
      : detail = const AsyncValue<DocumentDetail>.loading(),
        transactions = const <ExtractedTransaction>[],
        meta = PageMeta.empty,
        isLoadingMore = false;

  final AsyncValue<DocumentDetail> detail;

  /// Accumulated across pages, so approving a row on page 3 does not scroll the
  /// reviewer back to page 1.
  final List<ExtractedTransaction> transactions;

  final PageMeta meta;
  final bool isLoadingMore;

  bool get hasMore => meta.hasMore;

  int get openCount =>
      transactions.where((ExtractedTransaction t) => t.isOpen).length;

  DocumentDetailState copyWith({
    AsyncValue<DocumentDetail>? detail,
    List<ExtractedTransaction>? transactions,
    PageMeta? meta,
    bool? isLoadingMore,
  }) {
    return DocumentDetailState(
      detail: detail ?? this.detail,
      transactions: transactions ?? this.transactions,
      meta: meta ?? this.meta,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
    );
  }
}

class DocumentDetailController extends StateNotifier<DocumentDetailState> {
  DocumentDetailController(this._repository, this._documentId)
      : super(const DocumentDetailState.initial()) {
    unawaited(load());
  }

  final DocumentRepository _repository;
  final int _documentId;

  final CancelToken _cancelToken = CancelToken();
  int _generation = 0;

  Future<void> load({bool showLoading = false}) async {
    final int generation = ++_generation;

    if (showLoading || !state.detail.hasValue) {
      state = state.copyWith(
        detail: const AsyncValue<DocumentDetail>.loading(),
      );
    }

    try {
      final DocumentDetail detail = await _repository.detail(
        _documentId,
        cancelToken: _cancelToken,
      );
      if (!mounted || generation != _generation) {
        return;
      }
      state = DocumentDetailState(
        detail: AsyncValue<DocumentDetail>.data(detail),
        transactions: detail.transactions.items,
        meta: detail.transactions.meta,
        isLoadingMore: false,
      );
    } catch (error, stackTrace) {
      if (!mounted || generation != _generation) {
        return;
      }
      if (ApiException.from(error).isCancelled) {
        return;
      }
      state = state.copyWith(
        detail: AsyncValue<DocumentDetail>.error(error, stackTrace),
        isLoadingMore: false,
      );
    }
  }

  /// Next page of rows.
  ///
  /// Deliberately the detail endpoint again rather than `GET /transactions`:
  /// the two paginate at different sizes (100 against 30), so mixing them would
  /// skip rows in the middle of a statement. The re-sent header costs a couple
  /// of kilobytes and keeps the review counters honest as rows are approved.
  Future<void> loadMore() async {
    if (state.isLoadingMore || !state.meta.hasMore) {
      return;
    }

    final int generation = _generation;
    state = state.copyWith(isLoadingMore: true);

    try {
      final DocumentDetail next = await _repository.detail(
        _documentId,
        transactionsPage: state.meta.currentPage + 1,
        cancelToken: _cancelToken,
      );
      if (!mounted || generation != _generation) {
        return;
      }
      state = state.copyWith(
        detail: AsyncValue<DocumentDetail>.data(next),
        transactions: <ExtractedTransaction>[
          ...state.transactions,
          ...next.transactions.items,
        ],
        meta: next.transactions.meta,
        isLoadingMore: false,
      );
    } catch (error) {
      if (!mounted || generation != _generation) {
        return;
      }
      state = state.copyWith(isLoadingMore: false);
      if (!ApiException.from(error).isCancelled) {
        Log.warn('Documents: could not load more rows — $error');
      }
    }
  }

  /// Swap an edited row in place. The server's copy wins — it recomputes
  /// `amount_signed` and may have changed `needs_review`.
  void replaceTransaction(ExtractedTransaction updated) {
    if (!mounted) {
      return;
    }
    state = state.copyWith(
      transactions: state.transactions
          .map((ExtractedTransaction t) => t.id == updated.id ? updated : t)
          .toList(growable: false),
    );
  }

  void reset() {
    _generation++;
    state = const DocumentDetailState.initial();
    unawaited(load(showLoading: true));
  }

  @override
  void dispose() {
    _generation++;
    _cancelToken.cancel();
    super.dispose();
  }
}

final AutoDisposeStateNotifierProviderFamily<DocumentDetailController,
    DocumentDetailState, int> documentDetailProvider =
    StateNotifierProvider.autoDispose
        .family<DocumentDetailController, DocumentDetailState, int>(
  (Ref ref, int documentId) {
    final DocumentDetailController controller = DocumentDetailController(
      ref.watch(documentRepositoryProvider),
      documentId,
    );
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

/// Polls `GET /documents/{id}/status` while the document is in flight.
///
/// Three stopping conditions, all of them necessary:
///   * the document settled — the server withdraws `poll_after_seconds`, which
///     is the signal the client honours rather than matching status strings;
///   * [AppConfig.pollCeiling] elapsed — a worker that died must not leave a
///     phone polling for the rest of the day; the user can pull to refresh;
///   * the provider was disposed, i.e. the screen is gone.
///
/// The interval is the larger of [AppConfig.pollInterval] and whatever the
/// server asked for, so the client can only ever be politer than requested.
final AutoDisposeStreamProviderFamily<DocumentStatusInfo, int>
    documentStatusPollProvider =
    StreamProvider.autoDispose.family<DocumentStatusInfo, int>(
  (Ref ref, int documentId) async* {
    final DocumentRepository repository = ref.watch(documentRepositoryProvider);
    final CancelToken cancelToken = CancelToken();
    bool disposed = false;

    ref.onDispose(() {
      disposed = true;
      cancelToken.cancel();
    });

    final DateTime deadline = DateTime.now().add(AppConfig.pollCeiling);
    int failures = 0;

    while (!disposed && DateTime.now().isBefore(deadline)) {
      // `late` so definite-assignment analysis never has to reason about the
      // catch below, which only ever exits abruptly.
      late final DocumentStatusInfo info;
      try {
        info = await repository.status(documentId, cancelToken: cancelToken);
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
        // Back off linearly. A statement queued behind a long OCR job is the
        // normal case for a timeout here, and hammering it does not help.
        await Future<void>.delayed(AppConfig.pollInterval * failures);
        continue;
      }

      failures = 0;
      yield info;

      if (info.isSettled) {
        return;
      }

      await Future<void>.delayed(_pollDelay(info));
    }

    // The ceiling, not the document, ended this. Surfacing it as an error is
    // what puts "we stopped checking, pull to refresh" on the screen instead of
    // a spinner that never resolves.
    if (!disposed) {
      throw const ApiException(
        code: ApiException.codeTimeout,
        message: S.pollingStopped,
      );
    }
  },
);

Duration _pollDelay(DocumentStatusInfo info) {
  final Duration requested = Duration(seconds: info.pollAfterSeconds ?? 0);
  return requested > AppConfig.pollInterval
      ? requested
      : AppConfig.pollInterval;
}

// ---------------------------------------------------------------------------
// Extraction profiles (for the upload and reprocess pickers)
// ---------------------------------------------------------------------------

final AutoDisposeFutureProviderFamily<List<ProfileRef>, String>
    extractionProfileOptionsProvider =
    FutureProvider.autoDispose.family<List<ProfileRef>, String>(
  (Ref ref, String documentType) =>
      ref.watch(documentRepositoryProvider).profiles(documentType: documentType),
);

// ---------------------------------------------------------------------------
// Upload
// ---------------------------------------------------------------------------

enum UploadPhase { idle, preparing, ready, uploading, success, failure }

/// Where the file came from. Only the camera path builds a PDF locally.
enum UploadSource { file, scan }

/// The file that is about to be sent.
@immutable
class UploadSelection {
  const UploadSelection({
    required this.path,
    required this.filename,
    required this.sizeBytes,
    required this.source,
  });

  final String path;
  final String filename;
  final int sizeBytes;
  final UploadSource source;

  String get extension =>
      p.extension(filename).replaceFirst('.', '').toLowerCase();

  /// True for the formats the server stores but cannot extract from. Worth
  /// saying before the upload rather than as a warning after it.
  bool get isUnprocessable =>
      const <String>{'jpg', 'jpeg', 'png', 'zip'}.contains(extension);
}

@immutable
class UploadState {
  const UploadState({
    required this.phase,
    required this.documentType,
    required this.scanPages,
    required this.sentBytes,
    required this.totalBytes,
    this.selection,
    this.profileId,
    this.idempotencyKey,
    this.error,
    this.result,
  });

  const UploadState.initial(this.documentType, this.profileId)
      : phase = UploadPhase.idle,
        scanPages = const <String>[],
        sentBytes = 0,
        totalBytes = 0,
        selection = null,
        idempotencyKey = null,
        error = null,
        result = null;

  final UploadPhase phase;
  final String documentType;
  final int? profileId;
  final UploadSelection? selection;

  /// Camera captures, in page order.
  final List<String> scanPages;

  final int sentBytes;
  final int totalBytes;

  /// Generated once per selected file and reused across retries, so a retry
  /// after a dropped response resolves to the original document instead of
  /// consuming a second unit of quota.
  final String? idempotencyKey;

  final Object? error;
  final UploadResult? result;

  double get progress =>
      totalBytes <= 0 ? 0 : (sentBytes / totalBytes).clamp(0.0, 1.0).toDouble();

  bool get isBusy =>
      phase == UploadPhase.preparing || phase == UploadPhase.uploading;

  bool get isTooLarge =>
      (selection?.sizeBytes ?? 0) > AppConfig.maxDocumentUploadBytes;

  bool get canUpload => selection != null && !isTooLarge && !isBusy;

  bool get isBankStatement => documentType == DocumentKind.bankStatement.wire;

  UploadState copyWith({
    UploadPhase? phase,
    String? documentType,
    int? profileId,
    UploadSelection? selection,
    List<String>? scanPages,
    int? sentBytes,
    int? totalBytes,
    String? idempotencyKey,
    Object? error,
    UploadResult? result,
    bool clearProfile = false,
    bool clearSelection = false,
    bool clearError = false,
  }) {
    return UploadState(
      phase: phase ?? this.phase,
      documentType: documentType ?? this.documentType,
      profileId: clearProfile ? null : (profileId ?? this.profileId),
      selection: clearSelection ? null : (selection ?? this.selection),
      scanPages: scanPages ?? this.scanPages,
      sentBytes: sentBytes ?? this.sentBytes,
      totalBytes: totalBytes ?? this.totalBytes,
      idempotencyKey:
          clearSelection ? null : (idempotencyKey ?? this.idempotencyKey),
      error: clearError ? null : (error ?? this.error),
      result: result ?? this.result,
    );
  }
}

class UploadController extends StateNotifier<UploadState> {
  UploadController({
    required DocumentRepository repository,
    required Prefs prefs,
    ImagePicker? camera,
  })  : _repository = repository,
        _prefs = prefs,
        _camera = camera ?? ImagePicker(),
        super(
          UploadState.initial(prefs.defaultDocumentType, prefs.defaultProfileId),
        );

  final DocumentRepository _repository;
  final Prefs _prefs;
  final ImagePicker _camera;

  CancelToken? _cancelToken;

  /// The last percentage pushed into state. dio reports progress per chunk —
  /// thousands of times on a large file — and rebuilding the screen for a
  /// change nobody can see is the definition of jank.
  int _lastPercent = -1;

  // ------------------------------------------------------------- choices

  void setDocumentType(String type) {
    if (type == state.documentType) {
      return;
    }
    // A profile only means anything for a bank statement — the server nulls it
    // out for every other type — so switching away clears the picker rather
    // than silently sending a value that will be discarded.
    state = type == DocumentKind.bankStatement.wire
        ? state.copyWith(documentType: type)
        : state.copyWith(documentType: type, clearProfile: true);
    unawaited(_prefs.setDefaultDocumentType(type));
  }

  void setProfile(int? profileId) {
    state = profileId == null
        ? state.copyWith(clearProfile: true)
        : state.copyWith(profileId: profileId);
    unawaited(_prefs.setDefaultProfileId(profileId));
  }

  // --------------------------------------------------------------- file

  /// Opens the system file picker, restricted to the extensions the server
  /// actually accepts.
  Future<void> pickFile() async {
    if (state.isBusy) {
      return;
    }
    try {
      final FilePickerResult? picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: DocumentRepository.acceptedExtensions,
      );
      if (!mounted || picked == null || picked.files.isEmpty) {
        return;
      }

      final PlatformFile file = picked.files.first;
      final String? path = file.path;
      if (path == null) {
        state = state.copyWith(
          phase: UploadPhase.failure,
          error: const ApiException(
            code: ApiException.codeUnknown,
            message: S.filePickFailed,
          ),
        );
        return;
      }

      _select(
        UploadSelection(
          path: path,
          filename: file.name,
          sizeBytes: file.size,
          source: UploadSource.file,
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      Log.error('Document upload: the file picker failed', error);
      state = state.copyWith(phase: UploadPhase.failure, error: error);
    }
  }

  // --------------------------------------------------------------- scan

  /// Captures one more page. Returns silently when the user backs out of the
  /// camera, which is not an error.
  Future<void> capturePage() async {
    if (state.isBusy) {
      return;
    }
    try {
      final XFile? shot = await _camera.pickImage(
        source: ImageSource.camera,
        // Downscaled at capture as well as in the builder: a 12 MP JPEG that
        // never reaches Dart is a second of decode we never pay for.
        maxWidth: 2400,
        maxHeight: 2400,
        imageQuality: 92,
      );
      if (!mounted || shot == null) {
        return;
      }
      state = state.copyWith(
        scanPages: <String>[...state.scanPages, shot.path],
        clearSelection: true,
        clearError: true,
        phase: UploadPhase.idle,
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      Log.error('Document upload: the camera capture failed', error);
      state = state.copyWith(phase: UploadPhase.failure, error: error);
    }
  }

  void removePage(int index) {
    if (index < 0 || index >= state.scanPages.length) {
      return;
    }
    final List<String> pages = <String>[...state.scanPages]..removeAt(index);
    state = state.copyWith(
      scanPages: pages,
      clearSelection: true,
      clearError: true,
      phase: UploadPhase.idle,
    );
  }

  void reorderPages(int oldIndex, int newIndex) {
    final List<String> pages = <String>[...state.scanPages];
    if (oldIndex < 0 || oldIndex >= pages.length) {
      return;
    }
    // ReorderableListView reports the target index in the pre-removal list.
    final int target = newIndex > oldIndex ? newIndex - 1 : newIndex;
    final String moved = pages.removeAt(oldIndex);
    pages.insert(target.clamp(0, pages.length), moved);
    state = state.copyWith(
      scanPages: pages,
      clearSelection: true,
      clearError: true,
      phase: UploadPhase.idle,
    );
  }

  void clearPages() {
    state = state.copyWith(
      scanPages: const <String>[],
      clearSelection: true,
      clearError: true,
      phase: UploadPhase.idle,
    );
  }

  /// Assembles the captured pages into a PDF on a background isolate.
  ///
  /// The work is real — decode, rotate, resize and re-encode every page — and
  /// running it on the UI isolate would freeze the app for seconds on a ten
  /// page scan.
  Future<void> buildScanPdf() async {
    if (state.scanPages.isEmpty || state.isBusy) {
      return;
    }

    state = state.copyWith(phase: UploadPhase.preparing, clearError: true);

    try {
      final List<String> pages = List<String>.of(state.scanPages);
      final Uint8List bytes =
          await compute(ImagePdfBuilder.buildFromPaths, pages);

      final Directory directory = await getTemporaryDirectory();
      final String filename = _scanFilename();
      final File output = File(p.join(directory.path, filename));
      await output.writeAsBytes(bytes, flush: true);

      if (!mounted) {
        return;
      }

      _select(
        UploadSelection(
          path: output.path,
          filename: filename,
          sizeBytes: bytes.length,
          source: UploadSource.scan,
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      Log.error('Document upload: could not build the scanned PDF', error);
      state = state.copyWith(
        phase: UploadPhase.failure,
        error: error is ImagePdfException
            ? ApiException(
                code: ApiException.codeUnknown,
                message: S.scanPageUnreadable(error.pageNumber),
              )
            : error,
      );
    }
  }

  // ------------------------------------------------------------- upload

  Future<void> upload() async {
    final UploadSelection? selection = state.selection;
    if (selection == null || state.isTooLarge || state.isBusy) {
      return;
    }

    final CancelToken cancelToken = CancelToken();
    _cancelToken = cancelToken;
    _lastPercent = -1;

    state = state.copyWith(
      phase: UploadPhase.uploading,
      sentBytes: 0,
      totalBytes: selection.sizeBytes,
      clearError: true,
    );

    try {
      final UploadResult result = await _repository.upload(
        filePath: selection.path,
        filename: selection.filename,
        idempotencyKey: state.idempotencyKey ?? _newIdempotencyKey(),
        documentType: state.documentType,
        extractionProfileId: state.isBankStatement ? state.profileId : null,
        onProgress: (int sent, int total) {
          if (!mounted) {
            return;
          }
          final int resolved = total > 0 ? total : selection.sizeBytes;
          final int percent =
              resolved <= 0 ? 0 : ((sent / resolved) * 100).floor();
          if (percent == _lastPercent && sent < resolved) {
            return;
          }
          _lastPercent = percent;
          state = state.copyWith(sentBytes: sent, totalBytes: resolved);
        },
        cancelToken: cancelToken,
      );

      if (!mounted) {
        return;
      }
      state = state.copyWith(phase: UploadPhase.success, result: result);
    } catch (error) {
      if (!mounted) {
        return;
      }
      final ApiException failure = ApiException.from(error);
      state = failure.isCancelled
          // A cancel returns to "ready" rather than "failed": the same file is
          // still chosen, and the same idempotency key is still valid, so
          // tapping upload again resumes rather than double-charging.
          ? state.copyWith(phase: UploadPhase.ready, sentBytes: 0)
          : state.copyWith(phase: UploadPhase.failure, error: failure);
    } finally {
      _cancelToken = null;
    }
  }

  void cancel() {
    _cancelToken?.cancel();
    _cancelToken = null;
  }

  /// Back to a ready state after a failure, keeping the file and its key.
  void dismissError() {
    if (state.selection != null) {
      state = state.copyWith(phase: UploadPhase.ready, clearError: true);
    } else {
      state = state.copyWith(phase: UploadPhase.idle, clearError: true);
    }
  }

  void reset() {
    cancel();
    state = UploadState.initial(state.documentType, state.profileId);
  }

  // ---------------------------------------------------------- internals

  void _select(UploadSelection selection) {
    state = state.copyWith(
      selection: selection,
      // A new file is a new attempt, so it gets a new key. A *retry* of this
      // same file keeps it, which is the whole point.
      idempotencyKey: _newIdempotencyKey(),
      phase: UploadPhase.ready,
      sentBytes: 0,
      totalBytes: selection.sizeBytes,
      clearError: true,
    );
  }

  static String _newIdempotencyKey() {
    final math.Random random = math.Random.secure();
    final StringBuffer buffer = StringBuffer();
    for (int i = 0; i < 16; i++) {
      buffer.write(random.nextInt(256).toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString();
  }

  static String _scanFilename() {
    final DateTime now = DateTime.now();
    String two(int value) => value < 10 ? '0$value' : '$value';
    return '${S.scanFilenamePrefix}-${now.year}${two(now.month)}${two(now.day)}'
        '-${two(now.hour)}${two(now.minute)}${two(now.second)}.pdf';
  }

  @override
  void dispose() {
    cancel();
    super.dispose();
  }
}

final AutoDisposeStateNotifierProvider<UploadController, UploadState>
    uploadControllerProvider =
    StateNotifierProvider.autoDispose<UploadController, UploadState>(
  (Ref ref) => UploadController(
    repository: ref.watch(documentRepositoryProvider),
    prefs: ref.watch(prefsProvider),
  ),
);
