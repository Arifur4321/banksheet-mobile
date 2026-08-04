/// Tests for company-data extraction: the three resource parsers, the progress
/// arithmetic the screens draw a bar from, and the domain-list parser.
///
/// The parser is the one piece of this feature that decides what a job costs —
/// one scan per resolvable website — so it is tested against the shapes people
/// actually paste: a column copied out of a spreadsheet, full URLs with paths,
/// a stray email address, and the same company twice.
library;

import 'package:banksheet_mobile/features/web_extraction/domain/web_job.dart';
import 'package:flutter_test/flutter_test.dart';

/// A realistic `WebExtractionJobResource` body for a running job.
Map<String, dynamic> _job({
  String status = 'processing',
  int total = 50,
  int completed = 18,
  int failed = 3,
  bool finished = false,
}) {
  final int processed = completed + failed;
  return <String, dynamic>{
    'id': 88,
    'title': 'Milan suppliers',
    'status': status,
    'input_type': 'paste',
    'original_filename': null,
    'total_targets': total,
    'completed_targets': completed,
    'failed_targets': failed,
    'processed_targets': processed > total ? total : processed,
    'progress_percent':
        total > 0 ? ((processed > total ? total : processed) / total * 100).round() : 0,
    'emails_found_count': 34,
    'career_pages_found_count': 6,
    'max_pages_per_target': 12,
    'warning_message': null,
    'error_message': null,
    'is_finished': finished,
    'exports': <String, dynamic>{
      'xlsx': finished
          ? 'https://banksheet.pro/api/mobile/v1/web-extractions/88/export/xlsx'
          : null,
      'csv': finished
          ? 'https://banksheet.pro/api/mobile/v1/web-extractions/88/export/csv'
          : null,
    },
    'poll_after_seconds': finished ? null : 5,
    'created_by': <String, dynamic>{'id': 7, 'name': 'Giulia Rossi'},
    'created_at': '2025-04-02T09:14:22+02:00',
    'started_at': '2025-04-02T09:14:30+02:00',
    'completed_at': null,
    'cancelled_at': null,
  };
}

/// A completed target with a full result attached.
Map<String, dynamic> _target() => <String, dynamic>{
      'id': 4021,
      'input_name': 'Rossi Impianti Srl',
      'input_value': 'https://rossimpianti.it/',
      'domain': 'rossimpianti.it',
      'url': 'https://rossimpianti.it',
      'status': 'completed',
      'http_status': 200,
      'pages_scanned': 9,
      'emails_found_count': 2,
      'confidence_score': 84,
      'error_message': null,
      'warning_message': null,
      'started_at': '2025-04-02T09:15:02+02:00',
      'completed_at': '2025-04-02T09:15:41+02:00',
      'result': <String, dynamic>{
        'company_name': 'Rossi Impianti Srl',
        'website': 'https://rossimpianti.it',
        'emails': <Map<String, dynamic>>[
          <String, dynamic>{
            'value': 'info@rossimpianti.it',
            'category': 'generic',
            'source_url': 'https://rossimpianti.it/contatti',
            'source_urls': <String>[
              'https://rossimpianti.it/contatti',
              'https://rossimpianti.it/',
            ],
          },
          <String, dynamic>{
            'value': 'hr@rossimpianti.it',
            'category': 'role',
            // One page only: the server still sends the list, but this covers
            // the shape where it does not.
            'source_url': 'https://rossimpianti.it/lavora-con-noi',
            'source_urls': <String>[],
          },
        ],
        'pec_emails': <Map<String, dynamic>>[
          <String, dynamic>{
            'value': 'rossimpianti@pec.it',
            'category': 'pec',
            'source_url': 'https://rossimpianti.it/contatti',
            'source_urls': <String>['https://rossimpianti.it/contatti'],
          },
        ],
        'phones': <Map<String, dynamic>>[
          <String, dynamic>{
            'value': '+39 02 1234567',
            'source_url': 'https://rossimpianti.it/contatti',
            'source_urls': <String>['https://rossimpianti.it/contatti'],
          },
        ],
        'mobiles': <Map<String, dynamic>>[
          <String, dynamic>{
            'value': '+39 345 9876543',
            'source_url': 'https://rossimpianti.it/contatti',
            'source_urls': <String>['https://rossimpianti.it/contatti'],
          },
        ],
        'vat_numbers': <Map<String, dynamic>>[
          <String, dynamic>{
            'value': 'IT01234567890',
            'source_url': 'https://rossimpianti.it/',
            'source_urls': <String>['https://rossimpianti.it/'],
          },
        ],
        'tax_codes': <Map<String, dynamic>>[],
        'addresses': <Map<String, dynamic>>[
          <String, dynamic>{
            'value': 'Via Roma 1',
            'city': 'Milano',
            'province': 'MI',
            'country': 'IT',
            'source_url': 'https://rossimpianti.it/contatti',
            'source_urls': <String>['https://rossimpianti.it/contatti'],
          },
        ],
        'career_pages': <Map<String, dynamic>>[
          <String, dynamic>{
            'url': 'https://rossimpianti.it/lavora-con-noi',
            'source_url': 'https://rossimpianti.it/',
            'source_urls': <String>['https://rossimpianti.it/'],
          },
        ],
        'contact_pages': <Map<String, dynamic>>[],
        'about_pages': <Map<String, dynamic>>[],
        'privacy_pages': <Map<String, dynamic>>[],
        'people': <Map<String, dynamic>>[
          <String, dynamic>{
            'name': 'Marco Rossi',
            'role': 'Direttore tecnico',
            'email': null,
            'source_url': 'https://rossimpianti.it/azienda',
            'source_urls': <String>['https://rossimpianti.it/azienda'],
          },
          // Neither a name nor a role: dropped rather than rendered blank.
          <String, dynamic>{
            'name': null,
            'role': null,
            'email': null,
            'source_url': null,
            'source_urls': <String>[],
          },
        ],
        'social_links': <Map<String, dynamic>>[
          <String, dynamic>{
            'network': 'linkedin',
            'url': 'https://www.linkedin.com/company/rossimpianti',
            'source_url': 'https://rossimpianti.it/',
            'source_urls': <String>['https://rossimpianti.it/'],
          },
        ],
        'source_urls': <String>[
          'https://rossimpianti.it/',
          'https://rossimpianti.it/contatti',
          'https://rossimpianti.it/azienda',
        ],
        'confidence_score': 84,
        'field_confidence': <String, dynamic>{'emails': 'high'},
        'notes': null,
        'extracted_at': '2025-04-02T09:15:41+02:00',
      },
    };

