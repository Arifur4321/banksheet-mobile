/// Plain-English wording for the PDF tools, for the app only.
///
/// The server describes each tool in terms of what it runs — "with LibreOffice
/// headless", "local Ghostscript quality presets", "a qpdf page range", "with
/// Poppler", "OCR fallback", "linearize". That is exactly right for the API
/// documentation and for the workspace on banksheet.pro, where the audience
/// knows what those are. On a phone it reads as somebody else's release notes.
///
/// So this file is a **presentation layer and nothing else**. It maps a tool key
/// or an option name to a sentence a person can act on, and falls back to the
/// server's own text whenever it has nothing better to say — a tool added on the
/// server tomorrow still shows up, still works, and simply keeps the server's
/// wording until someone writes a line for it here.
///
/// **What this file must never touch.** Only the four display strings below are
/// rewritten: a tool's description, an option's label, an option's help, and the
/// text shown for one choice in a dropdown. Everything the server and the client
/// agree on stays byte-identical — tool keys, option names, option values,
/// defaults, `min`/`max`, `max_length`, `pattern`, `required`, `required_if`.
/// The value posted for "Smallest -- for viewing on a screen" is still exactly
/// `screen`. Changing anything here can change what a person reads; it can never
/// change what the app sends.
///
/// Tool names and badges are deliberately left alone. "Merge PDF", "Split PDF"
/// and "OCR PDF" are what people search for, what the website's navigation says
/// and what support conversations use; renaming them in one client only would
/// make those three disagree.
library;

import '../../../core/utils/formatters.dart';

abstract final class ToolCopy {
  // ---------------------------------------------------------------- tools

  /// What the tool does, in one or two sentences.
  ///
  /// Returns [serverText] unchanged for any key not listed, so an unknown tool
  /// is never left with a blank description.
  static String? description(String toolKey, String? serverText) =>
      _descriptions[toolKey] ?? serverText;

  static const Map<String, String> _descriptions = <String, String>{
    'pdf-to-word':
        'Turn a PDF into a Word document you can edit. If the pages were '
            'scanned, we read the words off the picture for you.',
    'office-to-pdf':
        'Turn a Word document into a PDF, so it looks the same on every '
            'screen and printer.',
    'images-to-pdf':
        'Put your photos or scans together into one PDF, without losing '
            'quality.',
    'pdf-to-images':
        'Save every page of a PDF as a picture. They all come back in a '
            'single download.',
    'merge-pdf':
        'Join several PDFs into one. Put them in the order you want first — '
            'nothing is squashed or re-saved.',
    'split-pdf':
        'Break a PDF into separate pages, or pull out just the pages you '
            'need.',
    'rotate-pdf':
        'Turn pages the right way up. Do the whole file, or only the pages '
            'you pick.',
    'compress-pdf':
        'Make a PDF smaller, so it is easier to email or upload.',
    'ocr-pdf':
        'Make a scanned PDF searchable, so you can find, select and copy the '
            'words in it.',
    'extract-text':
        'Pull the plain text out of a PDF, kept in reading order.',
    'html-to-pdf':
        'Build a contract, invoice or letter and get it back as a finished '
            'PDF.',
    'repair-pdf':
        'Fix a PDF that will not open properly, and tidy it up so other '
            'programs accept it.',
    'edit-pdf':
        'Change the words on a page, hide something, or swap a picture.',
  };

  // -------------------------------------------------------------- options

  /// The caption above a field.
  static String optionLabel(String optionName, String serverText) =>
      _optionLabels[optionName] ?? serverText;

  /// The line of guidance under a field.
  static String? optionHelp(String optionName, String? serverText) =>
      _optionHelp[optionName] ?? serverText;

  /// Option names are unique across the whole tool catalogue, so the option
  /// name alone is enough to look copy up — no tool key needs threading
  /// through the widgets.
  static const Map<String, String> _optionLabels = <String, String>{
    'image_format': 'Picture type',
    'dpi': 'Picture detail',
    'split_mode': 'How to split it',
    'page_range': 'Which pages',
    'excluded_pages': 'Pages to leave out',
    'rotation': 'Turn by',
    'pages': 'Which pages',
    'quality': 'How much to shrink it',
    'html_content': 'Document content',
    'variables': 'Details to fill in',
    'variables_json': 'Details to fill in (advanced)',
  };

  static const Map<String, String> _optionHelp = <String, String>{
    'title': 'A name to help you find this again later. Leave it empty to use '
        'the file name.',
    'image_format':
        'JPG pictures are smaller. PNG keeps text and thin lines sharper.',
    'dpi': 'Higher numbers look sharper, but the pictures are bigger and take '
        'longer to make.',
    'split_mode': 'Either every page becomes its own file, or you get one file '
        'containing only the pages you list below.',
    'page_range': 'For example 1-3, or 2,4,6-8. Type z for the last page, so '
        '1-z means all of them.',
    'excluded_pages':
        'Any pages you do not want in the result, for example 1,5,9-12.',
    'rotation': 'How far to turn the pages, clockwise.',
    'pages': 'Leave this as 1-z to turn every page, or list the ones you want, '
        'like 2,5-7.',
    'quality': 'Smaller files lose a little sharpness. Pick the one that '
        'matches how the file will be used.',
    'html_content': 'The content of your document. Anything you write as '
        '{{ name }} is replaced with the details you set below.',
    'variables':
        'One per line, written as name=value. For example: client=Rossi Ltd',
    'variables_json': 'Another way to give the same details. If you fill this '
        'in, it is used instead of the list above.',
  };

  // -------------------------------------------------------------- choices

  /// The text shown for one dropdown choice.
  ///
  /// [value] is the wire value and is what gets posted; only the label changes.
  /// Anything unlisted falls back to [Fmt.humanise], which is what the field
  /// did before this file existed.
  static String choiceLabel(String optionName, String value) =>
      _choices['$optionName:$value'] ?? Fmt.humanise(value);

  static const Map<String, String> _choices = <String, String>{
    'image_format:jpeg': 'JPG — smaller files',
    'image_format:png': 'PNG — sharper text',

    'split_mode:every-page': 'Every page on its own',
    'split_mode:range': 'Only the pages I choose',

    'rotation:90': '90° — a quarter turn right',
    'rotation:180': '180° — upside down',
    'rotation:270': '270° — a quarter turn left',

    // Ghostscript's own preset names. What they mean is not guessable from the
    // word, so the label says what the file is for and the size trade-off.
    'quality:screen': 'Smallest — for reading on a screen',
    'quality:ebook': 'Small — good for emailing',
    'quality:printer': 'Larger — good for printing',
    'quality:prepress': 'Largest — best possible quality',
  };
}
