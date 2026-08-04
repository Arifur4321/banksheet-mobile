/// Every document call the app makes, in one place.
///
/// Repositories are thin on purpose: they build the request, hand it to
/// [ApiClient], and parse the answer into a model. No caching, no retry policy,
/// no state — those belong to the providers above, where they can be reasoned
/// about per screen.
///
/// dio's [CancelToken] is the one transport type that leaks through, because the
/// upload and download signatures on [ApiClient] take one and an upload the user
/// can't cancel is not shippable.
library;

import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/endpoints.dart';
import '../../../core/providers.dart';
import '../../../core/utils/json.dart';
import '../domain/document.dart';

/// What `POST /documents` answers with.
class UploadResult {
  const UploadResult({
    required this.document,
    required this.queued,
    required this.idempotentReplay,
    this.pollAfterSeconds,
    this.warning,
  });

  factory UploadResult.fromJson(Map<String, dynamic> json) => UploadResult(
        document: DocumentSummary.fromJson(J.map(json['document'])),
        queued: J.boolOr(json['queued']),
        pollAfterSeconds: J.intOrNull(json['poll_after_seconds']),
        warning: J.str(json['warning']),
        idempotentReplay: J.boolOr(json['idempotent_replay']),
      );

  final DocumentSummary document;

  /// False when the file was stored but cannot be extracted — a JPG, a PNG or
  /// a ZIP. [warning] then carries the server's explanation.
  final bool queued;

  final int? pollAfterSeconds;
  final String? warning;

  /// True when this response is a replay of an earlier upload with the same
  /// `Idempotency-Key`. Nothing new was created and no quota was consumed.
  final bool idempotentReplay;
}

/// What `POST /documents/{id}/reprocess` answers with.
class ReprocessResult {
  const ReprocessResult({
    required this.document,
    this.job,
    this.pollAfterSeconds,
  });

  factory ReprocessResult.fromJson(Map<String, dynamic> json) =>
      ReprocessResult(
        document: DocumentSummary.fromJson(J.map(json['document'])),
        job: json['extraction_job'] == null
            ? null
            : ExtractionJobInfo.fromJson(J.map(json['extraction_job'])),
        pollAfterSeconds: J.intOrNull(json['poll_after_seconds']),
      );

  final DocumentSummary document;
  final ExtractionJobInfo? job;
  final int? pollAfterSeconds;
}

/// What `POST /documents/{id}/export` answers with.
class ExportResult {
  const ExportResult({
    required this.exportId,
    required this.filename,
    this.downloadUrl,
    this.size,
  });

  factory ExportResult.fromJson(Map<String, dynamic> json) => ExportResult(
        exportId: J.intOr(json['export_id'], 0),
        downloadUrl: J.str(json['download_url']),
        filename: J.strOr(json['filename'], 'export'),
        size: J.intOrNull(json['size']),
      );

  final int exportId;

  /// Absolute, and authenticated — it is not usable in a browser, only through
  /// [DocumentRepository.downloadExport].
  final String? downloadUrl;

  final String filename;
  final int? size;
}

/// What `POST /documents/{id}/transactions/approve-all` answers with.
class ApproveAllResult {
  const ApproveAllResult({
    required this.approvedCount,
    required this.transactionsCount,
    required this.approvedTransactionsCount,
    required this.pendingCount,
  });

  factory ApproveAllResult.fromJson(Map<String, dynamic> json) =>
      ApproveAllResult(
        approvedCount: J.intOr(json['approved_count'], 0),
        transactionsCount: J.intOr(json['transactions_count'], 0),
        approvedTransactionsCount:
            J.intOr(json['approved_transactions_count'], 0),
        pendingCount: J.intOr(json['pending_count'], 0),
      );

  /// How many rows this call actually changed.
  final int approvedCount;

  final int transactionsCount;
  final int approvedTransactionsCount;
  final int pendingCount;
}

class DocumentRepository {
  const DocumentRepository(this._api);

  final ApiClient _api;

  /// Byte-for-byte the server's `mimes:pdf,xml,p7m,jpg,jpeg,png,zip` rule.
  /// Offering the file picker anything wider only moves the rejection from a
  /// tap to a failed upload.
  static const List<String> acceptedExtensions = <String>[
    'pdf',
    'xml',
    'p7m',
    'jpg',
    'jpeg',
    'png',
    'zip',
  ];

  /// The three values `document_type` accepts.
  static const List<String> documentTypes = <String>[
    'bank_statement',
    'invoice',
    'generic_pdf',
  ];

  Future<Paged<DocumentSummary>> list({
    int page = 1,
    String? status,
    String? type,
    String? query,
    CancelToken? cancelToken,
  }) async {
    final String trimmed = (query ?? '').trim();

    final Map<String, dynamic> json = await _api.get(
      Endpoints.documents,
      query: <String, dynamic>{
        'page': page,
        'status': status,
        'type': type,
        'q': trimmed.isEmpty ? null : trimmed,
      },
      cancelToken: cancelToken,
    );

    return Paged<DocumentSummary>.fromJson(json, DocumentSummary.fromJson);
  }

