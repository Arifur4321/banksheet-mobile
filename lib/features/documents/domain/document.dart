/// Document models: the list row, the full detail payload, and the tiny object
/// the status poller reads.
///
/// Hand written and immutable, because the project ships without codegen. Every
/// field is parsed through [J], so a value that arrives as a string where a
/// number was promised degrades to null instead of taking the documents list
/// down on someone's phone.
///
/// Field names mirror `DocumentResource`, `DocumentDetailResource`,
/// `StatementSummaryResource` and `ExtractionJobResource` exactly. Nothing here
/// is invented: if the server does not send it, it is not here.
library;

import 'package:flutter/foundation.dart';

import '../../../core/i18n/strings.dart';
import '../../../core/utils/json.dart';
import 'transaction.dart';

/// The five values `documents.status` can hold, plus a defensive [unknown].
///
/// [isWorking] is byte-for-byte `DocumentController::status()`'s
/// `in_array($document->status, ['uploaded', 'queued', 'processing'], true)`.
/// [isFinished] is deliberately defined as "not working" rather than as its own
/// list: a status a future server adds must stop the poller, not spin it
/// forever on a document that will never change.
enum DocumentStatus {
  uploaded('uploaded'),
  queued('queued'),
  processing('processing'),
  processed('processed'),
  failed('failed'),
  unknown('unknown');

  const DocumentStatus(this.wire);

  /// The exact string the server uses.
  final String wire;

  static DocumentStatus from(String? raw) {
    return switch ((raw ?? '').trim().toLowerCase()) {
      'uploaded' => DocumentStatus.uploaded,
      'queued' => DocumentStatus.queued,
      'processing' => DocumentStatus.processing,
      'processed' => DocumentStatus.processed,
      'failed' => DocumentStatus.failed,
      _ => DocumentStatus.unknown,
    };
  }

  bool get isWorking =>
      this == DocumentStatus.uploaded ||
      this == DocumentStatus.queued ||
      this == DocumentStatus.processing;

  bool get isFinished => !isWorking;

  bool get isFailed => this == DocumentStatus.failed;

  bool get isProcessed => this == DocumentStatus.processed;
}

/// The three values `documents.document_type` can hold.
enum DocumentKind {
  bankStatement('bank_statement'),
  invoice('invoice'),
  genericPdf('generic_pdf');

  const DocumentKind(this.wire);

  final String wire;

  static DocumentKind from(String? raw) => switch ((raw ?? '').trim()) {
        'invoice' => DocumentKind.invoice,
        'generic_pdf' => DocumentKind.genericPdf,
        _ => DocumentKind.bankStatement,
      };

  String get label => switch (this) {
        DocumentKind.bankStatement => S.bankStatement,
        DocumentKind.invoice => S.invoice,
        DocumentKind.genericPdf => S.genericPdf,
      };
}

/// `{"id": 1, "name": "Ada"}` — the shape every actor reference uses.
@immutable
class UserRef {
  const UserRef({required this.id, this.name});

  factory UserRef.fromJson(Map<String, dynamic> json) => UserRef(
        id: J.intOr(json['id'], 0),
        name: J.str(json['name']),
      );

  final int id;
  final String? name;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UserRef && other.id == id && other.name == name;

  @override
  int get hashCode => Object.hash(id, name);
}

/// An extraction profile, as it appears nested on a document and as the upload
/// screen's picker lists it.
///
/// Deliberately a small reference type rather than the full profile model —
/// that one belongs to the profiles feature, and the two screens that need a
/// profile here need an id and something to print, nothing else.
@immutable
class ProfileRef {
  const ProfileRef({
    required this.id,
    this.name,
    this.bankName,
    this.documentType,
    this.isActive = true,
  });

  factory ProfileRef.fromJson(Map<String, dynamic> json) => ProfileRef(
        id: J.intOr(json['id'], 0),
        name: J.str(json['name']),
        bankName: J.str(json['bank_name']),
        documentType: J.str(json['document_type']),
        isActive: J.boolOr(json['is_active'], fallback: true),
      );

