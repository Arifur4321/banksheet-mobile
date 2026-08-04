/// The single HTTP entry point.
///
/// Repositories call [get], [post], [upload] and [download] and receive plain
/// Dart maps or a typed [ApiException]. Nothing above this file imports dio,
/// which keeps the transport swappable and the feature code testable with a
/// hand-written fake.
library;

import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';

import '../config/app_config.dart';
import 'api_exception.dart';
import 'auth_interceptor.dart';
import 'token_store.dart';

/// Identifies this build to the server. `EnforceMobileClientVersion` reads the
/// first header and answers 426 when the binary is below the supported floor.
class ClientIdentity {
  const ClientIdentity({
    required this.appVersion,
    required this.platform,
    required this.deviceName,
    required this.deviceId,
  });

  final String appVersion;

  /// `ios` or `android`.
  final String platform;

  /// Shown in the user's device list, e.g. "Pixel 8".
  final String deviceName;

  /// Stable per-install id used to revoke a single device.
  final String deviceId;

  Map<String, dynamic> get deviceFields => <String, dynamic>{
        'device_name': deviceName,
        'device_id': deviceId,
        'platform': platform,
        'app_version': appVersion,
      };
}

class ApiClient {
  ApiClient({
    required TokenStore tokens,
    required ClientIdentity identity,
    required Future<void> Function() onSessionLost,
    Dio? dio,
    Dio? refreshDio,
  })  : _tokens = tokens,
        _identity = identity,
        _dio = dio ?? Dio(),
        _refreshDio = refreshDio ?? Dio() {
    final BaseOptions base = BaseOptions(
      baseUrl: AppConfig.apiBase,
      connectTimeout: AppConfig.connectTimeout,
      receiveTimeout: AppConfig.receiveTimeout,
      // Never throw on a status code — every non-2xx is turned into an
      // ApiException in one place below, so behaviour cannot drift per call.
      validateStatus: (int? _) => true,
      headers: <String, dynamic>{
        'Accept': 'application/json',
        'X-BankSheet-App': _identity.appVersion,
        'X-BankSheet-Platform': _identity.platform,
      },
    );

    _dio.options = base;
    _refreshDio.options = base.copyWith(validateStatus: (int? s) => s != null && s < 400);

    _dio.interceptors.add(
      AuthInterceptor(
        tokens: _tokens,
        refreshClient: _refreshDio,
        onSessionLost: onSessionLost,
      ),
    );
  }

  final Dio _dio;
  final Dio _refreshDio;
  final TokenStore _tokens;
  final ClientIdentity _identity;

  ClientIdentity get identity => _identity;

  // -------------------------------------------------------------- verbs

  Future<Map<String, dynamic>> get(
    String path, {
    Map<String, dynamic>? query,
    CancelToken? cancelToken,
  }) =>
      _send(() => _dio.get<dynamic>(
            path,
            queryParameters: _clean(query),
            cancelToken: cancelToken,
          ));

  Future<Map<String, dynamic>> post(
    String path, {
    Map<String, dynamic>? body,
    Map<String, dynamic>? headers,
    CancelToken? cancelToken,
  }) =>
      _send(() => _dio.post<dynamic>(
            path,
            data: body,
            options: headers == null ? null : Options(headers: headers),
            cancelToken: cancelToken,
          ));

  Future<Map<String, dynamic>> patch(
    String path, {
    Map<String, dynamic>? body,
    CancelToken? cancelToken,
  }) =>
      _send(() => _dio.patch<dynamic>(
            path,
            data: body,
            cancelToken: cancelToken,
          ));

  Future<Map<String, dynamic>> put(
    String path, {
    Map<String, dynamic>? body,
    CancelToken? cancelToken,
  }) =>
      _send(() => _dio.put<dynamic>(path, data: body, cancelToken: cancelToken));

  Future<Map<String, dynamic>> delete(
    String path, {
    Map<String, dynamic>? body,
    CancelToken? cancelToken,
  }) =>
      _send(() => _dio.delete<dynamic>(
            path,
            data: body,
            cancelToken: cancelToken,
          ));

