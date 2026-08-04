/// State for the barcode generator.
///
/// One controller owns the whole form because every field feeds the same live
/// preview: changing the quiet zone has to re-render exactly like changing the
/// value does. The preview is debounced at 350 ms and each request cancels the
/// one before it, so holding a key down costs one render rather than twenty.
///
/// The data field is validated on the device first, with the same rules the
/// server applies, so a half-typed EAN-13 never becomes a request at all.
library;

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/utils/logger.dart';
import '../data/barcode_repository.dart';
import '../domain/symbology.dart';

@immutable
class BarcodeFormState {
  const BarcodeFormState({
    required this.catalogue,
    required this.value,
    required this.scale,
    required this.height,
    required this.margin,
    required this.foreground,
    required this.background,
    required this.showText,
    required this.transparent,
    required this.isPreviewing,
    required this.isGenerating,
    this.symbology,
    this.preview,
    this.previewError,
    this.created,
    this.error,
  });

  const BarcodeFormState.initial()
      : catalogue = const AsyncValue<SymbologyCatalogue>.loading(),
        symbology = null,
        value = '',
        scale = 3,
        height = 70,
        margin = 10,
        foreground = '#000000',
        background = '#FFFFFF',
        showText = true,
        transparent = false,
        isPreviewing = false,
        isGenerating = false,
        preview = null,
        previewError = null,
        created = null,
        error = null;

  final AsyncValue<SymbologyCatalogue> catalogue;
  final Symbology? symbology;
  final String value;
  final int scale;
  final int height;
  final int margin;
  final String foreground;
  final String background;
  final bool showText;
  final bool transparent;

  /// True while a preview render is in flight. Deliberately not an
  /// [AsyncValue]: the previous image stays on screen while the next one is
  /// fetched, because blanking it on every keystroke is what makes a live
  /// preview feel broken.
  final bool isPreviewing;

  final bool isGenerating;
  final BarcodePreviewImage? preview;

  /// Shown under the data field, never as a toast — the user is mid-typing.
  final String? previewError;

  final GeneratedBarcode? created;
  final Object? error;

  BarcodeOptions get options =>
      catalogue.valueOrNull?.options ?? BarcodeOptions.fallback;

  /// The "show text" switch is meaningless for a matrix symbology.
  bool get canShowText => symbology?.supportsText ?? false;

  bool get canGenerate =>
      symbology != null &&
      value.trim().isNotEmpty &&
      previewError == null &&
      !isGenerating;

