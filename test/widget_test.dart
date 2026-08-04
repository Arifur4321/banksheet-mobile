/// Replaces the stub `flutter create` generates.
///
/// The generated file references `MyApp`, which this project does not have, so
/// it fails to compile and takes `flutter analyze` down with it. There is no
/// smoke test of the whole app here on purpose: `BankSheetApp` needs a
/// [ProviderScope] with a real `Bootstrap` — keychain, preferences and an open
/// SQLite database — which is an integration test, not a widget test. The
/// focused suites in this directory cover the units that carry the logic.
library;

import 'package:banksheet_mobile/core/config/app_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppConfig', () {
    test('defaults to production', () {
      expect(AppConfig.baseUrl, 'https://banksheet.pro');
      expect(AppConfig.isProd, isTrue);
    });

    test('the API base carries the mobile prefix', () {
      expect(AppConfig.apiBase, 'https://banksheet.pro/api/mobile/v1');
    });

    test('only monthly products are offered until yearly is enabled', () {
      expect(AppConfig.yearlyEnabled, isFalse);
      expect(
        AppConfig.productIds,
        <String>{
          AppConfig.starterMonthly,
          AppConfig.professionalMonthly,
        },
        reason: 'a price the store has not approved yet is a rejection',
      );
    });

    test('upload ceiling mirrors the server rule', () {
      // DocumentController validates `max:20480` (kilobytes).
      expect(AppConfig.maxDocumentUploadBytes, 20480 * 1024);
    });
  });
}
