/// Tests for the two pieces of the tools feature that decide whether a
/// conversion is even attempted: the schema parser and the status model.
///
/// The whole tool form is drawn from `GET /tools`, so a parser that quietly
/// drops a bound turns a server-side rule into a 422 the user meets after
/// uploading a 40 MB PDF on mobile data. The payload below is shaped exactly
/// like `ToolResource` emits, including every one of the five option type
/// tokens the server uses and the two shapes that break clients in the field: a
/// `required_if` clause and an option whose default is a number rather than a
/// string.
library;

import 'package:banksheet_mobile/core/i18n/strings.dart';
import 'package:banksheet_mobile/features/tools/domain/conversion.dart';
import 'package:banksheet_mobile/features/tools/domain/tool.dart';
import 'package:flutter_test/flutter_test.dart';

/// One schema entry with all twelve keys present, as the resource promises.
Map<String, dynamic> _option({
  required String name,
  required String type,
  required String label,
  bool required = false,
  List<String> values = const <String>[],
  Object? defaultValue,
  int? min,
  int? max,
  int? maxLength,
  String? pattern,
  Map<String, dynamic>? requiredIf,
  String? help,
}) {
  return <String, dynamic>{
    'name': name,
    'type': type,
    'label': label,
    'required': required,
    'values': values,
    'default': defaultValue,
    'min': min,
    'max': max,
    'max_length': maxLength,
    'pattern': pattern,
    'required_if': requiredIf,
    'help': help,
  };
}

Map<String, dynamic> _title() => _option(
      name: 'title',
      type: 'string',
      label: 'Title',
      maxLength: 255,
      help: 'Shown in your conversion history. Defaults to the file name.',
    );

