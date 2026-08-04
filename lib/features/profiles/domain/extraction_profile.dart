/// Extraction profile models: the profile row, and the rule blobs behind it.
///
/// Field names mirror `ExtractionProfileResource`. `rules` follows the
/// list-vs-detail convention — the key is present in both shapes, valued null in
/// the list, because four JSON documents of regular expressions would multiply a
/// twenty-row payload for nothing.
///
/// [ProfileRules] does not invent structure. Every accessor on it reads exactly
/// the keys `ExtractionProfileService::compose()` writes, with the same
/// precedence `ProfileOptionResolver` applies when it feeds the parser — the
/// visual builder's state first where the builder owns the value, the legacy
/// rule blob where it does not. Anything it cannot recognise is still there, in
/// the raw sections the detail screen shows under "Advanced".
library;

import 'package:flutter/foundation.dart';

import '../../../core/i18n/strings.dart';
import '../../../core/utils/json.dart';

/// One field of the extracted table and the header text that identifies it.
///
/// The nine keys are `ExtractionProfileService::COLUMN_FIELDS`, in its order —
/// which is the order a statement's columns normally appear in.
enum ProfileColumnField {
  transactionDate('transaction_date'),
  valueDate('value_date'),
  description('description'),
  reference('reference'),
  debit('debit'),
  credit('credit'),
  amount('amount'),
  balance('balance'),
  currency('currency');

  const ProfileColumnField(this.wire);

  final String wire;

  String get label => switch (this) {
        ProfileColumnField.transactionDate => S.date,
        ProfileColumnField.valueDate => S.valueDate,
        ProfileColumnField.description => S.description,
        ProfileColumnField.reference => S.reference,
        ProfileColumnField.debit => S.debit,
        ProfileColumnField.credit => S.credit,
        ProfileColumnField.amount => S.amountColumn,
        ProfileColumnField.balance => S.balance,
        ProfileColumnField.currency => S.currency,
      };
}

/// The parsing rules, as the detail endpoint sends them.
@immutable
class ProfileRules {
  const ProfileRules({
    this.match,
    this.column,
    this.normalization,
    this.postProcessing,
    this.builder,
  });

  factory ProfileRules.fromJson(Map<String, dynamic> json) => ProfileRules(
        match: json['match'] == null ? null : J.map(json['match']),
        column: json['column'] == null ? null : J.map(json['column']),
        normalization: json['normalization'] == null
            ? null
            : J.map(json['normalization']),
        postProcessing: json['post_processing'] == null
            ? null
            : J.map(json['post_processing']),
        builder: json['builder'] == null ? null : J.map(json['builder']),
      );

  /// `match_rules_json` — the keywords that decide whether this profile applies.
  final Map<String, dynamic>? match;

  /// `column_rules_json` — which column is which.
  final Map<String, dynamic>? column;

  /// `normalization_rules_json` — dates, decimals, currency.
  final Map<String, dynamic>? normalization;

  /// `post_processing_rules_json` — what to strip once rows are parsed.
  final Map<String, dynamic>? postProcessing;

  /// `builder_json` — the visual builder's state, and the only human-readable
  /// version of the four blobs above.
  final Map<String, dynamic>? builder;

  /// True when the profile carries no rules at all, which means it can never
  /// match a statement — worth saying out loud rather than showing four empty
  /// sections.
  bool get isEmpty =>
      match == null &&
      column == null &&
      normalization == null &&
      postProcessing == null &&
      builder == null;

  // ------------------------------------------------------------- identity

  String? get country => J.str(builder?['country']);

  /// Read from normalization first, then the builder — the precedence
  /// `ProfileOptionResolver` uses when it hands the value to the parser.
  String? get language =>
      J.str(normalization?['language']) ?? J.str(builder?['language']);

  // ------------------------------------------------- region and formats

  String? get dateFormat =>
      J.str(normalization?['date_format']) ?? J.str(builder?['date_format']);

  String? get currency =>
      J.str(normalization?['currency']) ?? J.str(builder?['currency']);

  String? get decimalSeparator => J.str(normalization?['decimal_separator']);

  /// `us` or `eu` in the builder. Only meaningful alongside [decimalSeparator].
  String? get numberFormat => J.str(builder?['number_format']);

  /// Null when the profile leaves day/month order to the date format.
  bool? get dayFirst {
    final dynamic raw = normalization?['day_first'];
    return raw == null ? null : J.boolOr(raw);
  }

  // --------------------------------------------------------- recognition

  List<String> get statementKeywords => _strings(
        builder?['statement_keywords'],
        fallback: match?['keywords'],
      );

  List<String> get headerKeywords => _strings(
        builder?['header_keywords'],
        fallback: match?['headers'],
      );

  List<String> get tableStartKeywords =>
      J.strings(builder?['table_start_keywords']);

  List<String> get tableEndKeywords => _strings(
        builder?['table_end_keywords'],
        fallback: postProcessing?['stop_sections'],
      );

  /// Everything the parser throws away: repeated headers, footers and the
  /// user's own ignore patterns, which the server merges into one list.
  List<String> get ignoredLines {
    final List<String> merged = <String>[
      ...J.strings(postProcessing?['ignore_lines']),
      ...J.strings(builder?['repeated_headers']),
      ...J.strings(builder?['footer_lines']),
      ...J.strings(builder?['ignore_patterns']),
    ];
    return List<String>.unmodifiable(<String>{...merged});
  }

  List<String> get cleanupRules => J.strings(postProcessing?['cleanup_regex']);

  // ------------------------------------------------------ column mapping

