/// Tests for the four content features' parsers.
///
/// Every payload below is shaped exactly like the one its resource emits —
/// `TemplateResource`, `SignatureRequestResource`, `ExportArchiveResource` and
/// `ExtractionProfileResource` — including the two conventions that actually
/// break clients in the field: a key that is present but null because the
/// endpoint is in list mode, and a nested section the server never wrote.
///
/// The one piece of real logic on this side is signer progress. The server
/// computes it too, but a single-signer request has no signer rows at all, and
/// getting that branch wrong renders every legacy request as "0 of 0 signed" —
/// which is why all three of its branches are tested here.
library;

import 'package:banksheet_mobile/features/exports/domain/export_archive.dart';
import 'package:banksheet_mobile/features/profiles/domain/extraction_profile.dart';
import 'package:banksheet_mobile/features/signatures/domain/signature.dart';
import 'package:banksheet_mobile/features/templates/domain/generated_pdf.dart';
import 'package:banksheet_mobile/features/templates/domain/template.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

/// `GET /templates` — list mode: `html_content` present, valued null.
Map<String, dynamic> _templateListRow() => <String, dynamic>{
      'id': 12,
      'name': 'Invoice — standard terms',
      'type': 'invoice',
      'variables': <Map<String, dynamic>>[
        <String, dynamic>{
          'name': 'customer_name',
          'label': 'Customer name',
          'type': 'text',
          'required': true,
          'default': '',
          'currency': 'USD',
          'date_format': 'd/m/Y',
          'options': <String>[],
        },
        <String, dynamic>{
          'name': 'invoice_total',
          'label': 'Invoice total',
          'type': 'currency',
          'required': true,
          'default': '0',
          'currency': 'EUR',
          'date_format': 'd/m/Y',
          'options': <String>[],
        },
        <String, dynamic>{
          'name': 'due_date',
          'label': 'Due date',
          'type': 'date',
          'required': false,
          'default': '',
          'currency': 'USD',
          'date_format': 'd/m/Y',
          'options': <String>[],
        },
        <String, dynamic>{
          'name': 'payment_terms',
          'label': 'Payment terms',
          'type': 'select',
          'required': true,
          'default': '30 days',
          'currency': 'USD',
          'date_format': 'd/m/Y',
          'options': <String>['On receipt', '30 days', '60 days'],
        },
        <String, dynamic>{
          'name': 'notes',
          'label': 'Notes',
          'type': 'multiline',
          'required': false,
          'default': '',
          'currency': 'USD',
          'date_format': 'd/m/Y',
          'options': <String>[],
        },
        <String, dynamic>{
          'name': 'contact_email',
          'label': 'Contact email',
          'type': 'email',
          'required': false,
          'default': '',
          'currency': 'USD',
          'date_format': 'd/m/Y',
          'options': <String>[],
        },
      ],
      'variables_count': 6,
      'generated_pdfs_count': 4,
      // The convention under test: the key is here, and it is null.
      'html_content': null,
      'created_at': '2025-01-08T11:02:00+01:00',
      'updated_at': '2025-03-19T08:40:11+01:00',
    };

/// `GET /generated-pdfs/{id}`.
Map<String, dynamic> _generatedPdf() => <String, dynamic>{
      'id': 88,
      'title': 'Invoice 2025-014 — Rossi SRL',
      'kind': 'template',
      'template_id': 12,
      'template': <String, dynamic>{
        'id': 12,
        'name': 'Invoice — standard terms',
        'type': 'invoice',
      },
      'created_by': <String, dynamic>{'id': 7, 'name': 'Giulia Rossi'},
      'data': <String, dynamic>{
        'customer_name': 'Rossi SRL',
        'invoice_total': '1240,50',
      },
      'signature_fields': <Map<String, dynamic>>[
        <String, dynamic>{'page': 1, 'x': 0.6, 'y': 0.8},
      ],
      'filename': 'invoice-2025-014-rossi-srl.pdf',
      'file_size': 48211,
      'is_available': true,
      'download_url':
          'https://banksheet.pro/api/mobile/v1/generated-pdfs/88/download',
      'created_at': '2025-03-19T09:14:00+01:00',
      'updated_at': '2025-03-19T09:14:00+01:00',
    };