void main() {
  group('WebExtractionJob', () {
    test('parses a running job', () {
      final WebExtractionJob job = WebExtractionJob.fromJson(_job());

      expect(job.id, 88);
      expect(job.title, 'Milan suppliers');
      expect(job.status, 'processing');
      expect(job.totalTargets, 50);
      expect(job.completedTargets, 18);
      expect(job.failedTargets, 3);
      expect(job.emailsFoundCount, 34);
      expect(job.careerPagesFoundCount, 6);
      expect(job.maxPagesPerTarget, 12);
      expect(job.createdBy, 'Giulia Rossi');
      expect(job.createdAt, DateTime.parse('2025-04-02T09:14:22+02:00'));
    });

    test('computes progress from the server percentage', () {
      final WebExtractionJob job = WebExtractionJob.fromJson(_job());
      // 21 of 50 processed.
      expect(job.processedTargets, 21);
      expect(job.progressPercent, 42);
      expect(job.progress, closeTo(0.42, 0.0001));
    });

    test('clamps a percentage that overshoots mid-refresh', () {
      final Map<String, dynamic> raw = _job()..['progress_percent'] = 104;
      final WebExtractionJob job = WebExtractionJob.fromJson(raw);
      expect(job.progressPercent, 100);
      expect(job.progress, 1.0);
    });

    test('an empty job is 0%, not a division by zero', () {
      final WebExtractionJob job = WebExtractionJob.fromJson(
        _job(total: 0, completed: 0, failed: 0),
      );
      expect(job.progressPercent, 0);
      expect(job.progress, 0.0);
    });

    test('running and finished follow is_finished, not the status word', () {
      final WebExtractionJob running = WebExtractionJob.fromJson(_job());
      expect(running.isRunning, isTrue);
      expect(running.canCancel, isTrue);
      expect(running.canDelete, isFalse);
      expect(running.canExport, isFalse);
      expect(running.pollAfterSeconds, 5);

      final WebExtractionJob done = WebExtractionJob.fromJson(
        _job(status: 'completed', completed: 47, finished: true),
      );
      expect(done.isRunning, isFalse);
      expect(done.canCancel, isFalse);
      expect(done.canDelete, isTrue);
      expect(done.canExport, isTrue);
      expect(done.pollAfterSeconds, isNull);
      expect(done.xlsxUrl, endsWith('/export/xlsx'));
      expect(done.csvUrl, endsWith('/export/csv'));
    });

    test('a job saved with nothing usable is finished with a warning', () {
      final Map<String, dynamic> raw = _job(
        status: 'completed_with_warnings',
        total: 4,
        completed: 0,
        failed: 4,
        finished: true,
      )..['warning_message'] = 'Website/domain required for reliable extraction.';

      final WebExtractionJob job = WebExtractionJob.fromJson(raw);
      expect(job.hasWarnings, isTrue);
      expect(job.isFinished, isTrue);
      expect(job.failedTargets, 4);
    });
  });

  group('WebExtractionTarget', () {
    final WebExtractionTarget target =
        WebExtractionTarget.fromJson(_target());

    test('parses the website and its crawl outcome', () {
      expect(target.id, 4021);
      expect(target.domain, 'rossimpianti.it');
      expect(target.url, 'https://rossimpianti.it');
      expect(target.inputName, 'Rossi Impianti Srl');
      expect(target.httpStatus, 200);
      expect(target.pagesScanned, 9);
      expect(target.confidenceScore, 84);
      expect(target.isDone, isTrue);
      expect(target.isWorking, isFalse);
      expect(target.isRetryable, isFalse);
      expect(target.display, 'rossimpianti.it');
    });

    test('a skipped line keeps what the user typed and is retryable only '
        'when it resolved', () {
      final Map<String, dynamic> raw = _target()
        ..['status'] = 'skipped'
        ..['domain'] = null
        ..['url'] = null
        ..['result'] = null;

      final WebExtractionTarget skipped = WebExtractionTarget.fromJson(raw);
      expect(skipped.isSkipped, isTrue);
      expect(skipped.result, isNull);
      // No normalised URL, so a retry has nothing to fetch.
      expect(skipped.isRetryable, isFalse);
      expect(skipped.display, 'https://rossimpianti.it/');

      final Map<String, dynamic> failedRaw = _target()..['status'] = 'failed';
      expect(WebExtractionTarget.fromJson(failedRaw).isRetryable, isTrue);
    });

    test('a pending target reports itself as working', () {
      final Map<String, dynamic> raw = _target()
        ..['status'] = 'pending'
        ..['result'] = null;
      final WebExtractionTarget pending = WebExtractionTarget.fromJson(raw);
      expect(pending.isWorking, isTrue);
      expect(pending.isDone, isFalse);
    });
  });

  group('WebExtractionResult', () {
    final WebExtractionResult result =
        WebExtractionTarget.fromJson(_target()).result!;

    test('parses every contact group', () {
      expect(result.companyName, 'Rossi Impianti Srl');
      expect(result.emails.map((ContactValue e) => e.value), <String>[
        'info@rossimpianti.it',
        'hr@rossimpianti.it',
      ]);
      expect(result.pecEmails.single.value, 'rossimpianti@pec.it');
      expect(result.phones.single.value, '+39 02 1234567');
      expect(result.mobiles.single.value, '+39 345 9876543');
      expect(result.allPhones, hasLength(2));
      expect(result.vatNumbers.single.value, 'IT01234567890');
      expect(result.taxCodes, isEmpty);
      expect(
        result.careerPages.single.url,
        'https://rossimpianti.it/lavora-con-noi',
      );
      expect(result.socialLinks.single.network, 'linkedin');
      expect(result.sourceUrls, hasLength(3));
      expect(result.confidenceScore, 84);
      expect(result.contactCount, 5);
      expect(result.isEmpty, isFalse);
    });

    test('keeps an address together with its locality', () {
      final ContactValue address = result.addresses.single;
      expect(address.value, 'Via Roma 1');
      expect(address.locality, 'Milano, MI, IT');
    });

    test('drops a person with neither a name nor a role', () {
      expect(result.people, hasLength(1));
      expect(result.people.single.name, 'Marco Rossi');
      expect(result.people.single.display, 'Marco Rossi');
    });

    test('every value carries where it was found', () {
      final ContactValue info = result.emails.first;
      expect(info.provenance.sourceUrl, 'https://rossimpianti.it/contatti');
      expect(info.provenance.sourceUrls, hasLength(2));
      expect(info.provenance.hasMultipleSources, isTrue);

      // Found on one page: source_urls arrived empty, and is rebuilt so the
      // UI never has to branch on it.
      final ContactValue hr = result.emails.last;
      expect(hr.provenance.sourceUrl, 'https://rossimpianti.it/lavora-con-noi');
      expect(
        hr.provenance.sourceUrls,
        <String>['https://rossimpianti.it/lavora-con-noi'],
      );
      expect(hr.provenance.hasMultipleSources, isFalse);
    });

    test('an empty result reports itself empty', () {
      final WebExtractionResult blank =
          WebExtractionResult.fromJson(const <String, dynamic>{});
      expect(blank.isEmpty, isTrue);
      expect(blank.emails, isEmpty);
      expect(blank.sourceUrls, isEmpty);
      expect(blank.companyName, isNull);
    });
  });

  group('WebExtractionJobDetail', () {
    test('parses the job with its inline target page', () {
      final WebExtractionJobDetail detail =
          WebExtractionJobDetail.fromJson(<String, dynamic>{
        'job': _job(),
        'targets': <Map<String, dynamic>>[_target()],
        'targets_meta': <String, dynamic>{
          'current_page': 1,
          'last_page': 3,
          'per_page': 20,
          'total': 50,
        },
      });

      expect(detail.job.id, 88);
      expect(detail.targets, hasLength(1));
      expect(detail.targetsMeta.total, 50);
      // The nested paginator sends no has_more; it is derived.
      expect(detail.targetsMeta.hasMore, isTrue);
    });
  });

  group('WebExtractionCreated', () {
    test('parses the 202 body', () {
      final WebExtractionCreated created =
          WebExtractionCreated.fromJson(<String, dynamic>{
        'job': _job(status: 'pending', completed: 0, failed: 0),
        'queued_targets': 50,
        'message': 'Web extraction job queued.',
      });

      expect(created.job.id, 88);
      expect(created.queuedTargets, 50);
      expect(created.message, 'Web extraction job queued.');
    });
  });

  group('DomainList', () {
    test('splits on newlines and commas, trims, and drops blanks', () {
      final DomainListParse parsed = DomainList.parse(
        'example.com\n'
        '   acme.co.uk ,  sub.domain.io  \n'
        '\n'
        '   \n'
        'terzo.example.org;quarto.example.org',
      );

      expect(parsed.domains, <String>[
        'example.com',
        'acme.co.uk',
        'sub.domain.io',
        'terzo.example.org',
        'quarto.example.org',
      ]);
      expect(parsed.rejected, isEmpty);
      expect(parsed.count, 5);
    });

    test('reduces a URL to its host', () {
      final DomainListParse parsed = DomainList.parse(
        'https://example.com/contact?utm=1\n'
        'HTTP://WWW.Acme.CO.UK\n'
        'example.org:8443/path\n'
        'trailing.example.net.',
      );

      expect(parsed.domains, <String>[
        'example.com',
        'www.acme.co.uk',
        'example.org',
        'trailing.example.net',
      ]);
    });

    test('deduplicates, keeping the order they were first seen', () {
      final DomainListParse parsed = DomainList.parse(
        'example.com\n'
        'other.com\n'
        'https://example.com/\n'
        'EXAMPLE.COM\n'
        'other.com',
      );

      expect(parsed.domains, <String>['example.com', 'other.com']);
      expect(parsed.count, 2);
    });

    test('rejects the obvious non-domains people paste', () {
      final DomainListParse parsed = DomainList.parse(
        'good.example.com\n'
        'info@example.com\n'
        'notadomain\n'
        '1234\n'
        '192.168.0.1\n'
        '!!!.com\n'
        'n/a',
      );

      expect(parsed.domains, <String>['good.example.com']);
      expect(
        parsed.rejected,
        containsAll(<String>[
          'info@example.com',
          'notadomain',
          '1234',
          '192.168.0.1',
          '!!!.com',
        ]),
      );
      // "n/a" reduces to "n", which is not a hostname either.
      expect(parsed.rejected, contains('n/a'));
    });

    test('strips punctuation a paste drags along', () {
      final DomainListParse parsed = DomainList.parse(
        '"quoted.example.com", <angled.example.com>, (paren.example.com).',
      );

      expect(parsed.domains, <String>[
        'quoted.example.com',
        'angled.example.com',
        'paren.example.com',
      ]);
    });

    test('accepts an internationalised domain', () {
      expect(DomainList.normalise('münchen.de'), 'münchen.de');
      expect(DomainList.normalise('münchen'), isNull);
    });

    test('empty input is empty, not an error', () {
      expect(DomainList.parse('').isEmpty, isTrue);
      expect(DomainList.parse('   \n  \n').isEmpty, isTrue);
      expect(DomainList.parse('').rejected, isEmpty);
    });

    test('normalise answers null for anything that is not a hostname', () {
      expect(DomainList.normalise('example.com'), 'example.com');
      expect(DomainList.normalise('  Example.COM  '), 'example.com');
      expect(DomainList.normalise(''), isNull);
      expect(DomainList.normalise('-bad.com'), isNull);
      expect(DomainList.normalise('example.c'), isNull);
    });
  });
}
