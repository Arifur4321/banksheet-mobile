/// The contract `ToolCopy` has to keep: it may change what a person reads, and
/// it may never change what the app sends.
///
/// The friendly wording is a client-side override of the server's own tool
/// descriptions and option help. That is a presentation decision, and the risk
/// it carries is precise — if a rewrite ever leaked into an option's `name` or
/// into one of its allowed `values`, the form would post something the
/// validator rejects, and it would do so only for the one tool nobody retested.
/// These tests pin the boundary.
library;

import 'package:banksheet_mobile/features/tools/domain/tool_copy.dart';
import 'package:banksheet_mobile/core/utils/formatters.dart';
import 'package:flutter_test/flutter_test.dart';

/// Every tool key `DocumentConversionService::tools()` publishes.
const List<String> _serverToolKeys = <String>[
  'pdf-to-word',
  'office-to-pdf',
  'images-to-pdf',
  'pdf-to-images',
  'merge-pdf',
  'split-pdf',
  'rotate-pdf',
  'compress-pdf',
  'ocr-pdf',
  'extract-text',
  'html-to-pdf',
  'repair-pdf',
  'edit-pdf',
];

/// The infrastructure names and acronyms this rewrite exists to remove.
final RegExp _jargon = RegExp(
  r'\b(libreoffice|ghostscript|qpdf|poppler|tesseract|ocrmypdf|browsershot|'
  r'blade|headless|linearize|fallback|locally|dpi|mime|payload|endpoint)\b',
  caseSensitive: false,
);

void main() {
  group('ToolCopy descriptions', () {
    test('every tool the server publishes has plain-English wording', () {
      for (final String key in _serverToolKeys) {
        final String? text = ToolCopy.description(key, 'SERVER TEXT');
        expect(text, isNotNull, reason: '$key has no description');
        expect(text, isNot('SERVER TEXT'), reason: '$key was not rewritten');
      }
    });

    test('no description contains an infrastructure name or an acronym', () {
      for (final String key in _serverToolKeys) {
        final String text = ToolCopy.description(key, '')!;
        expect(
          _jargon.hasMatch(text),
          isFalse,
          reason: '$key still reads like release notes: $text',
        );
      }
    });

    test('an unknown tool keeps whatever the server sent', () {
      // A tool added on the server tomorrow must still appear, described in the
      // server's own words, rather than silently losing its description.
      expect(
        ToolCopy.description('some-new-tool', 'Server wording'),
        'Server wording',
      );
      expect(ToolCopy.description('some-new-tool', null), isNull);
    });
  });

  group('ToolCopy option text', () {
    test('known fields are rewritten and unknown ones fall through', () {
      expect(ToolCopy.optionLabel('quality', 'Quality preset'),
          'How much to shrink it');
      expect(ToolCopy.optionLabel('unheard_of', 'Server label'), 'Server label');

      expect(ToolCopy.optionHelp('rotation', 'Clockwise degrees.'),
          'How far to turn the pages, clockwise.');
      expect(ToolCopy.optionHelp('unheard_of', 'Server help'), 'Server help');
      expect(ToolCopy.optionHelp('unheard_of', null), isNull);
    });

    test('no field label or help contains an acronym or a program name', () {
      const List<String> names = <String>[
        'title', 'image_format', 'dpi', 'split_mode', 'page_range',
        'excluded_pages', 'rotation', 'pages', 'quality', 'html_content',
        'variables', 'variables_json',
      ];
      for (final String name in names) {
        final String label = ToolCopy.optionLabel(name, '');
        final String help = ToolCopy.optionHelp(name, '') ?? '';
        expect(_jargon.hasMatch(label), isFalse, reason: '$name label: $label');
        expect(_jargon.hasMatch(help), isFalse, reason: '$name help: $help');
      }
    });
  });

  group('ToolCopy choices', () {
    test('a choice gets a friendlier label', () {
      expect(ToolCopy.choiceLabel('quality', 'screen'),
          'Smallest — for reading on a screen');
      expect(ToolCopy.choiceLabel('split_mode', 'every-page'),
          'Every page on its own');
    });

    test('an unlisted choice falls back to the old humanised label', () {
      // This is what the dropdown did before ToolCopy existed, so a value the
      // server adds later is still readable rather than blank.
      expect(
        ToolCopy.choiceLabel('quality', 'something-new'),
        Fmt.humanise('something-new'),
      );
      expect(
        ToolCopy.choiceLabel('not_an_option', 'ebook'),
        Fmt.humanise('ebook'),
      );
    });

    test('relabelling a choice never changes the value posted', () {
      // The widget builds DropdownMenuItem(value: choice, child: Text(label)),
      // so the label and the wire value are independent by construction. This
      // asserts the intent: every label differs from its value, and looking one
      // up never mutates it.
      const Map<String, List<String>> wire = <String, List<String>>{
        'image_format': <String>['jpeg', 'png'],
        'split_mode': <String>['every-page', 'range'],
        'rotation': <String>['90', '180', '270'],
        'quality': <String>['screen', 'ebook', 'printer', 'prepress'],
      };

      wire.forEach((String option, List<String> values) {
        for (final String value in values) {
          final String label = ToolCopy.choiceLabel(option, value);
          expect(label, isNotEmpty);
          expect(label, isNot(equals(value)),
              reason: '$option:$value was not relabelled');
          // The value is untouched by the lookup.
          expect(ToolCopy.choiceLabel(option, value), label);
        }
      });
    });
  });
}