  /// Multipart upload with progress.
  ///
  /// [idempotencyKey] lets a retried upload after a timeout resolve to the same
  /// document instead of consuming a second unit of quota — the server honours
  /// the header for 24 hours.
  Future<Map<String, dynamic>> upload(
    String path, {
    required Map<String, dynamic> fields,
    required List<UploadFile> files,
    String? idempotencyKey,
    void Function(int sent, int total)? onProgress,
    CancelToken? cancelToken,
  }) async {
    final FormData form = FormData();

    _clean(fields).forEach((String key, dynamic value) {
      form.fields.add(MapEntry<String, String>(key, value.toString()));
    });

    for (final UploadFile f in files) {
      form.files.add(
        MapEntry<String, MultipartFile>(
          f.field,
          await MultipartFile.fromFile(f.path, filename: f.filename),
        ),
      );
    }

    return _send(
      () => _dio.post<dynamic>(
        path,
        data: form,
        cancelToken: cancelToken,
        onSendProgress: onProgress,
        options: Options(
          sendTimeout: AppConfig.uploadTimeout,
          receiveTimeout: AppConfig.uploadTimeout,
          headers: <String, dynamic>{
            if (idempotencyKey != null) 'Idempotency-Key': idempotencyKey,
          },
        ),
      ),
    );
  }

  /// Streams a file to [savePath]. Used for exports, source PDFs and converted
  /// output — all of which are served by authenticated routes, so a plain
  /// browser URL would not work.
  Future<File> download(
    String path,
    String savePath, {
    Map<String, dynamic>? query,
    void Function(int received, int total)? onProgress,
    CancelToken? cancelToken,
  }) async {
    try {
      final Response<dynamic> res = await _dio.download(
        path,
        savePath,
        queryParameters: _clean(query),
        onReceiveProgress: onProgress,
        cancelToken: cancelToken,
        options: Options(
          receiveTimeout: AppConfig.uploadTimeout,
          validateStatus: (int? s) => s != null && s < 400,
        ),
      );
      if ((res.statusCode ?? 500) >= 400) {
        throw ApiException.fromResponse(res);
      }
      return File(savePath);
    } catch (e, st) {
      // A partial file on disk is worse than none — a half-written XLSX will
      // silently fail to open and read as a product bug.
      final File partial = File(savePath);
      if (partial.existsSync()) {
        try {
          partial.deleteSync();
        } on FileSystemException {
          // Nothing more we can do; the exception below is the real signal.
        }
      }
      throw ApiException.from(e, st);
    }
  }

  // ------------------------------------------------------------- internals

  Future<Map<String, dynamic>> _send(
    Future<Response<dynamic>> Function() request,
  ) async {
    late final Response<dynamic> res;
    try {
      res = await request();
    } catch (e, st) {
      throw ApiException.from(e, st);
    }

    final int status = res.statusCode ?? 0;
    if (status >= 200 && status < 300) {
      final dynamic data = res.data;
      if (data == null || (data is String && data.isEmpty)) {
        return const <String, dynamic>{};
      }
      if (data is Map) {
        return Map<String, dynamic>.from(data);
      }
      if (data is List) {
        // A bare array is wrapped so callers always see a map.
        return <String, dynamic>{'data': data};
      }
      throw const ApiException(
        code: ApiException.codeMalformed,
        message: 'The server sent an unexpected response.',
      );
    }

    throw ApiException.fromResponse(res);
  }

  /// Drops null values so an optional filter never becomes the literal
  /// string "null" in a query string.
  Map<String, dynamic>? _clean(Map<String, dynamic>? input) {
    if (input == null) {
      return null;
    }
    final Map<String, dynamic> out = <String, dynamic>{};
    input.forEach((String k, dynamic v) {
      if (v != null) {
        out[k] = v;
      }
    });
    return out;
  }
}

/// One file in a multipart request.
class UploadFile {
  const UploadFile({
    required this.field,
    required this.path,
    required this.filename,
  });

  /// The form field name the server expects, e.g. `file` or `files[]`.
  final String field;
  final String path;
  final String filename;
}
