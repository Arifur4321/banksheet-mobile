/// Template models: the template itself and one variable in its schema.
///
/// Field names mirror `TemplateResource` exactly, and the variable schema
/// mirrors `Template::variableSchema()` — the same array the server then builds
/// its validation rules from. That is the whole point of this feature: a field
/// the app shows is a field the server accepts, and a required field is
/// required in both places. [TemplateVariable.validate] is that rule set
/// restated on the device, so the user finds out before the round trip.
///
/// `html_content` follows the list-vs-detail convention: the key is always
/// present, valued null everywhere except the detail endpoint. The app never
/// renders it — there is no HTML editor on a phone — but [Template.isDetail]
/// reads the distinction so a screen can tell a list row from a fully loaded
/// template.
library;

import 'package:flutter/foundation.dart';

import '../../../core/i18n/strings.dart';
import '../../../core/utils/json.dart';

/// The seven values `Template::VARIABLE_TYPES` allows, plus a defensive
/// [unknown] that degrades to a plain text field.
enum TemplateVariableType {
  text('text'),
  multiline('multiline'),
  number('number'),
  currency('currency'),
  date('date'),
  email('email'),
  select('select'),
  unknown('');

  const TemplateVariableType(this.wire);

  final String wire;

  static TemplateVariableType from(String? raw) =>
      switch ((raw ?? '').trim().toLowerCase()) {
        'text' => TemplateVariableType.text,
        'multiline' => TemplateVariableType.multiline,
        'number' => TemplateVariableType.number,
        'currency' => TemplateVariableType.currency,
        'date' => TemplateVariableType.date,
        'email' => TemplateVariableType.email,
        'select' => TemplateVariableType.select,
        _ => TemplateVariableType.unknown,
      };
}

/// One field in a template's generate form.
@immutable
class TemplateVariable {
  const TemplateVariable({
    required this.name,
    required this.label,
    required this.type,
    required this.required,
    required this.defaultValue,
    required this.currency,
    required this.dateFormat,
    required this.options,
  });

  factory TemplateVariable.fromJson(Map<String, dynamic> json) {
    final String name = J.strOr(json['name'], '');

    return TemplateVariable(
      name: name,
      // The server humanises the name when no label was set, but a legacy row
      // can still arrive with an empty one; falling back to the name keeps the
      // form from rendering a field with no caption.
      label: J.strOr(json['label'], name),
      type: TemplateVariableType.from(J.str(json['type'])),
      required: J.boolOr(json['required']),
      defaultValue: J.strOr(json['default'], ''),
      currency: J.strOr(json['currency'], 'USD'),
      dateFormat: J.strOr(json['date_format'], 'd/m/Y'),
      options: J.strings(json['options']),
    );
  }

  /// The placeholder name in the HTML, and the key the value is posted under.
  final String name;

  final String label;
  final TemplateVariableType type;
  final bool required;

  /// Pre-filled into the form. Always a string — every variable is substituted
  /// as text, whatever its type.
  final String defaultValue;

  /// ISO code used to format a `currency` field, e.g. `EUR`.
  final String currency;

  /// PHP date format the value will be rendered with, e.g. `d/m/Y`.
  final String dateFormat;

  /// Allowed values for a `select`. Empty for every other type.
  final List<String> options;

  /// The server's `max:5000` on every variable.
  static const int maxLength = 5000;

  /// A one-line explanation under the field.
  ///
  /// `TemplateResource` publishes no help text — there is no such column — so
  /// this is derived from the parts of the schema that do carry meaning for the
  /// person filling the form: which currency the number will be formatted as,
  /// and how a date will be printed.
  String? get hint => switch (type) {
        TemplateVariableType.currency => currency,
        TemplateVariableType.date => dateFormat,
        _ => null,
      };

