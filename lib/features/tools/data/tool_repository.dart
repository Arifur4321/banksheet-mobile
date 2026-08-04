/// Every PDF Tools call the app makes.
///
/// Thin by design: build the request, hand it to [ApiClient], parse the answer.
/// The one transport type that leaks through is dio's [CancelToken], because a
/// 40 MB merge the user cannot stop is not shippable.
///
/// `convert` deliberately takes the [ToolDefinition] rather than a bare key: the
/// multipart field name (`file` against `files`) and the file-count ceiling both
/// come from the schema the server published, so a new tool needs no change
/// here at all.
library;

import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/endpoints.dart';
import '../../../core/providers.dart';
import '../../../core/utils/json.dart';
import '../domain/conversion.dart';
import '../domain/tool.dart';

/// One file chosen for a conversion.
class ToolUpload {
  const ToolUpload({
    required this.path,
    required this.filename,
    required this.sizeBytes,
  });

  final String path;
  final String filename;
  final int sizeBytes;
}

class ToolRepository {
  const ToolRepository(this._api);

  final ApiClient _api;

  /// The tool catalogue, plan ceilings and remaining allowance.
  Future<ToolCatalogue> tools({CancelToken? cancelToken}) async {
    final Map<String, dynamic> json = await _api.get(
      Endpoints.tools,
      cancelToken: cancelToken,
    );
    return ToolCatalogue.fromJson(_unwrap(json));
  }

  /// Queue a conversion. Answers 202 with the row id and a polling interval.
  ///
  /// [fields] is the option map straight from the form — the server names, the
  /// server's values. Nulls and empty strings are dropped so an untouched
  /// optional field is absent rather than posted as an empty string, which is
  /// the difference between "use the default" and "this failed `regex`".
  Future<QueuedConversion> convert({
    required ToolDefinition tool,
    required Map<String, String?> fields,
    List<ToolUpload> files = const <ToolUpload>[],
    String? idempotencyKey,
    void Function(int sent, int total)? onProgress,
    CancelToken? cancelToken,
  }) async {
    final Map<String, dynamic> body = <String, dynamic>{};
    fields.forEach((String key, String? value) {
      final String trimmed = (value ?? '').trim();
      if (trimmed.isNotEmpty) {
        body[key] = trimmed;
      }
    });

    final Map<String, dynamic> json = await _api.upload(
      Endpoints.toolConvert(tool.key),
      fields: body,
      files: <UploadFile>[
        for (final ToolUpload file in files)
          UploadFile(
            // A multiple tool posts repeated `files` parts; Laravel reads them
            // back as the array its `files.*` rule validates.
            field: tool.uploadField,
            path: file.path,
            filename: file.filename,
          ),
      ],
      idempotencyKey: idempotencyKey,
      onProgress: onProgress,
      cancelToken: cancelToken,
    );

    return QueuedConversion.fromJson(_unwrap(json));
  }

  /// The workspace's history, newest first. [tool] narrows it the way the
  /// per-tool web page does.
  Future<Paged<Conversion>> conversions({
    int page = 1,
    String? tool,
    String? status,
    CancelToken? cancelToken,
  }) async {
    final Map<String, dynamic> json = await _api.get(
      Endpoints.conversions,
      query: <String, dynamic>{
        'page': page,
        'tool': tool,
        'status': status,
      },
      cancelToken: cancelToken,
    );
    return Paged<Conversion>.fromJson(json, Conversion.fromJson);
  }

  Future<Conversion> conversion(int id, {CancelToken? cancelToken}) async {
    final Map<String, dynamic> json = await _api.get(
      Endpoints.conversion(id),
      cancelToken: cancelToken,
    );
    return Conversion.fromJson(_unwrap(json));
  }

  Future<ConversionStatusInfo> status(int id, {CancelToken? cancelToken}) async {
    final Map<String, dynamic> json = await _api.get(
      Endpoints.conversionStatus(id),
      cancelToken: cancelToken,
    );
    return ConversionStatusInfo.fromJson(_unwrap(json));
  }

  /// Streams the output to [savePath]. Authenticated — these files sit on a
  /// private disk precisely because a converted bank statement must not be
  /// reachable by anyone holding a link.
  Future<File> download(
    int id,
    String savePath, {
    void Function(int received, int total)? onProgress,
    CancelToken? cancelToken,
  }) {
    return _api.download(
      Endpoints.conversionDownload(id),
      savePath,
      onProgress: onProgress,
      cancelToken: cancelToken,
    );
  }

  /// Requeue a failed job. Consumes no further quota — the unit was paid for
  /// when the job was first accepted.
  Future<QueuedConversion> retry(int id) async {
    final Map<String, dynamic> json =
        await _api.post(Endpoints.conversionRetry(id));
    return QueuedConversion.fromJson(_unwrap(json));
  }

  Future<void> delete(int id) async {
    await _api.delete(Endpoints.conversion(id));
  }

  /// Single-object responses are either the object itself or `{"data": {...}}`.
  static Map<String, dynamic> _unwrap(Map<String, dynamic> json) {
    final Map<String, dynamic> inner = J.map(json['data']);
    return inner.isEmpty ? json : inner;
  }
}

final Provider<ToolRepository> toolRepositoryProvider =
    Provider<ToolRepository>(
  (Ref ref) => ToolRepository(ref.watch(apiClientProvider)),
);
