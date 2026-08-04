/// A PDF the workspace has produced.
///
/// Field names mirror `GeneratedPdfResource` exactly. Two absences are
/// deliberate on the server and are worth knowing about here: `source_html` is
/// never published (it is the whole document body, and for a signed contract
/// the most sensitive field on the row), and there is no signature *status* on
/// this resource at all — only [signatureFieldCount], the boxes the web editor
/// placed. Whether a PDF has been signed is a question the signatures feature
/// answers, from `SignatureRequest.source`.
library;

import 'package:flutter/foundation.dart';

import '../../../core/i18n/strings.dart';
import '../../../core/utils/json.dart';

/// Where a generated PDF came from. The app shows a different icon and a
/// different sentence per kind.
enum GeneratedPdfKind {
  /// Filled in from a template — the one kind the app can create.
  template('template'),

  /// Written in the contract editor on the website.
  contract('contract'),

  /// Uploaded as a finished PDF, usually to be sent for signature.
  uploadedPdf('uploaded_pdf'),

  unknown('');

  const GeneratedPdfKind(this.wire);

  final String wire;

  static GeneratedPdfKind from(String? raw) =>
      switch ((raw ?? '').trim().toLowerCase()) {
        'template' => GeneratedPdfKind.template,
        'contract' => GeneratedPdfKind.contract,
        'uploaded_pdf' => GeneratedPdfKind.uploadedPdf,
        _ => GeneratedPdfKind.unknown,
      };

  String get label => switch (this) {
        GeneratedPdfKind.template => S.fromTemplate,
        GeneratedPdfKind.contract => S.contractPdf,
        GeneratedPdfKind.uploadedPdf => S.uploadedPdf,
        GeneratedPdfKind.unknown => S.generatedPdfs,
      };
}

/// The template a PDF was generated from, as it appears nested on the PDF.
@immutable
class GeneratedPdfTemplateRef {
  const GeneratedPdfTemplateRef({required this.id, this.name, this.type});

  factory GeneratedPdfTemplateRef.fromJson(Map<String, dynamic> json) =>
      GeneratedPdfTemplateRef(
        id: J.intOr(json['id'], 0),
        name: J.str(json['name']),
        type: J.str(json['type']),
      );

  final int id;
  final String? name;
  final String? type;

  String get displayName => name ?? S.untitledTemplate;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GeneratedPdfTemplateRef &&
          other.id == id &&
          other.name == name &&
          other.type == type;

  @override
  int get hashCode => Object.hash(id, name, type);
}

@immutable
class GeneratedPdf {
  const GeneratedPdf({
    required this.id,
    required this.kind,
    required this.filename,
    required this.isAvailable,
    required this.downloadUrl,
    required this.signatureFieldCount,
    this.title,
    this.templateId,
    this.template,
    this.data,
    this.sizeBytes,
    this.createdAt,
    this.updatedAt,
  });

  factory GeneratedPdf.fromJson(Map<String, dynamic> json) => GeneratedPdf(
        id: J.intOr(json['id'], 0),
        title: J.str(json['title']),
        kind: GeneratedPdfKind.from(J.str(json['kind'])),
        templateId: J.intOrNull(json['template_id']),
        template: json['template'] == null
            ? null
            : GeneratedPdfTemplateRef.fromJson(J.map(json['template'])),
        data: json['data'] == null ? null : J.map(json['data']),
        signatureFieldCount: J.list(json['signature_fields']).length,
        filename: J.strOr(json['filename'], 'generated-document.pdf'),
        sizeBytes: J.intOrNull(json['file_size']),
        isAvailable: J.boolOr(json['is_available']),
        downloadUrl: J.strOr(json['download_url'], ''),
        createdAt: J.date(json['created_at']),
        updatedAt: J.date(json['updated_at']),
      );

  final int id;
  final String? title;
  final GeneratedPdfKind kind;
  final int? templateId;

  /// Null when the template has since been deleted, or when the relation was
  /// not loaded.
  final GeneratedPdfTemplateRef? template;

  /// The values that were substituted in, so the detail view can show what this
  /// PDF was generated from. Null for a contract or an upload.
  final Map<String, dynamic>? data;

  /// How many signature boxes the web editor placed on this PDF. Not a
  /// signature *status* — the server publishes none on this resource.
  final int signatureFieldCount;

  /// The name the download endpoint sends, slugged from the title server-side.
  final String filename;

  final int? sizeBytes;

  /// False when the file is gone from the disk — read from the disk rather than
  /// trusted from the row, so the button is greyed instead of 404ing on tap.
  final bool isAvailable;

  final String downloadUrl;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  String get displayName => title ?? S.untitledPdf;

  /// What produced this PDF, in one line: the template's name when there is
  /// one, otherwise the kind.
  String get sourceLabel => template?.displayName ?? kind.label;

  bool get hasSignatureFields => signatureFieldCount > 0;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GeneratedPdf &&
          other.id == id &&
          other.title == title &&
          other.kind == kind &&
          other.templateId == templateId &&
          other.template == template &&
          mapEquals(other.data, data) &&
          other.signatureFieldCount == signatureFieldCount &&
          other.filename == filename &&
          other.sizeBytes == sizeBytes &&
          other.isAvailable == isAvailable &&
          other.downloadUrl == downloadUrl &&
          other.createdAt == createdAt &&
          other.updatedAt == updatedAt;

  @override
  int get hashCode => Object.hashAll(<Object?>[
        id,
        title,
        kind,
        templateId,
        template,
        signatureFieldCount,
        filename,
        sizeBytes,
        isAvailable,
        downloadUrl,
        createdAt,
        updatedAt,
      ]);
}