/// A multi-signer request as the detail endpoint sends it.
Map<String, dynamic> _multiSignerRequest() => <String, dynamic>{
      'id': 501,
      'title': 'Supply agreement 2025',
      'subject': 'Please sign: Supply agreement 2025',
      'message': null,
      'status': 'partially_signed',
      'provider': 'internal',
      'signing_mode': 'sequential',
      'is_multi_signer': true,
      'is_open': true,
      'source': <String, dynamic>{
        'type': 'generated_pdf',
        'id': 88,
        'label': 'Invoice 2025-014 — Rossi SRL',
      },
      'signer_name': 'Marco Bianchi',
      'signer_email': 'marco@example.com',
      'signer_phone': null,
      'cc_emails': <String>['accounts@example.com'],
      'progress': <String, dynamic>{
        'total': 3,
        'signed': 2,
        'declined': 0,
        'pending': 1,
      },
      'created_by': <String, dynamic>{'id': 7, 'name': 'Giulia Rossi'},
      'signers': <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 9001,
          'name': 'Marco Bianchi',
          'email': 'marco@example.com',
          'sort_order': 0,
          'status': 'signed',
          'color': '#059669',
          'message': null,
          'viewed_at': '2025-03-20T09:00:00+01:00',
          'signed_at': '2025-03-20T09:05:00+01:00',
          'declined_at': null,
          'decline_reason': null,
          'has_signed': true,
          'is_expired': false,
          'token_expires_at': '2025-04-19T09:00:00+02:00',
          'created_at': '2025-03-19T10:00:00+01:00',
        },
        // Deliberately out of order in the payload: the client sorts on
        // sort_order, because for a sequential request that order is the
        // signing order and the timeline would otherwise lie.
        <String, dynamic>{
          'id': 9003,
          'name': 'Chiara Neri',
          'email': 'chiara@example.com',
          'sort_order': 2,
          'status': 'pending',
          'color': '#B45309',
          'message': null,
          'viewed_at': null,
          'signed_at': null,
          'declined_at': null,
          'decline_reason': null,
          'has_signed': false,
          'is_expired': false,
          'token_expires_at': null,
          'created_at': '2025-03-19T10:00:00+01:00',
        },
        <String, dynamic>{
          'id': 9002,
          'name': 'Luca Verdi',
          'email': 'luca@example.com',
          'sort_order': 1,
          'status': 'signed',
          'color': '#1D4ED8',
          'message': null,
          'viewed_at': '2025-03-20T11:00:00+01:00',
          'signed_at': '2025-03-20T11:20:00+01:00',
          'declined_at': null,
          'decline_reason': null,
          'has_signed': true,
          'is_expired': false,
          'token_expires_at': null,
          'created_at': '2025-03-19T10:00:00+01:00',
        },
      ],
      'events': <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 71,
          'event_type': 'signer_signed',
          'actor_type': 'signer',
          'actor_name': 'Luca Verdi',
          'actor_email': 'luca@example.com',
          'ip_address': '81.2.69.142',
          'user_agent': 'Mozilla/5.0',
          'metadata': <String, dynamic>{'signer_id': 9002},
          'created_at': '2025-03-20T11:20:00+01:00',
        },
        <String, dynamic>{
          'id': 70,
          'event_type': 'sent',
          'actor_type': 'employee',
          'actor_name': 'Giulia Rossi',
          'actor_email': null,
          'ip_address': null,
          'user_agent': null,
          'metadata': null,
          'created_at': '2025-03-19T10:00:00+01:00',
        },
      ],
      'events_count': 2,
      'sent_at': '2025-03-19T10:00:00+01:00',
      'viewed_at': '2025-03-20T09:00:00+01:00',
      'signed_at': null,
      'declined_at': null,
      'completed_at': null,
      'expires_at': '2025-04-19T09:00:00+02:00',
      'last_event_at': '2025-03-20T11:20:00+01:00',
      'error_message': null,
      'signed_file_available': false,
      'signed_filename': 'supply-agreement-2025.pdf',
      'download_url': null,
      'created_at': '2025-03-19T10:00:00+01:00',
      'updated_at': '2025-03-20T11:20:00+01:00',
    };

