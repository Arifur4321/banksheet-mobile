/// One normalised statement row, plus the two enums the review UI is built on.
///
/// Mirrors `TransactionResource` field for field. Every money column on the
/// server is cast `decimal:2` — i.e. a string — and pushed back through
/// `toFloat()` before it is sent, but the client still parses through
/// [J.doubleOrNull] rather than casting: the review screen does arithmetic on
/// these numbers, and a quoted value that slipped through must not crash a
/// list.
///
/// The colours live here rather than in the widgets because a confidence chip
/// and a review pill appear on four different screens, and a review queue where
/// "approved" is a slightly different green in two places reads as a bug.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../core/i18n/strings.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/utils/json.dart';

/// The four public confidence buckets.
///
/// The server never sends a float: `NormalizesValues::confidenceBucket()`
/// collapses the engine's score at fixed thresholds (>= 0.95 certain,
/// >= 0.80 high, >= 0.60 medium, else low). Nobody can write a sensible UI rule
/// against 0.83; everybody can colour four buckets.
enum ConfidenceLevel {
  certain('certain'),
  high('high'),
  medium('medium'),
  low('low');

  const ConfidenceLevel(this.wire);

  final String wire;

  /// Falls back to [medium] — the same default the server uses for a score it
  /// could not read, so the two ends agree about an unreadable value.
  static ConfidenceLevel from(String? raw) =>
      switch ((raw ?? '').trim().toLowerCase()) {
        'certain' => ConfidenceLevel.certain,
        'high' => ConfidenceLevel.high,
        'low' => ConfidenceLevel.low,
        _ => ConfidenceLevel.medium,
      };

  String get label => switch (this) {
        ConfidenceLevel.certain => S.confidenceCertain,
        ConfidenceLevel.high => S.confidenceHigh,
        ConfidenceLevel.medium => S.confidenceMedium,
        ConfidenceLevel.low => S.confidenceLow,
      };

  Color get foreground => switch (this) {
        ConfidenceLevel.certain => AppColors.brandDeep,
        ConfidenceLevel.high => AppColors.success,
        ConfidenceLevel.medium => AppColors.warn,
        ConfidenceLevel.low => AppColors.danger,
      };

  Color get background => switch (this) {
        ConfidenceLevel.certain => AppColors.brandTint,
        ConfidenceLevel.high => AppColors.successTint,
        ConfidenceLevel.medium => AppColors.warnTint,
        ConfidenceLevel.low => AppColors.dangerTint,
      };

  /// Only the bottom two buckets are worth interrupting the reviewer for.
  bool get isDoubtful =>
      this == ConfidenceLevel.medium || this == ConfidenceLevel.low;
}

/// The review states `extracted_transactions.review_status` can hold.
///
/// Exactly the four values `TransactionController::update()` validates with
/// `in:pending_review,approved,rejected,edited`. An unrecognised value parses
/// as [pendingReview]: a row whose state we cannot read is a row that still
/// needs a human, which is the safe side to fail on.
enum ReviewStatus {
  pendingReview('pending_review'),
  approved('approved'),
  rejected('rejected'),
  edited('edited');

  const ReviewStatus(this.wire);

  final String wire;

  static ReviewStatus from(String? raw) =>
      switch ((raw ?? '').trim().toLowerCase()) {
        'approved' => ReviewStatus.approved,
        'rejected' => ReviewStatus.rejected,
        'edited' => ReviewStatus.edited,
        _ => ReviewStatus.pendingReview,
      };

  String get label => switch (this) {
        ReviewStatus.pendingReview => S.pendingReview,
        ReviewStatus.approved => S.approved,
        ReviewStatus.rejected => S.rejected,
        ReviewStatus.edited => S.edited,
      };

  Color get foreground => switch (this) {
        ReviewStatus.pendingReview => AppColors.warn,
        ReviewStatus.approved => AppColors.brandDeep,
        ReviewStatus.rejected => AppColors.danger,
        ReviewStatus.edited => AppColors.info,
      };

  Color get background => switch (this) {
        ReviewStatus.pendingReview => AppColors.warnTint,
        ReviewStatus.approved => AppColors.brandTint,
        ReviewStatus.rejected => AppColors.dangerTint,
        ReviewStatus.edited => AppColors.infoTint,
      };

