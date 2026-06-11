import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../theme/app_palette.dart';
import '../theme/app_spacing.dart';
import '../../features/map/map_screen.dart';
import '../../features/search/search_screen.dart';
import '../../features/route_planner/route_screen.dart';
import '../../features/saved_routes/saved_routes_screen.dart';
import '../../features/settings/settings_screen.dart';
import '../../features/alerts/alerts_screen.dart';
import '../../features/help/help_screen.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>();

/// Branch indices inside the [StatefulShellRoute]. Explore (the map) is the
/// substrate; Search and Settings are reachable surfaces that don't occupy a
/// bottom-bar slot.
class _Branch {
  static const explore = 0;
  static const search = 1;
  static const navigate = 2;
  static const saved = 3;
  // Branch 4 (Settings) is reached from the Explore profile button, not a tab.
}

final appRouter = GoRouter(
  navigatorKey: _rootNavigatorKey,
  initialLocation: '/map',
  routes: [
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
          GoRoute(path: '/route', builder: (_, __) => const RouteScreen()),
        ]),
        StatefulShellBranch(routes: [
          GoRoute(
              path: '/saved', builder: (_, __) => const SavedRoutesScreen()),
        ]),
        StatefulShellBranch(routes: [
          GoRoute(
              path: '/settings', builder: (_, __) => const SettingsScreen()),
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
  _NavItem(_Branch.navigate, Icons.alt_route_rounded, Icons.navigation_rounded,
      'Navigate'),
  _NavItem(_Branch.saved, Icons.bookmark_border_rounded, Icons.bookmark_rounded,
      'Saved'),
];

class ScaffoldWithNav extends StatelessWidget {
  final StatefulNavigationShell shell;

  const ScaffoldWithNav({super.key, required this.shell});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      body: shell,
      bottomNavigationBar: _GlassNavBar(
        currentBranch: shell.currentIndex,
        onSelect: (branch) {
          HapticFeedback.lightImpact();
          shell.goBranch(branch, initialLocation: branch == shell.currentIndex);
        },
      ),
    );
  }
}

class _GlassNavBar extends StatelessWidget {
  final int currentBranch;
  final ValueChanged<int> onSelect;

  const _GlassNavBar({required this.currentBranch, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bottomInset = MediaQuery.of(context).padding.bottom;

    final barColor = (isDark ? AppPalette.cardDark : Colors.white)
        .withValues(alpha: isDark ? 0.78 : 0.82);
    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.black.withValues(alpha: 0.05);

    return Padding(
      padding:
          EdgeInsets.fromLTRB(16, 0, 16, bottomInset > 0 ? bottomInset : 14),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(26),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            height: AppDims.navBarHeight,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: barColor,
              borderRadius: BorderRadius.circular(26),
              border: Border.all(color: borderColor),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.12),
                  blurRadius: 28,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (final item in _navItems)
                  _NavCell(
                    item: item,
                    selected: item.isSelected(currentBranch),
                    isDark: isDark,
                    onTap: () => onSelect(item.branch),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavCell extends StatelessWidget {
  final _NavItem item;
  final bool selected;
  final bool isDark;
  final VoidCallback onTap;

  const _NavCell({
    required this.item,
    required this.selected,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final inactiveColor =
        isDark ? AppPalette.inkMutedDark : AppPalette.inkMuted;

    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          height: 48,
          margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 9),
          decoration: BoxDecoration(
            gradient: selected ? AppPalette.brandGradient : null,
            borderRadius: BorderRadius.circular(16),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: AppPalette.brand.withValues(alpha: 0.35),
                      blurRadius: 16,
                      offset: const Offset(0, 5),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                selected ? item.activeIcon : item.icon,
                size: 22,
                color: selected ? Colors.white : inactiveColor,
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
                child: selected
                    ? Padding(
                        padding: const EdgeInsets.only(left: 8, right: 2),
                        child: Text(
                          item.label,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.2,
                          ),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