  BarcodeFormState copyWith({
    AsyncValue<SymbologyCatalogue>? catalogue,
    Symbology? symbology,
    String? value,
    int? scale,
    int? height,
    int? margin,
    String? foreground,
    String? background,
    bool? showText,
    bool? transparent,
    bool? isPreviewing,
    bool? isGenerating,
    BarcodePreviewImage? preview,
    String? previewError,
    GeneratedBarcode? created,
    Object? error,
    bool clearPreviewError = false,
    bool clearPreview = false,
    bool clearCreated = false,
    bool clearError = false,
  }) {
    return BarcodeFormState(
      catalogue: catalogue ?? this.catalogue,
      symbology: symbology ?? this.symbology,
      value: value ?? this.value,
      scale: scale ?? this.scale,
      height: height ?? this.height,
      margin: margin ?? this.margin,
      foreground: foreground ?? this.foreground,
      background: background ?? this.background,
      showText: showText ?? this.showText,
      transparent: transparent ?? this.transparent,
      isPreviewing: isPreviewing ?? this.isPreviewing,
      isGenerating: isGenerating ?? this.isGenerating,
      preview: clearPreview ? null : (preview ?? this.preview),
      previewError:
          clearPreviewError ? null : (previewError ?? this.previewError),
      created: clearCreated ? null : (created ?? this.created),
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class BarcodeController extends StateNotifier<BarcodeFormState> {
  BarcodeController(this._repository) : super(const BarcodeFormState.initial()) {
    unawaited(_load());
  }

  /// Long enough that typing a URL is one render, short enough that the preview
  /// feels attached to the keyboard.
  static const Duration _debounceDelay = Duration(milliseconds: 350);

  final BarcodeRepository _repository;

  Timer? _debounce;
  CancelToken? _previewToken;

  /// Bumped per preview so a slow response for an old value cannot land on top
  /// of a newer one.
  int _generation = 0;

  Future<void> _load() async {
    try {
      final SymbologyCatalogue catalogue = await _repository.symbologies();
      if (!mounted) {
        return;
      }
      final Symbology? first = catalogue.first;
      state = state.copyWith(
        catalogue: AsyncValue<SymbologyCatalogue>.data(catalogue),
        symbology: first,
        scale: catalogue.options.scale.value,
        height: catalogue.options.height.value,
        margin: catalogue.options.margin.value,
        foreground: catalogue.options.foreground.value,
        background: catalogue.options.background.value,
        showText: catalogue.options.showText && (first?.supportsText ?? false),
        transparent: catalogue.options.transparent,
      );
    } catch (error, stackTrace) {
      if (!mounted) {
        return;
      }
      state = state.copyWith(
        catalogue: AsyncValue<SymbologyCatalogue>.error(error, stackTrace),
      );
    }
  }

  Future<void> reload() async {
    state = state.copyWith(
      catalogue: const AsyncValue<SymbologyCatalogue>.loading(),
    );
    await _load();
  }

  // ------------------------------------------------------------------ fields

  void setSymbology(Symbology? symbology) {
    if (symbology == null || symbology == state.symbology) {
      return;
    }
    // A 2D symbology has no human-readable line, so the switch is forced off
    // rather than left set to a value the renderer would ignore. Coming back to
    // a 1D type restores the server's default rather than the off it was forced
    // to, which is otherwise a switch the user has to find and turn on again.
    final bool cameFrom1d = state.symbology?.supportsText ?? false;
    final bool showText = symbology.supportsText &&
        (cameFrom1d ? state.showText : state.options.showText);

    state = state.copyWith(
      symbology: symbology,
      showText: showText,
      clearPreviewError: true,
      clearCreated: true,
      clearError: true,
    );
    _schedulePreview();
  }

  void setValue(String value) {
    state = state.copyWith(
      value: value,
      clearPreviewError: true,
      clearCreated: true,
      clearError: true,
    );
    _schedulePreview();
  }

  void setScale(int scale) {
    state = state.copyWith(scale: state.options.scale.clamp(scale));
    _schedulePreview();
  }

  void setHeight(int height) {
    state = state.copyWith(height: state.options.height.clamp(height));
    _schedulePreview();
  }

  void setMargin(int margin) {
    state = state.copyWith(margin: state.options.margin.clamp(margin));
    _schedulePreview();
  }

  void setForeground(String colour) {
    state = state.copyWith(foreground: colour);
    if (state.options.foreground.accepts(colour)) {
      _schedulePreview();
    }
  }

  void setBackground(String colour) {
    state = state.copyWith(background: colour);
    if (state.options.background.accepts(colour)) {
      _schedulePreview();
    }
  }

  void setShowText({required bool enabled}) {
    state = state.copyWith(showText: enabled);
    _schedulePreview();
  }

  void setTransparent({required bool enabled}) {
    state = state.copyWith(transparent: enabled);
    _schedulePreview();
  }

  // ----------------------------------------------------------------- preview

  void _schedulePreview() {
    _debounce?.cancel();
    _debounce = Timer(_debounceDelay, () => unawaited(refreshPreview()));
  }

  /// Renders now, skipping the debounce. Used by the retry affordance.
  Future<void> refreshPreview() async {
    final Symbology? symbology = state.symbology;
    final String value = state.value.trim();

    if (symbology == null || value.isEmpty) {
      _previewToken?.cancel();
      _previewToken = null;
      state = state.copyWith(
        isPreviewing: false,
        clearPreview: true,
        clearPreviewError: true,
      );
      return;
    }

    // The same rules the server applies, run here so a half-typed EAN-13 never
    // becomes a request.
    final String? local = symbology.validate(
      value,
      absoluteMax: state.options.dataMaxLength,
    );
    if (local != null) {
      _previewToken?.cancel();
      _previewToken = null;
      state = state.copyWith(
        isPreviewing: false,
        previewError: local,
        clearPreview: true,
      );
      return;
    }

    final int generation = ++_generation;
    _previewToken?.cancel();
    final CancelToken token = CancelToken();
    _previewToken = token;

    state = state.copyWith(isPreviewing: true, clearPreviewError: true);

    try {
      final BarcodePreviewImage image = await _repository.preview(
        _request(symbology, value),
        cancelToken: token,
      );
      if (!mounted || generation != _generation) {
        return;
      }
      state = state.copyWith(
        preview: image,
        isPreviewing: false,
        clearPreviewError: true,
      );
    } catch (error) {
      if (!mounted || generation != _generation) {
        return;
      }
      final ApiException failure = ApiException.from(error);
      if (failure.isCancelled) {
        return;
      }
      state = state.copyWith(
        isPreviewing: false,
        previewError: failure.fieldError('data') ?? failure.message,
      );
    }
  }

  // ---------------------------------------------------------------- generate

  /// Spends one barcode unit. Returns null when the server refused, leaving the
  /// reason in `state.error` for the screen to route on.
  Future<GeneratedBarcode?> generate() async {
    final Symbology? symbology = state.symbology;
    final String value = state.value.trim();

    if (symbology == null || value.isEmpty || state.isGenerating) {
      return null;
    }

    final String? local = symbology.validate(
      value,
      absoluteMax: state.options.dataMaxLength,
    );
    if (local != null) {
      state = state.copyWith(previewError: local);
      return null;
    }

    state = state.copyWith(
      isGenerating: true,
      clearError: true,
      clearCreated: true,
    );

    try {
      final GeneratedBarcode created =
          await _repository.create(_request(symbology, value));
      if (!mounted) {
        return created;
      }
      state = state.copyWith(isGenerating: false, created: created);
      return created;
    } catch (error) {
      if (!mounted) {
        return null;
      }
      final ApiException failure = ApiException.from(error);
      state = state.copyWith(
        isGenerating: false,
        error: failure,
        previewError: failure.fieldError('data'),
      );
      Log.warn('Barcode: generation refused — ${failure.code}');
      return null;
    }
  }

  BarcodeRequest _request(Symbology symbology, String value) => BarcodeRequest(
        type: symbology.key,
        data: value,
        scale: state.scale,
        height: state.height,
        margin: state.margin,
        foreground: state.foreground,
        background: state.background,
        showText: symbology.supportsText && state.showText,
        transparent: state.transparent,
      );

  @override
  void dispose() {
    _debounce?.cancel();
    _previewToken?.cancel();
    super.dispose();
  }
}

final AutoDisposeStateNotifierProvider<BarcodeController, BarcodeFormState>
    barcodeControllerProvider =
    StateNotifierProvider.autoDispose<BarcodeController, BarcodeFormState>(
  (Ref ref) => BarcodeController(ref.watch(barcodeRepositoryProvider)),
);