  IconData get icon => switch (this) {
        ReviewStatus.pendingReview => Icons.schedule_rounded,
        ReviewStatus.approved => Icons.check_circle_rounded,
        ReviewStatus.rejected => Icons.cancel_rounded,
        ReviewStatus.edited => Icons.edit_rounded,
      };

  /// Rows still waiting on a decision. The same set the server sweeps in
  /// `approveAllTransactions()`: `whereIn('review_status', ['pending_review',
  /// 'edited'])`.
  bool get isOpen =>
      this == ReviewStatus.pendingReview || this == ReviewStatus.edited;
}

/// The document a queue row came from, so a cross-document review list can say
/// which statement it is looking at without a second request.
@immutable
class TransactionDocumentRef {
  const TransactionDocumentRef({
    required this.id,
    this.originalFilename,
    this.documentType,
  });

  factory TransactionDocumentRef.fromJson(Map<String, dynamic> json) =>
      TransactionDocumentRef(
        id: J.intOr(json['id'], 0),
        originalFilename: J.str(json['original_filename']),
        documentType: J.str(json['document_type']),
      );

  final int id;
  final String? originalFilename;
  final String? documentType;

  String get displayName => originalFilename ?? S.untitledDocument;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TransactionDocumentRef &&
          other.id == id &&
          other.originalFilename == originalFilename &&
          other.documentType == documentType;

  @override
  int get hashCode => Object.hash(id, originalFilename, documentType);
}

/// `{"id": 1, "name": "Ada"}`.
@immutable
class ReviewerRef {
  const ReviewerRef({required this.id, this.name});

  factory ReviewerRef.fromJson(Map<String, dynamic> json) => ReviewerRef(
        id: J.intOr(json['id'], 0),
        name: J.str(json['name']),
      );

  final int id;
  final String? name;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReviewerRef && other.id == id && other.name == name;

  @override
  int get hashCode => Object.hash(id, name);
}

/// A single extracted statement row.
@immutable
class ExtractedTransaction {
  const ExtractedTransaction({
    required this.id,
    required this.confidence,
    required this.reviewStatus,
    required this.needsReview,
    required this.isReconciled,
    required this.validationFlags,
    this.documentId,
    this.document,
    this.position,
    this.transactionDate,
    this.valueDate,
    this.description,
    this.reference,
    this.counterparty,
    this.category,
    this.debit,
    this.credit,
    this.amountSigned,
    this.balance,
    this.currency,
    this.sourcePage,
    this.sourceLine,
    this.reviewedAt,
    this.reviewedBy,
    this.extractionProfileId,
    this.extractionProfileName,
    this.createdAt,
    this.updatedAt,
  });

  factory ExtractedTransaction.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic> profile = J.map(json['extraction_profile']);

