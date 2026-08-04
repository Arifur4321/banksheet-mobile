/// Tests for the document feature's two load-bearing pieces of logic: the
/// parsers, and the on-device PDF writer.
///
/// The parsers are tested against payloads shaped exactly like the ones
/// `DocumentDetailResource` and `TransactionResource` emit — including the two
/// cases that actually break clients in the field: a failed document, and a
/// document where every optional field is null. The mobile API promises never to
/// drop a key, and these tests are what that promise is worth on this side.
///
/// The PDF writer is tested because it is the one place in this app that
/// produces a binary format by hand, and because a malformed PDF fails silently
/// — it uploads happily and comes back as a failed extraction an hour later.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:banksheet_mobile/features/documents/data/image_pdf_builder.dart';
import 'package:banksheet_mobile/features/documents/domain/document.dart';
import 'package:banksheet_mobile/features/documents/domain/transaction.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// A realistic `GET /documents/{id}` body for a processed bank statement.
Map<String, dynamic> _processedStatement() => <String, dynamic>{
      'document': <String, dynamic>{
        'id': 412,
        'original_filename': 'intesa-marzo-2025.pdf',
        'document_type': 'bank_statement',
        'status': 'processed',
        'error_message': null,
        'mime_type': 'application/pdf',
        'file_size': 284913,
        'page_count': 4,
        'is_pdf': true,
        'uploaded_by': <String, dynamic>{'id': 7, 'name': 'Giulia Rossi'},
        'extraction_profile': <String, dynamic>{
          'id': 3,
          'name': 'Intesa Sanpaolo — conto ordinario',
          'bank_name': 'Intesa Sanpaolo',
        },
        'transactions_count': 62,
        'approved_transactions_count': 40,
        'records_count': 62,
        'approved_records_count': 40,
        'exports_count': 1,
        'created_at': '2025-04-02T09:14:22+02:00',
        'updated_at': '2025-04-02T09:16:04+02:00',
        'statement_summary': <String, dynamic>{
          'confidence': 'high',
          'engine': 'pdftotext-layout',
          'matched_profile': 'Intesa Sanpaolo — conto ordinario',
          'bank_name': 'Intesa Sanpaolo',
          'account_holder': 'Rossi Giulia',
          'iban_masked': '••••••••4471',
          'account_number_masked': '••••1234',
          'account_display': '••••••••4471',
          'bic': 'BCITITMM',
          'branch': 'Milano Duomo',
          'currency': 'EUR',
          'period': <String, dynamic>{
            'start': '2025-03-01',
            'end': '2025-03-31',
            'label': '01/03/2025 - 31/03/2025',
          },
          'opening_balance': 2410.55,
          'closing_balance': 3188.02,
          'totals': <String, dynamic>{
            'transaction_count': 62,
            'total_debits': 4211.9,
            'total_credits': 4989.37,
            'net_change': 777.47,
          },
          'reconciliation': <String, dynamic>{
            'status': 'balanced',
            'statement_balanced': true,
            'opening_balance': 2410.55,
            'closing_balance': 3188.02,
            'expected_net_change': 777.47,
            'computed_net_change': 777.47,
            'discrepancy': 0.0,
            'rows_checked': 62,
            'rows_matched': 62,
            'rows_flagged': 0,
          },
          'needs_review_count': 3,
          'records_count': 62,
          'transactions_count': 62,
          'warnings': <String>['Two rows had no value date'],
          'ocr_warnings': <String>[],
        },
        'latest_extraction_job': <String, dynamic>{
          'id': 980,
          'document_id': 412,
          'status': 'completed',
          'error_message': null,
          'started_at': '2025-04-02T09:14:30+02:00',
          'finished_at': '2025-04-02T09:16:04+02:00',
          'ocr_status': 'skipped',
          'ocr_driver': null,
          'matched_profile_score': 0.94,
          'matched_profile': 'Intesa Sanpaolo — conto ordinario',
          'match_reasons': <String>['IBAN prefix', 'header keywords'],
          'engine': 'pdftotext-layout',
          'records_count': 62,
          'transactions_count': 62,
          'needs_review_count': 3,
          'warnings': <String>[],
          'created_at': '2025-04-02T09:14:25+02:00',
          'updated_at': '2025-04-02T09:16:04+02:00',
        },
        'exports': <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 55,
            'document_id': 412,
            'document': <String, dynamic>{
              'id': 412,
              'original_filename': 'intesa-marzo-2025.pdf',
            },
            'created_by': <String, dynamic>{'id': 7, 'name': 'Giulia Rossi'},
            'export_type': 'xlsx',
            'status': 'completed',
            'record_count': 40,
            'filename': 'intesa-marzo-2025-55.xlsx',
            'file_size': 18422,
            'is_available': true,
            'download_url':
                'https://banksheet.pro/api/mobile/v1/exports/55/download',
            'generated_at': '2025-04-02T10:02:00+02:00',
            'created_at': '2025-04-02T10:02:00+02:00',
          },
        ],
        'review_counts': <String, dynamic>{
          'total': 62,
          'approved': 40,
          'pending': 20,
          'rejected': 2,
        },
        'stored_page_count': 4,
      },
      'transactions': <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 9001,
          'document_id': 412,
          'document': <String, dynamic>{
            'id': 412,
            'original_filename': 'intesa-marzo-2025.pdf',
            'document_type': 'bank_statement',
          },
          'position': 1,
          'transaction_date': '2025-03-03',
          'value_date': '2025-03-04',
          'description': 'BONIFICO DA ACME SRL',
          'reference': 'TRN-99182',
          'counterparty': 'ACME SRL',
          'category': 'income',
          'debit': null,
          'credit': 1500.0,
          'amount_signed': 1500.0,
          'balance': 3910.55,
          'currency': 'EUR',
          'confidence': 'certain',
          'review_status': 'approved',
          'needs_review': false,
          'is_reconciled': true,
          'source_page': 1,
          'source_line': '03/03 04/03 BONIFICO DA ACME SRL 1.500,00 3.910,55',
          'validation_flags': <String>[],
          'reviewed_at': '2025-04-02T11:00:00+02:00',
          'reviewed_by': <String, dynamic>{'id': 7, 'name': 'Giulia Rossi'},
          'extraction_profile': <String, dynamic>{
            'id': 3,
            'name': 'Intesa Sanpaolo — conto ordinario',
          },
          'created_at': '2025-04-02T09:16:00+02:00',
          'updated_at': '2025-04-02T11:00:00+02:00',
        },
        <String, dynamic>{
          'id': 9002,
          'document_id': 412,
          'document': null,
          'position': 2,
          'transaction_date': '2025-03-05',
          'value_date': null,
          'description': 'PAGAMENTO POS 0512',
          'reference': null,
          'counterparty': null,
          'category': null,
          'debit': 42.9,
          'credit': null,
          'amount_signed': -42.9,
          'balance': 3867.65,
          'currency': 'EUR',
          'confidence': 'low',
          'review_status': 'pending_review',
          'needs_review': true,
          'is_reconciled': false,
          'source_page': 1,
          'source_line': '05/03 PAGAMENTO POS 0512 42,90 3.867,65',
          'validation_flags': <String>['balance_drift'],
          'reviewed_at': null,
          'reviewed_by': null,
          'extraction_profile': null,
          'created_at': '2025-04-02T09:16:00+02:00',
          'updated_at': '2025-04-02T09:16:00+02:00',
        },
      ],
      'transactions_meta': <String, dynamic>{
        'current_page': 1,
        'last_page': 1,
        'per_page': 100,
        'total': 2,
        'has_more': false,
      },
    };

