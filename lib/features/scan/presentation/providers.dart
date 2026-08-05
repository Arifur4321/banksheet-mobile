/// Scanner state.
///
/// The page list is a [StateNotifier] rather than a widget field for one
/// reason: the camera takes the app to the background, and on a low-memory
/// Android device the scan screen's [State] can be disposed and rebuilt while
/// the user is framing page four. A notifier held by a provider outlives that;
/// a `List` in a `StatefulWidget` does not, and the bug it causes — "my first
/// three pages vanished" — only ever reproduces on the cheap phone you do not
/// have.
///
/// The notifier is *not* auto-disposed for the same reason. It is cleared
/// explicitly when a scan is finished or abandoned, which is the one moment
/// that decision can be made correctly.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../../core/storage/local_db.dart';
import '../../../core/utils/logger.dart';
import '../data/scan_repository.dart';
import '../domain/scan_page.dart';

final Provider<ScanRepository> scanRepositoryProvider =
    Provider<ScanRepository>((Ref ref) => ScanRepository(ref.watch(localDbProvider)));

/// How many free scan PDFs this install has left.
///
/// Read by the welcome screen, the home screen and the scanner itself, so it is
/// a provider rather than three separate queries that can disagree.
final FutureProvider<int> freeScansLeftProvider = FutureProvider<int>(
  (Ref ref) => ref.watch(localDbProvider).installRemaining(InstallMeter.scanPdf),
);

/// What the scanner is doing right now.
enum ScanPhase {
  /// Collecting pages.
  editing,

  /// The camera or gallery sheet is open — used to suppress a second launch
  /// from a double tap, which on iOS throws rather than being ignored.
  picking,

  /// Building the PDF.
  building,
}

@immutable
class ScanState {
  const ScanState({
    this.pages = const <ScanPage>[],
    this.phase = ScanPhase.editing,
    this.error,
  });

  final List<ScanPage> pages;
  final ScanPhase phase;

  /// Set when the last action failed. Cleared by the next successful one, so
  /// the screen never shows a stale message next to fresh content.
  final Object? error;

  bool get isEmpty => pages.isEmpty;

  bool get isBusy => phase != ScanPhase.editing;

  int get pageCount => pages.length;

  ScanState copyWith({
    List<ScanPage>? pages,
    ScanPhase? phase,
    Object? error,
    bool clearError = false,
  }) {
    return ScanState(
      pages: pages ?? this.pages,
      phase: phase ?? this.phase,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class ScanController extends StateNotifier<ScanState> {
  ScanController(this._ref) : super(const ScanState());

  final Ref _ref;

  ScanRepository get _repo => _ref.read(scanRepositoryProvider);

  /// The most pages one PDF will take.
  ///
  /// Matches the server's `files` => `max:30` rule on `images-to-pdf`, so a
  /// scan that is later re-run through the workspace tool does not fail a
  /// validation the user was never warned about. It is also about where a
  /// hand-held scan stops being reasonable on a phone.
  static const int maxPages = 30;

  bool get isFull => state.pageCount >= maxPages;

  Future<void> addFromCamera() async {
    if (state.isBusy || isFull) {
      return;
    }
    state = state.copyWith(phase: ScanPhase.picking, clearError: true);
    try {
      final ScanPage? page = await _repo.capture();
      state = state.copyWith(
        pages: page == null
            ? state.pages
            : <ScanPage>[...state.pages, page],
        phase: ScanPhase.editing,
      );
    } on Object catch (e, s) {
      Log.error('Camera capture failed', e, s);
      state = state.copyWith(phase: ScanPhase.editing, error: e);
    }
  }

  Future<void> addFromGallery() async {
    if (state.isBusy || isFull) {
      return;
    }
    state = state.copyWith(phase: ScanPhase.picking, clearError: true);
    try {
      final List<ScanPage> picked = await _repo.pickFromGallery();
      // Truncate rather than reject: a user who selected 40 images meant "all
      // of these", and losing the whole selection to a limit they were never
      // shown is worse than taking the first 30 and saying so.
      final int room = maxPages - state.pageCount;
      final List<ScanPage> kept =
          picked.length > room ? picked.sublist(0, room) : picked;

      state = state.copyWith(
        pages: <ScanPage>[...state.pages, ...kept],
        phase: ScanPhase.editing,
        error: kept.length < picked.length
            ? ScanTooManyPages(picked.length, maxPages)
            : null,
      );
    } on Object catch (e, s) {
      Log.error('Gallery pick failed', e, s);
      state = state.copyWith(phase: ScanPhase.editing, error: e);
    }
  }

  void removeAt(int index) {
    if (index < 0 || index >= state.pageCount) {
      return;
    }
    final List<ScanPage> next = <ScanPage>[...state.pages]..removeAt(index);
    state = state.copyWith(pages: next, clearError: true);
  }

  /// Moves a page, using [ReorderableListView]'s index convention where the
  /// destination is computed before the source is removed.
  void reorder(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= state.pageCount) {
      return;
    }
    final List<ScanPage> next = <ScanPage>[...state.pages];
    final int target = newIndex > oldIndex ? newIndex - 1 : newIndex;
    next.insert(target.clamp(0, next.length - 1), next.removeAt(oldIndex));
    state = state.copyWith(pages: next, clearError: true);
  }

  void clear() => state = const ScanState();

  /// Builds the PDF. Returns null if it failed; the reason is on [ScanState].
  Future<ScanResult?> build({required bool metered, String? title}) async {
    if (state.isEmpty || state.isBusy) {
      return null;
    }

    state = state.copyWith(phase: ScanPhase.building, clearError: true);
    try {
      final ScanResult result = await _repo.buildPdf(
        state.pages,
        metered: metered,
        title: title,
      );
      state = state.copyWith(phase: ScanPhase.editing);
      // The count the welcome and home screens display has just changed.
      _ref.invalidate(freeScansLeftProvider);
      return result;
    } on Object catch (e, s) {
      Log.error('Scan build failed', e, s);
      state = state.copyWith(phase: ScanPhase.editing, error: e);
      return null;
    }
  }
}

/// Raised when a gallery selection was truncated to [limit].
class ScanTooManyPages implements Exception {
  const ScanTooManyPages(this.selected, this.limit);

  final int selected;
  final int limit;
}

final StateNotifierProvider<ScanController, ScanState> scanControllerProvider =
    StateNotifierProvider<ScanController, ScanState>(
  (Ref ref) => ScanController(ref),
);
