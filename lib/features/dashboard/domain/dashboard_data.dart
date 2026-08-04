/// The home screen's data, in one object.
///
/// `GET /dashboard` answers with a flat body — thirteen counters plus the five
/// most recent documents — because the client renders it as a fixed grid of
/// tiles rather than as a generic list. This mirrors that body exactly; every
/// key below is one the controller actually emits.
///
/// The document rows are kept deliberately small and local rather than reusing
/// the documents feature's own model: the dashboard needs a filename, a status
/// and a row count, and coupling the home screen to another feature's parser
/// would make a change there able to break the first screen after sign-in.
library;

import 'package:flutter/foundation.dart';

import '../../../core/utils/json.dart';

/// One row in the "recent documents" list.
@immutable
class DashboardDocument {
  const DashboardDocument({
    required this.id,
    this.originalFilename,
    this.documentType,
    this.status,
    this.errorMessage,
    this.pageCount = 0,
    this.transactionsCount,
    this.approvedTransactionsCount,
    this.recordsCount,
    this.approvedRecordsCount,
    this.exportsCount,
    this.createdAt,
  });

  factory DashboardDocument.fromJson(Map<String, dynamic> json) {
    return DashboardDocument(
      id: J.intOr(json['id'], 0),
      originalFilename: J.str(json['original_filename']),
      documentType: J.str(json['document_type']),
      status: J.str(json['status']),
      errorMessage: J.str(json['error_message']),
      pageCount: J.intOr(json['page_count'], 0),
      transactionsCount: J.intOrNull(json['transactions_count']),
      approvedTransactionsCount:
          J.intOrNull(json['approved_transactions_count']),
      recordsCount: J.intOrNull(json['records_count']),
      approvedRecordsCount: J.intOrNull(json['approved_records_count']),
      exportsCount: J.intOrNull(json['exports_count']),
      createdAt: J.date(json['created_at']),
    );
  }

  final int id;
  final String? originalFilename;

  /// `bank_statement`, `invoice` or `generic_pdf`.
  final String? documentType;

  /// `uploaded`, `processing`, `processed`, `pending_review` or `failed`.
  final String? status;

  /// Already made human by `DocumentResource::friendlyError()`.
  final String? errorMessage;

  final int pageCount;

  /// Null means "not counted in this response", which is different from zero.
  final int? transactionsCount;
  final int? approvedTransactionsCount;
  final int? recordsCount;
  final int? approvedRecordsCount;
  final int? exportsCount;

  final DateTime? createdAt;

  /// A statement carries transactions, everything else carries records; the
  /// list row wants whichever the document actually has.
  int? get rowCount => transactionsCount ?? recordsCount;

  int? get approvedCount =>
      approvedTransactionsCount ?? approvedRecordsCount;

  bool get isFailed => status == 'failed';

  bool get isWorking =>
      status == 'processing' || status == 'queued' || status == 'uploaded';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DashboardDocument &&
          other.id == id &&
          other.originalFilename == originalFilename &&
          other.documentType == documentType &&
          other.status == status &&
          other.errorMessage == errorMessage &&
          other.pageCount == pageCount &&
          other.transactionsCount == transactionsCount &&
          other.approvedTransactionsCount == approvedTransactionsCount &&
          other.recordsCount == recordsCount &&
          other.approvedRecordsCount == approvedRecordsCount &&
          other.exportsCount == exportsCount &&
          other.createdAt == createdAt;

  @override
  int get hashCode => Object.hash(
        id,
        originalFilename,
        documentType,
        status,
        errorMessage,
        pageCount,
        transactionsCount,
        approvedTransactionsCount,
        recordsCount,
        approvedRecordsCount,
        exportsCount,
        createdAt,
      );

  @override
  String toString() => 'DashboardDocument($id, $status)';
}

@immutable
class DashboardData {
  const DashboardData({
    required this.plan,
    required this.companyId,
    required this.companyName,
    required this.usedPages,
    required this.monthlyPageLimit,
    required this.teamSize,
    required this.employeeLimit,
    required this.profileCount,
    required this.profileLimit,
    required this.pendingReviews,
    required this.completedExports,
    required this.webExtractionJobs,
    required this.webEmailsFound,
    required this.totalDocuments,
    required this.processedDocuments,
    required this.failedDocuments,
    required this.latestDocuments,
  });

  factory DashboardData.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic> root =
        J.map(json['data']).isEmpty ? json : J.map(json['data']);

    return DashboardData(
      // A platform admin has no workspace; the controller labels that 'admin'
      // rather than pretending they are on the free plan.
      plan: J.strOr(root['plan'], 'free'),
      companyId: J.intOrNull(root['company_id']),
      companyName: J.str(root['company_name']),
      usedPages: J.intOr(root['used_pages'], 0),
      monthlyPageLimit: J.intOr(root['monthly_page_limit'], 0),
      teamSize: J.intOr(root['team_size'], 0),
      employeeLimit: J.intOr(root['employee_limit'], 0),
      profileCount: J.intOr(root['profile_count'], 0),
      profileLimit: J.intOr(root['profile_limit'], 0),
      pendingReviews: J.intOr(root['pending_reviews'], 0),
      completedExports: J.intOr(root['completed_exports'], 0),
      webExtractionJobs: J.intOr(root['web_extraction_jobs'], 0),
      webEmailsFound: J.intOr(root['web_emails_found'], 0),
      totalDocuments: J.intOr(root['total_documents'], 0),
      processedDocuments: J.intOr(root['processed_documents'], 0),
      failedDocuments: J.intOr(root['failed_documents'], 0),
      latestDocuments: List<DashboardDocument>.unmodifiable(
        J.list(root['latest_documents']).map(DashboardDocument.fromJson),
      ),
    );
  }

  /// Plan key, or `admin` for a platform account with no workspace.
  final String plan;

  final int? companyId;
  final String? companyName;

  final int usedPages;
  final int monthlyPageLimit;

  final int teamSize;
  final int employeeLimit;

  final int profileCount;
  final int profileLimit;

  /// Rows waiting in the review queue. Doubles as the review tab's badge.
  final int pendingReviews;

  final int completedExports;
  final int webExtractionJobs;
  final int webEmailsFound;

  final int totalDocuments;
  final int processedDocuments;
  final int failedDocuments;

  /// The five most recent documents, newest first.
  final List<DashboardDocument> latestDocuments;

  bool get isEmptyWorkspace => totalDocuments == 0;

  List<Object?> get _scalars => <Object?>[
        plan,
        companyId,
        companyName,
        usedPages,
        monthlyPageLimit,
        teamSize,
        employeeLimit,
        profileCount,
        profileLimit,
        pendingReviews,
        completedExports,
        webExtractionJobs,
        webEmailsFound,
        totalDocuments,
        processedDocuments,
        failedDocuments,
      ];

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DashboardData &&
          listEquals(other._scalars, _scalars) &&
          listEquals(other.latestDocuments, latestDocuments);

  @override
  int get hashCode =>
      Object.hash(Object.hashAll(_scalars), Object.hashAll(latestDocuments));

  @override
  String toString() =>
      'DashboardData($plan, documents: $totalDocuments, '
      'pending: $pendingReviews)';
}