/// A realistic `GET /tools` body.
Map<String, dynamic> _catalogue() => <String, dynamic>{
      'tools': <Map<String, dynamic>>[
        <String, dynamic>{
          'key': 'pdf-to-images',
          'label': 'PDF to Images',
          'badge': 'PDF -> ZIP',
          'description':
              'Render PDF pages as JPEG or PNG images and download them as a '
                  'ZIP archive.',
          'submit_label': 'Create images',
          'accepted_label': 'PDF',
          'accepted_extensions': <String>['pdf'],
          'accept': '.pdf,application/pdf',
          'multiple': false,
          'file_field': 'file',
          'max_files': 1,
          'max_file_kb': 51200,
          'warning': null,
          'supported': true,
          'unsupported_reason': null,
          'options': <Map<String, dynamic>>[
            _title(),
            _option(
              name: 'image_format',
              type: 'enum',
              label: 'Image format',
              values: <String>['jpeg', 'png'],
              defaultValue: 'jpeg',
              help: 'JPEG is smaller; PNG keeps sharp edges.',
            ),
            _option(
              name: 'dpi',
              type: 'int',
              label: 'Resolution (DPI)',
              // A number on the wire, not a string.
              defaultValue: 200,
              min: 72,
              max: 600,
              help: 'Higher values produce larger images and slower jobs.',
            ),
          ],
        },
        <String, dynamic>{
          'key': 'split-pdf',
          'label': 'Split PDF',
          'badge': 'PDF -> ZIP',
          'description': 'Split every page into a ZIP, or extract ranges.',
          'submit_label': 'Split PDF',
          'accepted_label': 'PDF',
          'accepted_extensions': <String>['pdf'],
          'accept': '.pdf,application/pdf',
          'multiple': false,
          'file_field': 'file',
          'max_files': 1,
          'max_file_kb': 51200,
          'warning': null,
          'supported': true,
          'unsupported_reason': null,
          'options': <Map<String, dynamic>>[
            _title(),
            _option(
              name: 'split_mode',
              type: 'enum',
              label: 'Split mode',
              values: <String>['every-page', 'range'],
              defaultValue: 'every-page',
            ),
            _option(
              name: 'page_range',
              type: 'string',
              label: 'Page range',
              defaultValue: '1-z',
              maxLength: 100,
              pattern: r'^[0-9zZ,\-\s]+$',
              requiredIf: <String, dynamic>{
                'field': 'split_mode',
                'value': 'range',
              },
              help: 'Pages like 1-3, 2,4,6-8 or 1-z.',
            ),
          ],
        },
        <String, dynamic>{
          'key': 'merge-pdf',
          'label': 'Merge PDF',
          'badge': 'PDF + PDF',
          'description': 'Combine multiple PDFs.',
          'submit_label': 'Merge PDFs',
          'accepted_label': 'PDF files',
          'accepted_extensions': <String>['pdf'],
          'accept': '.pdf,application/pdf',
          'multiple': true,
          'file_field': 'files[]',
          'max_files': 30,
          'max_file_kb': 51200,
          'warning': null,
          'supported': true,
          'unsupported_reason': null,
          'options': <Map<String, dynamic>>[_title()],
        },
        <String, dynamic>{
          'key': 'html-to-pdf',
          'label': 'HTML to PDF',
          'badge': 'Contracts',
          'description': 'Render contracts and invoices from HTML.',
          'submit_label': 'Render PDF',
          'accepted_label': 'HTML',
          'accepted_extensions': <String>[],
          'accept': null,
          'multiple': false,
          'file_field': null,
          'max_files': 0,
          'max_file_kb': 51200,
          'warning': null,
          'supported': true,
          'unsupported_reason': null,
          'options': <Map<String, dynamic>>[
            _title(),
            _option(
              name: 'html_content',
              type: 'text',
              label: 'HTML',
              required: true,
              maxLength: 200000,
            ),
            _option(
              name: 'variables_json',
              type: 'json',
              label: 'Variables (JSON)',
              maxLength: 20000,
            ),
          ],
        },
        <String, dynamic>{
          'key': 'edit-pdf',
          'label': 'Edit PDF',
          'badge': 'Visual editor',
          'description': 'Replace visible text and cover content.',
          'submit_label': 'Open visual editor',
          'accepted_label': 'PDF',
          'accepted_extensions': <String>['pdf'],
          'accept': '.pdf,application/pdf',
          'multiple': false,
          'file_field': 'file',
          'max_files': 1,
          'max_file_kb': 51200,
          'warning': null,
          'supported': false,
          'unsupported_reason':
              'The visual PDF editor is only available on banksheet.pro.',
          'options': <Map<String, dynamic>>[_title()],
        },
      ],
      'limits': <String, dynamic>{
        'max_merge_files': 5,
        'max_pages_per_file': 100,
        'max_total_pages': 200,
        'max_total_upload_kb': 51200,
        'max_file_kb': 51200,
      },
      'usage': <String, dynamic>{
        'remaining_conversions': 47,
        'monthly_conversion_limit': 50,
        'used_conversions': 3,
        'remaining_pages': 940,
        'monthly_page_limit': 1000,
        'used_pages': 60,
      },
    };

