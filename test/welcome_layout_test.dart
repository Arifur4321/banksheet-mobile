/// The welcome screen must fit on the smallest phone we support, without
/// scrolling, at the default text size.
///
/// This is the one layout rule in the app written down as a requirement rather
/// than a preference, and it is the rule most likely to be broken by an
/// innocent-looking edit — adding the two action tiles was exactly such an
/// edit. A call to action below the fold is a call to action that does not
/// exist, and "I already have an account" being off-screen is how a returning
/// user concludes the app is broken.
///
/// "Did it fit" has to be *measured*, not caught: the screen wraps its content
/// in a `SingleChildScrollView` as a safety net for extreme text scaling, and a
/// scroll view never throws an overflow error. So the assertion is that the
/// scroll position has nowhere to go — `maxScrollExtent == 0`.
///
/// The sizes below are post-safe-area heights, because that is what the
/// screen's `LayoutBuilder` actually receives:
///
///   * 320x548 — iPhone SE 1st gen (568 tall, 20pt status bar). The floor.
///   * 360x616 — the commonest low-end Android.
///   * 393x759 — iPhone 15 (852 tall, 59pt notch, 34pt home indicator).
///
/// It is pumped in both states the free-scan counter can be in, because the
/// caption under the tiles gets longer once the count arrives — and a layout
/// that fits only before the database answers is a layout that reflows in front
/// of the user.
library;

import 'package:banksheet_mobile/core/i18n/strings.dart';
import 'package:banksheet_mobile/features/auth/presentation/welcome_screen.dart';
import 'package:banksheet_mobile/features/home/presentation/home_screen.dart';
import 'package:banksheet_mobile/features/scan/presentation/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  /// Pumps the real screen at [size] logical pixels.
  ///
  /// `freeScansLeftProvider` is overridden rather than left to resolve: it
  /// reads the SQLite database through `bootstrapProvider`, which only exists
  /// once `main()` has run. Overriding it is also what lets the same test cover
  /// both the "count not known yet" and "count known" layouts.
  Future<void> pumpAt(
    WidgetTester tester,
    Size size, {
    int? freeScans,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          if (freeScans != null)
            freeScansLeftProvider.overrideWith((Ref ref) async => freeScans),
        ],
        child: const MaterialApp(home: WelcomeScreen()),
      ),
    );
    await tester.pump();
  }

  void assertFits(WidgetTester tester, Size size, String label) {
    expect(tester.takeException(), isNull, reason: label);

    // Every way forward is on screen.
    expect(find.text('Open PDF'), findsOneWidget, reason: label);
    expect(find.text('Scan to PDF'), findsOneWidget, reason: label);
    expect(find.text(S.createFreeAccount), findsOneWidget, reason: label);
    expect(find.text(S.alreadyHaveAccount), findsOneWidget, reason: label);

    // And the removed link stays removed.
    expect(find.textContaining('no account'), findsNothing, reason: label);

    final ScrollableState scrollable =
        tester.state<ScrollableState>(find.byType(Scrollable).first);
    expect(
      scrollable.position.maxScrollExtent,
      0,
      reason: '$label: the welcome screen scrolls, so something is below the '
          'fold. Trim a band in the LayoutBuilder rather than accepting it.',
    );

    // The last control is fully inside the viewport, not merely laid out.
    final Rect signIn = tester.getRect(find.text(S.alreadyHaveAccount));
    expect(signIn.bottom, lessThanOrEqualTo(size.height), reason: label);
  }

  group('WelcomeScreen fits above the fold', () {
    const List<(String, Size)> devices = <(String, Size)>[
      ('iPhone SE 1st gen', Size(320, 548)),
      ('low-end Android', Size(360, 616)),
      ('iPhone 15', Size(393, 759)),
    ];

    for (final (String name, Size size) in devices) {
      testWidgets('on $name before the scan count loads', (
        WidgetTester tester,
      ) async {
        await pumpAt(tester, size);
        assertFits(tester, size, name);
      });

      testWidgets('on $name with the scan count loaded', (
        WidgetTester tester,
      ) async {
        await pumpAt(tester, size, freeScans: 3);
        await tester.pumpAndSettle();
        assertFits(tester, size, '$name (count shown)');
      });

      testWidgets('on $name with the free scans spent', (
        WidgetTester tester,
      ) async {
        await pumpAt(tester, size, freeScans: 0);
        await tester.pumpAndSettle();
        assertFits(tester, size, '$name (quota spent)');
      });
    }
  });

  group('PrimaryActionTile', () {
    testWidgets('renders label and caption and fires once', (
      WidgetTester tester,
    ) async {
      int taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PrimaryActionTile(
              icon: Icons.folder_open_rounded,
              label: 'Open PDF',
              caption: 'From this phone',
              onTap: () => taps++,
            ),
          ),
        ),
      );

      expect(find.text('Open PDF'), findsOneWidget);
      expect(find.text('From this phone'), findsOneWidget);

      await tester.tap(find.byType(PrimaryActionTile));
      await tester.pump();
      expect(taps, 1);
    });

    testWidgets('survives the narrowest slot it ships in', (
      WidgetTester tester,
    ) async {
      // Two tiles plus gutters and page padding on a 320pt phone leaves each
      // one about 134pt.
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 132,
                child: PrimaryActionTile(
                  icon: Icons.document_scanner_rounded,
                  label: 'Scan to PDF',
                  caption: 'Photos to pages',
                  onTap: _noop,
                ),
              ),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
    });
  });
}

void _noop() {}