  final int id;
  final String? name;
  final String? bankName;
  final String? documentType;
  final bool isActive;

  String get label => name ?? bankName ?? S.profileNumber(id);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ProfileRef &&
          other.id == id &&
          other.name == name &&
          other.bankName == bankName &&
          other.documentType == documentType &&
          other.isActive == isActive;

  @override
  int get hashCode => Object.hash(id, name, bankName, documentType, isActive);
}

/// A document as the list screen renders it.
@immutable
class DocumentSummary {
  const DocumentSummary({
    required this.id,
    required this.status,
    required this.pageCount,
    required this.isPdf,
    this.originalFilename,
    this.documentType,
    this.errorMessage,
    this.mimeType,
    this.fileSize,
    this.uploadedBy,
    this.extractionProfile,
    this.transactionsCount,
    this.approvedTransactionsCount,
    this.recordsCount,
    this.approvedRecordsCount,
    this.exportsCount,
    this.createdAt,
    this.updatedAt,
  });

  factory DocumentSummary.fromJson(Map<String, dynamic> json) {
    return DocumentSummary(
      id: J.intOr(json['id'], 0),
      originalFilename: J.str(json['original_filename']),
      documentType: J.str(json['document_type']),
      status: J.strOr(json['status'], DocumentStatus.unknown.wire),
      errorMessage: J.str(json['error_message']),
      mimeType: J.str(json['mime_type']),
      fileSize: J.intOrNull(json['file_size']),
      pageCount: J.intOr(json['page_count'], 0),
      isPdf: J.boolOr(json['is_pdf']),
      uploadedBy: json['uploaded_by'] == null
          ? null
          : UserRef.fromJson(J.map(json['uploaded_by'])),
      extractionProfile: json['extraction_profile'] == null
          ? null
          : ProfileRef.fromJson(J.map(json['extraction_profile'])),
      transactionsCount: J.intOrNull(json['transactions_count']),
      approvedTransactionsCount:
          J.intOrNull(json['approved_transactions_count']),
      recordsCount: J.intOrNull(json['records_count']),
      approvedRecordsCount: J.intOrNull(json['approved_records_count']),
      exportsCount: J.intOrNull(json['exports_count']),
      createdAt: J.date(json['created_at']),
      updatedAt: J.date(json['updated_at']),
    );
  }

  final int id;
  final String? originalFilename;
  final String? documentType;

  /// The raw server string, kept verbatim so `StatusBadge` can colour it and
  /// so a value this build has never seen still round-trips.
  final String status;

  final String? errorMessage;
  final String? mimeType;
  final int? fileSize;
  final int pageCount;

  /// Computed server-side: `Document::isPdf()` also accepts a `.pdf` filename
  /// carrying a wrong MIME type, which the client cannot know.
  final bool isPdf;

  final UserRef? uploadedBy;
  final ProfileRef? extractionProfile;

  /// Null (not zero) when the query did not select the count.
  final int? transactionsCount;
  final int? approvedTransactionsCount;
  final int? recordsCount;
  final int? approvedRecordsCount;
  final int? exportsCount;

  final DateTime? createdAt;
  final DateTime? updatedAt;

  DocumentStatus get state => DocumentStatus.from(status);

  DocumentKind get kind => DocumentKind.from(documentType);

  bool get isBankStatement => kind == DocumentKind.bankStatement;

  String get displayName => originalFilename ?? S.untitledDocument;

  /// Rows the reviewer has not approved yet.
  ///
  /// The list resource carries a total and an approved count but no rejected
  /// count, so a document whose remaining rows were all *rejected* still reads
  /// as unapproved here. That is the honest limit of the list payload; the
  /// detail screen has the real four-way breakdown.
  int get unapprovedCount {
    final int total = transactionsCount ?? recordsCount ?? 0;
    final int approved = approvedTransactionsCount ?? approvedRecordsCount ?? 0;
    final int open = total - approved;
    return open < 0 ? 0 : open;
  }

