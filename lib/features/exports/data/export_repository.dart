/// The two export-archive calls the app makes.
///
/// There is no `create` here on purpose: an export is generated from a document
/// (`POST /documents/{id}/export`), which is where the format and the approved
/// rows are, and that call belongs to the documents feature. This repository
/// only lists what already exists and streams it to the device.
library;

import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/endpoints.dart';
import '../../../core/providers.dart';
import '../../../core/utils/json.dart';
import '../domain/export_archive.dart';
import 'file_downloader.dart';

class ExportRepository {
  const ExportRepository(this._api, this._downloader);

  final ApiClient _api;
  final FileDownloader _downloader;

  Future<Paged<ExportArchive>> list({
    int page = 1,
    int? documentId,
    String? exportType,
    CancelToken? cancelToken,
  }) async {
    final Map<String, dynamic> json = await _api.get(
      Endpoints.exports,
      query: <String, dynamic>{
        'page': page,
        'document_id': documentId,
        'export_type': exportType,
      },
      cancelToken: cancelToken,
    );

    return Paged<ExportArchive>.fromJson(json, ExportArchive.fromJson);
  }

  /// Streams the spreadsheet to the app documents directory.
  ///
  /// [filename] is the server's own name for the file rather than one invented
  /// here, so an export saved from the phone and the same export saved from the
  /// website do not become two differently-named copies in the user's drive.
  Future<File> download(
    int id, {
    required String filename,
    void Function(int received, int total)? onProgress,
    CancelToken? cancelToken,
  }) {
    return _downloader.download(
      path: Endpoints.exportDownload(id),
      filename: filename,
      onProgress: onProgress,
      cancelToken: cancelToken,
    );
  }
}

final Provider<ExportRepository> exportRepositoryProvider =
    Provider<ExportRepository>(
  (Ref ref) => ExportRepository(
    ref.watch(apiClientProvider),
    ref.watch(fileDownloaderProvider),
  ),
);
