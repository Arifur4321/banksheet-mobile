/// The PDF tool catalogue, exactly as `GET /tools` publishes it.
///
/// `ToolController::optionSchema()` is a 1:1 description of the validation rules
/// the same controller applies on submit. That is what makes one generic,
/// schema-driven form possible for thirteen tools: the app draws whatever the
/// server describes and refuses a bad DPI before spending the user's mobile
/// data on an upload the server would reject anyway.
///
/// Nothing here is invented. Every field maps onto a key in `ToolResource`, and
/// the five wire type tokens the server emits (`string`, `text`, `json`, `int`,
/// `enum`) are folded into the four widgets the app knows how to draw.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../../core/i18n/strings.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/json.dart';

/// How one option is rendered.
///
/// Four cases rather than the server's five: `string` and `text` differ only in
/// how many lines the field gets, and `json` is a long text field with one more
/// validation rule — see [ToolOption.isJson].
enum ToolOptionType {
  /// A closed set of values — a dropdown built from `values`.
  enumChoice,

  /// A bounded integer — a stepper between `min` and `max`.
  integer,

  /// A single-line string.
  text,

  /// A multi-line string (HTML bodies, variable lists, JSON objects).
  longText,
}

/// The server's `required_if` clause: "required when `field` equals `value`".
@immutable
class ToolOptionCondition {
  const ToolOptionCondition({required this.field, required this.value});

  static ToolOptionCondition? fromJson(dynamic raw) {
    final Map<String, dynamic> map = J.map(raw);
    final String? field = J.str(map['field']);
    if (field == null) {
      return null;
    }
    return ToolOptionCondition(field: field, value: J.strOr(map['value'], ''));
  }

  final String field;
  final String value;

  /// True when the rest of the form makes this option mandatory.
  bool isMetBy(Map<String, String?> form) => (form[field] ?? '') == value;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ToolOptionCondition &&
          other.field == field &&
          other.value == value;

  @override
  int get hashCode => Object.hash(field, value);
}

/// One entry of the twelve-key option schema.
@immutable
class ToolOption {
  const ToolOption({
    required this.name,
    required this.rawType,
    required this.type,
    required this.label,
    required this.required,
    required this.values,
    this.defaultValue,
    this.min,
    this.max,
    this.maxLength,
    this.pattern,
    this.patternRegex,
    this.requiredIf,
    this.help,
  });

  factory ToolOption.fromJson(Map<String, dynamic> json) {
    final String rawType = J.strOr(json['type'], 'string');
    final String? pattern = J.str(json['pattern']);

    return ToolOption(
      name: J.strOr(json['name'], ''),
      rawType: rawType,
      type: _typeFor(rawType),
      label: J.strOr(json['label'], Fmt.humanise(J.str(json['name']))),
      required: J.boolOr(json['required']),
      values: J.strings(json['values']),
      // `default` is `mixed` on the wire — dpi arrives as the number 200 and
      // split_mode as the string "every-page". Both are held as text because
      // that is what a form field edits; [defaultInt] casts back on demand.
      defaultValue: J.str(json['default']),
      min: J.intOrNull(json['min']),
      max: J.intOrNull(json['max']),
      maxLength: J.intOrNull(json['max_length']),
      pattern: pattern,
      patternRegex: _compile(pattern),
      requiredIf: ToolOptionCondition.fromJson(json['required_if']),
      help: J.str(json['help']),
    );
  }

  /// Field name to post, e.g. `page_range`.
  final String name;

  /// The server's own token: `string`, `text`, `json`, `int` or `enum`. Kept so
  /// a JSON field stays distinguishable after the fold into [type].
  final String rawType;

  final ToolOptionType type;
  final String label;
  final bool required;

  /// Allowed values for [ToolOptionType.enumChoice]; always present, empty for
  /// every other type.
  final List<String> values;

  final String? defaultValue;
  final int? min;
  final int? max;
  final int? maxLength;

  /// The server's regex source, without delimiters.
  final String? pattern;

  /// [pattern] compiled once, or null when the server sent none — or sent one
  /// this platform cannot compile, in which case the server still enforces it.
  final RegExp? patternRegex;

  final ToolOptionCondition? requiredIf;
  final String? help;

  /// True for `variables_json`, which must parse as a JSON object.
  bool get isJson => rawType == 'json';

  /// The default as a number, for the integer stepper.
  int? get defaultInt => J.intOrNull(defaultValue);