/// A document the pipeline could not process. Everything derived is absent.
Map<String, dynamic> _failedDocument() => <String, dynamic>{
      'document': <String, dynamic>{
        'id': 77,
        'original_filename': 'scan.zip',
        'document_type': 'generic_pdf',
        'status': 'failed',
        'error_message':
            'Processing not supported yet for JPG, PNG, or ZIP uploads. '
                'The file was saved successfully.',
        'mime_type': 'application/zip',
        'file_size': 91234,
        'page_count': 0,
        'is_pdf': false,
        'uploaded_by': null,
        'extraction_profile': null,
        'transactions_count': 0,
        'approved_transactions_count': 0,
        'records_count': 0,
        'approved_records_count': 0,
        'exports_count': 0,
        'created_at': '2025-04-02T09:14:22+02:00',
        'updated_at': '2025-04-02T09:14:23+02:00',
        'statement_summary': null,
        'latest_extraction_job': null,
        'exports': <Map<String, dynamic>>[],
        'review_counts': <String, dynamic>{
          'total': 0,
          'approved': 0,
          'pending': 0,
          'rejected': 0,
        },
        'stored_page_count': null,
      },
      'transactions': <Map<String, dynamic>>[],
      'transactions_meta': <String, dynamic>{
        'current_page': 1,
        'last_page': 1,
        'per_page': 100,
        'total': 0,
        'has_more': false,
      },
    };