void main() {
  group('ToolCatalogue', () {
    final ToolCatalogue catalogue = ToolCatalogue.fromJson(_catalogue());

    test('parses every tool with its file rules', () {
      expect(catalogue.tools, hasLength(5));

      final ToolDefinition merge = catalogue.byKey('merge-pdf')!;
      expect(merge.multiple, isTrue);
      expect(merge.maxFiles, 30);
      expect(merge.minFiles, 2);
      // The `[]` the web form carries is not part of the multipart field name.
      expect(merge.uploadField, 'files');
      expect(merge.acceptedExtensions, <String>['pdf']);
      expect(merge.maxFileBytes, 51200 * 1024);
    });

    test('caps merge files at the plan ceiling, not the validator ceiling', () {
      final ToolDefinition merge = catalogue.byKey('merge-pdf')!;
      expect(merge.maxFiles, 30);
      expect(catalogue.maxFilesFor(merge), 5);
    });

    test('html-to-pdf takes no upload', () {
      final ToolDefinition html = catalogue.byKey('html-to-pdf')!;
      expect(html.needsFiles, isFalse);
      expect(html.minFiles, 0);
      expect(html.acceptedExtensions, isEmpty);
    });

    test('groups tools into the three families', () {
      expect(catalogue.byKey('merge-pdf')!.category, ToolCategory.pdfUtilities);
      expect(
        catalogue.byKey('html-to-pdf')!.category,
        ToolCategory.documentConversion,
      );
      expect(
        catalogue.byKey('pdf-to-images')!.category,
        ToolCategory.imageConversion,
      );
    });

    test('carries the unsupported flag and its reason', () {
      final ToolDefinition edit = catalogue.byKey('edit-pdf')!;
      expect(edit.supported, isFalse);
      expect(edit.unsupportedReason, contains('banksheet.pro'));
    });

    test('publishes plan limits and remaining allowance', () {
      expect(catalogue.limits.maxMergeFiles, 5);
      expect(catalogue.limits.maxTotalPages, 200);
      expect(catalogue.usage!.remainingConversions, 47);
      expect(catalogue.usage!.conversionsUnlimited, isFalse);
      expect(catalogue.usage!.conversionsExhausted, isFalse);
    });

    test('survives an unknown key without losing the rest', () {
      final ToolCatalogue partial = ToolCatalogue.fromJson(<String, dynamic>{
        'tools': <Map<String, dynamic>>[
          <String, dynamic>{'key': 'brand-new-tool', 'options': <dynamic>[]},
        ],
        'limits': <String, dynamic>{},
        'usage': null,
      });

      final ToolDefinition tool = partial.tools.single;
      expect(tool.key, 'brand-new-tool');
      // No label from the server, so the key is humanised rather than blank.
      expect(tool.label, 'Brand new tool');
      expect(tool.category, ToolCategory.pdfUtilities);
      expect(partial.usage, isNull);
      expect(partial.limits.maxMergeFiles, 2);
    });
  });

  group('ToolOption', () {
    final ToolCatalogue catalogue = ToolCatalogue.fromJson(_catalogue());

    test('folds the five wire types into four widgets', () {
      final ToolDefinition images = catalogue.byKey('pdf-to-images')!;
      final ToolDefinition html = catalogue.byKey('html-to-pdf')!;

      expect(images.optionNamed('title')!.type, ToolOptionType.text);
      expect(
        images.optionNamed('image_format')!.type,
        ToolOptionType.enumChoice,
      );
      expect(images.optionNamed('dpi')!.type, ToolOptionType.integer);
      expect(
        html.optionNamed('html_content')!.type,
        ToolOptionType.longText,
      );
      expect(
        html.optionNamed('variables_json')!.type,
        ToolOptionType.longText,
      );
      expect(html.optionNamed('variables_json')!.isJson, isTrue);
      expect(html.optionNamed('html_content')!.isJson, isFalse);
    });

    test('keeps a numeric default usable as both text and number', () {
      final ToolOption dpi = catalogue.byKey('pdf-to-images')!.optionNamed('dpi')!;
      expect(dpi.defaultValue, '200');
      expect(dpi.defaultInt, 200);
      expect(dpi.min, 72);
      expect(dpi.max, 600);
    });

    test('seeds a form from the server defaults', () {
      final Map<String, String> defaults =
          catalogue.byKey('split-pdf')!.defaults;
      expect(defaults['split_mode'], 'every-page');
      expect(defaults['page_range'], '1-z');
      expect(defaults.containsKey('title'), isFalse);
    });

    test('separates the title from the rest of the form', () {
      final ToolDefinition split = catalogue.byKey('split-pdf')!;
      expect(split.titleOption!.name, 'title');
      expect(
        split.formOptions.map((ToolOption o) => o.name),
        <String>['split_mode', 'page_range'],
      );
    });

    group('integer validation', () {
      final ToolOption dpi =
          catalogue.byKey('pdf-to-images')!.optionNamed('dpi')!;

      test('accepts a value inside the bounds', () {
        expect(dpi.validate('72'), isNull);
        expect(dpi.validate('200'), isNull);
        expect(dpi.validate('600'), isNull);
        // Whitespace is trimmed, exactly as the server trims it.
        expect(dpi.validate('  300  '), isNull);
      });

      test('rejects a value outside the bounds', () {
        expect(dpi.validate('71'), S.valueBetween(72, 600));
        expect(dpi.validate('601'), S.valueBetween(72, 600));
        expect(dpi.validate('-1'), S.valueBetween(72, 600));
      });

      test('rejects a non-number', () {
        expect(dpi.validate('300dpi'), S.mustBeNumber);
        expect(dpi.validate('high'), S.mustBeNumber);
      });

      test('accepts blank, because the option is optional', () {
        expect(dpi.validate(null), isNull);
        expect(dpi.validate(''), isNull);
        expect(dpi.validate('   '), isNull);
      });
    });

    test('enforces the enum', () {
      final ToolOption format =
          catalogue.byKey('pdf-to-images')!.optionNamed('image_format')!;
      expect(format.validate('png'), isNull);
      expect(format.validate('jpeg'), isNull);
      expect(format.validate('gif'), S.invalidChoice);
    });

    test('enforces the pattern and the length', () {
      final ToolOption range =
          catalogue.byKey('split-pdf')!.optionNamed('page_range')!;
      expect(range.validate('1-3, 5, 7-z'), isNull);
      expect(range.validate('first page'), S.invalidFormat);
      expect(range.validate('1' * 101), S.maxCharacters(100));
    });

    test('honours required_if against the rest of the form', () {
      final ToolOption range =
          catalogue.byKey('split-pdf')!.optionNamed('page_range')!;

      expect(
        range.validate('', form: <String, String>{'split_mode': 'every-page'}),
        isNull,
      );
      expect(
        range.validate('', form: <String, String>{'split_mode': 'range'}),
        S.required,
      );
      expect(
        range.isRequiredIn(<String, String>{'split_mode': 'range'}),
        isTrue,
      );
      expect(range.isRequiredIn(const <String, String>{}), isFalse);
    });

    test('enforces required on its own', () {
      final ToolOption html =
          catalogue.byKey('html-to-pdf')!.optionNamed('html_content')!;
      expect(html.validate(''), S.required);
      expect(html.validate('<p>Hello</p>'), isNull);
    });

    test('requires a JSON object for a json option', () {
      final ToolOption variables =
          catalogue.byKey('html-to-pdf')!.optionNamed('variables_json')!;
      expect(variables.validate('{"name":"Ada"}'), isNull);
      expect(variables.validate('not json'), S.invalidJson);
      // A valid JSON array is still not the object the server wants.
      expect(variables.validate('[1,2]'), S.invalidJson);
      expect(variables.validate(''), isNull);
    });
  });

  group('Conversion', () {
    Map<String, dynamic> row({
      required String status,
      String tool = 'merge-pdf',
      bool hasOutput = true,
      String? error,
    }) {
      return <String, dynamic>{
        'id': 91,
        'tool': tool,
        'tool_label': 'Merge PDF',
        'title': 'Q1 statements',
        'status': status,
        'error_message': error,
        'original_filename': 'january.pdf',
        'output_filename': 'merged.pdf',
        'mime_type': 'application/pdf',
        'output_mime_type': 'application/pdf',
        'file_size': 918273,
        'page_count': 24,
        'file_count': 3,
        'options': <String, dynamic>{'page_count': 24, 'file_count': 3},
        'has_output': hasOutput,
        'download_url': hasOutput
            ? 'https://banksheet.pro/api/mobile/v1/tools/conversions/91/download'
            : null,
        'poll_after_seconds':
            status == 'pending' || status == 'processing' ? 3 : null,
        'generated_pdf_id': null,
        'created_by': <String, dynamic>{'id': 7, 'name': 'Giulia Rossi'},
        'created_at': '2025-04-02T09:14:22+02:00',
        'started_at': null,
        'completed_at': null,
      };
    }

    test('derives working, finished and failed from the status', () {
      expect(Conversion.fromJson(row(status: 'pending')).isWorking, isTrue);
      expect(Conversion.fromJson(row(status: 'processing')).isWorking, isTrue);
      expect(Conversion.fromJson(row(status: 'completed')).isFinished, isTrue);
      expect(Conversion.fromJson(row(status: 'processed')).isFinished, isTrue);

      final Conversion failed =
          Conversion.fromJson(row(status: 'failed', hasOutput: false));
      expect(failed.isFailed, isTrue);
      expect(failed.isFinished, isTrue);
      expect(failed.isWorking, isFalse);
    });

    test('an unknown status stops the poller rather than spinning', () {
      final Conversion future = Conversion.fromJson(row(status: 'quarantined'));
      expect(future.status, ConversionStatus.unknown);
      expect(future.isWorking, isFalse);
      expect(future.isFinished, isTrue);
    });

    test('downloadability follows the bytes, not the status column', () {
      expect(
        Conversion.fromJson(row(status: 'completed')).isDownloadable,
        isTrue,
      );
      // Swept by the retention job: still "completed", nothing to download.
      final Conversion swept =
          Conversion.fromJson(row(status: 'completed', hasOutput: false));
      expect(swept.isDownloadable, isFalse);
      expect(swept.canRetry, isTrue);
    });

    test('retry and delete follow the server rules', () {
      expect(Conversion.fromJson(row(status: 'failed')).canRetry, isTrue);
      expect(Conversion.fromJson(row(status: 'completed')).canRetry, isFalse);
      // The visual editor has no mobile equivalent, so its rows are never
      // retryable here.
      expect(
        Conversion.fromJson(row(status: 'failed', tool: 'edit-pdf')).canRetry,
        isFalse,
      );
      expect(
        Conversion.fromJson(row(status: 'processing')).canDelete,
        isFalse,
      );
      expect(Conversion.fromJson(row(status: 'failed')).canDelete, isTrue);
    });

    test('falls back through the names it has for a headline', () {
      final Map<String, dynamic> untitled = row(status: 'completed')
        ..['title'] = null;
      expect(Conversion.fromJson(untitled).displayTitle, 'merged.pdf');

      final Map<String, dynamic> bare = row(status: 'completed')
        ..['title'] = null
        ..['output_filename'] = null
        ..['original_filename'] = null;
      expect(Conversion.fromJson(bare).displayTitle, 'Merge PDF');
      expect(Conversion.fromJson(bare).downloadFilename, 'conversion-91');
    });
  });

  group('ConversionStatusInfo', () {
    test('settles when the server withdraws the interval', () {
      final ConversionStatusInfo running =
          ConversionStatusInfo.fromJson(<String, dynamic>{
        'id': 91,
        'status': 'processing',
        'error_message': null,
        'download_url': null,
        'poll_after_seconds': 3,
      });
      expect(running.isSettled, isFalse);

      final ConversionStatusInfo done =
          ConversionStatusInfo.fromJson(<String, dynamic>{
        'id': 91,
        'status': 'completed',
        'error_message': null,
        'download_url':
            'https://banksheet.pro/api/mobile/v1/tools/conversions/91/download',
        'poll_after_seconds': null,
      });
      expect(done.isSettled, isTrue);
      expect(done.status.isSucceeded, isTrue);
    });

    test('carries the failure message', () {
      final ConversionStatusInfo failed =
          ConversionStatusInfo.fromJson(<String, dynamic>{
        'id': 91,
        'status': 'failed',
        'error_message': 'Ghostscript could not read the file.',
        'download_url': null,
        'poll_after_seconds': null,
      });
      expect(failed.isSettled, isTrue);
      expect(failed.status.isFailed, isTrue);
      expect(failed.error, 'Ghostscript could not read the file.');
    });
  });

  group('QueuedConversion', () {
    test('parses the 202 body', () {
      final QueuedConversion queued =
          QueuedConversion.fromJson(<String, dynamic>{
        'id': 512,
        'tool': 'compress-pdf',
        'status': 'pending',
        'poll_after_seconds': 3,
      });
      expect(queued.id, 512);
      expect(queued.tool, 'compress-pdf');
      expect(queued.status, ConversionStatus.pending);
      expect(queued.pollAfterSeconds, 3);
    });
  });
}