  /// The device-side half of `TemplateController::generate()`'s rule set.
  ///
  /// Deliberately the same rules in the same order, so a value this returns
  /// null for is a value the server will accept. Returns the message to show
  /// under the field, or null when the value is fine.
  String? validate(String? raw) {
    final String value = (raw ?? '').trim();

    if (value.isEmpty) {
      return required ? S.required : null;
    }

    if (value.length > maxLength) {
      return S.tooLong;
    }

    return switch (type) {
      TemplateVariableType.email =>
        _emailPattern.hasMatch(value) ? null : S.invalidEmail,
      TemplateVariableType.number ||
      TemplateVariableType.currency =>
        _numberPattern.hasMatch(value) ? null : S.mustBeNumber,
      TemplateVariableType.date =>
        DateTime.tryParse(value) == null ? S.invalidDate : null,
      TemplateVariableType.select => options.isEmpty || options.contains(value)
          ? null
          : S.selectOption,
      TemplateVariableType.text ||
      TemplateVariableType.multiline ||
      TemplateVariableType.unknown =>
        null,
    };
  }

  /// `regex:/^-?[0-9.,\s]+$/` from the controller, character for character.
  static final RegExp _numberPattern = RegExp(r'^-?[0-9.,\s]+$');

  /// Deliberately loose. Laravel's `email` rule is looser than any regex worth
  /// writing, and rejecting an address the server would have accepted is the
  /// worse failure.
  static final RegExp _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TemplateVariable &&
          other.name == name &&
          other.label == label &&
          other.type == type &&
          other.required == required &&
          other.defaultValue == defaultValue &&
          other.currency == currency &&
          other.dateFormat == dateFormat &&
          listEquals(other.options, options);

  @override
  int get hashCode => Object.hash(
        name,
        label,
        type,
        required,
        defaultValue,
        currency,
        dateFormat,
        Object.hashAll(options),
      );
}

/// A reusable document template.
@immutable
class Template {
  const Template({
    required this.id,
    required this.variables,
    required this.variablesCount,
    this.name,
    this.type,
    this.generatedPdfsCount,
    this.htmlContent,
    this.createdAt,
    this.updatedAt,
  });

  factory Template.fromJson(Map<String, dynamic> json) {
    final List<TemplateVariable> variables = J
        .list(json['variables'])
        .map(TemplateVariable.fromJson)
        .where((TemplateVariable v) => v.name.isNotEmpty)
        .toList(growable: false);

    return Template(
      id: J.intOr(json['id'], 0),
      name: J.str(json['name']),
      type: J.str(json['type']),
      variables: variables,
      // The server sends its own count; falling back to the parsed length keeps
      // the two from disagreeing if a definition was dropped above.
      variablesCount: J.intOr(json['variables_count'], variables.length),
      generatedPdfsCount: J.intOrNull(json['generated_pdfs_count']),
      htmlContent: J.str(json['html_content']),
      createdAt: J.date(json['created_at']),
      updatedAt: J.date(json['updated_at']),
    );
  }

  final int id;
  final String? name;

  /// The template's own category, e.g. `invoice`. Free text on the server.
  final String? type;

  final List<TemplateVariable> variables;
  final int variablesCount;

  /// Null when the query did not select the count.
  final int? generatedPdfsCount;

  /// Only ever populated by `GET /templates/{id}`; null in list mode. The app
  /// does not render it — see [isDetail].
  final String? htmlContent;

  final DateTime? createdAt;
  final DateTime? updatedAt;

  String get displayName => name ?? S.untitledTemplate;

  /// True when this instance came from the detail endpoint.
  ///
  /// `html_content` is the only field that differs between the two shapes, so
  /// it is also the only honest way to tell them apart — and a template whose
  /// HTML really is empty simply loads again, which costs one request and
  /// cannot show the user anything wrong.
  bool get isDetail => htmlContent != null;

  bool get hasVariables => variables.isNotEmpty;

  /// The form's starting values: every variable's default, keyed by name.
  Map<String, String> get initialValues => <String, String>{
        for (final TemplateVariable variable in variables)
          variable.name: variable.defaultValue,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Template &&
          other.id == id &&
          other.name == name &&
          other.type == type &&
          listEquals(other.variables, variables) &&
          other.variablesCount == variablesCount &&
          other.generatedPdfsCount == generatedPdfsCount &&
          other.htmlContent == htmlContent &&
          other.createdAt == createdAt &&
          other.updatedAt == updatedAt;

  @override
  int get hashCode => Object.hashAll(<Object?>[
        id,
        name,
        type,
        Object.hashAll(variables),
        variablesCount,
        generatedPdfsCount,
        htmlContent,
        createdAt,
        updatedAt,
      ]);
}