/// A completed single-signer request as the *list* sends it: no signer rows
/// anywhere, and `withCount` found none either.
Map<String, dynamic> _singleSignerListRow() => <String, dynamic>{
      'id': 402,
      'title': 'NDA — Bianchi',
      'subject': null,
      'message': null,
      'status': 'completed',
      'provider': 'internal',
      'signing_mode': null,
      'is_multi_signer': false,
      'is_open': false,
      'source': <String, dynamic>{
        'type': 'document',
        'id': 31,
        'label': 'nda-bianchi.pdf',
      },
      'signer_name': 'Marco Bianchi',
      'signer_email': 'marco@example.com',
      'signer_phone': null,
      'cc_emails': <String>[],
      'progress': <String, dynamic>{
        'total': 1,
        'signed': 1,
        'declined': 0,
        'pending': 0,
      },
      'created_by': null,
      'signers': null,
      'events': null,
      'events_count': 4,
      'sent_at': '2025-02-01T09:00:00+01:00',
      'viewed_at': '2025-02-01T09:30:00+01:00',
      'signed_at': '2025-02-01T09:35:00+01:00',
      'declined_at': null,
      'completed_at': '2025-02-01T09:35:00+01:00',
      'expires_at': null,
      'last_event_at': '2025-02-01T09:35:00+01:00',
      'error_message': null,
      'signed_file_available': true,
      'signed_filename': 'nda-bianchi.pdf',
      'download_url':
          'https://banksheet.pro/api/mobile/v1/signatures/402/download',
      'created_at': '2025-02-01T08:55:00+01:00',
      'updated_at': '2025-02-01T09:35:00+01:00',
    };

Map<String, dynamic> _exportRow() => <String, dynamic>{
      'id': 88,
      'document_id': 412,
      'document': <String, dynamic>{
        'id': 412,
        'original_filename': 'intesa-marzo-2025.pdf',
      },
      'created_by': <String, dynamic>{'id': 7, 'name': 'Giulia Rossi'},
      'export_type': 'xlsx',
      'status': 'completed',
      'record_count': 62,
      'filename': 'intesa-marzo-2025-88.xlsx',
      'file_size': 18944,
      'is_available': true,
      'download_url': 'https://banksheet.pro/api/mobile/v1/exports/88/download',
      'generated_at': '2025-04-02T09:20:00+02:00',
      'created_at': '2025-04-02T09:20:00+02:00',
    };

