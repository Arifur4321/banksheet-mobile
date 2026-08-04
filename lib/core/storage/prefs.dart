/// Non-secret local preferences.
///
/// Anything here is readable on a rooted device by design — it holds display
/// choices and cache stamps, never credentials.
library;

import 'package:shared_preferences/shared_preferences.dart';

class Prefs {
  const Prefs(this._prefs);

  final SharedPreferences _prefs;

  static Future<Prefs> open() async => Prefs(await SharedPreferences.getInstance());

  static const String _kLocale = 'banksheet.locale';
  static const String _kOnboarded = 'banksheet.onboarded';
  static const String _kLastDocumentSync = 'banksheet.documents.synced_at';
  static const String _kDefaultDocType = 'banksheet.upload.default_type';
  static const String _kDefaultProfileId = 'banksheet.upload.default_profile';

  String get locale => _prefs.getString(_kLocale) ?? 'en';
  Future<void> setLocale(String value) => _prefs.setString(_kLocale, value);

  bool get hasOnboarded => _prefs.getBool(_kOnboarded) ?? false;
  Future<void> setOnboarded() => _prefs.setBool(_kOnboarded, true);

  DateTime? get lastDocumentSync {
    final int? ms = _prefs.getInt(_kLastDocumentSync);
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  Future<void> markDocumentSync() =>
      _prefs.setInt(_kLastDocumentSync, DateTime.now().millisecondsSinceEpoch);

  /// Remembering the last upload choices removes two taps from the most
  /// repeated action in the product.
  String get defaultDocumentType =>
      _prefs.getString(_kDefaultDocType) ?? 'bank_statement';

  Future<void> setDefaultDocumentType(String value) =>
      _prefs.setString(_kDefaultDocType, value);

  int? get defaultProfileId => _prefs.getInt(_kDefaultProfileId);

  Future<void> setDefaultProfileId(int? id) async {
    if (id == null) {
      await _prefs.remove(_kDefaultProfileId);
    } else {
      await _prefs.setInt(_kDefaultProfileId, id);
    }
  }

  Future<void> clearSessionScoped() async {
    await _prefs.remove(_kLastDocumentSync);
    await _prefs.remove(_kDefaultProfileId);
  }
}