    return ExtractedTransaction(
      id: J.intOr(json['id'], 0),
      documentId: J.intOrNull(json['document_id']),
      document: json['document'] == null
          ? null
          : TransactionDocumentRef.fromJson(J.map(json['document'])),
      position: J.intOrNull(json['position']),
      transactionDate: J.date(json['transaction_date']),
      valueDate: J.date(json['value_date']),
      description: J.str(json['description']),
      reference: J.str(json['reference']),
      counterparty: J.str(json['counterparty']),
      category: J.str(json['category']),
      debit: J.doubleOrNull(json['debit']),
      credit: J.doubleOrNull(json['credit']),
      amountSigned: J.doubleOrNull(json['amount_signed']),
      balance: J.doubleOrNull(json['balance']),
      currency: J.str(json['currency']),
      confidence: ConfidenceLevel.from(J.str(json['confidence'])),
      reviewStatus: ReviewStatus.from(J.str(json['review_status'])),
      needsReview: J.boolOr(json['needs_review']),
      isReconciled: J.boolOr(json['is_reconciled']),
      sourcePage: J.intOrNull(json['source_page']),
      sourceLine: J.str(json['source_line']),
      validationFlags: J.strings(json['validation_flags']),
      reviewedAt: J.date(json['reviewed_at']),
      reviewedBy: json['reviewed_by'] == null
          ? null
          : ReviewerRef.fromJson(J.map(json['reviewed_by'])),
      extractionProfileId: profile.isEmpty ? null : J.intOrNull(profile['id']),
      extractionProfileName: profile.isEmpty ? null : J.str(profile['name']),
      createdAt: J.date(json['created_at']),
      updatedAt: J.date(json['updated_at']),
    );
  }

  final int id;
  final int? documentId;

  /// Only loaded on the cross-document queue.
  final TransactionDocumentRef? document;

  /// The row's place in the statement, which is the order the reviewer reads.
  final int? position;

  final DateTime? transactionDate;
  final DateTime? valueDate;
  final String? description;
  final String? reference;
  final String? counterparty;
  final String? category;
  final double? debit;
  final double? credit;

  /// Credit positive, debit negative. Recomputed server-side on every edit.
  final double? amountSigned;

  final double? balance;
  final String? currency;
  final ConfidenceLevel confidence;
  final ReviewStatus reviewStatus;
  final bool needsReview;
  final bool isReconciled;
  final int? sourcePage;

  /// The raw line the parser read — the reviewer's only way to check a
  /// suspicious row without opening the original PDF.
  final String? sourceLine;

  final List<String> validationFlags;
  final DateTime? reviewedAt;
  final ReviewerRef? reviewedBy;
  final int? extractionProfileId;
  final String? extractionProfileName;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// The one number a row is really about: credit positive, debit negative.
  /// Falls back to deriving it when the server has not recomputed it yet.
  double? get signedAmount {
    if (amountSigned != null) {
      return amountSigned;
    }
    if (debit == null && credit == null) {
      return null;
    }
    return (credit ?? 0) - (debit ?? 0);
  }

  bool get isCredit => (signedAmount ?? 0) >= 0;

  bool get isOpen => reviewStatus.isOpen;

  /// Worth pulling the reviewer's eye: the parser was unsure, flagged something,
  /// or could not reconcile the row against the running balance.
  bool get isSuspicious =>
      needsReview || confidence.isDoubtful || validationFlags.isNotEmpty;

  String get displayDescription => description ?? counterparty ?? reference ?? '—';

  ExtractedTransaction copyWith({
    int? id,
    int? documentId,
    TransactionDocumentRef? document,
    int? position,
    DateTime? transactionDate,
    DateTime? valueDate,
    String? description,
    String? reference,
    String? counterparty,
    String? category,
    double? debit,
    double? credit,
    double? amountSigned,
    double? balance,
    String? currency,
    ConfidenceLevel? confidence,
    ReviewStatus? reviewStatus,
    bool? needsReview,
    bool? isReconciled,
    int? sourcePage,
    String? sourceLine,
    List<String>? validationFlags,
    DateTime? reviewedAt,
    ReviewerRef? reviewedBy,
    int? extractionProfileId,
    String? extractionProfileName,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return ExtractedTransaction(
      id: id ?? this.id,
      documentId: documentId ?? this.documentId,
      document: document ?? this.document,
      position: position ?? this.position,
      transactionDate: transactionDate ?? this.transactionDate,
      valueDate: valueDate ?? this.valueDate,
      description: description ?? this.description,
      reference: reference ?? this.reference,
      counterparty: counterparty ?? this.counterparty,
      category: category ?? this.category,
      debit: debit ?? this.debit,
      credit: credit ?? this.credit,
      amountSigned: amountSigned ?? this.amountSigned,
      balance: balance ?? this.balance,
      currency: currency ?? this.currency,
      confidence: confidence ?? this.confidence,
      reviewStatus: reviewStatus ?? this.reviewStatus,
      needsReview: needsReview ?? this.needsReview,
      isReconciled: isReconciled ?? this.isReconciled,
      sourcePage: sourcePage ?? this.sourcePage,
      sourceLine: sourceLine ?? this.sourceLine,
      validationFlags: validationFlags ?? this.validationFlags,
      reviewedAt: reviewedAt ?? this.reviewedAt,
      reviewedBy: reviewedBy ?? this.reviewedBy,
      extractionProfileId: extractionProfileId ?? this.extractionProfileId,
      extractionProfileName:
          extractionProfileName ?? this.extractionProfileName,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ExtractedTransaction &&
          other.id == id &&
          other.documentId == documentId &&
          other.document == document &&
          other.position == position &&
          other.transactionDate == transactionDate &&
          other.valueDate == valueDate &&
          other.description == description &&
          other.reference == reference &&
          other.counterparty == counterparty &&
          other.category == category &&
          other.debit == debit &&
          other.credit == credit &&
          other.amountSigned == amountSigned &&
          other.balance == balance &&
          other.currency == currency &&
          other.confidence == confidence &&
          other.reviewStatus == reviewStatus &&
          other.needsReview == needsReview &&
          other.isReconciled == isReconciled &&
          other.sourcePage == sourcePage &&
          other.sourceLine == sourceLine &&
          listEquals(other.validationFlags, validationFlags) &&
          other.reviewedAt == reviewedAt &&
          other.reviewedBy == reviewedBy &&
          other.extractionProfileId == extractionProfileId &&
          other.extractionProfileName == extractionProfileName &&
          other.createdAt == createdAt &&
          other.updatedAt == updatedAt;

  @override
  int get hashCode => Object.hashAll(<Object?>[
        id,
        documentId,
        document,
        position,
        transactionDate,
        valueDate,
        description,
        reference,
        counterparty,
        category,
        debit,
        credit,
        amountSigned,
        balance,
        currency,
        confidence,
        reviewStatus,
        needsReview,
        isReconciled,
        sourcePage,
        sourceLine,
        reviewedAt,
        reviewedBy,
        extractionProfileId,
        extractionProfileName,
        createdAt,
        updatedAt,
        ...validationFlags,
      ]);
}

/// The body of `PATCH /transactions/{id}`.
///
/// The server validates every field as `nullable` and only writes the keys it
/// actually received, so this class distinguishes "leave it alone" (the key is
/// absent) from "clear it" (the key is present and null). That distinction is
/// the whole reason it exists rather than a bare map: a reviewer who empties
/// the reference field must end up with an empty reference, and a swipe that
/// only sets a status must not blank out nine other columns.
@immutable
class TransactionEdit {
  const TransactionEdit({
    required this.reviewStatus,
    this.fields = const <String, dynamic>{},
  });

  /// A status-only change — what a swipe in the review queue sends.
  factory TransactionEdit.statusOnly(ReviewStatus status) =>
      TransactionEdit(reviewStatus: status);

  /// A full edit from the sheet. Every column is sent explicitly, including the
  /// nulls, because that is what makes clearing a field work.
  factory TransactionEdit.full({
    required ReviewStatus reviewStatus,
    required DateTime? transactionDate,
    required DateTime? valueDate,
    required String? description,
    required String? reference,
    required String? counterparty,
    required String? category,
    required double? debit,
    required double? credit,
    required double? balance,
    required String? currency,
  }) {
    return TransactionEdit(
      reviewStatus: reviewStatus,
      fields: <String, dynamic>{
        'transaction_date': _isoDate(transactionDate),
        'value_date': _isoDate(valueDate),
        'description': description,
        'reference': reference,
        'counterparty': counterparty,
        'category': category,
        'debit': debit,
        'credit': credit,
        'balance': balance,
        'currency': currency,
      },
    );
  }

  /// Required by the server on every call.
  final ReviewStatus reviewStatus;

  final Map<String, dynamic> fields;

  Map<String, dynamic> toJson() => <String, dynamic>{
        ...fields,
        'review_status': reviewStatus.wire,
      };

  /// Date-only, matching `NormalizesValues::isoDate()`. Sending midnight UTC
  /// instead would land on the previous day for every user west of Greenwich,
  /// which on a bank statement looks like a data error rather than a formatting
  /// one.
  static String? _isoDate(DateTime? value) {
    if (value == null) {
      return null;
    }
    final DateTime d = value.toLocal();
    final String month = d.month < 10 ? '0${d.month}' : '${d.month}';
    final String day = d.day < 10 ? '0${d.day}' : '${d.day}';
    return '${d.year}-$month-$day';
  }
}
