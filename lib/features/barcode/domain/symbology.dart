/// The barcode generator's vocabulary, as `GET /barcode/symbologies` sends it.
///
/// The endpoint exists so the app can validate "EAN-13 wants 12 or 13 digits"
/// without a round trip and can build its sliders with the same bounds the
/// server clamps to. [Symbology.validate] is therefore a port of
/// `BarcodeImageService::imageValidationError()`, check digit included — not an
/// approximation of it. The two disagreeing would mean a preview the user can
/// see and a Generate button the server refuses.
library;

import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../../../core/i18n/strings.dart';
import '../../../core/utils/json.dart';

/// A `{min, max, default}` triplet for one numeric render option.
@immutable
class BarcodeRange {
  const BarcodeRange({
    required this.min,
    required this.max,
    required this.value,
  });

  factory BarcodeRange.fromJson(
    dynamic raw, {
    required int min,
    required int max,
    required int value,
  }) {
    final Map<String, dynamic> json = J.map(raw);
    return BarcodeRange(
      min: J.intOr(json['min'], min),
      max: J.intOr(json['max'], max),
      value: J.intOr(json['default'], value),
    );
  }

  final int min;
  final int max;

  /// The server's default, which the form pre-fills with.
  final int value;

  int clamp(int input) => input < min ? min : (input > max ? max : input);

  /// Slider divisions that never collapse to zero on a one-step range.
  int get divisions => (max - min) <= 0 ? 1 : (max - min);
}

/// A `#rrggbb` option with its regex and default.
@immutable
class BarcodeColour {
  const BarcodeColour({required this.pattern, required this.value});

  factory BarcodeColour.fromJson(dynamic raw, String fallback) {
    final Map<String, dynamic> json = J.map(raw);
    return BarcodeColour(
      pattern: J.strOr(json['pattern'], r'^#[0-9A-Fa-f]{6}$'),
      value: J.strOr(json['default'], fallback),
    );
  }

  final String pattern;
  final String value;

  bool accepts(String input) {
    try {
      return RegExp(pattern).hasMatch(input);
    } on FormatException {
      return RegExp(r'^#[0-9A-Fa-f]{6}$').hasMatch(input);
    }
  }
}

/// The shared rendering bounds every symbology obeys.
@immutable
class BarcodeOptions {
  const BarcodeOptions({
    required this.dataMaxLength,
    required this.scale,
    required this.height,
    required this.margin,
    required this.foreground,
    required this.background,
    required this.showText,
    required this.transparent,
    required this.maxPixels,
  });

  factory BarcodeOptions.fromJson(Map<String, dynamic> json) => BarcodeOptions(
        dataMaxLength: J.intOr(J.map(json['data'])['max_length'], 1200),
        scale: BarcodeRange.fromJson(json['scale'], min: 1, max: 8, value: 3),
        height:
            BarcodeRange.fromJson(json['height'], min: 20, max: 240, value: 70),
        margin:
            BarcodeRange.fromJson(json['margin'], min: 0, max: 40, value: 10),
        foreground: BarcodeColour.fromJson(json['foreground'], '#000000'),
        background: BarcodeColour.fromJson(json['background'], '#FFFFFF'),
        showText: J.boolOr(J.map(json['show_text'])['default'], fallback: true),
        transparent: J.boolOr(J.map(json['transparent'])['default']),
        maxPixels: J.intOr(json['max_pixels'], 4000000),
      );

  static const BarcodeOptions fallback = BarcodeOptions(
    dataMaxLength: 1200,
    scale: BarcodeRange(min: 1, max: 8, value: 3),
    height: BarcodeRange(min: 20, max: 240, value: 70),
    margin: BarcodeRange(min: 0, max: 40, value: 10),
    foreground: BarcodeColour(pattern: r'^#[0-9A-Fa-f]{6}$', value: '#000000'),
    background: BarcodeColour(pattern: r'^#[0-9A-Fa-f]{6}$', value: '#FFFFFF'),
    showText: true,
    transparent: false,
    maxPixels: 4000000,
  );

  /// The absolute ceiling on the encoded value, whatever the symbology allows.
  final int dataMaxLength;

  /// Module size in px.
  final BarcodeRange scale;