/// Every optional field null, every list empty. Nothing here may throw.
Map<String, dynamic> _nullHeavyDocument() => <String, dynamic>{
      'document': <String, dynamic>{
        'id': 5,
        'original_filename': null,
        'document_type': null,
        'status': null,
        'error_message': null,
        'mime_type': null,
        'file_size': null,
        'page_count': 0,
        'is_pdf': false,
        'uploaded_by': null,
        'extraction_profile': null,
        'transactions_count': null,
        'approved_transactions_count': null,
        'records_count': null,
        'approved_records_count': null,
        'exports_count': null,
        'created_at': null,
        'updated_at': null,
        'statement_summary': null,
        'latest_extraction_job': null,
        'exports': <Map<String, dynamic>>[],
        'review_counts': <String, dynamic>{
          'total': null,
          'approved': null,
          'pending': null,
          'rejected': null,
        },
        'stored_page_count': null,
      },
      'transactions': <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 1,
          'document_id': null,
          'document': null,
          'position': null,
          'transaction_date': null,
          'value_date': null,
          'description': null,
          'reference': null,
          'counterparty': null,
          'category': null,
          'debit': null,
          'credit': null,
          'amount_signed': null,
          'balance': null,
          'currency': null,
          'confidence': null,
          'review_status': null,
          'needs_review': false,
          'is_reconciled': false,
          'source_page': null,
          'source_line': null,
          'validation_flags': <String>[],
          'reviewed_at': null,
          'reviewed_by': null,
          'extraction_profile': null,
          'created_at': null,
          'updated_at': null,
        },
      ],
      'transactions_meta': <String, dynamic>{},
    };

/// A tiny image encoded as PNG, so the builder exercises its real decode path.
Uint8List _sourceImage({required int width, required int height}) {
  final img.Image image = img.Image(width: width, height: height);
  for (int y = 0; y < height; y++) {
    for (int x = 0; x < width; x++) {
      image.setPixelRgb(x, y, (x * 7) % 256, (y * 11) % 256, 128);
    }
  }
  return img.encodePng(image);
}

