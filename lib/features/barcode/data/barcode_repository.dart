/// Every barcode call the app makes.
///
/// `preview` is the interesting one: it costs no quota and writes nothing, so
/// the screen may call it on every keystroke (debounced), while `create` is the
/// only path that spends a barcode unit. Keeping them as two methods with two
/// return types makes it hard to call the expensive one by accident.
///
/// The preview answer is `{mime, base64, width, height, byte_size}` rather than
/// raw PNG bytes, because a JSON client cannot consume an `image/png` body from
/// the same parser it uses for everything else.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/endpoints.dart';
import '../../../core/providers.dart';
import '../../../core/utils/json.dart';
import '../domain/symbology.dart';

/// One barcode request, in the exact field names `validatedInput()` reads.
class BarcodeRequest {
  const BarcodeRequest({
    required this.type,
    required this.data,
    required this.scale,
    required this.height,
    required this.margin,
    required this.foreground,
    required this.background,
    required this.showText,
    required this.transparent,
  });

  final String type;
  final String data;
  final int scale;
  final int height;
  final int margin;
  final String foreground;
  final String background;
  final bool showText;
  final bool transparent;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'type': type,
        'data': data,
        'scale': scale,
        'height': height,
        'margin': margin,
        'foreground': foreground,
        // The server ignores `background` when `transparent` is set, but
        // sending a valid colour anyway keeps the payload one shape.
        'background': background,
        'show_text': showText,
        'transparent': transparent,
      };
}

class BarcodeRepository {
  const BarcodeRepository(this._api);

  final ApiClient _api;

  /// The eight types with their per-type data rules and the shared bounds.
  Future<SymbologyCatalogue> symbologies({CancelToken? cancelToken}) async {
    final Map<String, dynamic> json = await _api.get(
      Endpoints.barcodeSymbologies,
      cancelToken: cancelToken,
    );
    return SymbologyCatalogue.fromJson(_unwrap(json));
  }

  /// Render without storing and without billing.
  Future<BarcodePreviewImage> preview(
    BarcodeRequest request, {
    CancelToken? cancelToken,
  }) async {
    final Map<String, dynamic> json = await _api.post(
      Endpoints.barcodePreview,
      body: request.toJson(),
      cancelToken: cancelToken,
    );

    final Map<String, dynamic> body = _unwrap(json);
    final String? encoded = J.str(body['base64']);
    if (encoded == null) {
      throw const ApiException(
        code: ApiException.codeMalformed,
        message: 'The preview came back without an image.',
      );
    }

    late final Uint8List bytes;
    try {
      bytes = base64Decode(encoded);
    } on FormatException {
      throw const ApiException(
        code: ApiException.codeMalformed,
        message: 'The preview image could not be decoded.',
      );
    }

    return BarcodePreviewImage(
      bytes: bytes,
      mime: J.strOr(body['mime'], 'image/png'),
      width: J.intOrNull(body['width']),
      height: J.intOrNull(body['height']),
      byteSize: J.intOrNull(body['byte_size']),
    );
  }

  /// Generate, store and bill one barcode.
  Future<GeneratedBarcode> create(
    BarcodeRequest request, {
    CancelToken? cancelToken,
  }) async {
    final Map<String, dynamic> json = await _api.post(
      Endpoints.barcode,
      body: request.toJson(),
      cancelToken: cancelToken,
    );
    return GeneratedBarcode.fromJson(_unwrap(json));
  }

  /// Streams a stored barcode to [savePath]. [format] is `png` or `svg`.
  Future<File> download(
    int id,
    String format,
    String savePath, {
    void Function(int received, int total)? onProgress,
    CancelToken? cancelToken,
  }) {
    return _api.download(
      Endpoints.barcodeDownload(id, format),
      savePath,
      onProgress: onProgress,
      cancelToken: cancelToken,
    );
  }

  static Map<String, dynamic> _unwrap(Map<String, dynamic> json) {
    final Map<String, dynamic> inner = J.map(json['data']);
    return inner.isEmpty ? json : inner;
  }
}

final Provider<BarcodeRepository> barcodeRepositoryProvider =
    Provider<BarcodeRepository>(
  (Ref ref) => BarcodeRepository(ref.watch(apiClientProvider)),
);