  /// Field to header text, for the fields this profile actually maps.
  Map<ProfileColumnField, String> get columnMap {
    final Map<String, dynamic> raw = builder?['column_map'] is Map
        ? J.map(builder?['column_map'])
        : J.map(column?['column_map']);

    final Map<ProfileColumnField, String> mapped =
        <ProfileColumnField, String>{};

    for (final ProfileColumnField field in ProfileColumnField.values) {
      final String? header = J.str(raw[field.wire]);
      if (header != null) {
        mapped[field] = header;
      }
    }

    return Map<ProfileColumnField, String>.unmodifiable(mapped);
  }

  /// The header texts the matcher scores against, when no field mapping exists.
  List<String> get columns => J.strings(column?['columns']);

  /// `separate` (debit and credit columns) or `single` (one signed amount).
  String? get amountMode => J.str(builder?['amount_mode']);

  bool? get inferFromBalance {
    final dynamic raw = builder?['infer_from_balance'];
    return raw == null ? null : J.boolOr(raw);
  }

  bool? get mergeMultiline {
    final dynamic raw = builder?['merge_multiline'];
    return raw == null ? null : J.boolOr(raw);
  }

  String? get amountPattern =>
      J.str(column?['amount_regex']) ?? J.str(builder?['amount_regex']);

  /// The blobs as they arrived, for the "Advanced" disclosure. Only the ones
  /// that exist, so the raw view never shows an empty heading.
  List<(String, Map<String, dynamic>)> get rawSections =>
      <(String, Map<String, dynamic>)>[
        if (match != null) (S.rulesMatch, match!),
        if (column != null) (S.rulesColumn, column!),
        if (normalization != null) (S.rulesNormalization, normalization!),
        if (postProcessing != null) (S.rulesPostProcessing, postProcessing!),
        if (builder != null) (S.rulesBuilder, builder!),
      ];

  /// Prefers [primary], falls back to [fallback], never returns null.
  static List<String> _strings(dynamic primary, {dynamic fallback}) {
    final List<String> first = J.strings(primary);
    return first.isNotEmpty ? first : J.strings(fallback);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ProfileRules &&
          mapEquals(other.match, match) &&
          mapEquals(other.column, column) &&
          mapEquals(other.normalization, normalization) &&
          mapEquals(other.postProcessing, postProcessing) &&
          mapEquals(other.builder, builder);

  @override
  int get hashCode => Object.hash(
        match?.length,
        column?.length,
        normalization?.length,
        postProcessing?.length,
        builder?.length,
      );
}

/// A parsing layout for one bank's statement format.
@immutable
class ExtractionProfile {
  const ExtractionProfile({
    required this.id,
    required this.isActive,
    required this.hasSample,
    this.name,
    this.documentType,
    this.bankName,
    this.lastMatchedAt,
    this.documentsCount,
    this.transactionsCount,
    this.rules,
    this.createdAt,
    this.updatedAt,
  });

  factory ExtractionProfile.fromJson(Map<String, dynamic> json) =>
      ExtractionProfile(
        id: J.intOr(json['id'], 0),
        name: J.str(json['name']),
        documentType: J.str(json['document_type']),
        bankName: J.str(json['bank_name']),
        isActive: J.boolOr(json['is_active']),
        lastMatchedAt: J.date(json['last_matched_at']),
        documentsCount: J.intOrNull(json['documents_count']),
        transactionsCount: J.intOrNull(json['transactions_count']),
        hasSample: J.boolOr(json['has_sample']),
        rules: json['rules'] == null
            ? null
            : ProfileRules.fromJson(J.map(json['rules'])),
        createdAt: J.date(json['created_at']),
        updatedAt: J.date(json['updated_at']),
      );

  final int id;
  final String? name;

  /// `bank_statement`, `invoice` or `generic_pdf`.
  final String? documentType;

  final String? bankName;

  /// Only active profiles are considered by the matcher.
  final bool isActive;

  /// When this profile last won a document. Null means it never has.
  final DateTime? lastMatchedAt;

  /// Null (not zero) when the query did not select the count.
  final int? documentsCount;
  final int? transactionsCount;

  /// A sample statement is stored with the profile on the website.
  final bool hasSample;

  /// Null in list mode. Present, possibly with null members, in detail mode.
  final ProfileRules? rules;

  final DateTime? createdAt;
  final DateTime? updatedAt;

  String get displayName => name ?? bankName ?? S.profileNumber(id);

  /// True when this instance came from the detail endpoint.
  bool get isDetail => rules != null;

  /// Optimistic toggle: the row is redrawn immediately and rolled back by
  /// handing the previous value back if the request fails.
  ExtractionProfile withActive({required bool active}) => ExtractionProfile(
        id: id,
        name: name,
        documentType: documentType,
        bankName: bankName,
        isActive: active,
        lastMatchedAt: lastMatchedAt,
        documentsCount: documentsCount,
        transactionsCount: transactionsCount,
        hasSample: hasSample,
        rules: rules,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ExtractionProfile &&
          other.id == id &&
          other.name == name &&
          other.documentType == documentType &&
          other.bankName == bankName &&
          other.isActive == isActive &&
          other.lastMatchedAt == lastMatchedAt &&
          other.documentsCount == documentsCount &&
          other.transactionsCount == transactionsCount &&
          other.hasSample == hasSample &&
          other.rules == rules &&
          other.createdAt == createdAt &&
          other.updatedAt == updatedAt;

  @override
  int get hashCode => Object.hashAll(<Object?>[
        id,
        name,
        documentType,
        bankName,
        isActive,
        lastMatchedAt,
        documentsCount,
        transactionsCount,
        hasSample,
        rules,
        createdAt,
        updatedAt,
      ]);
}
