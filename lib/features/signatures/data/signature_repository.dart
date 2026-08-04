/// The three signature calls the app makes.
///
/// Read-only by design, matching the server: sending a request consumes a
/// metered e-sign unit, needs signature boxes placed on the page, and puts an
/// email in a third party's inbox in the workspace's name. What the app does
/// give is the thing people open their phone for — is it signed yet, who is
/// holding it up, and the signed PDF.
library;

import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/endpoints.dart';
import '../../../core/providers.dart';
import '../../../core/utils/json.dart';
import '../../exports/data/file_downloader.dart';
import '../domain/signature.dart';

class SignatureRepository {
  const SignatureRepository(this._api, this._downloader);

  final ApiClient _api;
  final FileDownloader _downloader;

  /// [status] matches one value exactly, which is why "awaiting" is expressed
  /// as [openOnly] instead: it covers `sent`, `viewed` and `partially_signed`,
  /// and the server has a scope for precisely that set.
  Future<Paged<SignatureRequest>> list({
    int page = 1,
    String? status,
    bool openOnly = false,
    CancelToken? cancelToken,
  }) async {
    final Map<String, dynamic> json = await _api.get(
      Endpoints.signatures,
      query: <String, dynamic>{
        'page': page,
        'status': status,
        'open_only': openOnly ? 1 : null,
      },
      cancelToken: cancelToken,
    );

    return Paged<SignatureRequest>.fromJson(json, SignatureRequest.fromJson);
  }

  /// The full request: signers in signing order, and the audit trail in full.
  Future<SignatureRequest> detail(int id, {CancelToken? cancelToken}) async {
    final Map<String, dynamic> json = await _api.get(
      Endpoints.signature(id),
      cancelToken: cancelToken,
    );
    return SignatureRequest.fromJson(_unwrap(json));
  }

  /// Streams the signed PDF to the app documents directory.
  ///
  /// The server answers 404 until every signer has signed, which is why the UI
  /// only offers this once `signed_file_available` is true.
  Future<File> download(
    int id, {
    required String filename,
    void Function(int received, int total)? onProgress,
    CancelToken? cancelToken,
  }) {
    return _downloader.download(
      path: Endpoints.signatureDownload(id),
      filename: filename,
      onProgress: onProgress,
      cancelToken: cancelToken,
    );
  }

  static Map<String, dynamic> _unwrap(Map<String, dynamic> json) {
    final Map<String, dynamic> keyed = J.map(json['signature_request']);
    if (keyed.isNotEmpty) {
      return keyed;
    }
    final Map<String, dynamic> data = J.map(json['data']);
    return data.isEmpty ? json : data;
  }
}

final Provider<SignatureRepository> signatureRepositoryProvider =
    Provider<SignatureRepository>(
  (Ref ref) => SignatureRepository(
    ref.watch(apiClientProvider),
    ref.watch(fileDownloaderProvider),
  ),
);