  /// True when this option can never be left blank, whatever else is filled in.
  bool get isAlwaysRequired => required;

  /// True when the rest of the form currently makes this option mandatory.
  bool isRequiredIn(Map<String, String?> form) =>
      required || (requiredIf?.isMetBy(form) ?? false);

  /// The same rules `ToolController::validateTool()` applies, minus the ones
  /// that need the file itself. Returns null when [raw] is acceptable.
  ///
  /// [form] carries the other field values so `required_if` can be evaluated;
  /// an option nobody has filled in is only an error when something else in the
  /// form made it mandatory.
  String? validate(
    String? raw, {
    Map<String, String?> form = const <String, String?>{},
  }) {
    final String value = (raw ?? '').trim();

    if (value.isEmpty) {
      return isRequiredIn(form) ? S.required : null;
    }

    final int? limit = maxLength;
    if (limit != null && value.length > limit) {
      return S.maxCharacters(limit);
    }

    if (type == ToolOptionType.integer) {
      final String? bounds = _boundsError(value);
      if (bounds != null) {
        return bounds;
      }
    }

    if (type == ToolOptionType.enumChoice &&
        values.isNotEmpty &&
        !values.contains(value)) {
      return S.invalidChoice;
    }

    if (isJson && !_isJsonObject(value)) {
      return S.invalidJson;
    }

    final RegExp? regex = patternRegex;
    if (regex != null && !regex.hasMatch(value)) {
      return S.invalidFormat;
    }

    return null;
  }

  /// `min`/`max` against a parsed integer, or null when it fits.
  String? _boundsError(String value) {
    final int? parsed = int.tryParse(value);
    if (parsed == null) {
      return S.mustBeNumber;
    }

    final int? low = min;
    final int? high = max;

    if (low != null && high != null && (parsed < low || parsed > high)) {
      return S.valueBetween(low, high);
    }
    if (low != null && parsed < low) {
      return S.valueAtLeast(low);
    }
    if (high != null && parsed > high) {
      return S.valueAtMost(high);
    }
    return null;
  }

  static ToolOptionType _typeFor(String raw) => switch (raw) {
        'enum' => ToolOptionType.enumChoice,
        'int' || 'integer' => ToolOptionType.integer,
        'text' || 'json' => ToolOptionType.longText,
        _ => ToolOptionType.text,
      };

  static RegExp? _compile(String? pattern) {
    if (pattern == null) {
      return null;
    }
    try {
      return RegExp(pattern);
    } on FormatException {
      // A pattern Dart cannot compile is not a reason to block the submission:
      // the server applies the same rule and will answer 422 with a message
      // written for a person.
      return null;
    }
  }