  /// 1D bar height in px.
  final BarcodeRange height;

  /// Quiet zone in px.
  final BarcodeRange margin;

  final BarcodeColour foreground;
  final BarcodeColour background;
  final bool showText;
  final bool transparent;

  /// width × height guard; the render is refused above it.
  final int maxPixels;
}

/// One barcode type, with the rules its data has to satisfy.
@immutable
class Symbology {
  const Symbology({
    required this.key,
    required this.label,
    required this.dimension,
    required this.supportsText,
    required this.maxLength,
    required this.numeric,
    required this.checksum,
    this.help,
    this.dataLength,
    this.fullLength,
    this.charsetRegex,
  });

  factory Symbology.fromJson(Map<String, dynamic> json) => Symbology(
        key: J.strOr(json['key'], ''),
        label: J.strOr(json['label'], J.strOr(json['key'], '')),
        dimension: J.strOr(json['dimension'], '1d'),
        supportsText: J.boolOr(json['supports_text']),
        help: J.str(json['help']),
        maxLength: J.intOr(json['max_length'], 1200),
        numeric: J.boolOr(json['numeric']),
        dataLength: J.intOrNull(json['data_length']),
        fullLength: J.intOrNull(json['full_length']),
        checksum: J.boolOr(json['checksum']),
        charsetRegex: J.str(json['charset_regex']),
      );

  /// The identifier posted as `type`, e.g. `EAN13`.
  final String key;

  final String label;

  /// `1d` or `2d`.
  final String dimension;

  /// False for the 2D symbologies, which have no human-readable line — the app
  /// hides the "show text" switch rather than sending a no-op.
  final bool supportsText;

  final String? help;
  final int maxLength;
  final bool numeric;

  /// Digits before the check digit, for the EAN/UPC family.
  final int? dataLength;

  /// Digits including it.
  final int? fullLength;

  final bool checksum;

  /// A PHP regex complete with delimiters, e.g. `/^[0-9A-Z\-. $\/+%]+$/`.
  final String? charsetRegex;

  bool get isMatrix => dimension == '2d';

  /// The same answer `BarcodeImageService::imageValidationError()` gives, so a
  /// value the preview accepts is a value Generate will accept.
  String? validate(String value, {int absoluteMax = 1200}) {
    if (value.isEmpty) {
      return S.barcodeValueRequired;
    }

    if (value.length > absoluteMax) {
      return S.barcodeValueTooLong;
    }

    if (value.length > maxLength) {
      return S.barcodeMaxCharacters(label, maxLength);
    }

    if (numeric) {
      return _numericError(value);
    }

    final RegExp? charset = _charset();
    if (charset != null && !charset.hasMatch(value.toUpperCase())) {
      return S.barcodeUnsupportedCharacters(label);
    }

    return null;
  }

  String? _numericError(String value) {
    if (!RegExp(r'^\d+$').hasMatch(value)) {
      return S.barcodeDigitsOnly(label);
    }

    final int data = dataLength ?? 0;
    final int full = fullLength ?? 0;
    final int length = value.length;

    if (length != data && length != full) {
      return S.barcodeDigitCount(label, data, full);
    }

    if (length == full && checksum) {
      final int expected = eanCheckDigit(value.substring(0, value.length - 1));
      if (int.parse(value.substring(value.length - 1)) != expected) {
        return S.barcodeCheckDigit(label, expected);
      }
    }

    return null;
  }

  /// Strips the PHP delimiters and any trailing modifiers before compiling.
  RegExp? _charset() {
    final String? raw = charsetRegex;
    if (raw == null || raw.length < 2) {
      return null;
    }

    String body = raw;
    if (body.startsWith('/')) {
      final int end = body.lastIndexOf('/');
      if (end > 0) {
        body = body.substring(1, end);
      }
    }

    try {
      return RegExp(body);
    } on FormatException {
      // The server still enforces it; refusing to preview would be worse.
      return null;
    }
  }

