/// The tab set is a product decision, so it gets a test.
///
/// Specifically: a signed-out user is offered no tabs at all. Every screen in
/// the shell now calls authenticated endpoints, and a tab that leads to a
/// redirect is how a store reviewer decides the app is broken. The two things a
/// guest *can* do — open a PDF and scan one — are full-screen routes launched
/// from the welcome screen, not tabs.
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
    test('Home is the landing tab for a signed-in user', () {
      final List<ShellDestination> tabs =
          AppShell.destinationsFor(signedIn: true);

      expect(tabs.first.route, AppRoute.home);
      expect(tabs.first.path, AppRoute.homePath);
    });

    test('a guest gets no tabs at all', () {
      // Not "no authenticated tabs" — none. The shell drops its navigation bar
      // entirely rather than rendering one that cannot be used, which also
      // keeps NavigationBar from asserting on an empty destination list during
      // the frame between signing out and the redirect landing.
      expect(AppShell.destinationsFor(signedIn: false), isEmpty);
    });

    test('signing in adds Documents when the feature is on', () {
      final Set<String> routes = AppShell.destinationsFor(signedIn: true)
          .map((ShellDestination d) => d.route)
          .toSet();

      expect(routes.contains(AppRoute.documents), Features.documents);
    });

    test('the removed guest reader tab is really gone', () {
      // `/viewer` was the guest landing page. Only the reader itself survives,
      // at `/viewer/read`, and it is not a tab.
      final Set<String> paths = AppShell.destinationsFor(signedIn: true)
          .map((ShellDestination d) => d.path)
          .toSet();

      expect(paths, isNot(contains('/viewer')));
      expect(paths, isNot(contains(AppRoute.pdfViewPath)));
      expect(paths, isNot(contains(AppRoute.scanPath)));
    });

    test('every destination has a distinct route and a label', () {
      final List<ShellDestination> tabs =
          AppShell.destinationsFor(signedIn: true);

      expect(
        tabs.map((ShellDestination d) => d.route).toSet().length,
        tabs.length,
        reason: 'duplicate routes would make the selected index ambiguous',
      );
      expect(
        tabs.map((ShellDestination d) => d.label).toSet().length,
        tabs.length,
        reason: 'two tabs sharing a label only shows up on the device',
      );
      expect(tabs.every((ShellDestination d) => d.label.isNotEmpty), isTrue);

      // Material's NavigationBar throws below two destinations, and more than
      // five is unreadable on a phone.
      expect(tabs.length, greaterThanOrEqualTo(2));
      expect(tabs.length, lessThanOrEqualTo(5));
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
      expect(Features.templates, isFalse);
      expect(Features.apiKeys, isFalse);
    });

    // Web-to-Excel is on. It came back because the navigation offered it in
    // three places (Tools, More, the dashboard) while the flag kept its route
    // out of the router, so every one of those taps threw. Those entries are
    // now gated on the flag as well, so this is a product decision again
    // rather than a crash.
    test('web-to-excel ships', () {
      expect(Features.webExtraction, isTrue);
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