  static bool _isJsonObject(String value) {
    try {
      return jsonDecode(value) is Map;
    } on FormatException {
      return false;
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ToolOption &&
          other.name == name &&
          other.rawType == rawType &&
          other.label == label &&
          other.required == required &&
          listEquals(other.values, values) &&
          other.defaultValue == defaultValue &&
          other.min == min &&
          other.max == max &&
          other.maxLength == maxLength &&
          other.pattern == pattern &&
          other.requiredIf == requiredIf &&
          other.help == help;

  @override
  int get hashCode => Object.hash(
        name,
        rawType,
        label,
        required,
        Object.hashAll(values),
        defaultValue,
        min,
        max,
        maxLength,
        pattern,
        requiredIf,
        help,
      );

  @override
  String toString() => 'ToolOption($name, $rawType)';
}

/// The three groups the tools screen renders as sections.
///
/// A presentation concern that lives here because the grouping is a property of
/// the tool, not of the screen — the dashboard's shortcuts use it too.
enum ToolCategory {
  pdfUtilities,
  documentConversion,
  imageConversion;

  String get label => switch (this) {
        ToolCategory.pdfUtilities => S.toolsPdfUtilities,
        ToolCategory.documentConversion => S.toolsDocumentConversion,
        ToolCategory.imageConversion => S.toolsImageConversion,
      };
}

/// One tool, with everything needed to draw and submit its form.
@immutable
class ToolDefinition {
  const ToolDefinition({
    required this.key,
    required this.label,
    required this.acceptedExtensions,
    required this.multiple,
    required this.maxFiles,
    required this.maxFileKb,
    required this.supported,
    required this.options,
    this.badge,
    this.description,
    this.submitLabel,
    this.acceptedLabel,
    this.accept,
    this.fileField,
    this.warning,
    this.unsupportedReason,
  });

  factory ToolDefinition.fromJson(Map<String, dynamic> json) {
    final String key = J.strOr(json['key'], '');

    return ToolDefinition(
      key: key,
      label: J.strOr(json['label'], Fmt.humanise(key)),
      badge: J.str(json['badge']),
      description: J.str(json['description']),
      submitLabel: J.str(json['submit_label']),
      acceptedLabel: J.str(json['accepted_label']),
      acceptedExtensions: J
          .strings(json['accepted_extensions'])
          .map((String e) => e.toLowerCase())
          .toList(growable: false),
      accept: J.str(json['accept']),
      multiple: J.boolOr(json['multiple']),
      fileField: J.str(json['file_field']),
      maxFiles: J.intOr(json['max_files'], 0),
      maxFileKb: J.intOr(json['max_file_kb'], 0),
      warning: J.str(json['warning']),
      supported: J.boolOr(json['supported'], fallback: true),
      unsupportedReason: J.str(json['unsupported_reason']),
      options: J
          .list(json['options'])
          .map(ToolOption.fromJson)
          .where((ToolOption o) => o.name.isNotEmpty)
          .toList(growable: false),
    );
  }

  /// Tool key, e.g. `merge-pdf`. The path segment of `POST /tools/{tool}/convert`.
  final String key;

  final String label;
  final String? badge;
  final String? description;

  /// The web's own button copy, e.g. "Merge PDFs".
  final String? submitLabel;

  /// Human-readable accepted formats, e.g. "DOC, DOCX, ODT, RTF".
  final String? acceptedLabel;

  /// The machine list the file picker is restricted to. Empty for html-to-pdf,
  /// which takes no upload at all.
  final List<String> acceptedExtensions;

  /// The HTML accept attribute, kept verbatim from the web form.
  final String? accept;

  final bool multiple;

  /// The multipart field name: `file`, or `files[]` when [multiple].
  final String? fileField;

  final int maxFiles;
  final int maxFileKb;

  /// A caveat the web prints in a warning box (PDF to Word only, today).
  final String? warning;

  /// False for edit-pdf, the one tool whose visual editor is web-only.
  final bool supported;

  final String? unsupportedReason;

  final List<ToolOption> options;

  ToolCategory get category => _categoryFor(key);

  /// True when this tool wants an upload. html-to-pdf renders from a field.
  bool get needsFiles => maxFiles > 0;

  /// The validator's floor, mirroring `validateTool()`: merge-pdf needs two
  /// PDFs to merge, every other uploading tool needs one.
  int get minFiles {
    if (!needsFiles) {
      return 0;
    }
    return key == 'merge-pdf' ? 2 : 1;
  }

  int get maxFileBytes => maxFileKb * 1024;

  /// The multipart field, resolved. The server reads `files` for a multiple
  /// tool and `file` otherwise, so the `[]` suffix the web form carries is
  /// stripped rather than posted.
  String get uploadField {
    final String? declared = fileField;
    if (declared == null || declared.isEmpty) {
      return multiple ? 'files' : 'file';
    }
    return declared.endsWith('[]')
        ? declared.substring(0, declared.length - 2)
        : declared;
  }

  /// The title option, which `validateTool()`'s `$base` rules give every tool.
  ToolOption? get titleOption => optionNamed('title');

  /// Everything except the title, in the order the server listed it.
  List<ToolOption> get formOptions =>
      options.where((ToolOption o) => o.name != 'title').toList(growable: false);

  ToolOption? optionNamed(String name) {
    for (final ToolOption option in options) {
      if (option.name == name) {
        return option;
      }
    }
    return null;
  }

  /// Every option's default, ready to seed a form.
  Map<String, String> get defaults => <String, String>{
        for (final ToolOption option in options)
          if (option.defaultValue != null) option.name: option.defaultValue!,
      };

  static ToolCategory _categoryFor(String key) => switch (key) {
        'pdf-to-word' ||
        'office-to-pdf' ||
        'html-to-pdf' ||
        'extract-text' =>
          ToolCategory.documentConversion,
        'images-to-pdf' || 'pdf-to-images' => ToolCategory.imageConversion,
        _ => ToolCategory.pdfUtilities,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is ToolDefinition && other.key == key;

  @override
  int get hashCode => key.hashCode;

  @override
  String toString() => 'ToolDefinition($key)';
}

/// The plan-scoped ceilings published alongside the tools.
///
/// [maxMergeFiles] is the one that matters on the client: `max_files` on the
/// tool is the validator's hard ceiling (the largest any plan allows), while
/// this is what THIS workspace may actually send.
@immutable
class ToolLimits {
  const ToolLimits({
    required this.maxMergeFiles,
    required this.maxPagesPerFile,
    required this.maxTotalPages,
    required this.maxTotalUploadKb,
    required this.maxFileKb,
  });

  factory ToolLimits.fromJson(Map<String, dynamic> json) => ToolLimits(
        maxMergeFiles: J.intOr(json['max_merge_files'], 2),
        maxPagesPerFile: J.intOr(json['max_pages_per_file'], 100),
        maxTotalPages: J.intOr(json['max_total_pages'], 200),
        maxTotalUploadKb: J.intOr(json['max_total_upload_kb'], 51200),
        maxFileKb: J.intOr(json['max_file_kb'], 51200),
      );

  static const ToolLimits fallback = ToolLimits(
    maxMergeFiles: 2,
    maxPagesPerFile: 100,
    maxTotalPages: 200,
    maxTotalUploadKb: 51200,
    maxFileKb: 51200,
  );

  final int maxMergeFiles;
  final int maxPagesPerFile;
  final int maxTotalPages;
  final int maxTotalUploadKb;
  final int maxFileKb;

  int get maxTotalUploadBytes => maxTotalUploadKb * 1024;
  int get maxFileBytes => maxFileKb * 1024;
}

/// The conversion and page allowance, when the caller has a workspace.
@immutable
class ToolUsage {
  const ToolUsage({
    this.remainingConversions,
    this.conversionLimit,
    this.usedConversions,
    this.remainingPages,
    this.pageLimit,
    this.usedPages,
  });

  factory ToolUsage.fromJson(Map<String, dynamic> json) => ToolUsage(
        remainingConversions: J.intOrNull(json['remaining_conversions']),
        conversionLimit: J.intOrNull(json['monthly_conversion_limit']),
        usedConversions: J.intOrNull(json['used_conversions']),
        remainingPages: J.intOrNull(json['remaining_pages']),
        pageLimit: J.intOrNull(json['monthly_page_limit']),
        usedPages: J.intOrNull(json['used_pages']),
      );

  final int? remainingConversions;
  final int? conversionLimit;
  final int? usedConversions;
  final int? remainingPages;
  final int? pageLimit;
  final int? usedPages;

  /// A limit of zero means "not metered on this plan", which reads to a person
  /// as no ceiling rather than as a ceiling of nothing.
  bool get conversionsUnlimited => (conversionLimit ?? 0) <= 0;

  bool get conversionsExhausted =>
      !conversionsUnlimited && (remainingConversions ?? 1) <= 0;
}

/// The whole `GET /tools` payload.
@immutable
class ToolCatalogue {
  const ToolCatalogue({
    required this.tools,
    required this.limits,
    this.usage,
  });

  factory ToolCatalogue.fromJson(Map<String, dynamic> json) => ToolCatalogue(
        tools: J
            .list(json['tools'])
            .map(ToolDefinition.fromJson)
            .where((ToolDefinition t) => t.key.isNotEmpty)
            .toList(growable: false),
        limits: ToolLimits.fromJson(J.map(json['limits'])),
        usage: json['usage'] == null
            ? null
            : ToolUsage.fromJson(J.map(json['usage'])),
      );

  final List<ToolDefinition> tools;
  final ToolLimits limits;
  final ToolUsage? usage;

  ToolDefinition? byKey(String key) {
    for (final ToolDefinition tool in tools) {
      if (tool.key == key) {
        return tool;
      }
    }
    return null;
  }

  List<ToolDefinition> inCategory(ToolCategory category) => tools
      .where((ToolDefinition t) => t.category == category)
      .toList(growable: false);

  /// How many files this workspace may actually send to [tool] — the lower of
  /// the validator's ceiling and the plan's.
  int maxFilesFor(ToolDefinition tool) {
    if (tool.key != 'merge-pdf') {
      return tool.maxFiles;
    }
    return tool.maxFiles < limits.maxMergeFiles
        ? tool.maxFiles
        : limits.maxMergeFiles;
  }
}
