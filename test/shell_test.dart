/// The tab set is a product decision, so it gets a test.
///
/// Specifically: a signed-out user must never be offered Documents. That is not
/// cosmetic — those screens call authenticated endpoints, and a tab that leads
/// to a redirect is how a store reviewer decides the app is broken.
///
/// [AppShell.destinationsFor] is a pure function precisely so this can be
/// asserted without a widget binding, a provider container or a fake session.
library;

import 'package:banksheet_mobile/app/routes.dart';
import 'package:banksheet_mobile/app/shell.dart';
import 'package:banksheet_mobile/core/config/feature_flags.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppShell.destinationsFor', () {
    test('the reader is first for everyone', () {
      for (final bool signedIn in <bool>[true, false]) {
        final List<ShellDestination> tabs =
            AppShell.destinationsFor(signedIn: signedIn);
        expect(
          tabs.first.route,
          AppRoute.viewer,
          reason: 'signedIn: $signedIn — the reader is the landing tab',
        );
      }
    });

    test('a guest is never offered an authenticated destination', () {
      final Set<String> guestRoutes = AppShell.destinationsFor(signedIn: false)
          .map((ShellDestination d) => d.route)
          .toSet();

      expect(guestRoutes, isNot(contains(AppRoute.documents)));
      expect(guestRoutes, isNot(contains(AppRoute.review)));
      expect(guestRoutes, isNot(contains(AppRoute.dashboard)));
    });

    test('signing in adds Documents when the feature is on', () {
      final Set<String> routes = AppShell.destinationsFor(signedIn: true)
          .map((ShellDestination d) => d.route)
          .toSet();

      expect(routes.contains(AppRoute.documents), Features.documents);
    });

    test('every destination has a distinct route and a label', () {
      for (final bool signedIn in <bool>[true, false]) {
        final List<ShellDestination> tabs =
            AppShell.destinationsFor(signedIn: signedIn);

        expect(
          tabs.map((ShellDestination d) => d.route).toSet().length,
          tabs.length,
          reason: 'duplicate routes would make the selected index ambiguous',
        );
        expect(tabs.every((ShellDestination d) => d.label.isNotEmpty), isTrue);

        // Material's NavigationBar throws below two destinations, and more
        // than five is unreadable on a phone.
        expect(tabs.length, greaterThanOrEqualTo(2));
        expect(tabs.length, lessThanOrEqualTo(5));
      }
    });
  });

  group('Features', () {
    test('v1 ships the reader-first feature set', () {
      expect(Features.tools, isTrue);
      expect(Features.documents, isTrue);
      expect(Features.billing, isTrue);
    });

    test('v1 hides the long tail', () {
      expect(Features.reviewQueue, isFalse);
      expect(Features.webExtraction, isFalse);
      expect(Features.templates, isFalse);
      expect(Features.apiKeys, isFalse);
    });

    test('the diagnostics map covers every flag', () {
      // A build whose behaviour cannot be read off a support screenshot is a
      // build you debug by guessing.
      expect(Features.all.length, 12);
      expect(Features.all['review_queue'], Features.reviewQueue);
      expect(Features.all['tools'], Features.tools);
    });
  });
}
