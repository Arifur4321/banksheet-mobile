/// The bottom navigation shell.
///
/// Five destinations mirroring how the website's sidebar is actually used:
/// the dashboard, the two screens that carry the core loop (documents and the
/// review queue), the tools hub, and a "More" hub for everything else. The
/// website's sidebar has 19 entries; a phone cannot carry 19 tabs, so the long
/// tail lives one level down instead of being cut.
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/theme/tokens.dart';
import 'routes.dart';

class AppShell extends StatelessWidget {
  const AppShell({required this.child, super.key});

  final Widget child;

  static const List<_Destination> _destinations = <_Destination>[
    _Destination(
      route: AppRoute.dashboard,
      path: AppRoute.dashboardPath,
      label: 'Home',
      icon: Icons.space_dashboard_outlined,
      activeIcon: Icons.space_dashboard_rounded,
    ),
    _Destination(
      route: AppRoute.documents,
      path: AppRoute.documentsPath,
      label: 'Documents',
      icon: Icons.description_outlined,
      activeIcon: Icons.description_rounded,
    ),
    _Destination(
      route: AppRoute.review,
      path: AppRoute.reviewPath,
      label: 'Review',
      icon: Icons.fact_check_outlined,
      activeIcon: Icons.fact_check_rounded,
    ),
    _Destination(
      route: AppRoute.tools,
      path: AppRoute.toolsPath,
      label: 'Tools',
      icon: Icons.build_outlined,
      activeIcon: Icons.build_rounded,
    ),
    _Destination(
      route: AppRoute.more,
      path: AppRoute.morePath,
      label: 'More',
      icon: Icons.grid_view_outlined,
      activeIcon: Icons.grid_view_rounded,
    ),
  ];

  int _indexFor(BuildContext context) {
    final String location = GoRouterState.of(context).uri.path;
    final int index = _destinations.indexWhere(
      (_Destination d) => location.startsWith(d.path),
    );
    return index < 0 ? 0 : index;
  }

  @override
  Widget build(BuildContext context) {
    final int index = _indexFor(context);

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
            // Tapping the current tab pops its stack back to root, which is
            // the behaviour users expect from every other app.
            if (i == index) {
              return;
            }
            context.goNamed(_destinations[i].route);
          },
          destinations: <NavigationDestination>[
            for (final _Destination d in _destinations)
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
