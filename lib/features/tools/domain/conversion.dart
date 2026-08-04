/// One PDF Tools job, as `DocumentConversionResource` publishes it.
///
/// Barcodes live in this same history — they are `DocumentConversion` rows with
/// `tool_type` `barcode-generator` — so nothing here assumes a PDF.
///
/// The status vocabulary is the server's, and [ConversionStatus.isWorking] is
/// exactly the predicate `DocumentConversionResource::pollAfterSeconds()` uses:
/// a job is in flight while it is `pending` or `processing`, and any other value
/// — including one a future server adds — stops the poller rather than spinning
/// it forever on a row that will never change.
library;

import 'package:flutter/foundation.dart';

import '../../../core/utils/json.dart';

enum ConversionStatus {
  pending('pending'),
  processing('processing'),
  completed('completed'),

  /// The web writes `processed` on some paths and `completed` on others; both
  /// mean "finished successfully" and both are filterable server-side.
  processed('processed'),
  failed('failed'),
  unknown('unknown');

  const ConversionStatus(this.wire);

  final String wire;

  static ConversionStatus from(String? raw) =>
      switch ((raw ?? '').trim().toLowerCase()) {
        'pending' => ConversionStatus.pending,
        'processing' => ConversionStatus.processing,
        'completed' => ConversionStatus.completed,
        'processed' => ConversionStatus.processed,
        'failed' => ConversionStatus.failed,
        _ => ConversionStatus.unknown,
      };

  bool get isWorking =>
      this == ConversionStatus.pending || this == ConversionStatus.processing;

  bool get isFinished => !isWorking;

  bool get isFailed => this == ConversionStatus.failed;

  bool get isSucceeded =>
      this == ConversionStatus.completed || this == ConversionStatus.processed;
}

/// Who queued a job. Matches the `{"id", "name"}` shape every actor uses.
@immutable
class ConversionActor {
  const ConversionActor({required this.id, this.name});

  factory ConversionActor.fromJson(Map<String, dynamic> json) =>
      ConversionActor(id: J.intOr(json['id'], 0), name: J.str(json['name']));

  final int id;
  final String? name;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ConversionActor && other.id == id && other.name == name;

  @override
  int get hashCode => Object.hash(id, name);
}

@immutable
class Conversion {
  const Conversion({
    required this.id,
    required this.tool,
    required this.status,
    required this.hasOutput,
    required this.options,
    this.toolLabel,
    this.title,
    this.error,
    this.originalFilename,
    this.outputFilename,
    this.mimeType,
    this.outputMimeType,
    this.fileSize,
    this.pageCount,
    this.fileCount,
    this.downloadUrl,
    this.pollAfterSeconds,
    this.generatedPdfId,
    this.createdBy,
    this.createdAt,
    this.startedAt,
    this.completedAt,
  });

  factory Conversion.fromJson(Map<String, dynamic> json) => Conversion(
        id: J.intOr(json['id'], 0),
        tool: J.strOr(json['tool'], ''),
        toolLabel: J.str(json['tool_label']),
        title: J.str(json['title']),
        status: ConversionStatus.from(J.str(json['status'])),
        error: J.str(json['error_message']),
        originalFilename: J.str(json['original_filename']),
        outputFilename: J.str(json['output_filename']),
        mimeType: J.str(json['mime_type']),
        outputMimeType: J.str(json['output_mime_type']),
        fileSize: J.intOrNull(json['file_size']),
        pageCount: J.intOrNull(json['page_count']),
        fileCount: J.intOrNull(json['file_count']),
        options: J.map(json['options']),
        hasOutput: J.boolOr(json['has_output']),
        downloadUrl: J.str(json['download_url']),
        pollAfterSeconds: J.intOrNull(json['poll_after_seconds']),
        generatedPdfId: J.intOrNull(json['generated_pdf_id']),
        createdBy: json['created_by'] == null
            ? null
            : ConversionActor.fromJson(J.map(json['created_by'])),
        createdAt: J.date(json['created_at']),
        startedAt: J.date(json['started_at']),
        completedAt: J.date(json['completed_at']),
      );

  final int id;

  /// Tool key, e.g. `merge-pdf` or `barcode-generator`.
  final String tool;

  /// The tool's display name, resolved server-side so barcode rows read
  /// sensibly in a history that is otherwise all PDF tools.
  final String? toolLabel;

