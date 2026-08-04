/// The slice of `GET /config` the settings screens need.
///
/// `/config` is the server's promise that a shipped binary never hard-codes a
/// price, a limit or a language list. Settings reads two things from it: the
/// supported locales for the language picker, and the legal URLs for About —
/// so a policy that moves does not need an App Store release to follow.
///
/// [ServerConfig.fallback] carries the same thirteen locales as
/// `config/locales.php`. It exists because the language screen has to work when
/// `/config` is unreachable: a picker that shows nothing when the network is
/// down is worse than one that shows the list the app was built with.
library;

import 'package:flutter/foundation.dart';

import '../../../core/utils/json.dart';

@immutable
class AppLocale {
  const AppLocale({
    required this.code,
    required this.name,
    required this.native,
    this.dir = 'ltr',
  });

  factory AppLocale.fromJson(Map<String, dynamic> json) {
    final String code = J.strOr(json['code'], '');
    return AppLocale(
      code: code,
      name: J.strOr(json['name'], code),
      native: J.strOr(json['native'], J.strOr(json['name'], code)),
      dir: J.strOr(json['dir'], 'ltr'),
    );
  }

  /// ISO code the server accepts on `PATCH /me`, e.g. `it`.
  final String code;

  /// English name, e.g. "Italian".
  final String name;

  /// The language's own name, e.g. "Italiano" — what the row leads with,
  /// because someone looking for their language reads it in their language.
  final String native;

  /// `ltr` for every currently supported language.
  final String dir;

  bool get isValid => code.isNotEmpty;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppLocale &&
          other.code == code &&
          other.name == name &&
          other.native == native &&
          other.dir == dir;

  @override
  int get hashCode => Object.hash(code, name, native, dir);

  @override
  String toString() => 'AppLocale($code)';
}

@immutable
class ServerConfig {
  const ServerConfig({
    required this.locales,
    required this.defaultLocale,
    this.privacyUrl,
    this.termsUrl,
    this.supportUrl,
    this.minClientVersion,
  });

  factory ServerConfig.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic> localeBlock = J.map(json['locales']);
    final Map<String, dynamic> urls = J.map(json['urls']);

    final List<AppLocale> parsed = J
        .list(localeBlock['supported'])
        .map(AppLocale.fromJson)
        .where((AppLocale locale) => locale.isValid)
        .toList(growable: false);

    return ServerConfig(
      // An empty list would leave the picker blank; the built-in catalogue is
      // the same one the server reads from, so falling back to it is honest.
      locales: parsed.isEmpty ? bundledLocales : parsed,
      defaultLocale: J.strOr(localeBlock['default'], 'en'),
      privacyUrl: J.str(urls['privacy']),
      termsUrl: J.str(urls['terms']),
      supportUrl: J.str(urls['support']),
      minClientVersion: J.str(json['min_client_version']),
    );
  }

  /// `config/locales.php`, in the server's own order. English first because it
  /// is the default and the fallback; the rest follow the catalogue.
  static const List<AppLocale> bundledLocales = <AppLocale>[
    AppLocale(code: 'en', name: 'English', native: 'English'),
    AppLocale(code: 'bn', name: 'Bengali', native: 'বাংলা'),
    AppLocale(code: 'it', name: 'Italian', native: 'Italiano'),
    AppLocale(code: 'fr', name: 'French', native: 'Français'),
    AppLocale(code: 'pl', name: 'Polish', native: 'Polski'),
    AppLocale(code: 'es', name: 'Spanish', native: 'Español'),
    AppLocale(code: 'de', name: 'German', native: 'Deutsch'),
    AppLocale(code: 'nl', name: 'Dutch', native: 'Nederlands'),
    AppLocale(code: 'sv', name: 'Swedish', native: 'Svenska'),
    AppLocale(code: 'pt', name: 'Portuguese', native: 'Português'),
    AppLocale(code: 'zh', name: 'Chinese', native: '中文'),
    AppLocale(code: 'ja', name: 'Japanese', native: '日本語'),
    AppLocale(code: 'ko', name: 'Korean', native: '한국어'),
  ];

  /// What the app shows when `/config` cannot be reached.
  static const ServerConfig fallback = ServerConfig(
    locales: bundledLocales,
    defaultLocale: 'en',
  );

  final List<AppLocale> locales;
  final String defaultLocale;

  final String? privacyUrl;
  final String? termsUrl;
  final String? supportUrl;

  /// The oldest build this server still answers. Shown in About so a support
  /// conversation can start from a fact rather than a guess.
  final String? minClientVersion;

  /// The locale for [code], or null when the server does not support it.
  AppLocale? locale(String? code) {
    if (code == null || code.isEmpty) {
      return null;
    }
    for (final AppLocale locale in locales) {
      if (locale.code == code) {
        return locale;
      }
    }
    return null;
  }

  @override
  String toString() => 'ServerConfig(${locales.length} locales)';
}
