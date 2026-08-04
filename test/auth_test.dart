/// Parsing and error-mapping tests for the session layer.
///
/// These cover the three places a wrong assumption would be expensive and
/// invisible until a user hits it: the shape of `GET /me`, a resource that
/// legitimately sends nulls, and the field-error mapping the sign-in form
/// depends on to put a message under the right box.
///
/// No widgets are pumped on purpose — everything here is pure Dart, so the
/// suite runs in milliseconds and can be trusted as a pre-commit gate.
library;

import 'package:banksheet_mobile/core/i18n/strings.dart';
import 'package:banksheet_mobile/core/network/api_exception.dart';
import 'package:banksheet_mobile/features/auth/domain/session.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

/// A realistic `GET /me` body, keyed exactly as UserResource, CompanyResource,
/// PlanResource and UsageResource emit it.
Map<String, dynamic> meResponse() => <String, dynamic>{
      'user': <String, dynamic>{
        'id': 42,
        'name': 'Marta Rossi',
        'email': 'marta@example.com',
        'locale': 'it',
        'role': 'owner',
        'email_verified': true,
        'email_verified_at': '2026-07-01T09:12:44+00:00',
        'avatar_url': null,
        'auth_provider': 'password',
        'company_id': 7,
        'created_at': '2026-06-20T08:00:00+00:00',
      },
      'company': <String, dynamic>{
        'id': 7,
        'name': 'Studio Rossi',
        'vat_number': 'IT01234567890',
        'email': 'amministrazione@studiorossi.it',
        'phone': null,
        'address': null,
        'plan': 'starter',
        'subscription_status': 'active',
        'on_paid_plan': true,
        'trial_ends_at': null,
        'renews_at': '2026-09-01T00:00:00+00:00',
        'features': <String>['review_queue', 'ocr'],
        'member_count': 3,
        'created_at': '2026-06-20T08:00:00+00:00',
      },
      'plan': <String, dynamic>{
        'key': 'starter',
        'name': 'Starter',
        'price_eur': 20,
        'limits': <String, dynamic>{
          'monthly_document_limit': 200,
          'monthly_conversion_limit': 200,
          'monthly_esign_limit': 100,
          'monthly_page_limit': 1500,
          'monthly_web_scan_limit': 1000,
          'monthly_barcode_limit': 200,
          'monthly_api_limit': 250,
          'employee_limit': 10,
          'extraction_profile_limit': 10,
          'storage_limit_mb': 2048,
        },
        'features': <String>['api_access', 'review_queue', 'web_to_excel'],
      },
      'usage': <String, dynamic>{
        'period_started_at': '2026-08-01T00:00:00+00:00',
        'period_ends_at': '2026-09-01T00:00:00+00:00',
        'documents': <String, dynamic>{
          'used': 180,
          'limit': 200,
          'remaining': 20,
        },
        'conversions': <String, dynamic>{
          'used': 12,
          'limit': 200,
          'remaining': 188,
        },
        'esign_requests': <String, dynamic>{
          'used': 4,
          'limit': 100,
          'remaining': 96,
        },
        'pages': <String, dynamic>{
          'used': 640,
          'limit': 1500,
          'remaining': 860,
        },
        'web_scans': <String, dynamic>{
          'used': 0,
          'limit': 1000,
          'remaining': 1000,
        },
        'barcodes': <String, dynamic>{'used': 9, 'limit': 200, 'remaining': 191},
        'api_documents': <String, dynamic>{
          'used': 0,
          'limit': 250,
          'remaining': 250,
        },
        'api_trial': <String, dynamic>{'used': 3, 'limit': 3, 'remaining': 0},
        'employees': <String, dynamic>{'used': 2, 'limit': 10, 'remaining': 8},
        'extraction_profiles': <String, dynamic>{
          'used': 1,
          'limit': 10,
          'remaining': 9,
        },
        'storage_mb': <String, dynamic>{
          'used': null,
          'limit': 2048,
          'remaining': null,
        },
      },
    };

