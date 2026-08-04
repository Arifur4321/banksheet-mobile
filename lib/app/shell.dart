/// The bottom navigation shell.
///
/// The destination list is built per session rather than declared as a
/// constant, because v1 has two different apps behind one binary:
///
///   * **Signed out** — a PDF reader with a tools hub that asks for an account
///     at the point of use. Three tabs, no dead ends.
///   * **Signed in** — the reader plus the workspace: documents, statements,
///     exports and everything under More. Four tabs.
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
  /// Order is deliberate: the reader is first because it is the one thing that
  /// works with no account, and a first-run user who lands on a login wall
  /// uninstalls. Everything else earns its place to the right of it.
  static List<_Destination> destinationsFor({required bool signedIn}) {
    return <_Destination>[
      const _Destination(
        route: AppRoute.viewer,
        path: AppRoute.viewerPath,
        label: 'Read',
        icon: Icons.menu_book_outlined,
        activeIcon: Icons.menu_book_rounded,
      ),
      if (signedIn && Features.dashboardTab)
        const _Destination(
          route: AppRoute.dashboard,
          path: AppRoute.dashboardPath,
          label: 'Home',
          icon: Icons.space_dashboard_outlined,
          activeIcon: Icons.space_dashboard_rounded,
        ),
      if (signedIn && Features.documents)
        const _Destination(
          route: AppRoute.documents,
          path: AppRoute.documentsPath,
          label: 'Documents',
          icon: Icons.description_outlined,
          activeIcon: Icons.description_rounded,
        ),
      if (signedIn && Features.reviewQueue)
        const _Destination(
          route: AppRoute.review,
          path: AppRoute.reviewPath,
          label: 'Review',
          icon: Icons.fact_check_outlined,
          activeIcon: Icons.fact_check_rounded,
        ),
      if (Features.tools)
        const _Destination(
          route: AppRoute.tools,
          path: AppRoute.toolsPath,
          label: 'Tools',
          icon: Icons.build_outlined,
          activeIcon: Icons.build_rounded,
        ),
      const _Destination(
        route: AppRoute.more,
        path: AppRoute.morePath,
        label: 'More',
        icon: Icons.grid_view_outlined,
        activeIcon: Icons.grid_view_rounded,
      ),
    ];
  }

  int _indexFor(BuildContext context, List<_Destination> destinations) {
    final String location = GoRouterState.of(context).uri.path;
    final int index = destinations.indexWhere(
      (_Destination d) => location.startsWith(d.path),
    );
    return index < 0 ? 0 : index;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watching the store rather than reading it means signing in or out
    // rebuilds the bar, so a user who signs in mid-session gets the Documents
    // tab immediately instead of after the next cold start.
    final bool signedIn = ref.watch(tokenStoreProvider).hasSession;
    final List<_Destination> destinations =
        destinationsFor(signedIn: signedIn);
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
            for (final _Destination d in destinations)
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

class _Destination {
  const _Destination({
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
