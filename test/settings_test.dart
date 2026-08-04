/// Parsing and rule tests for the settings layer.
///
/// Three things here are expensive to get wrong and invisible until a user hits
/// them: the shape of an API credential (a mis-parsed `revoked_at` draws a dead
/// key as live), the password checklist (a rule stricter than the server's would
/// refuse a password `PUT /me/password` would accept), and the language list —
/// including what the picker shows when `GET /config` cannot be reached, which
/// is the one path that is never exercised on a developer's connection.
///
/// Pure Dart, no widgets pumped, so the suite runs in milliseconds.
library;

import 'package:banksheet_mobile/features/settings/domain/api_key.dart';
import 'package:banksheet_mobile/features/settings/domain/server_config.dart';
import 'package:banksheet_mobile/features/settings/presentation/widgets/password_strength_checklist.dart';
import 'package:flutter_test/flutter_test.dart';

/// One key exactly as `ApiKeyResource` emits it.
Map<String, dynamic> apiKeyJson({
  int id = 11,
  String? maskedKey = 'sk_live_••••••••3f7a',
  String environment = 'live',
  String? revokedAt,
  String? lastUsedAt = '2026-07-30T11:02:00+00:00',
  String createdAt = '2026-07-01T09:00:00+00:00',
}) =>
    <String, dynamic>{
      'id': id,
      'name': 'Billing server',
      'masked_key': maskedKey,
      'environment': environment,
      'last_four': '3f7a',
      'scopes': <String>['documents:write', 'documents:read'],
      'created_by': <String, dynamic>{'id': 42, 'name': 'Marta Rossi'},
      'is_active': revokedAt == null,
      'last_used_at': lastUsedAt,
      'last_used_ip': '81.2.69.142',
      'expires_at': null,
      'revoked_at': revokedAt,
      'created_at': createdAt,
    };

/// `GET /api-keys` — `MobileController::ok()` sends the array flat, with no
/// `data` envelope.
Map<String, dynamic> apiKeysResponse() => <String, dynamic>{
      'keys': <Map<String, dynamic>>[apiKeyJson()],
      'usage': <String, dynamic>{
        'plan': 'starter',
        'api_included_in_plan': true,
        'trial': <String, dynamic>{
          'limit': 25,
          'used': 25,
          'remaining': 0,
        },
        'current_period': <String, dynamic>{
          'limit': 200,
          'used': 34,
          'remaining': 166,
          'resets_at': '2026-09-01T00:00:00+00:00',
        },
      },
    };

/// The `locales` block of `GET /config`, built from `config/locales.php`.
Map<String, dynamic> localesBlock() => <String, dynamic>{
      'default': 'en',
      'supported': <Map<String, dynamic>>[
        <String, dynamic>{
          'code': 'en',
          'name': 'English',
          'native': 'English',
          'dir': 'ltr',
        },
        <String, dynamic>{
          'code': 'it',
          'name': 'Italian',
          'native': 'Italiano',
          'dir': 'ltr',
        },
        <String, dynamic>{
          'code': 'ja',
          'name': 'Japanese',
          'native': '日本語',
          'dir': 'ltr',
        },
      ],
    };