  /// The detail payload. [transactionsPage] drives the nested paginator — the
  /// server's `paginate(100)` reads the same `page` query parameter the list
  /// endpoint does.
  Future<DocumentDetail> detail(
    int id, {
    int transactionsPage = 1,
    CancelToken? cancelToken,
  }) async {
    final Map<String, dynamic> json = await _api.get(
      Endpoints.document(id),
      query: <String, dynamic>{'page': transactionsPage},
      cancelToken: cancelToken,
    );
    return DocumentDetail.fromJson(_unwrap(json));
  }

  Future<DocumentStatusInfo> status(int id, {CancelToken? cancelToken}) async {
    final Map<String, dynamic> json = await _api.get(
      Endpoints.documentStatus(id),
      cancelToken: cancelToken,
    );
    return DocumentStatusInfo.fromJson(_unwrap(json));
  }

  /// Multipart upload.
  ///
  /// [idempotencyKey] is not optional in practice and the caller owns it: it
  /// must survive a retry of the *same* file, or the retry consumes a second
  /// document from the monthly allowance. The server honours the header for 24
  /// hours.
  Future<UploadResult> upload({
    required String filePath,
    required String filename,
    required String idempotencyKey,
    String documentType = 'bank_statement',
    int? extractionProfileId,
    void Function(int sent, int total)? onProgress,
    CancelToken? cancelToken,
  }) async {
    final Map<String, dynamic> json = await _api.upload(
      Endpoints.documents,
      fields: <String, dynamic>{
        'document_type': documentType,
        // Dropped by the client when null, and ignored by the server for
        // anything that is not a bank statement.
        'extraction_profile_id': extractionProfileId,
      },
      files: <UploadFile>[
        UploadFile(field: 'file', path: filePath, filename: filename),
      ],
      idempotencyKey: idempotencyKey,
      onProgress: onProgress,
      cancelToken: cancelToken,
    );

    return UploadResult.fromJson(_unwrap(json));
  }

  /// Queue the document again.
  ///
  /// For a bank statement the submitted value *replaces* the stored profile,
  /// and a null clears it — which is what "auto-match the best profile" means
  /// on the server. That is why the key is always sent rather than omitted.
  Future<ReprocessResult> reprocess(int id, {int? profileId}) async {
    final Map<String, dynamic> json = await _api.post(
      Endpoints.documentReprocess(id),
      body: <String, dynamic>{'extraction_profile_id': profileId},
    );
    return ReprocessResult.fromJson(_unwrap(json));
  }

  /// Generate a spreadsheet. [format] is one of `xlsx`, `csv`, `json`.
  Future<ExportResult> export(int id, String format) async {
    final Map<String, dynamic> json = await _api.post(
      Endpoints.documentExport(id),
      body: <String, dynamic>{'format': format},
    );
    return ExportResult.fromJson(_unwrap(json));
  }

  Future<ApproveAllResult> approveAll(int id) async {
    final Map<String, dynamic> json =
        await _api.post(Endpoints.documentApproveAll(id));
    return ApproveAllResult.fromJson(_unwrap(json));
  }

  /// Streams the original upload to [savePath]. Always authenticated — these
  /// files sit on a private disk precisely because a bank statement must not be
  /// reachable by anyone holding a link.
  Future<File> downloadOriginal(
    int id,
    String savePath, {
    void Function(int received, int total)? onProgress,
    CancelToken? cancelToken,
  }) {
    return _api.download(
      Endpoints.documentFile(id),
      savePath,
      onProgress: onProgress,
      cancelToken: cancelToken,
    );
  }

  Future<File> downloadExport(
    int exportId,
    String savePath, {
    void Function(int received, int total)? onProgress,
    CancelToken? cancelToken,
  }) {
    return _api.download(
      Endpoints.exportDownload(exportId),
      savePath,
      onProgress: onProgress,
      cancelToken: cancelToken,
    );
  }

  Future<void> delete(int id) async {
    await _api.delete(Endpoints.document(id));
  }

  /// Profiles for the upload and reprocess pickers.
  ///
  /// The server paginates these at 20 and takes no page-size parameter; a
  /// workspace with more than 20 profiles would need a searchable picker, which
  /// is a screen the profiles feature owns rather than something to bolt onto a
  /// dropdown here.
  Future<List<ProfileRef>> profiles({
    String documentType = 'bank_statement',
    bool activeOnly = true,
    CancelToken? cancelToken,
  }) async {
    final Map<String, dynamic> json = await _api.get(
      Endpoints.extractionProfiles,
      query: <String, dynamic>{
        'document_type': documentType,
        'active_only': activeOnly ? 1 : null,
      },
      cancelToken: cancelToken,
    );

    return J
        .list(json['data'])
        .map(ProfileRef.fromJson)
        .toList(growable: false);
  }

  /// Single-object responses are either the object itself or `{"data": {...}}`.
  static Map<String, dynamic> _unwrap(Map<String, dynamic> json) {
    final Map<String, dynamic> inner = J.map(json['data']);
    return inner.isEmpty ? json : inner;
  }
}

final Provider<DocumentRepository> documentRepositoryProvider =
    Provider<DocumentRepository>(
  (Ref ref) => DocumentRepository(ref.watch(apiClientProvider)),
);
