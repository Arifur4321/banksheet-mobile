/// The bottom navigation shell.
///
/// Every screen inside this shell requires a session. That is a change from the
/// version with a guest "Read" tab: a signed-out user now lands on the welcome
/// screen, and the two things they can do without an account — open a PDF and
/// scan one — are full-screen routes launched straight from it rather than
/// tabs. A navigation bar whose tabs all end in a login prompt is worse than no
/// navigation bar.
///
/// The list is still built per session rather than declared as a constant,
/// because [Features] decides which tabs a given build has at all, and
/// [destinationsFor] is what the tests assert against.
///
/// The website's sidebar has 19 entries. A phone cannot carry 19 tabs, so the
/// long tail lives under "More" rather than being cut — and for v1 the entries
/// [Features] turns off are not built at all.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/config/feature_flags.dart';
import '../core/providers.dart';
import '../core/theme/tokens.dart';
import 'routes.dart';

class AppShell extends ConsumerWidget {
  const AppShell({required this.child, super.key});

  final Widget child;

  /// The tabs this session gets.
  ///
  /// Order is deliberate: Home is first because it carries the two actions the
  /// app is *for* — open a PDF, scan a PDF — plus what you were last reading.
  /// Everything else earns its place to the right of it.
  ///
  /// [signedIn] is retained rather than removed even though every destination
  /// below is now behind the session gate: the shell rebuilds on sign-out, and
  /// a bar that keeps rendering the previous account's tabs for a frame while
  /// the redirect runs is a flash of the wrong app.
  static List<ShellDestination> destinationsFor({required bool signedIn}) {
    if (!signedIn) {
      return const <ShellDestination>[];
    }

    return <ShellDestination>[
      const ShellDestination(
        route: AppRoute.home,
        path: AppRoute.homePath,
        label: 'Home',
        icon: Icons.home_outlined,
        activeIcon: Icons.home_rounded,
      ),
      if (signedIn && Features.dashboardTab)
        const ShellDestination(
          route: AppRoute.dashboard,
          path: AppRoute.dashboardPath,
          // "Metrics", not "Home" — Home is the tab above it now. Two tabs with
          // the same label is the sort of thing that only shows up on the
          // device, in a screenshot, after the build is uploaded.
          label: 'Metrics',
          icon: Icons.space_dashboard_outlined,
          activeIcon: Icons.space_dashboard_rounded,
        ),
      if (signedIn && Features.documents)
        const ShellDestination(
          route: AppRoute.documents,
          path: AppRoute.documentsPath,
          label: 'Documents',
          icon: Icons.description_outlined,
          activeIcon: Icons.description_rounded,
        ),
      if (signedIn && Features.reviewQueue)
        const ShellDestination(
          route: AppRoute.review,
          path: AppRoute.reviewPath,
          label: 'Review',
          icon: Icons.fact_check_outlined,
          activeIcon: Icons.fact_check_rounded,
        ),
      if (Features.tools)
        const ShellDestination(
          route: AppRoute.tools,
          path: AppRoute.toolsPath,
          label: 'Tools',
          icon: Icons.build_outlined,
          activeIcon: Icons.build_rounded,
        ),
      const ShellDestination(
        route: AppRoute.more,
        path: AppRoute.morePath,
        label: 'More',
        icon: Icons.grid_view_outlined,
        activeIcon: Icons.grid_view_rounded,
      ),
    ];
  }

  int _indexFor(BuildContext context, List<ShellDestination> destinations) {
    final String location = GoRouterState.of(context).uri.path;
    final int index = destinations.indexWhere(
      (ShellDestination d) => location.startsWith(d.path),
    );
    return index < 0 ? 0 : index;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watching the store rather than reading it means signing in or out
    // rebuilds the bar, so a user who signs in mid-session gets the Documents
    // tab immediately instead of after the next cold start.
    final bool signedIn = ref.watch(tokenStoreProvider).hasSession;
    final List<ShellDestination> destinations =
        destinationsFor(signedIn: signedIn);

    // Sign-out empties the list, and this frame renders before the router's
    // redirect has moved the user off. NavigationBar asserts on an empty
    // destination list, so the bar is dropped rather than built empty.
    if (destinations.isEmpty) {
      return Scaffold(
        backgroundColor: AppColors.canvas,
        body: child,
      );
    }

    final int index = _indexFor(context, destinations);

    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: child,
      bottomNavigationBar: DecoratedBox(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.border)),
        ),
        child: NavigationBar(
          selectedIndex: index,
          onDestinationSelected: (int i) {
            if (i == index) {
              return;
            }
            context.goNamed(destinations[i].route);
          },
          destinations: <NavigationDestination>[
            for (final ShellDestination d in destinations)
              NavigationDestination(
                icon: Icon(d.icon),
                selectedIcon: Icon(d.activeIcon),
                label: d.label,
                tooltip: d.label,
              ),
          ],
        ),
      ),
    );
  }
}

/// One bottom-navigation destination.
///
/// Public because [AppShell.destinationsFor] is the unit under test: the tab
/// set is a product decision (a guest must never be offered Documents) and
/// deserves a test that does not need a widget binding to run.
class ShellDestination {
  const ShellDestination({
    required this.route,
    required this.path,
    required this.label,
    required this.icon,
    required this.activeIcon,
  });

  final String route;
  final String path;
  final String label;
  final IconData icon;
  final IconData activeIcon;
}
