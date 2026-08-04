/// Every company-data extraction call the app makes.
///
/// `create` posts the domain list as an array. The server accepts either a raw
/// paste or an array and folds both back into the newline-separated text
/// `InputListParser` reads, so sending the list the device already parsed keeps
/// the two ends agreeing about how many websites the job contains — which is
/// how many scans it costs.
library;

import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/endpoints.dart';
import '../../../core/providers.dart';
import '../../../core/utils/json.dart';
import '../domain/web_job.dart';

class WebExtractionRepository {
  const WebExtractionRepository(this._api);

  /// The two formats `GET /web-extractions/{id}/export/{format}` accepts.
  static const List<String> exportFormats = <String>['xlsx', 'csv'];

  final ApiClient _api;

  Future<Paged<WebExtractionJob>> list({
    int page = 1,
    CancelToken? cancelToken,
  }) async {
    final Map<String, dynamic> json = await _api.get(
      Endpoints.webExtractions,
      query: <String, dynamic>{'page': page},
      cancelToken: cancelToken,
    );
    return Paged<WebExtractionJob>.fromJson(json, WebExtractionJob.fromJson);
  }

  /// Queue a job. Answers 202, and bills one scan per resolvable website.
  Future<WebExtractionCreated> create({
    required List<String> domains,
    String? title,
    int? maxPages,
  }) async {
    final Map<String, dynamic> json = await _api.post(
      Endpoints.webExtractions,
      body: <String, dynamic>{
        'title': title,
        'domains': domains,
        'max_pages': maxPages,
      }..removeWhere((String _, dynamic value) => value == null),
    );
    return WebExtractionCreated.fromJson(_unwrap(json));
  }

  /// The job plus one page of its targets. Targets are paginated inline
  /// server-side, so the progress bar and its list never disagree.
  Future<WebExtractionJobDetail> detail(
    int id, {
    int targetsPage = 1,
    CancelToken? cancelToken,
  }) async {
    final Map<String, dynamic> json = await _api.get(
      Endpoints.webExtraction(id),
      query: <String, dynamic>{'page': targetsPage},
      cancelToken: cancelToken,
    );
    return WebExtractionJobDetail.fromJson(_unwrap(json));
  }

  /// The extracted contacts, grouped per website.
  Future<Paged<WebExtractionTarget>> results(
    int id, {
    int page = 1,
    String? status,
    bool? hasEmail,
    CancelToken? cancelToken,
  }) async {
    final Map<String, dynamic> json = await _api.get(
      Endpoints.webExtractionResults(id),
      query: <String, dynamic>{
        'page': page,
        'status': status,
        'has_email': hasEmail == null ? null : (hasEmail ? 'yes' : 'no'),
      },
      cancelToken: cancelToken,
    );
    return Paged<WebExtractionTarget>.fromJson(
      json,
      WebExtractionTarget.fromJson,
    );
  }

  /// Requeue the failed and skipped websites. Spends no further scans: those
  /// targets were billed when the job was created.
  Future<WebExtractionJob> retry(int id) async {
    final Map<String, dynamic> json =
        await _api.post(Endpoints.webExtractionRetry(id));
    return WebExtractionJob.fromJson(J.map(_unwrap(json)['job']));
  }

  /// Stop the outstanding websites. Everything already extracted stays
  /// downloadable — those scans were paid for.
  Future<WebExtractionJob> cancel(int id) async {
    final Map<String, dynamic> json =
        await _api.post(Endpoints.webExtractionCancel(id));
    return WebExtractionJob.fromJson(J.map(_unwrap(json)['job']));
  }

  Future<void> delete(int id) async {
    await _api.delete(Endpoints.webExtraction(id));
  }

  /// Streams the spreadsheet to [savePath]. [format] is `xlsx` or `csv`.
  Future<File> export(
    int id,
    String format,
    String savePath, {
    void Function(int received, int total)? onProgress,
    CancelToken? cancelToken,
  }) {
    return _api.download(
      Endpoints.webExtractionExport(id, format),
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

final Provider<WebExtractionRepository> webExtractionRepositoryProvider =
    Provider<WebExtractionRepository>(
  (Ref ref) => WebExtractionRepository(ref.watch(apiClientProvider)),
);