  bool get needsReview => state.isProcessed && unapprovedCount > 0;

  DocumentSummary copyWith({
    int? id,
    String? originalFilename,
    String? documentType,
    String? status,
    String? errorMessage,
    String? mimeType,
    int? fileSize,
    int? pageCount,
    bool? isPdf,
    UserRef? uploadedBy,
    ProfileRef? extractionProfile,
    int? transactionsCount,
    int? approvedTransactionsCount,
    int? recordsCount,
    int? approvedRecordsCount,
    int? exportsCount,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return DocumentSummary(
      id: id ?? this.id,
      originalFilename: originalFilename ?? this.originalFilename,
      documentType: documentType ?? this.documentType,
      status: status ?? this.status,
      errorMessage: errorMessage ?? this.errorMessage,
      mimeType: mimeType ?? this.mimeType,
      fileSize: fileSize ?? this.fileSize,
      pageCount: pageCount ?? this.pageCount,
      isPdf: isPdf ?? this.isPdf,
      uploadedBy: uploadedBy ?? this.uploadedBy,
      extractionProfile: extractionProfile ?? this.extractionProfile,
      transactionsCount: transactionsCount ?? this.transactionsCount,
      approvedTransactionsCount:
          approvedTransactionsCount ?? this.approvedTransactionsCount,
      recordsCount: recordsCount ?? this.recordsCount,
      approvedRecordsCount: approvedRecordsCount ?? this.approvedRecordsCount,
      exportsCount: exportsCount ?? this.exportsCount,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DocumentSummary &&
          other.id == id &&
          other.originalFilename == originalFilename &&
          other.documentType == documentType &&
          other.status == status &&
          other.errorMessage == errorMessage &&
          other.mimeType == mimeType &&
          other.fileSize == fileSize &&
          other.pageCount == pageCount &&
          other.isPdf == isPdf &&
          other.uploadedBy == uploadedBy &&
          other.extractionProfile == extractionProfile &&
          other.transactionsCount == transactionsCount &&
          other.approvedTransactionsCount == approvedTransactionsCount &&
          other.recordsCount == recordsCount &&
          other.approvedRecordsCount == approvedRecordsCount &&
          other.exportsCount == exportsCount &&
          other.createdAt == createdAt &&
          other.updatedAt == updatedAt;

  @override
  int get hashCode => Object.hashAll(<Object?>[
        id,
        originalFilename,
        documentType,
        status,
        errorMessage,
        mimeType,
        fileSize,
        pageCount,
        isPdf,
        uploadedBy,
        extractionProfile,
        transactionsCount,
        approvedTransactionsCount,
        recordsCount,
        approvedRecordsCount,
        exportsCount,
        createdAt,
        updatedAt,
      ]);
}

/// The statement period. `label` is the engine's own display string and is
/// often present when the parsed dates are not.
@immutable
class StatementPeriod {
  const StatementPeriod({this.start, this.end, this.label});

  factory StatementPeriod.fromJson(Map<String, dynamic> json) =>
      StatementPeriod(
        start: J.date(json['start']),
        end: J.date(json['end']),
        label: J.str(json['label']),
      );

  final DateTime? start;
  final DateTime? end;
  final String? label;

  bool get isEmpty => start == null && end == null && label == null;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StatementPeriod &&
          other.start == start &&
          other.end == end &&
          other.label == label;

  @override
  int get hashCode => Object.hash(start, end, label);
}

/// `summary_json.totals`.
@immutable
class StatementTotals {
  const StatementTotals({
    required this.transactionCount,
    this.totalDebits,
    this.totalCredits,
    this.netChange,
  });

  factory StatementTotals.fromJson(Map<String, dynamic> json) =>
      StatementTotals(
        transactionCount: J.intOr(json['transaction_count'], 0),
        totalDebits: J.doubleOrNull(json['total_debits']),
        totalCredits: J.doubleOrNull(json['total_credits']),
        netChange: J.doubleOrNull(json['net_change']),
      );

  final int transactionCount;
  final double? totalDebits;
  final double? totalCredits;
  final double? netChange;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StatementTotals &&
          other.transactionCount == transactionCount &&
          other.totalDebits == totalDebits &&
          other.totalCredits == totalCredits &&
          other.netChange == netChange;

  @override
  int get hashCode =>
      Object.hash(transactionCount, totalDebits, totalCredits, netChange);
}

/// Whether opening + credits - debits actually equals closing.
///
/// This is the one thing the user can check against the paper in their hand, so
/// the app states it in a sentence rather than showing four numbers and hoping.
@immutable
class ReconciliationInfo {
  const ReconciliationInfo({
    required this.status,
    required this.statementBalanced,
    required this.rowsChecked,
    required this.rowsMatched,
    required this.rowsFlagged,
    this.openingBalance,
    this.closingBalance,
    this.expectedNetChange,
    this.computedNetChange,
    this.discrepancy,
  });

  factory ReconciliationInfo.fromJson(Map<String, dynamic> json) =>
      ReconciliationInfo(
        status: J.strOr(json['status'], 'unknown'),
        statementBalanced: J.boolOr(json['statement_balanced']),
        openingBalance: J.doubleOrNull(json['opening_balance']),
        closingBalance: J.doubleOrNull(json['closing_balance']),
        expectedNetChange: J.doubleOrNull(json['expected_net_change']),
        computedNetChange: J.doubleOrNull(json['computed_net_change']),
        discrepancy: J.doubleOrNull(json['discrepancy']),
        rowsChecked: J.intOr(json['rows_checked'], 0),
        rowsMatched: J.intOr(json['rows_matched'], 0),
        rowsFlagged: J.intOr(json['rows_flagged'], 0),
      );

  final String status;
  final bool statementBalanced;
  final double? openingBalance;
  final double? closingBalance;
  final double? expectedNetChange;
  final double? computedNetChange;

  /// `computed - expected`, rounded to cents by the server. Null when either
  /// side is unknown, which is a different statement from "the gap is zero".
  final double? discrepancy;

  final int rowsChecked;
  final int rowsMatched;
  final int rowsFlagged;

  /// True when the server had both sides of the equation to compare.
  bool get isKnown => discrepancy != null;

  /// True only when we checked and it held.
  bool get isBalanced => isKnown && statementBalanced;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReconciliationInfo &&
          other.status == status &&
          other.statementBalanced == statementBalanced &&
          other.openingBalance == openingBalance &&
          other.closingBalance == closingBalance &&
          other.expectedNetChange == expectedNetChange &&
          other.computedNetChange == computedNetChange &&
          other.discrepancy == discrepancy &&
          other.rowsChecked == rowsChecked &&
          other.rowsMatched == rowsMatched &&
          other.rowsFlagged == rowsFlagged;

  @override
  int get hashCode => Object.hashAll(<Object?>[
        status,
        statementBalanced,
        openingBalance,
        closingBalance,
        expectedNetChange,
        computedNetChange,
        discrepancy,
        rowsChecked,
        rowsMatched,
        rowsFlagged,
      ]);
}

/// The bank-statement header: who the bank is, whose account it is, and what
/// the period totalled.
@immutable
class StatementSummary {
  const StatementSummary({
    required this.confidence,
    required this.period,
    required this.totals,
    required this.reconciliation,
    required this.needsReviewCount,
    required this.recordsCount,
    required this.transactionsCount,
    required this.warnings,
    required this.ocrWarnings,
    this.engine,
    this.matchedProfile,
    this.bankName,
    this.accountHolder,
    this.ibanMasked,
    this.accountNumberMasked,
    this.accountDisplay,
    this.bic,
    this.branch,
    this.currency,
    this.openingBalance,
    this.closingBalance,
  });

  factory StatementSummary.fromJson(Map<String, dynamic> json) =>
      StatementSummary(
        confidence: ConfidenceLevel.from(J.str(json['confidence'])),
        engine: J.str(json['engine']),
        matchedProfile: J.str(json['matched_profile']),
        bankName: J.str(json['bank_name']),
        accountHolder: J.str(json['account_holder']),
        ibanMasked: J.str(json['iban_masked']),
        accountNumberMasked: J.str(json['account_number_masked']),
        accountDisplay: J.str(json['account_display']),
        bic: J.str(json['bic']),
        branch: J.str(json['branch']),
        currency: J.str(json['currency']),
        period: StatementPeriod.fromJson(J.map(json['period'])),
        openingBalance: J.doubleOrNull(json['opening_balance']),
        closingBalance: J.doubleOrNull(json['closing_balance']),
        totals: StatementTotals.fromJson(J.map(json['totals'])),
        reconciliation:
            ReconciliationInfo.fromJson(J.map(json['reconciliation'])),
        needsReviewCount: J.intOr(json['needs_review_count'], 0),
        recordsCount: J.intOr(json['records_count'], 0),
        transactionsCount: J.intOr(json['transactions_count'], 0),
        warnings: J.strings(json['warnings']),
        ocrWarnings: J.strings(json['ocr_warnings']),
      );

  final ConfidenceLevel confidence;
  final String? engine;
  final String? matchedProfile;
  final String? bankName;
  final String? accountHolder;

  /// Already masked server-side — the full IBAN never reaches the device.
  final String? ibanMasked;
  final String? accountNumberMasked;

  /// IBAN when there is one, otherwise the account number. Precomputed so the
  /// app and the website label the account identically.
  final String? accountDisplay;

  final String? bic;
  final String? branch;
  final String? currency;
  final StatementPeriod period;
  final double? openingBalance;
  final double? closingBalance;
  final StatementTotals totals;
  final ReconciliationInfo reconciliation;
  final int needsReviewCount;
  final int recordsCount;
  final int transactionsCount;

  /// What the statement parser thought of the document.
  final List<String> warnings;

  /// What the text layer or OCR reported. Separate because the causes and the
  /// fixes are different.
  final List<String> ocrWarnings;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StatementSummary &&
          other.confidence == confidence &&
          other.engine == engine &&
          other.matchedProfile == matchedProfile &&
          other.bankName == bankName &&
          other.accountHolder == accountHolder &&
          other.ibanMasked == ibanMasked &&
          other.accountNumberMasked == accountNumberMasked &&
          other.accountDisplay == accountDisplay &&
          other.bic == bic &&
          other.branch == branch &&
          other.currency == currency &&
          other.period == period &&
          other.openingBalance == openingBalance &&
          other.closingBalance == closingBalance &&
          other.totals == totals &&
          other.reconciliation == reconciliation &&
          other.needsReviewCount == needsReviewCount &&
          other.recordsCount == recordsCount &&
          other.transactionsCount == transactionsCount &&
          listEquals(other.warnings, warnings) &&
          listEquals(other.ocrWarnings, ocrWarnings);

  @override
  int get hashCode => Object.hashAll(<Object?>[
        confidence,
        engine,
        matchedProfile,
        bankName,
        accountHolder,
        ibanMasked,
        accountNumberMasked,
        accountDisplay,
        bic,
        branch,
        currency,
        period,
        openingBalance,
        closingBalance,
        totals,
        reconciliation,
        needsReviewCount,
        recordsCount,
        transactionsCount,
        ...warnings,
        ...ocrWarnings,
      ]);
}

/// One processing run of a document.
@immutable
class ExtractionJobInfo {
  const ExtractionJobInfo({
    required this.id,
    required this.recordsCount,
    required this.transactionsCount,
    required this.needsReviewCount,
    required this.matchReasons,
    required this.warnings,
    this.documentId,
    this.status,
    this.errorMessage,
    this.startedAt,
    this.finishedAt,
    this.ocrStatus,
    this.ocrDriver,
    this.matchedProfileScore,
    this.matchedProfile,
    this.engine,
    this.createdAt,
    this.updatedAt,
  });

  factory ExtractionJobInfo.fromJson(Map<String, dynamic> json) =>
      ExtractionJobInfo(
        id: J.intOr(json['id'], 0),
        documentId: J.intOrNull(json['document_id']),
        status: J.str(json['status']),
        errorMessage: J.str(json['error_message']),
        startedAt: J.date(json['started_at']),
        finishedAt: J.date(json['finished_at']),
        ocrStatus: J.str(json['ocr_status']),
        ocrDriver: J.str(json['ocr_driver']),
        matchedProfileScore: J.doubleOrNull(json['matched_profile_score']),
        matchedProfile: J.str(json['matched_profile']),
        matchReasons: J.strings(json['match_reasons']),
        engine: J.str(json['engine']),
        recordsCount: J.intOr(json['records_count'], 0),
        transactionsCount: J.intOr(json['transactions_count'], 0),
        needsReviewCount: J.intOr(json['needs_review_count'], 0),
        warnings: J.strings(json['warnings']),
        createdAt: J.date(json['created_at']),
        updatedAt: J.date(json['updated_at']),
      );

  final int id;
  final int? documentId;
  final String? status;
  final String? errorMessage;
  final DateTime? startedAt;
  final DateTime? finishedAt;
  final String? ocrStatus;
  final String? ocrDriver;
  final double? matchedProfileScore;
  final String? matchedProfile;
  final List<String> matchReasons;
  final String? engine;
  final int recordsCount;
  final int transactionsCount;
  final int needsReviewCount;
  final List<String> warnings;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// How long the run took, when both ends are known.
  Duration? get duration => (startedAt == null || finishedAt == null)
      ? null
      : finishedAt!.difference(startedAt!);

  bool get usedOcr => ocrStatus != null && ocrStatus != 'skipped';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ExtractionJobInfo &&
          other.id == id &&
          other.documentId == documentId &&
          other.status == status &&
          other.errorMessage == errorMessage &&
          other.startedAt == startedAt &&
          other.finishedAt == finishedAt &&
          other.ocrStatus == ocrStatus &&
          other.ocrDriver == ocrDriver &&
          other.matchedProfileScore == matchedProfileScore &&
          other.matchedProfile == matchedProfile &&
          listEquals(other.matchReasons, matchReasons) &&
          other.engine == engine &&
          other.recordsCount == recordsCount &&
          other.transactionsCount == transactionsCount &&
          other.needsReviewCount == needsReviewCount &&
          listEquals(other.warnings, warnings) &&
          other.createdAt == createdAt &&
          other.updatedAt == updatedAt;

  @override
  int get hashCode => Object.hashAll(<Object?>[
        id,
        documentId,
        status,
        errorMessage,
        startedAt,
        finishedAt,
        ocrStatus,
        ocrDriver,
        matchedProfileScore,
        matchedProfile,
        engine,
        recordsCount,
        transactionsCount,
        needsReviewCount,
        createdAt,
        updatedAt,
        ...matchReasons,
        ...warnings,
      ]);
}

/// The four-way review breakdown from `DocumentDetailResource::review_counts`.
@immutable
class ReviewCounts {
  const ReviewCounts({
    this.total,
    this.approved,
    this.pending,
    this.rejected,
  });

  factory ReviewCounts.fromJson(Map<String, dynamic> json) => ReviewCounts(
        total: J.intOrNull(json['total']),
        approved: J.intOrNull(json['approved']),
        pending: J.intOrNull(json['pending']),
        rejected: J.intOrNull(json['rejected']),
      );

  final int? total;
  final int? approved;
  final int? pending;
  final int? rejected;

  /// Whether there is anything left for a reviewer to act on.
  ///
  /// Not simply `pending > 0`: a generic PDF has no pending state — a record is
  /// approved or it is not — and the server reports `pending: 0` for those. The
  /// gap between total and approved is what actually means "unfinished".
  bool get hasPending =>
      (pending ?? 0) > 0 || (total ?? 0) > (approved ?? 0);

  double get approvedRatio {
    final int t = total ?? 0;
    if (t <= 0) {
      return 0;
    }
    return ((approved ?? 0) / t).clamp(0.0, 1.0).toDouble();
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReviewCounts &&
          other.total == total &&
          other.approved == approved &&
          other.pending == pending &&
          other.rejected == rejected;

  @override
  int get hashCode => Object.hash(total, approved, pending, rejected);
}

/// A generated spreadsheet attached to this document.
///
/// `isAvailable` is read from disk server-side: export files are pruned, and a
/// download button for a file that no longer exists is worse than a greyed-out
/// row.
@immutable
class DocumentExport {
  const DocumentExport({
    required this.id,
    required this.recordCount,
    required this.filename,
    required this.isAvailable,
    required this.downloadUrl,
    this.documentId,
    this.exportType,
    this.status,
    this.fileSize,
    this.generatedAt,
    this.createdAt,
  });

  factory DocumentExport.fromJson(Map<String, dynamic> json) => DocumentExport(
        id: J.intOr(json['id'], 0),
        documentId: J.intOrNull(json['document_id']),
        exportType: J.str(json['export_type']),
        status: J.str(json['status']),
        recordCount: J.intOr(json['record_count'], 0),
        filename: J.strOr(json['filename'], 'export'),
        fileSize: J.intOrNull(json['file_size']),
        isAvailable: J.boolOr(json['is_available']),
        downloadUrl: J.strOr(json['download_url'], ''),
        generatedAt: J.date(json['generated_at']),
        createdAt: J.date(json['created_at']),
      );

  final int id;
  final int? documentId;
  final String? exportType;
  final String? status;
  final int recordCount;
  final String filename;
  final int? fileSize;
  final bool isAvailable;
  final String downloadUrl;
  final DateTime? generatedAt;
  final DateTime? createdAt;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DocumentExport &&
          other.id == id &&
          other.documentId == documentId &&
          other.exportType == exportType &&
          other.status == status &&
          other.recordCount == recordCount &&
          other.filename == filename &&
          other.fileSize == fileSize &&
          other.isAvailable == isAvailable &&
          other.downloadUrl == downloadUrl &&
          other.generatedAt == generatedAt &&
          other.createdAt == createdAt;

  @override
  int get hashCode => Object.hashAll(<Object?>[
        id,
        documentId,
        exportType,
        status,
        recordCount,
        filename,
        fileSize,
        isAvailable,
        downloadUrl,
        generatedAt,
        createdAt,
      ]);
}

/// Everything `GET /documents/{id}` returns: the document, its statement
/// header, the last run, its exports, and the first page of transactions.
@immutable
class DocumentDetail {
  const DocumentDetail({
    required this.summary,
    required this.reviewCounts,
    required this.exports,
    required this.transactions,
    this.statementSummary,
    this.latestJob,
    this.storedPageCount,
  });

  factory DocumentDetail.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic> doc = J.map(json['document']);

    return DocumentDetail(
      summary: DocumentSummary.fromJson(doc),
      statementSummary: doc['statement_summary'] == null
          ? null
          : StatementSummary.fromJson(J.map(doc['statement_summary'])),
      latestJob: doc['latest_extraction_job'] == null
          ? null
          : ExtractionJobInfo.fromJson(J.map(doc['latest_extraction_job'])),
      exports: J
          .list(doc['exports'])
          .map(DocumentExport.fromJson)
          .toList(growable: false),
      reviewCounts: ReviewCounts.fromJson(J.map(doc['review_counts'])),
      storedPageCount: J.intOrNull(doc['stored_page_count']),
      transactions: Paged<ExtractedTransaction>(
        items: J
            .list(json['transactions'])
            .map(ExtractedTransaction.fromJson)
            .toList(growable: false),
        meta: PageMeta.fromJson(J.map(json['transactions_meta'])),
      ),
    );
  }

  final DocumentSummary summary;

  /// Null for invoices and generic PDFs, and for a bank statement that has not
  /// been processed yet.
  final StatementSummary? statementSummary;

  final ExtractionJobInfo? latestJob;
  final List<DocumentExport> exports;
  final ReviewCounts reviewCounts;

  /// Pages actually stored with extracted text, which can legitimately differ
  /// from [DocumentSummary.pageCount] when OCR skipped a page.
  final int? storedPageCount;

  final Paged<ExtractedTransaction> transactions;

  int get id => summary.id;
  String get displayName => summary.displayName;
  DocumentStatus get state => summary.state;
  DocumentKind get kind => summary.kind;
  bool get isBankStatement => summary.isBankStatement;
  String? get errorMessage => summary.errorMessage;
  bool get isPdf => summary.isPdf;

  bool get hasStatement => statementSummary != null;

  DocumentDetail copyWith({
    DocumentSummary? summary,
    StatementSummary? statementSummary,
    ExtractionJobInfo? latestJob,
    List<DocumentExport>? exports,
    ReviewCounts? reviewCounts,
    int? storedPageCount,
    Paged<ExtractedTransaction>? transactions,
  }) {
    return DocumentDetail(
      summary: summary ?? this.summary,
      statementSummary: statementSummary ?? this.statementSummary,
      latestJob: latestJob ?? this.latestJob,
      exports: exports ?? this.exports,
      reviewCounts: reviewCounts ?? this.reviewCounts,
      storedPageCount: storedPageCount ?? this.storedPageCount,
      transactions: transactions ?? this.transactions,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DocumentDetail &&
          other.summary == summary &&
          other.statementSummary == statementSummary &&
          other.latestJob == latestJob &&
          listEquals(other.exports, exports) &&
          other.reviewCounts == reviewCounts &&
          other.storedPageCount == storedPageCount &&
          listEquals(other.transactions.items, transactions.items);

  @override
  int get hashCode => Object.hash(
        summary,
        statementSummary,
        latestJob,
        Object.hashAll(exports),
        reviewCounts,
        storedPageCount,
        Object.hashAll(transactions.items),
      );
}

/// The response of `GET /documents/{id}/status`.
///
/// Deliberately tiny: the app hits it every few seconds while a document is in
/// flight, and the detail payload it would otherwise re-download is two orders
/// of magnitude larger.
@immutable
class DocumentStatusInfo {
  const DocumentStatusInfo({
    required this.id,
    required this.status,
    required this.transactionsCount,
    required this.pendingCount,
    this.errorMessage,
    this.pollAfterSeconds,
  });

  factory DocumentStatusInfo.fromJson(Map<String, dynamic> json) =>
      DocumentStatusInfo(
        id: J.intOr(json['id'], 0),
        status: J.strOr(json['status'], DocumentStatus.unknown.wire),
        errorMessage: J.str(json['error_message']),
        transactionsCount: J.intOr(json['transactions_count'], 0),
        pendingCount: J.intOr(json['pending_count'], 0),
        pollAfterSeconds: J.intOrNull(json['poll_after_seconds']),
      );

  final int id;
  final String status;
  final String? errorMessage;
  final int transactionsCount;
  final int pendingCount;

  /// Null once the document has settled — the server's own signal to stop the
  /// timer, which the client honours instead of matching on status strings.
  final int? pollAfterSeconds;

  DocumentStatus get state => DocumentStatus.from(status);

  /// True when either the server withdrew the poll hint or the status left the
  /// working set. Both are checked because the two must never disagree, and if
  /// they ever do, stopping is the safe answer.
  bool get isSettled => pollAfterSeconds == null || state.isFinished;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DocumentStatusInfo &&
          other.id == id &&
          other.status == status &&
          other.errorMessage == errorMessage &&
          other.transactionsCount == transactionsCount &&
          other.pendingCount == pendingCount &&
          other.pollAfterSeconds == pollAfterSeconds;

  @override
  int get hashCode => Object.hash(
        id,
        status,
        errorMessage,
        transactionsCount,
        pendingCount,
        pollAfterSeconds,
      );
}