  /// Standard EAN/UPC modulo-10 check digit for a payload WITHOUT its trailing
  /// check digit. Weights alternate 3, 1 from the right.
  static int eanCheckDigit(String digits) {
    int sum = 0;
    for (int i = 0; i < digits.length; i++) {
      final int digit = int.tryParse(digits[digits.length - 1 - i]) ?? 0;
      sum += digit * (i.isEven ? 3 : 1);
    }
    return (10 - (sum % 10)) % 10;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is Symbology && other.key == key;

  @override
  int get hashCode => key.hashCode;

  @override
  String toString() => 'Symbology($key)';
}

/// The barcode allowance, when the caller has a workspace.
@immutable
class BarcodeUsage {
  const BarcodeUsage({this.used, this.limit, this.remaining});

  factory BarcodeUsage.fromJson(Map<String, dynamic> json) => BarcodeUsage(
        used: J.intOrNull(json['used']),
        limit: J.intOrNull(json['limit']),
        remaining: J.intOrNull(json['remaining']),
      );

  final int? used;
  final int? limit;
  final int? remaining;

  bool get isUnlimited => (limit ?? 0) <= 0;

  bool get isExhausted => !isUnlimited && (remaining ?? 1) <= 0;
}

/// The whole `GET /barcode/symbologies` payload.
@immutable
class SymbologyCatalogue {
  const SymbologyCatalogue({
    required this.types,
    required this.options,
    this.usage,
  });

  factory SymbologyCatalogue.fromJson(Map<String, dynamic> json) =>
      SymbologyCatalogue(
        types: J
            .list(json['types'])
            .map(Symbology.fromJson)
            .where((Symbology s) => s.key.isNotEmpty)
            .toList(growable: false),
        options: BarcodeOptions.fromJson(J.map(json['options'])),
        usage: json['usage'] == null
            ? null
            : BarcodeUsage.fromJson(J.map(json['usage'])),
      );

  final List<Symbology> types;
  final BarcodeOptions options;
  final BarcodeUsage? usage;

  Symbology? byKey(String? key) {
    if (key == null) {
      return null;
    }
    for (final Symbology type in types) {
      if (type.key == key) {
        return type;
      }
    }
    return null;
  }

  Symbology? get first => types.isEmpty ? null : types.first;
}

/// The decoded `POST /barcode/preview` answer.
@immutable
class BarcodePreviewImage {
  const BarcodePreviewImage({
    required this.bytes,
    required this.mime,
    this.width,
    this.height,
    this.byteSize,
  });

  final Uint8List bytes;
  final String mime;
  final int? width;
  final int? height;
  final int? byteSize;

  double get aspectRatio {
    final int w = width ?? 0;
    final int h = height ?? 0;
    return (w > 0 && h > 0) ? w / h : 2.4;
  }
}

/// A stored barcode, as `BarcodeResource` publishes it.
@immutable
class GeneratedBarcode {
  const GeneratedBarcode({
    required this.id,
    required this.imageOptions,
    this.symbology,
    this.symbologyLabel,
    this.title,
    this.status,
    this.filename,
    this.outputFormat,
    this.fileSize,
    this.pngUrl,
    this.svgUrl,
    this.createdAt,
  });

  factory GeneratedBarcode.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic> download = J.map(json['download']);
    return GeneratedBarcode(
      id: J.intOr(json['id'], 0),
      symbology: J.str(json['symbology']),
      symbologyLabel: J.str(json['symbology_label']),
      title: J.str(json['title']),
      status: J.str(json['status']),
      filename: J.str(json['filename']),
      outputFormat: J.str(json['output_format']),
      fileSize: J.intOrNull(json['file_size']),
      imageOptions: J.map(json['image_options']),
      pngUrl: J.str(download['png']),
      svgUrl: J.str(download['svg']),
      createdAt: J.date(json['created_at']),
    );
  }

  final int id;
  final String? symbology;
  final String? symbologyLabel;
  final String? title;
  final String? status;
  final String? filename;

  /// Always "PNG + SVG" today; carried rather than assumed.
  final String? outputFormat;

  final int? fileSize;

  /// The normalised render options the server actually used.
  final Map<String, dynamic> imageOptions;

  final String? pngUrl;
  final String? svgUrl;
  final DateTime? createdAt;

  /// A filename safe to save under, whatever the server had.
  String downloadFilename(String format) {
    final String base = (filename ?? 'barcode').split('.').first;
    return '$base.$format';
  }
}