  final String? title;
  final ConversionStatus status;
  final String? error;

  final String? originalFilename;
  final String? outputFilename;
  final String? mimeType;
  final String? outputMimeType;

  /// Bytes of the source upload.
  final int? fileSize;

  /// Set by the merge/split pre-flight inspection only.
  final int? pageCount;
  final int? fileCount;

  /// The whitelisted subset of the job's options — never a storage path.
  final Map<String, dynamic> options;

  /// Whether the bytes are actually on disk. The server checks the file, not
  /// the status column, because retention sweeps a completed row's output.
  final bool hasOutput;

  /// Absolute and authenticated: usable only through the repository's
  /// `download`, never in a browser.
  final String? downloadUrl;

  /// Withdrawn (null) the moment the job settles.
  final int? pollAfterSeconds;

  final int? generatedPdfId;
  final ConversionActor? createdBy;
  final DateTime? createdAt;
  final DateTime? startedAt;
  final DateTime? completedAt;

  bool get isWorking => status.isWorking;

  bool get isFinished => status.isFinished;

  bool get isFailed => status.isFailed;

  /// True when there is something to open, download or share.
  bool get isDownloadable => hasOutput && downloadUrl != null;

  /// A "completed" row whose file has gone is retryable, which is the web's
  /// rule and the reason this checks the bytes rather than the status.
  bool get canRetry =>
      tool != 'edit-pdf' && (isFailed || (status.isSucceeded && !hasOutput));

  /// The server refuses to delete a row that is mid-flight.
  bool get canDelete => status != ConversionStatus.processing;

  /// What to print as the row's headline. Never empty.
  String get displayTitle =>
      title ?? outputFilename ?? originalFilename ?? toolLabel ?? tool;

  /// A filename safe to save under, whatever the server had.
  String get downloadFilename =>
      outputFilename ?? originalFilename ?? 'conversion-$id';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Conversion &&
          other.id == id &&
          other.status == status &&
          other.title == title &&
          other.error == error &&
          other.hasOutput == hasOutput &&
          other.downloadUrl == downloadUrl &&
          other.completedAt == completedAt;

  @override
  int get hashCode =>
      Object.hash(id, status, title, error, hasOutput, downloadUrl, completedAt);

  @override
  String toString() => 'Conversion($id, $tool, ${status.wire})';
}

/// The tiny body `GET /tools/conversions/{id}/status` answers with.
@immutable
class ConversionStatusInfo {
  const ConversionStatusInfo({
    required this.id,
    required this.status,
    this.error,
    this.downloadUrl,
    this.pollAfterSeconds,
  });

  factory ConversionStatusInfo.fromJson(Map<String, dynamic> json) =>
      ConversionStatusInfo(
        id: J.intOr(json['id'], 0),
        status: ConversionStatus.from(J.str(json['status'])),
        error: J.str(json['error_message']),
        downloadUrl: J.str(json['download_url']),
        pollAfterSeconds: J.intOrNull(json['poll_after_seconds']),
      );

  final int id;
  final ConversionStatus status;
  final String? error;
  final String? downloadUrl;
  final int? pollAfterSeconds;

  /// The server withdraws the interval when the job reaches a final state, and
  /// that — not a status string the client has to keep in sync — is the signal
  /// to stop polling.
  bool get isSettled => pollAfterSeconds == null || status.isFinished;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ConversionStatusInfo &&
          other.id == id &&
          other.status == status &&
          other.error == error &&
          other.downloadUrl == downloadUrl &&
          other.pollAfterSeconds == pollAfterSeconds;

  @override
  int get hashCode =>
      Object.hash(id, status, error, downloadUrl, pollAfterSeconds);
}

/// The 202 body that `convert` and `retry` answer with.
@immutable
class QueuedConversion {
  const QueuedConversion({
    required this.id,
    required this.tool,
    required this.status,
    this.pollAfterSeconds,
  });

  factory QueuedConversion.fromJson(Map<String, dynamic> json) =>
      QueuedConversion(
        id: J.intOr(json['id'], 0),
        tool: J.strOr(json['tool'], ''),
        status: ConversionStatus.from(J.str(json['status'])),
        pollAfterSeconds: J.intOrNull(json['poll_after_seconds']),
      );

  final int id;
  final String tool;
  final ConversionStatus status;
  final int? pollAfterSeconds;
}
