import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../shared/providers/providers.dart';
import '../../features/map/map_screen.dart';
import '../../features/search/search_screen.dart';
import '../../features/route_planner/route_screen.dart';
import '../../features/saved_routes/saved_routes_screen.dart';
import '../../features/directory/directory_screen.dart';
import '../../features/map3d/map3d_screen.dart';
import '../../features/alerts/alerts_screen.dart';
import '../../features/help/help_screen.dart';
import '../../features/onboarding/onboarding_screen.dart';
import '../../data/datasources/local_storage.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>();

/// Branch indices inside the [StatefulShellRoute]. Explore (the map) is the
/// substrate; Search is a reachable surface that doesn't occupy a
/// bottom-bar slot.
class _Branch {
  static const explore = 0;
  static const search = 1;
  static const directory = 2;
  static const navigate = 3;
  static const saved = 4;
}

final appRouter = GoRouter(
  navigatorKey: _rootNavigatorKey,
  initialLocation: '/map',
  redirect: (context, state) {
    final complete = LocalStorage().getOnboardingComplete();
    final atOnboarding = state.matchedLocation == '/onboarding';
    if (!complete && !atOnboarding) return '/onboarding';
    if (complete && atOnboarding) return '/map';
    return null;
  },
  routes: [
    GoRoute(
      path: '/onboarding',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (_, __) => const OnboardingScreen(),
    ),
    StatefulShellRoute.indexedStack(
      builder: (context, state, shell) => ScaffoldWithNav(shell: shell),
      branches: [
        StatefulShellBranch(routes: [
          GoRoute(path: '/map', builder: (_, __) => const MapScreen()),
        ]),
        StatefulShellBranch(routes: [
          GoRoute(path: '/search', builder: (_, __) => const SearchScreen()),
        ]),
        StatefulShellBranch(routes: [
          GoRoute(
              path: '/directory', builder: (_, __) => const DirectoryScreen()),
        ]),
        StatefulShellBranch(routes: [
          GoRoute(path: '/route', builder: (_, __) => const RouteScreen()),
        ]),
        StatefulShellBranch(routes: [
          GoRoute(
              path: '/saved', builder: (_, __) => const SavedRoutesScreen()),
        ]),
      ],
    ),
    // Conditional chrome — pushed over the shell with their own back affordance.
    GoRoute(
      path: '/alerts',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (_, __) => const AlertsScreen(),
    ),
    GoRoute(
      path: '/help',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (_, __) => const HelpScreen(),
    ),
    GoRoute(
      path: '/map3d',
      parentNavigatorKey: _rootNavigatorKey,
      pageBuilder: (_, state) => CustomTransitionPage(
        key: state.pageKey,
        transitionDuration: const Duration(milliseconds: 320),
        transitionsBuilder: (_, animation, __, child) => FadeTransition(
          opacity: CurveTween(curve: Curves.easeOut).animate(animation),
          child: child,
        ),
        child: const Map3DScreen(),
      ),
    ),
  ],
);

/// A bottom-bar tab mapped to a shell branch.
class _NavItem {
  final int branch;
  final IconData icon;
  final IconData activeIcon;
  final String label;

  /// Branch indices that should light this tab as selected (a tab can "own"
  /// deeper surfaces — Explore owns Search).
  final Set<int> ownedBranches;

  const _NavItem(
    this.branch,
    this.icon,
    this.activeIcon,
    this.label, {
    this.ownedBranches = const {},
  });

  bool isSelected(int current) =>
      current == branch || ownedBranches.contains(current);
}

const _navItems = [
  _NavItem(_Branch.explore, Icons.explore_outlined, Icons.explore_rounded,
      'Explore',
      ownedBranches: {_Branch.search}),
  _NavItem(_Branch.directory, Icons.storefront_outlined,
      Icons.storefront_rounded, 'Directory'),
  _NavItem(_Branch.navigate, Icons.alt_route_rounded, Icons.navigation_rounded,
      'Navigate'),
  _NavItem(_Branch.saved, Icons.bookmark_border_rounded, Icons.bookmark_rounded,
      'Saved'),
];

class ScaffoldWithNav extends ConsumerWidget {
  final StatefulNavigationShell shell;

  const ScaffoldWithNav({super.key, required this.shell});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = _navItems.indexWhere((i) => i.isSelected(shell.currentIndex));
    final onMap = shell.currentIndex == _Branch.explore;
    final building = ref.watch(selectedBuildingProvider);
    // A previewed route closes with back; live navigation keeps running.
    final preview = ref.watch(activeRouteProvider) != null &&
        !ref.watch(navigationSessionProvider.select((s) => s.isActive));
    // Android back: other tabs return to the map, the map first closes what
    // is open on it, and only then does the app close.
    return PopScope(
      canPop: onMap && building == null && !preview,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (!onMap) {
          shell.goBranch(_Branch.explore);
        } else if (building != null) {
          ref.read(selectedBuildingProvider.notifier).state = null;
        } else {
          ref.read(activeRouteProvider.notifier).state = null;
        }
      },
      child: _scaffold(context, selected),
    );
  }

  Widget _scaffold(BuildContext context, int selected) {
    return Scaffold(
      body: shell,
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: Theme.of(context).colorScheme.outlineVariant)),
        ),
        child: NavigationBar(
          selectedIndex: selected < 0 ? 0 : selected,
          onDestinationSelected: (i) {
            HapticFeedback.selectionClick();
            final branch = _navItems[i].branch;
            shell.goBranch(branch, initialLocation: branch == shell.currentIndex);
          },
          destinations: [
            for (final item in _navItems)
              NavigationDestination(
                icon: Icon(item.icon),
                selectedIcon: Icon(item.activeIcon),
                label: item.label,
              ),
          ],
        ),
      ),
    );
  }
}