void main() {
  group('Session.fromJson', () {
    test('parses a realistic GET /me payload', () {
      final Session session = Session.fromJson(meResponse());

      expect(session.user.id, 42);
      expect(session.user.email, 'marta@example.com');
      expect(session.user.firstName, 'Marta');
      expect(session.user.initials, 'MR');
      expect(session.user.isOwner, isTrue);
      expect(session.user.canChangePassword, isTrue);

      expect(session.workspace.id, 7);
      expect(session.workspace.name, 'Studio Rossi');
      expect(session.workspace.plan, 'starter');
      // The display name comes from the sibling `plan` block, not the company.
      expect(session.workspace.planLabel, 'Starter');
      expect(session.workspace.memberCount, 3);
      expect(session.workspace.onPaidPlan, isTrue);
      // And the reset date from the `usage` block.
      expect(
        session.workspace.usagePeriodEndsAt,
        DateTime.parse('2026-09-01T00:00:00+00:00'),
      );

      expect(session.limits.documentsUsed, 180);
      expect(session.limits.documentsLimit, 200);
      expect(session.limits.esignUsed, 4);

      // The union of what the workspace holds and what the plan grants — the
      // same set Company::hasPlanFeature() checks.
      expect(session.has('ocr'), isTrue);
      expect(session.has('api_access'), isTrue);
      expect(session.has('esign_requests'), isFalse);
      expect(session.features.length, 4);
    });

    test('accepts a {"data": {...}} envelope', () {
      final Session session =
          Session.fromJson(<String, dynamic>{'data': meResponse()});

      expect(session.user.id, 42);
      expect(session.workspace.plan, 'starter');
    });

    test('refuses to guess a billing source it was not told', () {
      final Session paid = Session.fromJson(meResponse());

      // /me cannot distinguish a card subscription from a store one, so the
      // entitlement says so and declines to claim a purchase is allowed.
      expect(paid.entitlement.plan, 'starter');
      expect(paid.entitlement.source, Entitlement.sourceUnknown);
      expect(paid.entitlement.isKnown, isFalse);
      expect(paid.entitlement.canPurchase, isFalse);

      final Map<String, dynamic> freeJson = meResponse();
      freeJson['company'] = <String, dynamic>{
        ...freeJson['company']! as Map<String, dynamic>,
        'plan': 'free',
        'on_paid_plan': false,
      };

      final Session free = Session.fromJson(freeJson);
      expect(free.entitlement.source, Entitlement.sourceFree);
      expect(free.entitlement.isFree, isTrue);
      expect(free.entitlement.canPurchase, isTrue);
    });

    test('survives a body with nothing in it', () {
      final Session session = Session.fromJson(const <String, dynamic>{});

      expect(session.user.id, 0);
      expect(session.workspace.plan, 'free');
      expect(session.features, isEmpty);
      expect(session.limits.documentsUsed, isNull);
    });

    test('compares by value, so an identical refresh does not rebuild', () {
      expect(Session.fromJson(meResponse()), Session.fromJson(meResponse()));
      expect(
        Session.fromJson(meResponse()).hashCode,
        Session.fromJson(meResponse()).hashCode,
      );
    });
  });

  group('AppUser.fromJson', () {
    test('tolerates every optional value being null', () {
      final AppUser user = AppUser.fromJson(const <String, dynamic>{
        'id': 9,
        'name': null,
        'email': 'nobody@example.com',
        'locale': null,
        'role': null,
        'email_verified': false,
        'email_verified_at': null,
        'avatar_url': null,
        'auth_provider': null,
        'company_id': null,
        'created_at': null,
      });

      expect(user.id, 9);
      expect(user.name, '');
      expect(user.locale, isNull);
      expect(user.emailVerified, isFalse);
      expect(user.emailVerifiedAt, isNull);
      expect(user.companyId, isNull);
      // Falls back to the local part rather than greeting an empty string.
      expect(user.firstName, 'nobody');
      expect(user.initials, 'N');
    });

    test('infers verification from the timestamp when the flag is missing', () {
      final AppUser user = AppUser.fromJson(const <String, dynamic>{
        'id': 1,
        'name': 'Ada Lovelace',
        'email': 'ada@example.com',
        'email_verified_at': '2026-01-02T03:04:05+00:00',
      });

      expect(user.emailVerified, isTrue);
      expect(user.firstName, 'Ada');
      expect(user.initials, 'AL');
    });

    test('greets a nameless, address-less account without breaking', () {
      final AppUser user =
          AppUser.fromJson(const <String, dynamic>{'id': 2, 'name': '  '});

      expect(user.firstName, S.greetingFallback);
      expect(user.initials, '?');
    });

    test('a Google account is not offered a password change', () {
      final AppUser user = AppUser.fromJson(const <String, dynamic>{
        'id': 3,
        'name': 'Gio',
        'email': 'gio@example.com',
        'auth_provider': 'google',
      });

      expect(user.canChangePassword, isFalse);
    });
  });

  group('PlanLimits', () {
    test('produces one labelled line per metered bucket', () {
      final PlanLimits limits = PlanLimits.fromJson(_usageOf(meResponse()));

      final List<UsageLine> lines = limits.lines;

      expect(
        lines.map((UsageLine l) => l.key).toList(),
        <String>[
          PlanLimits.keyDocuments,
          PlanLimits.keyPages,
          PlanLimits.keyConversions,
          PlanLimits.keyEsign,
          PlanLimits.keyWebScans,
          PlanLimits.keyBarcodes,
        ],
      );

      final UsageLine documents = lines.first;
      expect(documents.label, S.documents);
      expect(documents.used, 180);
      expect(documents.limit, 200);
      expect(documents.remaining, 20);
      expect(documents.ratio, closeTo(0.9, 0.0001));
      // Past 85% is where the dashboard starts offering an upgrade.
      expect(documents.isNearLimit, isTrue);
      expect(documents.isExhausted, isFalse);

      final UsageLine pages = lines[1];
      expect(pages.label, S.usagePages);
      expect(pages.isNearLimit, isFalse);

      expect(limits.anyNearLimit, isTrue);
      expect(
        limits.linesFor(<String>[PlanLimits.keyPages, 'nonsense']).single.key,
        PlanLimits.keyPages,
      );
    });

    test('reads the billing snapshot spelling of the e-sign bucket', () {
      final PlanLimits limits = PlanLimits.fromJson(const <String, dynamic>{
        'esign': <String, dynamic>{'used': 7, 'limit': 10, 'remaining': 3},
      });

      expect(limits.esignUsed, 7);
      expect(limits.esignLimit, 10);
    });

    test('treats a zero limit as unmetered rather than as no allowance', () {
      final PlanLimits limits = PlanLimits.fromJson(const <String, dynamic>{
        'documents': <String, dynamic>{'used': 4, 'limit': 0, 'remaining': 0},
      });

      final UsageLine documents = limits.lines.first;
      expect(documents.isUnlimited, isTrue);
      expect(documents.ratio, 0);
      expect(documents.isExhausted, isFalse);
      expect(documents.remaining, isNull);
    });

    test('an absent bucket degrades to null, not to zero', () {
      final UsageLine barcodes =
          PlanLimits.empty.line(PlanLimits.keyBarcodes)!;

      expect(barcodes.used, isNull);
      expect(barcodes.limit, isNull);
      expect(barcodes.isUnlimited, isTrue);
    });
  });

  group('ApiException field errors', () {
    test('maps a 422 onto the fields the sign-in form renders', () {
      final ApiException failure = ApiException.fromResponse(
        _response(422, <String, dynamic>{
          'error': <String, dynamic>{
            'code': 'validation_failed',
            'status': 422,
            'title': 'Check the form',
            'detail': 'The email field must be a valid email address.',
            'errors': <String, dynamic>{
              'email': <String>['The email field must be a valid email address.'],
              'password': <String>['The password field is required.'],
            },
          },
        }),
      );

      expect(failure.code, 'validation_failed');
      expect(failure.status, 422);
      expect(
        failure.fieldError('email'),
        'The email field must be a valid email address.',
      );
      expect(failure.fieldError('password'), 'The password field is required.');
      // Anything the form does not have a box for stays null, which is what
      // makes the screen fall back to a toast.
      expect(failure.fieldError('company_name'), isNull);
    });

    test('a wrong password is not a field error', () {
      final ApiException failure = ApiException.fromResponse(
        _response(401, <String, dynamic>{
          'error': <String, dynamic>{
            'code': 'invalid_credentials',
            'status': 401,
            'title': 'Wrong email or password',
            'detail': 'Check the email address and password and try again.',
          },
        }),
      );

      expect(failure.fieldErrors, isEmpty);
      expect(failure.fieldError('email'), isNull);
      expect(failure.fieldError('password'), isNull);
      expect(failure.isAuthFailure, isFalse);
      expect(
        failure.message,
        'Check the email address and password and try again.',
      );
    });

    test('email_taken arrives as a code, which register pins to the field', () {
      final ApiException failure = ApiException.fromResponse(
        _response(422, <String, dynamic>{
          'error': <String, dynamic>{
            'code': 'email_taken',
            'status': 422,
            'title': 'Email already registered',
            'detail': 'An account already exists with that email address. '
                'Sign in instead.',
          },
        }),
      );

      expect(failure.code, 'email_taken');
      expect(failure.fieldErrors, isEmpty);
      expect(failure.message, contains('Sign in instead.'));
    });

    test('reads Laravel\'s default envelope too', () {
      final ApiException failure = ApiException.fromResponse(
        _response(422, <String, dynamic>{
          'message': 'The given data was invalid.',
          'errors': <String, dynamic>{
            'company_name': <String>['The company name field is required.'],
          },
        }),
      );

      expect(failure.code, 'validation_failed');
      expect(
        failure.fieldError('company_name'),
        'The company name field is required.',
      );
    });
  });
}

Response<dynamic> _response(int status, Map<String, dynamic> body) {
  return Response<dynamic>(
    requestOptions: RequestOptions(path: '/auth/login'),
    statusCode: status,
    data: body,
  );
}

/// Pulls the `usage` block out of the fixture, so it is written once.
Map<String, dynamic> _usageOf(Map<String, dynamic> me) =>
    me['usage']! as Map<String, dynamic>;
