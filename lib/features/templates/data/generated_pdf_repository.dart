/// Generated PDFs: list, detail and download.
///
/// Read-only, which mirrors the server: the two creation paths this repository
/// does not cover — the contract editor and a PDF upload with signature boxes —
/// both need a canvas, and neither belongs on a phone.
library;

import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/endpoints.dart';
import '../../../core/providers.dart';
import '../../../core/utils/json.dart';
import '../../exports/data/file_downloader.dart';
import '../domain/generated_pdf.dart';

class GeneratedPdfRepository {
  const GeneratedPdfRepository(this._api, this._downloader);

  final ApiClient _api;
  final FileDownloader _downloader;

  Future<Paged<GeneratedPdf>> list({
    int page = 1,
    String? kind,
    int? templateId,
    CancelToken? cancelToken,
  }) async {
    final Map<String, dynamic> json = await _api.get(
      Endpoints.generatedPdfs,
      query: <String, dynamic>{
        'page': page,
        'kind': kind,
        'template_id': templateId,
      },
      cancelToken: cancelToken,
    );

    return Paged<GeneratedPdf>.fromJson(json, GeneratedPdf.fromJson);
  }

  Future<GeneratedPdf> detail(int id, {CancelToken? cancelToken}) async {
    final Map<String, dynamic> json = await _api.get(
      Endpoints.generatedPdf(id),
      cancelToken: cancelToken,
    );
    return GeneratedPdf.fromJson(_unwrap(json));
  }

  /// Streams the PDF to the app documents directory under the server's own
  /// filename, so the copy on the phone matches the copy on the website.
  Future<File> download(
    int id, {
    required String filename,
    void Function(int received, int total)? onProgress,
    CancelToken? cancelToken,
  }) {
    return _downloader.download(
      path: Endpoints.generatedPdfDownload(id),
      filename: filename,
      onProgress: onProgress,
      cancelToken: cancelToken,
    );
  }

  static Map<String, dynamic> _unwrap(Map<String, dynamic> json) {
    final Map<String, dynamic> keyed = J.map(json['generated_pdf']);
    if (keyed.isNotEmpty) {
      return keyed;
    }
    final Map<String, dynamic> data = J.map(json['data']);
    return data.isEmpty ? json : data;
  }
}

final Provider<GeneratedPdfRepository> generatedPdfRepositoryProvider =
    Provider<GeneratedPdfRepository>(
  (Ref ref) => GeneratedPdfRepository(
    ref.watch(apiClientProvider),
    ref.watch(fileDownloaderProvider),
  ),
);