void main() {
  group('DocumentStatus', () {
    test('parses every status the server can send', () {
      expect(DocumentStatus.from('uploaded'), DocumentStatus.uploaded);
      expect(DocumentStatus.from('queued'), DocumentStatus.queued);
      expect(DocumentStatus.from('processing'), DocumentStatus.processing);
      expect(DocumentStatus.from('processed'), DocumentStatus.processed);
      expect(DocumentStatus.from('failed'), DocumentStatus.failed);
    });

    test('an unknown or absent status parses to unknown', () {
      expect(DocumentStatus.from(null), DocumentStatus.unknown);
      expect(DocumentStatus.from(''), DocumentStatus.unknown);
      expect(DocumentStatus.from('archived'), DocumentStatus.unknown);
    });

    test('the working set matches the server poll condition exactly', () {
      expect(DocumentStatus.uploaded.isWorking, isTrue);
      expect(DocumentStatus.queued.isWorking, isTrue);
      expect(DocumentStatus.processing.isWorking, isTrue);
      expect(DocumentStatus.processed.isWorking, isFalse);
      expect(DocumentStatus.failed.isWorking, isFalse);
    });

    test('isFinished is the complement of isWorking, so polling always stops',
        () {
      for (final DocumentStatus status in DocumentStatus.values) {
        expect(status.isFinished, !status.isWorking, reason: status.wire);
      }
      // Including a status this build has never heard of.
      expect(DocumentStatus.unknown.isFinished, isTrue);
    });

    test('isFailed is true only for failed', () {
      expect(DocumentStatus.failed.isFailed, isTrue);
      expect(
        DocumentStatus.values
            .where((DocumentStatus s) => s.isFailed)
            .toList(growable: false),
        <DocumentStatus>[DocumentStatus.failed],
      );
    });
  });

  group('DocumentDetail — processed bank statement', () {
    late DocumentDetail detail;

    setUp(() => detail = DocumentDetail.fromJson(_processedStatement()));

    test('parses the document header', () {
      expect(detail.id, 412);
      expect(detail.displayName, 'intesa-marzo-2025.pdf');
      expect(detail.state, DocumentStatus.processed);
      expect(detail.kind, DocumentKind.bankStatement);
      expect(detail.isBankStatement, isTrue);
      expect(detail.isPdf, isTrue);
      expect(detail.summary.pageCount, 4);
      expect(detail.summary.fileSize, 284913);
      expect(detail.summary.uploadedBy?.name, 'Giulia Rossi');
      expect(detail.summary.extractionProfile?.id, 3);
      expect(detail.summary.extractionProfile?.bankName, 'Intesa Sanpaolo');
      expect(detail.storedPageCount, 4);
      expect(detail.summary.createdAt, isNotNull);
    });

    test('parses the statement summary, masked account included', () {
      final StatementSummary summary = detail.statementSummary!;
      expect(summary.confidence, ConfidenceLevel.high);
      expect(summary.bankName, 'Intesa Sanpaolo');
      expect(summary.accountHolder, 'Rossi Giulia');
      // Masked server-side: the full IBAN must never reach the device.
      expect(summary.accountDisplay, '••••••••4471');
      expect(summary.currency, 'EUR');
      expect(summary.period.start, DateTime(2025, 3));
      expect(summary.period.end, DateTime(2025, 3, 31));
      expect(summary.openingBalance, 2410.55);
      expect(summary.closingBalance, 3188.02);
      expect(summary.totals.transactionCount, 62);
      expect(summary.totals.netChange, 777.47);
      expect(summary.warnings, <String>['Two rows had no value date']);
      expect(summary.ocrWarnings, isEmpty);
    });

    test('reads the reconciliation as balanced', () {
      final ReconciliationInfo info = detail.statementSummary!.reconciliation;
      expect(info.isKnown, isTrue);
      expect(info.isBalanced, isTrue);
      expect(info.discrepancy, 0.0);
      expect(info.rowsChecked, 62);
      expect(info.rowsFlagged, 0);
    });

    test('parses the latest extraction job', () {
      final ExtractionJobInfo job = detail.latestJob!;
      expect(job.id, 980);
      expect(job.status, 'completed');
      expect(job.engine, 'pdftotext-layout');
      expect(job.matchedProfileScore, 0.94);
      expect(job.matchReasons, hasLength(2));
      expect(job.usedOcr, isFalse);
      expect(job.duration, const Duration(minutes: 1, seconds: 34));
    });

    test('parses exports and review counts', () {
      expect(detail.exports, hasLength(1));
      expect(detail.exports.first.filename, 'intesa-marzo-2025-55.xlsx');
      expect(detail.exports.first.isAvailable, isTrue);
      expect(detail.reviewCounts.total, 62);
      expect(detail.reviewCounts.approved, 40);
      expect(detail.reviewCounts.hasPending, isTrue);
      expect(detail.reviewCounts.approvedRatio, closeTo(40 / 62, 0.0001));
    });

    test('parses the first page of transactions', () {
      final List<ExtractedTransaction> rows = detail.transactions.items;
      expect(rows, hasLength(2));
      expect(detail.transactions.meta.hasMore, isFalse);

      final ExtractedTransaction credit = rows.first;
      expect(credit.confidence, ConfidenceLevel.certain);
      expect(credit.reviewStatus, ReviewStatus.approved);
      expect(credit.isOpen, isFalse);
      expect(credit.isCredit, isTrue);
      expect(credit.signedAmount, 1500.0);
      expect(credit.balance, 3910.55);
      expect(credit.document?.id, 412);
      expect(credit.reviewedBy?.name, 'Giulia Rossi');
      expect(credit.extractionProfileId, 3);
      expect(credit.isSuspicious, isFalse);

      final ExtractedTransaction debit = rows[1];
      expect(debit.confidence, ConfidenceLevel.low);
      expect(debit.reviewStatus, ReviewStatus.pendingReview);
      expect(debit.isOpen, isTrue);
      expect(debit.isCredit, isFalse);
      expect(debit.signedAmount, -42.9);
      expect(debit.validationFlags, <String>['balance_drift']);
      expect(debit.isSuspicious, isTrue);
      expect(debit.document, isNull);
    });

    test('value equality holds across two parses of the same payload', () {
      expect(DocumentDetail.fromJson(_processedStatement()), detail);
      expect(
        DocumentDetail.fromJson(_processedStatement()).hashCode,
        detail.hashCode,
      );
    });

    test('copyWith replaces only what it is given', () {
      final DocumentDetail renamed = detail.copyWith(
        summary: detail.summary.copyWith(originalFilename: 'renamed.pdf'),
      );
      expect(renamed.displayName, 'renamed.pdf');
      expect(renamed.statementSummary, detail.statementSummary);
      expect(renamed.reviewCounts, detail.reviewCounts);
      expect(renamed, isNot(detail));
    });
  });

  group('DocumentDetail — failed document', () {
    late DocumentDetail detail;

    setUp(() => detail = DocumentDetail.fromJson(_failedDocument()));

    test('carries the server error message through verbatim', () {
      expect(detail.state, DocumentStatus.failed);
      expect(detail.state.isFailed, isTrue);
      expect(detail.state.isFinished, isTrue);
      expect(detail.errorMessage, contains('not supported yet'));
    });

    test('has nothing derived from it', () {
      expect(detail.statementSummary, isNull);
      expect(detail.latestJob, isNull);
      expect(detail.exports, isEmpty);
      expect(detail.transactions.items, isEmpty);
      expect(detail.isPdf, isFalse);
      expect(detail.reviewCounts.hasPending, isFalse);
      expect(detail.reviewCounts.approvedRatio, 0);
    });
  });

  group('DocumentDetail — null-heavy payload', () {
    late DocumentDetail detail;

    setUp(() => detail = DocumentDetail.fromJson(_nullHeavyDocument()));

    test('every absent field degrades instead of throwing', () {
      expect(detail.id, 5);
      expect(detail.summary.originalFilename, isNull);
      expect(detail.displayName, isNotEmpty);
      expect(detail.state, DocumentStatus.unknown);
      expect(detail.summary.fileSize, isNull);
      expect(detail.summary.createdAt, isNull);
      expect(detail.summary.transactionsCount, isNull);
      expect(detail.summary.unapprovedCount, 0);
      expect(detail.summary.needsReview, isFalse);
      expect(detail.storedPageCount, isNull);
    });

    test('an unreadable document type falls back to bank statement', () {
      // The server's own default when `document_type` is omitted on upload.
      expect(detail.kind, DocumentKind.bankStatement);
    });

    test('a row with no values still parses', () {
      final ExtractedTransaction row = detail.transactions.items.single;
      expect(row.id, 1);
      // The server's own fallback bucket for an unreadable score.
      expect(row.confidence, ConfidenceLevel.medium);
      // A row whose state we cannot read still needs a human.
      expect(row.reviewStatus, ReviewStatus.pendingReview);
      expect(row.signedAmount, isNull);
      expect(row.displayDescription, isNotEmpty);
      expect(row.validationFlags, isEmpty);
    });

    test('missing pagination metadata falls back to a single page', () {
      expect(detail.transactions.meta.currentPage, 1);
      expect(detail.transactions.meta.hasMore, isFalse);
    });
  });

  group('DocumentStatusInfo', () {
    test('settles when the server withdraws the poll hint', () {
      final DocumentStatusInfo done =
          DocumentStatusInfo.fromJson(<String, dynamic>{
        'id': 412,
        'status': 'processed',
        'error_message': null,
        'transactions_count': 62,
        'pending_count': 20,
        'poll_after_seconds': null,
      });
      expect(done.state, DocumentStatus.processed);
      expect(done.isSettled, isTrue);
    });

    test('keeps polling while the server still asks for it', () {
      final DocumentStatusInfo working =
          DocumentStatusInfo.fromJson(<String, dynamic>{
        'id': 412,
        'status': 'processing',
        'error_message': null,
        'transactions_count': 12,
        'pending_count': 12,
        'poll_after_seconds': 2,
      });
      expect(working.state.isWorking, isTrue);
      expect(working.isSettled, isFalse);
    });

    test('a failed poll settles even though it still carries a hint', () {
      final DocumentStatusInfo failed =
          DocumentStatusInfo.fromJson(<String, dynamic>{
        'id': 412,
        'status': 'failed',
        'error_message': 'Could not read the PDF.',
        'transactions_count': 0,
        'pending_count': 0,
        'poll_after_seconds': 2,
      });
      expect(failed.isSettled, isTrue);
      expect(failed.errorMessage, 'Could not read the PDF.');
    });
  });

  group('TransactionEdit', () {
    test('a status-only change sends nothing else', () {
      final Map<String, dynamic> body =
          TransactionEdit.statusOnly(ReviewStatus.approved).toJson();
      expect(body, <String, dynamic>{'review_status': 'approved'});
    });

    test('a full edit sends every column, nulls included, so clearing works',
        () {
      final Map<String, dynamic> body = TransactionEdit.full(
        reviewStatus: ReviewStatus.edited,
        transactionDate: DateTime(2025, 3, 7),
        valueDate: null,
        description: 'Corrected description',
        reference: null,
        counterparty: 'ACME SRL',
        category: null,
        debit: 12.5,
        credit: null,
        balance: 100.0,
        currency: 'EUR',
      ).toJson();

      expect(body['review_status'], 'edited');
      // Date-only, matching NormalizesValues::isoDate().
      expect(body['transaction_date'], '2025-03-07');
      expect(body.containsKey('value_date'), isTrue);
      expect(body['value_date'], isNull);
      expect(body.containsKey('reference'), isTrue);
      expect(body['reference'], isNull);
      expect(body['debit'], 12.5);
      expect(body['currency'], 'EUR');
    });
  });

  group('ImagePdfBuilder', () {
    test('produces a file that starts with the PDF magic number', () {
      final Uint8List pdf = ImagePdfBuilder.buildFromBytes(<Uint8List>[
        _sourceImage(width: 40, height: 60),
      ]);

      expect(pdf.length, greaterThan(200));
      expect(latin1.decode(pdf.sublist(0, 5)), '%PDF-');
      expect(latin1.decode(pdf.sublist(pdf.length - 6)).trim(), '%%EOF');
    });

    test('writes exactly one page object per source image', () {
      for (final int pages in <int>[1, 2, 5]) {
        final Uint8List pdf = ImagePdfBuilder.buildFromBytes(<Uint8List>[
          for (int i = 0; i < pages; i++)
            _sourceImage(width: 30 + i, height: 40 + i),
        ]);
        final String body = latin1.decode(pdf, allowInvalid: true);

        // `(?!s)` keeps the single `/Type /Pages` tree node out of the count.
        expect(
          RegExp(r'/Type /Page(?!s)').allMatches(body).length,
          pages,
          reason: '$pages source images should yield $pages page objects',
        );
        expect(RegExp(r'/Type /Pages').allMatches(body), hasLength(1));
        expect(body, contains('/Count $pages'));
        // One embedded JPEG per page, and never a re-encoded raw bitmap.
        expect(
          RegExp(r'/Filter /DCTDecode').allMatches(body).length,
          pages,
        );
      }
    });

    test('the cross reference table names every object it declares', () {
      final Uint8List pdf = ImagePdfBuilder.buildFromBytes(<Uint8List>[
        _sourceImage(width: 40, height: 60),
        _sourceImage(width: 60, height: 40),
      ]);
      final String body = latin1.decode(pdf, allowInvalid: true);

      // Catalog + page tree + three objects per page.
      const int expectedObjects = 2 + 3 * 2;
      expect(body, contains('xref\n0 ${expectedObjects + 1}\n'));
      expect(body, contains('/Size ${expectedObjects + 1}'));
      expect(body, contains('/Root 1 0 R'));
      expect(body, contains('startxref'));

      // Every entry in the table is exactly 20 bytes, which is what lets a
      // reader seek into it by multiplication.
      //
      // `\nxref\n` rather than `xref\n`: the latter also matches inside
      // `startxref`, and could in principle occur inside the JPEG data above.
      const String header = 'xref\n0 ${expectedObjects + 1}\n';
      final int start = body.lastIndexOf('\nxref\n') + 1;
      final int end = body.indexOf('trailer', start);
      expect(start, greaterThan(0));
      expect(end, greaterThan(start));

      final String table = body.substring(start + header.length, end);
      expect(table.length, (expectedObjects + 1) * 20);
    });

    test('caps the long edge so a ten page scan stays inside the upload limit',
        () {
      // Comfortably over the cap, to prove it is enforced rather than merely
      // unnecessary.
      final ScannedPage page = ImagePdfBuilder.normalise(
        _sourceImage(width: 2400, height: 1800),
        1,
      );

      expect(page.width, ImagePdfBuilder.maxEdge);
      expect(page.height, 1200);
      expect(page.isPortrait, isFalse);
      // JPEG, not PNG — the PDF embeds these bytes with /DCTDecode.
      expect(page.jpeg.sublist(0, 2), <int>[0xFF, 0xD8]);
    });

    test('a page already under the cap is not upscaled', () {
      final ScannedPage page = ImagePdfBuilder.normalise(
        _sourceImage(width: 800, height: 1000),
        1,
      );
      expect(page.width, 800);
      expect(page.height, 1000);
      expect(page.isPortrait, isTrue);
    });

    test('ten capped pages stay well inside the server upload limit', () {
      // Three real pages, then extrapolated: enough to measure what an embedded
      // JPEG plus its page objects actually costs, without decoding thirty
      // megapixels inside a unit test.
      final Uint8List source = _sourceImage(width: 2000, height: 1500);
      final Uint8List pdf = ImagePdfBuilder.buildFromBytes(
        <Uint8List>[source, source, source],
      );
      final int perPage = pdf.length ~/ 3;

      // The server rejects anything over 20 MB (`max:20480`, in kilobytes).
      expect(perPage * 10, lessThan(20480 * 1024));
    });

    test('an undecodable capture names the page that failed', () {
      expect(
        () => ImagePdfBuilder.buildFromBytes(<Uint8List>[
          _sourceImage(width: 10, height: 10),
          Uint8List.fromList(<int>[1, 2, 3, 4]),
        ]),
        throwsA(
          isA<ImagePdfException>()
              .having((ImagePdfException e) => e.pageNumber, 'pageNumber', 2),
        ),
      );
    });
  });
}