/// A full profile from the detail endpoint.
Map<String, dynamic> _profileDetail() => <String, dynamic>{
      'id': 3,
      'name': 'Intesa Sanpaolo — conto ordinario',
      'document_type': 'bank_statement',
      'bank_name': 'Intesa Sanpaolo',
      'is_active': true,
      'last_matched_at': '2025-04-02T09:15:00+02:00',
      'documents_count': 41,
      'transactions_count': 2180,
      'has_sample': true,
      'rules': <String, dynamic>{
        'match': <String, dynamic>{
          'keywords': <String>['estratto conto', 'intesa sanpaolo'],
          'headers': <String>['data', 'valuta', 'descrizione'],
        },
        'column': <String, dynamic>{
          'columns': <String>['data', 'valuta', 'descrizione', 'saldo'],
          'column_map': <String, dynamic>{
            'transaction_date': 'Data',
            'value_date': 'Valuta',
            'description': 'Descrizione operazioni',
            'debit': 'Dare',
            'credit': 'Avere',
            'balance': 'Saldo',
          },
          'amount_regex': r'-?\d{1,3}(\.\d{3})*,\d{2}',
        },
        'normalization': <String, dynamic>{
          'date_format': 'd/m/Y',
          'day_first': true,
          'currency': 'EUR',
          'decimal_separator': ',',
          'language': 'ita',
        },
        'post_processing': <String, dynamic>{
          'stop_sections': <String>['saldo finale'],
          'ignore_lines': <String>['riporto', 'segue'],
          'cleanup_regex': <String>[r'/\s{2,}/'],
        },
        'builder': <String, dynamic>{
          'country': 'IT',
          'currency': 'EUR',
          'language': 'ita',
          'date_format': 'd/m/Y',
          'number_format': 'eu',
          'statement_keywords': <String>['estratto conto'],
          'header_keywords': <String>['data', 'valuta'],
          'table_start_keywords': <String>['saldo iniziale'],
          'table_end_keywords': <String>['saldo finale'],
          'repeated_headers': <String>['riporto'],
          'footer_lines': <String>['segue'],
          'ignore_patterns': <String>[r'/^totale/i'],
          'column_map': <String, dynamic>{
            'transaction_date': 'Data',
            'value_date': 'Valuta',
            'description': 'Descrizione operazioni',
            'debit': 'Dare',
            'credit': 'Avere',
            'balance': 'Saldo',
          },
          'amount_mode': 'separate',
          'infer_from_balance': true,
          'merge_multiline': true,
          'amount_regex': null,
        },
      },
      'created_at': '2024-11-02T10:00:00+01:00',
      'updated_at': '2025-03-01T10:00:00+01:00',
    };

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('Template', () {
    test('parses a list row and honours the null html_content convention', () {
      final Template template = Template.fromJson(_templateListRow());

      expect(template.id, 12);
      expect(template.displayName, 'Invoice — standard terms');
      expect(template.type, 'invoice');
      expect(template.variablesCount, 6);
      expect(template.variables, hasLength(6));
      expect(template.generatedPdfsCount, 4);

      // Present-but-null means "list mode", not "empty template".
      expect(template.htmlContent, isNull);
      expect(template.isDetail, isFalse);
    });

    test('detail mode is distinguished by html_content alone', () {
      final Map<String, dynamic> json = _templateListRow()
        ..['html_content'] = '<h1>{{ customer_name }}</h1>';

      expect(Template.fromJson(json).isDetail, isTrue);
    });

    test('parses every variable type and its extras', () {
      final Template template = Template.fromJson(_templateListRow());
      final Map<String, TemplateVariable> byName =
          <String, TemplateVariable>{
        for (final TemplateVariable v in template.variables) v.name: v,
      };

      expect(byName['customer_name']!.type, TemplateVariableType.text);
      expect(byName['customer_name']!.required, isTrue);

      expect(byName['invoice_total']!.type, TemplateVariableType.currency);
      expect(byName['invoice_total']!.currency, 'EUR');
      expect(byName['invoice_total']!.hint, 'EUR');
      expect(byName['invoice_total']!.defaultValue, '0');

      expect(byName['due_date']!.type, TemplateVariableType.date);
      expect(byName['due_date']!.required, isFalse);
      expect(byName['due_date']!.hint, 'd/m/Y');

      expect(byName['payment_terms']!.type, TemplateVariableType.select);
      expect(byName['payment_terms']!.options, hasLength(3));

      expect(byName['notes']!.type, TemplateVariableType.multiline);
      expect(byName['contact_email']!.type, TemplateVariableType.email);
    });

    test('an unknown type degrades to a plain text field', () {
      final TemplateVariable variable = TemplateVariable.fromJson(
        <String, dynamic>{'name': 'mystery', 'type': 'colour_picker'},
      );

      expect(variable.type, TemplateVariableType.unknown);
      // The label falls back to the name so the field is never captionless.
      expect(variable.label, 'mystery');
      expect(variable.validate('anything'), isNull);
    });

    test('initialValues seeds the form from the schema defaults', () {
      final Template template = Template.fromJson(_templateListRow());

      expect(template.initialValues['payment_terms'], '30 days');
      expect(template.initialValues['customer_name'], '');
      expect(template.initialValues.keys, hasLength(6));
    });

    test('a variable with no name is dropped rather than rendered', () {
      final Map<String, dynamic> json = _templateListRow()
        ..['variables'] = <Map<String, dynamic>>[
          <String, dynamic>{'name': '', 'label': 'Ghost', 'type': 'text'},
          <String, dynamic>{'name': 'real', 'label': 'Real', 'type': 'text'},
        ]
        ..['variables_count'] = 2;

      final Template template = Template.fromJson(json);

      expect(template.variables, hasLength(1));
      expect(template.variables.single.name, 'real');
    });
  });

  group('TemplateVariable.validate', () {
    TemplateVariable variable(
      String type, {
      bool required = false,
      List<String> options = const <String>[],
    }) {
      return TemplateVariable.fromJson(<String, dynamic>{
        'name': 'field',
        'label': 'Field',
        'type': type,
        'required': required,
        'options': options,
      });
    }

    test('required is only enforced on an empty value', () {
      expect(variable('text', required: true).validate(''), isNotNull);
      expect(variable('text', required: true).validate('   '), isNotNull);
      expect(variable('text', required: true).validate('Ada'), isNull);
      expect(variable('text').validate(''), isNull);
      expect(variable('text').validate(null), isNull);
    });

    test('a number accepts the separators the server regex allows', () {
      expect(variable('currency').validate('1.240,50'), isNull);
      expect(variable('number').validate('-42'), isNull);
      expect(variable('number').validate('1 000'), isNull);
      expect(variable('number').validate('twelve'), isNotNull);
    });

    test('a date must parse, and a select must be one of its options', () {
      expect(variable('date').validate('2025-04-02'), isNull);
      expect(variable('date').validate('02/04/2025'), isNotNull);

      final TemplateVariable select =
          variable('select', options: <String>['A', 'B']);
      expect(select.validate('A'), isNull);
      expect(select.validate('C'), isNotNull);
    });

    test('an email is checked, and 5000 characters is the ceiling', () {
      expect(variable('email').validate('ada@example.com'), isNull);
      expect(variable('email').validate('ada@'), isNotNull);
      expect(
        variable('text').validate('x' * (TemplateVariable.maxLength + 1)),
        isNotNull,
      );
    });
  });

  group('GeneratedPdf', () {
    test('parses the detail payload', () {
      final GeneratedPdf pdf = GeneratedPdf.fromJson(_generatedPdf());

      expect(pdf.id, 88);
      expect(pdf.kind, GeneratedPdfKind.template);
      expect(pdf.templateId, 12);
      expect(pdf.sourceLabel, 'Invoice — standard terms');
      expect(pdf.filename, 'invoice-2025-014-rossi-srl.pdf');
      expect(pdf.sizeBytes, 48211);
      expect(pdf.isAvailable, isTrue);
      expect(pdf.signatureFieldCount, 1);
      expect(pdf.hasSignatureFields, isTrue);
      expect(pdf.data?['customer_name'], 'Rossi SRL');
    });

    test('a pruned file is parsed as unavailable with no size', () {
      final Map<String, dynamic> json = _generatedPdf()
        ..['is_available'] = false
        ..['file_size'] = null;

      final GeneratedPdf pdf = GeneratedPdf.fromJson(json);

      expect(pdf.isAvailable, isFalse);
      expect(pdf.sizeBytes, isNull);
    });

    test('falls back to the kind when the template is gone', () {
      final Map<String, dynamic> json = _generatedPdf()
        ..['template'] = null
        ..['kind'] = 'uploaded_pdf';

      final GeneratedPdf pdf = GeneratedPdf.fromJson(json);

      expect(pdf.kind, GeneratedPdfKind.uploadedPdf);
      expect(pdf.sourceLabel, GeneratedPdfKind.uploadedPdf.label);
    });
  });

  group('SignatureRequest', () {
    test('computes progress from the loaded signer rows', () {
      final SignatureRequest request =
          SignatureRequest.fromJson(_multiSignerRequest());

      expect(request.progress.total, 3);
      expect(request.progress.signed, 2);
      expect(request.progress.declined, 0);
      expect(request.progress.pending, 1);
      expect(request.progress.label, '2 of 3 signed');
      expect(request.progress.isComplete, isFalse);
    });

    test('signers are ordered by sort_order, not by payload order', () {
      final SignatureRequest request =
          SignatureRequest.fromJson(_multiSignerRequest());

      expect(
        request.signers!.map((SignatureSigner s) => s.id).toList(),
        <int>[9001, 9002, 9003],
      );
      expect(request.signerList.first.state, SignerStatus.signed);
      expect(request.signerList.last.state, SignerStatus.pending);
    });

    test('the loaded rows win over a stale progress block', () {
      final Map<String, dynamic> json = _multiSignerRequest()
        // What withCount() reported before a signer finished.
        ..['progress'] = <String, dynamic>{
          'total': 3,
          'signed': 0,
          'declined': 0,
          'pending': 3,
        };

      expect(SignatureRequest.fromJson(json).progress.signed, 2);
    });

    test('list mode falls back to the server counts', () {
      final Map<String, dynamic> json = _multiSignerRequest()
        ..['signers'] = null
        ..['events'] = null;

      final SignatureRequest request = SignatureRequest.fromJson(json);

      expect(request.hasDetail, isFalse);
      expect(request.progress.total, 3);
      expect(request.progress.signed, 2);
      expect(request.progress.pending, 1);
    });

    test('pending is recomputed rather than trusted', () {
      final Map<String, dynamic> json = _multiSignerRequest()
        ..['signers'] = null
        ..['progress'] = <String, dynamic>{
          'total': 3,
          'signed': 2,
          'declined': 1,
          // A value that cannot be true alongside the three above.
          'pending': 9,
        };

      expect(SignatureRequest.fromJson(json).progress.pending, 0);
    });

    test('a single-signer request reads as one signer, not zero of zero', () {
      final Map<String, dynamic> json = _singleSignerListRow()
        // The shape a legacy row really has: no signer rows, so withCount()
        // reports nothing at all.
        ..['progress'] = <String, dynamic>{
          'total': 0,
          'signed': 0,
          'declined': 0,
          'pending': 0,
        };

      final SignatureRequest request = SignatureRequest.fromJson(json);

      expect(request.progress.total, 1);
      expect(request.progress.signed, 1);
      expect(request.progress.pending, 0);
      expect(request.progress.label, '1 of 1 signed');
      expect(request.progress.isComplete, isTrue);
    });

    test('an open single-signer request is one pending signer', () {
      final Map<String, dynamic> json = _singleSignerListRow()
        ..['status'] = 'sent'
        ..['progress'] = <String, dynamic>{'total': 0};

      final SignatureRequest request = SignatureRequest.fromJson(json);

      expect(request.progress.pending, 1);
      expect(request.progress.signed, 0);
      expect(request.isOpen, isTrue);
      expect(request.state, SignatureStatus.sent);
    });

    test('a declined single-signer request is one declined signer', () {
      final Map<String, dynamic> json = _singleSignerListRow()
        ..['status'] = 'declined'
        ..['progress'] = <String, dynamic>{'total': 0};

      final SignatureRequest request = SignatureRequest.fromJson(json);

      expect(request.progress.declined, 1);
      expect(request.progress.pending, 0);
      expect(request.state.isProblem, isTrue);
    });

    test('awaiting_download counts as signed', () {
      final Map<String, dynamic> json = _singleSignerListRow()
        ..['status'] = 'awaiting_download'
        ..['progress'] = <String, dynamic>{'total': 0};

      expect(SignatureRequest.fromJson(json).progress.signed, 1);
    });

    test('synthesises a signer row when the server sent none', () {
      final SignatureRequest request =
          SignatureRequest.fromJson(_singleSignerListRow());

      expect(request.signers, isNull);
      expect(request.signerList, hasLength(1));
      expect(request.signerList.single.displayName, 'Marco Bianchi');
      expect(request.signerList.single.state, SignerStatus.signed);
    });

    test('parses the audit trail and the source document', () {
      final SignatureRequest request =
          SignatureRequest.fromJson(_multiSignerRequest());

      expect(request.events, hasLength(2));
      expect(request.events!.first.title, 'Signer signed');
      expect(request.events!.first.actor, 'Luca Verdi');
      expect(request.events!.last.actor, 'Giulia Rossi');
      expect(request.eventsCount, 2);
      expect(request.source.type, 'generated_pdf');
      expect(request.source.id, 88);
      expect(request.canDownloadSigned, isFalse);
    });

    test('a decline reason survives parsing', () {
      final Map<String, dynamic> json = _multiSignerRequest();
      final List<Map<String, dynamic>> signers =
          (json['signers']! as List<Map<String, dynamic>>).toList();
      signers[1] = <String, dynamic>{
        ...signers[1],
        'status': 'declined',
        'declined_at': '2025-03-21T08:00:00+01:00',
        'decline_reason': 'The payment terms are wrong.',
      };
      json['signers'] = signers;

      final SignatureRequest request = SignatureRequest.fromJson(json);
      final SignatureSigner declined = request.signerList.last;

      expect(declined.state, SignerStatus.declined);
      expect(declined.declineReason, 'The payment terms are wrong.');
      expect(request.progress.declined, 1);
      expect(request.progress.pending, 0);
    });

    test('an unknown status is kept verbatim and reads as nothing special', () {
      final Map<String, dynamic> json = _singleSignerListRow()
        ..['status'] = 'quantum_superposition';

      final SignatureRequest request = SignatureRequest.fromJson(json);

      expect(request.status, 'quantum_superposition');
      expect(request.state, SignatureStatus.unknown);
      expect(request.isOpen, isFalse);
      expect(request.state.isProblem, isFalse);
    });
  });

  group('ExportArchive', () {
    test('parses a row', () {
      final ExportArchive archive = ExportArchive.fromJson(_exportRow());

      expect(archive.id, 88);
      expect(archive.format, ExportFormat.xlsx);
      expect(archive.format.label, 'XLSX');
      expect(archive.recordCount, 62);
      expect(archive.filename, 'intesa-marzo-2025-88.xlsx');
      expect(archive.sizeBytes, 18944);
      expect(archive.isAvailable, isTrue);
      expect(archive.sourceName, 'intesa-marzo-2025.pdf');
    });

    test('groups on the local calendar day of generated_at', () {
      final ExportArchive archive = ExportArchive.fromJson(_exportRow());
      final DateTime local =
          DateTime.parse('2025-04-02T09:20:00+02:00').toLocal();

      expect(archive.madeAt, DateTime.parse('2025-04-02T09:20:00+02:00'));
      expect(archive.day, DateTime(local.year, local.month, local.day));
    });

    test('falls back to created_at when generated_at is missing', () {
      final Map<String, dynamic> json = _exportRow()..['generated_at'] = null;

      expect(
        ExportArchive.fromJson(json).madeAt,
        DateTime.parse('2025-04-02T09:20:00+02:00'),
      );
    });

    test('survives a deleted source document', () {
      final Map<String, dynamic> json = _exportRow()
        ..['document'] = null
        ..['document_id'] = null;

      final ExportArchive archive = ExportArchive.fromJson(json);

      expect(archive.document, isNull);
      expect(archive.documentId, isNull);
      expect(archive.sourceName, isNotEmpty);
    });

    test('a pruned file is unavailable with no size, and day is null when '
        'both timestamps are', () {
      final Map<String, dynamic> json = _exportRow()
        ..['is_available'] = false
        ..['file_size'] = null
        ..['generated_at'] = null
        ..['created_at'] = null;

      final ExportArchive archive = ExportArchive.fromJson(json);

      expect(archive.isAvailable, isFalse);
      expect(archive.sizeBytes, isNull);
      expect(archive.day, isNull);
    });

    test('an unrecognised format degrades rather than throwing', () {
      final Map<String, dynamic> json = _exportRow()
        ..['export_type'] = 'parquet';

      final ExportArchive archive = ExportArchive.fromJson(json);

      expect(archive.format, ExportFormat.unknown);
      expect(archive.exportType, 'parquet');
    });
  });

  group('ExtractionProfile', () {
    test('parses a list row, where rules are null by convention', () {
      final Map<String, dynamic> json = _profileDetail()..['rules'] = null;

      final ExtractionProfile profile = ExtractionProfile.fromJson(json);

      expect(profile.id, 3);
      expect(profile.displayName, 'Intesa Sanpaolo — conto ordinario');
      expect(profile.bankName, 'Intesa Sanpaolo');
      expect(profile.isActive, isTrue);
      expect(profile.documentsCount, 41);
      expect(profile.transactionsCount, 2180);
      expect(profile.hasSample, isTrue);
      expect(profile.rules, isNull);
      expect(profile.isDetail, isFalse);
    });

    test('parses the four rule blobs and the builder state', () {
      final ExtractionProfile profile =
          ExtractionProfile.fromJson(_profileDetail());
      final ProfileRules rules = profile.rules!;

      expect(profile.isDetail, isTrue);
      expect(rules.isEmpty, isFalse);

      expect(rules.country, 'IT');
      expect(rules.language, 'ita');
      expect(rules.dateFormat, 'd/m/Y');
      expect(rules.dayFirst, isTrue);
      expect(rules.currency, 'EUR');
      expect(rules.decimalSeparator, ',');
      expect(rules.numberFormat, 'eu');

      expect(rules.statementKeywords, <String>['estratto conto']);
      expect(rules.tableStartKeywords, <String>['saldo iniziale']);
      expect(rules.tableEndKeywords, <String>['saldo finale']);
      // Merged from post-processing, repeated headers, footers and patterns,
      // de-duplicated exactly as the server merges them.
      expect(rules.ignoredLines, containsAll(<String>['riporto', 'segue']));
      expect(
        rules.ignoredLines.where((String v) => v == 'riporto'),
        hasLength(1),
      );
      expect(rules.cleanupRules, hasLength(1));

      expect(rules.columnMap[ProfileColumnField.transactionDate], 'Data');
      expect(rules.columnMap[ProfileColumnField.description],
          'Descrizione operazioni');
      expect(rules.columnMap[ProfileColumnField.amount], isNull);
      expect(rules.amountMode, 'separate');
      expect(rules.inferFromBalance, isTrue);
      expect(rules.mergeMultiline, isTrue);
      // Null in the builder, present on the column rules — the fallback path.
      expect(rules.amountPattern, isNotNull);
    });

    test('a profile with no builder still reads from the legacy blobs', () {
      final Map<String, dynamic> json = _profileDetail();
      final Map<String, dynamic> rules =
          Map<String, dynamic>.from(json['rules']! as Map<String, dynamic>)
            ..['builder'] = null;
      json['rules'] = rules;

      final ProfileRules parsed = ExtractionProfile.fromJson(json).rules!;

      expect(parsed.builder, isNull);
      expect(parsed.country, isNull);
      expect(parsed.language, 'ita');
      expect(parsed.dateFormat, 'd/m/Y');
      // Falls back to match_rules_json when the builder is not there.
      expect(parsed.statementKeywords, hasLength(2));
      expect(parsed.headerKeywords, hasLength(3));
      expect(parsed.tableStartKeywords, isEmpty);
      expect(parsed.tableEndKeywords, <String>['saldo finale']);
      expect(parsed.columnMap[ProfileColumnField.balance], 'Saldo');
      expect(parsed.amountMode, isNull);
      expect(parsed.inferFromBalance, isNull);
    });

    test('every section missing is an empty rule set, not a crash', () {
      final Map<String, dynamic> json = _profileDetail()
        ..['rules'] = <String, dynamic>{
          'match': null,
          'column': null,
          'normalization': null,
          'post_processing': null,
          'builder': null,
        };

      final ProfileRules rules = ExtractionProfile.fromJson(json).rules!;

      expect(rules.isEmpty, isTrue);
      expect(rules.statementKeywords, isEmpty);
      expect(rules.columnMap, isEmpty);
      expect(rules.columns, isEmpty);
      expect(rules.dayFirst, isNull);
      expect(rules.amountPattern, isNull);
      expect(rules.rawSections, isEmpty);
    });

    test('rawSections only lists the blobs that exist', () {
      final Map<String, dynamic> json = _profileDetail();
      final Map<String, dynamic> rules =
          Map<String, dynamic>.from(json['rules']! as Map<String, dynamic>)
            ..['post_processing'] = null
            ..['builder'] = null;
      json['rules'] = rules;

      expect(ExtractionProfile.fromJson(json).rules!.rawSections, hasLength(3));
    });

    test('the optimistic toggle copies everything but is_active', () {
      final ExtractionProfile profile =
          ExtractionProfile.fromJson(_profileDetail());
      final ExtractionProfile flipped = profile.withActive(active: false);

      expect(flipped.isActive, isFalse);
      expect(flipped.id, profile.id);
      expect(flipped.name, profile.name);
      expect(flipped.rules, profile.rules);
      expect(flipped.lastMatchedAt, profile.lastMatchedAt);
      expect(profile.isActive, isTrue);
    });

    test('an unnamed profile falls back to its id', () {
      final Map<String, dynamic> json = _profileDetail()
        ..['name'] = null
        ..['bank_name'] = null;

      expect(ExtractionProfile.fromJson(json).displayName, contains('3'));
    });
  });
}