void main() {
  group('ApiKey.fromJson', () {
    test('reads every field ApiKeyResource publishes', () {
      final ApiKey key = ApiKey.fromJson(apiKeyJson());

      expect(key.id, 11);
      expect(key.name, 'Billing server');
      expect(key.maskedKey, 'sk_live_••••••••3f7a');
      expect(key.environment, ApiKey.environmentLive);
      expect(key.lastFour, '3f7a');
      expect(key.scopes, <String>['documents:write', 'documents:read']);
      expect(key.createdByName, 'Marta Rossi');
      expect(key.isActive, isTrue);
      expect(key.lastUsedIp, '81.2.69.142');
      expect(key.expiresAt, isNull);
      expect(key.createdAt, DateTime.parse('2026-07-01T09:00:00+00:00'));
      expect(key.isTest, isFalse);
      expect(key.isRevoked, isFalse);
      expect(key.hasBeenUsed, isTrue);
    });

    test('rebuilds a mask when the resource sends null', () {
      // `masked_key` is guarded on the model type server-side, so null is a
      // real answer; the row must still be identifiable.
      final ApiKey key = ApiKey.fromJson(apiKeyJson(maskedKey: null));

      expect(key.maskedKey, 'sk_live_••••••••3f7a');
      expect(key.maskedKey.contains('null'), isFalse);
    });

    test('masks a test key with its own prefix', () {
      final ApiKey key = ApiKey.fromJson(
        apiKeyJson(maskedKey: null, environment: 'test'),
      );

      expect(key.isTest, isTrue);
      expect(key.maskedKey.startsWith('sk_test_'), isTrue);
    });

    test('a revoked key reports itself revoked and inactive', () {
      final ApiKey key = ApiKey.fromJson(
        apiKeyJson(revokedAt: '2026-07-31T08:00:00+00:00'),
      );

      expect(key.isRevoked, isTrue);
      expect(key.isActive, isFalse);
      expect(key.revokedAt, DateTime.parse('2026-07-31T08:00:00+00:00'));
    });

    test('a key that has never been used reports so', () {
      final ApiKey key = ApiKey.fromJson(apiKeyJson(lastUsedAt: null));

      expect(key.hasBeenUsed, isFalse);
      expect(key.lastUsedAt, isNull);
    });

    test('survives a payload with nothing in it', () {
      final ApiKey key = ApiKey.fromJson(const <String, dynamic>{});

      expect(key.id, 0);
      expect(key.name, '');
      expect(key.environment, ApiKey.environmentLive);
      expect(key.scopes, isEmpty);
      expect(key.createdByName, isNull);
      expect(key.isRevoked, isFalse);
    });

    test('equality is by value, so a rebuilt list does not flicker', () {
      expect(ApiKey.fromJson(apiKeyJson()), ApiKey.fromJson(apiKeyJson()));
      expect(
        ApiKey.fromJson(apiKeyJson()).hashCode,
        ApiKey.fromJson(apiKeyJson()).hashCode,
      );
      expect(
        ApiKey.fromJson(apiKeyJson()),
        isNot(ApiKey.fromJson(apiKeyJson(id: 12))),
      );
    });
  });

  group('MintedApiKey.fromJson', () {
    test('reads the one response that carries a plaintext', () {
      final MintedApiKey minted = MintedApiKey.fromJson(<String, dynamic>{
        'key': apiKeyJson(),
        'plain_key': 'sk_live_2f6d9c0b4a8e41d3b7c5',
      });

      expect(minted.key.id, 11);
      expect(minted.plainKey, 'sk_live_2f6d9c0b4a8e41d3b7c5');
      expect(minted.hasPlainKey, isTrue);
    });

    test('accepts a data envelope as well as the flat body', () {
      final MintedApiKey minted = MintedApiKey.fromJson(<String, dynamic>{
        'data': <String, dynamic>{
          'key': apiKeyJson(id: 12),
          'plain_key': 'sk_live_abc',
        },
      });

      expect(minted.key.id, 12);
      expect(minted.plainKey, 'sk_live_abc');
    });

    test('reports no plaintext rather than an empty reveal sheet', () {
      final MintedApiKey minted = MintedApiKey.fromJson(<String, dynamic>{
        'key': apiKeyJson(),
      });

      expect(minted.hasPlainKey, isFalse);
    });
  });

  group('ApiKeyBundle.fromJson', () {
    test('parses the keys and the allowance snapshot together', () {
      final ApiKeyBundle bundle = ApiKeyBundle.fromJson(apiKeysResponse());

      expect(bundle.keys, hasLength(1));
      expect(bundle.isEmpty, isFalse);

      final ApiUsage usage = bundle.usage!;
      expect(usage.includedInPlan, isTrue);
      expect(usage.used, 34);
      expect(usage.limit, 200);
      expect(usage.remaining, 166);
      expect(usage.resetsAt, DateTime.parse('2026-09-01T00:00:00+00:00'));
      expect(usage.trialRemaining, 0);
    });

    test('a workspace with no keys is empty, not broken', () {
      final ApiKeyBundle bundle = ApiKeyBundle.fromJson(<String, dynamic>{
        'keys': <Map<String, dynamic>>[],
        'usage': <String, dynamic>{},
      });

      expect(bundle.isEmpty, isTrue);
      expect(bundle.usage, isNull);
      expect(bundle.sorted, isEmpty);
    });

    test('sorts active keys first, newest first inside each group', () {
      final ApiKeyBundle bundle = ApiKeyBundle.fromJson(<String, dynamic>{
        'keys': <Map<String, dynamic>>[
          apiKeyJson(id: 1, createdAt: '2026-01-01T00:00:00+00:00'),
          apiKeyJson(
            id: 2,
            createdAt: '2026-06-01T00:00:00+00:00',
            revokedAt: '2026-07-01T00:00:00+00:00',
          ),
          apiKeyJson(id: 3, createdAt: '2026-05-01T00:00:00+00:00'),
        ],
      });

      expect(
        bundle.sorted.map((ApiKey k) => k.id).toList(),
        <int>[3, 1, 2],
      );
    });

    test('reads a data envelope too', () {
      final ApiKeyBundle bundle = ApiKeyBundle.fromJson(<String, dynamic>{
        'data': apiKeysResponse(),
      });

      expect(bundle.keys, hasLength(1));
      expect(bundle.usage?.limit, 200);
    });
  });

  group('PasswordRules', () {
    test('an empty password meets nothing', () {
      expect(PasswordRules.evaluate(''), isEmpty);
      expect(PasswordRules.meetsServerMinimum(''), isFalse);
      expect(PasswordRules.isStrong(''), isFalse);
    });

    test('length is the eight the server enforces, not seven', () {
      expect(PasswordRules.satisfies(PasswordRule.length, 'abcdefg'), isFalse);
      expect(PasswordRules.satisfies(PasswordRule.length, 'abcdefgh'), isTrue);
      expect(PasswordRules.meetsServerMinimum('abcdefgh'), isTrue);
    });

    test('mixed case needs both cases, not just one', () {
      expect(
        PasswordRules.satisfies(PasswordRule.mixedCase, 'lowercase'),
        isFalse,
      );
      expect(
        PasswordRules.satisfies(PasswordRule.mixedCase, 'UPPERCASE'),
        isFalse,
      );
      expect(
        PasswordRules.satisfies(PasswordRule.mixedCase, 'MixedCase'),
        isTrue,
      );
    });

    test('digits and symbols are detected independently', () {
      expect(PasswordRules.satisfies(PasswordRule.digit, 'abc1'), isTrue);
      expect(PasswordRules.satisfies(PasswordRule.digit, 'abc!'), isFalse);
      expect(PasswordRules.satisfies(PasswordRule.symbol, 'abc!'), isTrue);
      expect(PasswordRules.satisfies(PasswordRule.symbol, 'abc1'), isFalse);
    });

    test('a space counts as a symbol, so a passphrase is not punished', () {
      expect(
        PasswordRules.satisfies(PasswordRule.symbol, 'correct horse'),
        isTrue,
      );
    });

    test('a long lower-case password still passes the server minimum', () {
      // The checklist is advice; only the length rule may block the form, or
      // the app would refuse a password the server accepts.
      const String password = 'correcthorsebatterystaple';

      expect(PasswordRules.meetsServerMinimum(password), isTrue);
      expect(PasswordRules.isStrong(password), isFalse);
      expect(
        PasswordRules.evaluate(password),
        <PasswordRule>{PasswordRule.length},
      );
    });

    test('a password meeting all four is reported strong', () {
      const String password = 'Str0ng-Passphrase';

      expect(
        PasswordRules.evaluate(password),
        <PasswordRule>{
          PasswordRule.length,
          PasswordRule.mixedCase,
          PasswordRule.digit,
          PasswordRule.symbol,
        },
      );
      expect(PasswordRules.isStrong(password), isTrue);
    });

    test('every rule has a label, so no row can render blank', () {
      for (final PasswordRule rule in PasswordRule.values) {
        expect(PasswordRules.label(rule), isNotEmpty);
      }
    });
  });

  group('ServerConfig locales', () {
    test('parses the supported list and the legal URLs', () {
      final ServerConfig config = ServerConfig.fromJson(<String, dynamic>{
        'api_version': 'v1',
        'min_client_version': '1.0.0',
        'urls': <String, dynamic>{
          'privacy': 'https://banksheet.pro/privacy',
          'terms': 'https://banksheet.pro/terms',
          'support': 'https://banksheet.pro/contact',
        },
        'locales': localesBlock(),
      });

      expect(config.locales, hasLength(3));
      expect(config.defaultLocale, 'en');
      expect(config.locale('it')?.native, 'Italiano');
      expect(config.locale('ja')?.native, '日本語');
      expect(config.locale('xx'), isNull);
      expect(config.privacyUrl, 'https://banksheet.pro/privacy');
      expect(config.termsUrl, 'https://banksheet.pro/terms');
      expect(config.supportUrl, 'https://banksheet.pro/contact');
      expect(config.minClientVersion, '1.0.0');
    });

    test('a locale with no native name falls back to the English one', () {
      final ServerConfig config = ServerConfig.fromJson(<String, dynamic>{
        'locales': <String, dynamic>{
          'default': 'en',
          'supported': <Map<String, dynamic>>[
            <String, dynamic>{'code': 'sv', 'name': 'Swedish'},
          ],
        },
      });

      expect(config.locales.single.native, 'Swedish');
      expect(config.locales.single.dir, 'ltr');
    });

    test('drops an entry with no code instead of rendering a blank row', () {
      final ServerConfig config = ServerConfig.fromJson(<String, dynamic>{
        'locales': <String, dynamic>{
          'supported': <Map<String, dynamic>>[
            <String, dynamic>{'code': 'it', 'name': 'Italian'},
            <String, dynamic>{'name': 'Nonsense'},
          ],
        },
      });

      expect(config.locales, hasLength(1));
      expect(config.locales.single.code, 'it');
    });

    test('an empty supported list falls back to the bundled catalogue', () {
      final ServerConfig config = ServerConfig.fromJson(<String, dynamic>{
        'locales': <String, dynamic>{
          'default': 'en',
          'supported': <Map<String, dynamic>>[],
        },
      });

      expect(config.locales, ServerConfig.bundledLocales);
      expect(config.locales, isNotEmpty);
    });

    test('a payload with no locales block at all still yields a picker', () {
      final ServerConfig config =
          ServerConfig.fromJson(const <String, dynamic>{});

      expect(config.locales, hasLength(13));
      expect(config.defaultLocale, 'en');
      expect(config.privacyUrl, isNull);
    });

    test(
      'the /config failure fallback mirrors config/locales.php exactly',
      () {
        // What the language screen shows when the request throws. These are the
        // thirteen codes in `config/locales.php`, in the server's own order.
        final ServerConfig config = ServerConfig.fallback;

        expect(
          config.locales.map((AppLocale l) => l.code).toList(),
          <String>[
            'en',
            'bn',
            'it',
            'fr',
            'pl',
            'es',
            'de',
            'nl',
            'sv',
            'pt',
            'zh',
            'ja',
            'ko',
          ],
        );
        expect(config.defaultLocale, 'en');
      },
    );

    test('every bundled locale carries a native name a reader recognises', () {
      for (final AppLocale locale in ServerConfig.bundledLocales) {
        expect(locale.isValid, isTrue);
        expect(locale.native, isNotEmpty);
        expect(locale.name, isNotEmpty);
        expect(locale.dir, 'ltr');
      }

      expect(ServerConfig.fallback.locale('bn')?.native, 'বাংলা');
      expect(ServerConfig.fallback.locale('ko')?.native, '한국어');
      expect(ServerConfig.fallback.locale('zh')?.native, '中文');
    });

    test('locale lookup ignores an empty or missing code', () {
      expect(ServerConfig.fallback.locale(null), isNull);
      expect(ServerConfig.fallback.locale(''), isNull);
    });
  });
}
