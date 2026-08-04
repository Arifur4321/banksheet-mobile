/// The export archive model.
///
/// Field names mirror `ExportArchiveResource` exactly. Two of them are computed
/// server-side from the disk rather than from the row — [isAvailable] and
/// [sizeBytes] — because export files are pruned, and a phone that has been
/// offline for a week would otherwise offer a download button for something
/// that no longer exists.
library;

import 'package:flutter/foundation.dart';

import '../../../core/i18n/strings.dart';
import '../../../core/utils/json.dart';

/// The three formats `DocumentController::export()` produces, plus a defensive
/// [unknown] for anything a later server adds.
enum ExportFormat {
  xlsx('xlsx'),
  csv('csv'),
  json('json'),
  unknown('');

  const ExportFormat(this.wire);

  final String wire;

  static ExportFormat from(String? raw) =>
      switch ((raw ?? '').trim().toLowerCase()) {
        'xlsx' => ExportFormat.xlsx,
        'csv' => ExportFormat.csv,
        'json' => ExportFormat.json,
        _ => ExportFormat.unknown,
      };

  String get label => switch (this) {
        ExportFormat.xlsx => 'XLSX',
        ExportFormat.csv => 'CSV',
        ExportFormat.json => 'JSON',
        ExportFormat.unknown => S.exportUnknownFormat,
      };
}

/// The document an export was generated from.
///
/// Only an id and the original filename are published — enough to say which
/// statement this spreadsheet came out of, and to deep link to it.
@immutable
class ExportDocumentRef {
  const ExportDocumentRef({required this.id, this.originalFilename});

  factory ExportDocumentRef.fromJson(Map<String, dynamic> json) =>
      ExportDocumentRef(
        id: J.intOr(json['id'], 0),
        originalFilename: J.str(json['original_filename']),
      );

  final int id;
  final String? originalFilename;

  String get displayName => originalFilename ?? S.untitledDocument;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ExportDocumentRef &&
          other.id == id &&
          other.originalFilename == originalFilename;

  @override
  int get hashCode => Object.hash(id, originalFilename);
}

/// One generated spreadsheet.
@immutable
class ExportArchive {
  const ExportArchive({
    required this.id,
    required this.filename,
    required this.recordCount,
    required this.isAvailable,
    required this.downloadUrl,
    this.documentId,
    this.document,
    this.exportType,
    this.status,
    this.sizeBytes,
    this.generatedAt,
    this.createdAt,
  });

  factory ExportArchive.fromJson(Map<String, dynamic> json) => ExportArchive(
        id: J.intOr(json['id'], 0),
        documentId: J.intOrNull(json['document_id']),
        document: json['document'] == null
            ? null
            : ExportDocumentRef.fromJson(J.map(json['document'])),
        exportType: J.str(json['export_type']),
        status: J.str(json['status']),
        recordCount: J.intOr(json['record_count'], 0),
        filename: J.strOr(json['filename'], 'export'),
        sizeBytes: J.intOrNull(json['file_size']),
        isAvailable: J.boolOr(json['is_available']),
        downloadUrl: J.strOr(json['download_url'], ''),
        generatedAt: J.date(json['generated_at']),
        createdAt: J.date(json['created_at']),
      );

  final int id;
  final int? documentId;

  /// Null when the source document has been deleted — the archive row outlives
  /// it, which is the whole point of an archive.
  final ExportDocumentRef? document;

  /// The raw server string. [format] interprets it; this keeps the original so
  /// a value this build has never seen still round-trips.
  final String? exportType;

  final String? status;
  final int recordCount;

  /// Byte-for-byte the name the download endpoint sends, so the same export
  /// downloaded on the phone and on the website is one file, not two.
  final String filename;

  final int? sizeBytes;

  /// False when the file has been pruned from the disk.
  final bool isAvailable;

  /// Absolute and authenticated — usable only through the app's downloader.
  final String downloadUrl;

  final DateTime? generatedAt;
  final DateTime? createdAt;

  ExportFormat get format => ExportFormat.from(exportType);

  /// The moment this export was made. `generated_at` is the meaningful one and
  /// is what the server sorts by; `created_at` is the fallback for legacy rows.
  DateTime? get madeAt => generatedAt ?? createdAt;

  /// The calendar day [madeAt] falls on, in the device's zone. Used to group
  /// the list, so grouping and the date printed on each row cannot disagree.
  DateTime? get day {
    final DateTime? at = madeAt?.toLocal();
    return at == null ? null : DateTime(at.year, at.month, at.day);
  }

  String get sourceName => document?.displayName ?? S.untitledDocument;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ExportArchive &&
          other.id == id &&
          other.documentId == documentId &&
          other.document == document &&
          other.exportType == exportType &&
          other.status == status &&
          other.recordCount == recordCount &&
          other.filename == filename &&
          other.sizeBytes == sizeBytes &&
          other.isAvailable == isAvailable &&
          other.downloadUrl == downloadUrl &&
          other.generatedAt == generatedAt &&
          other.createdAt == createdAt;

  @override
  int get hashCode => Object.hashAll(<Object?>[
        id,
        documentId,
        document,
        exportType,
        status,
        recordCount,
        filename,
        sizeBytes,
        isAvailable,
        downloadUrl,
        generatedAt,
        createdAt,
      ]);
}
