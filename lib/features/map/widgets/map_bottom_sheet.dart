import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../data/models/bridge.dart';
import '../../../data/models/building.dart';
import '../../../data/models/entry_point.dart';
import '../../../data/models/shop.dart';
import '../../../shared/providers/providers.dart';
import '../../../shared/widgets/app_pill.dart';
import '../../../shared/widgets/section_header.dart';
import '../../../shared/widgets/sheet_surface.dart';
import '../../route_planner/widgets/step_list.dart';
import '../../shop_detail/shop_detail_sheet.dart';
import 'building_tooltip.dart';

/// The single draggable sheet that anchors the bottom of the map.
///
/// It is always present and swaps its content based on app state:
///   • a route/navigation in progress → summary + live status + steps
///   • a building selected            → place detail
///   • otherwise (idle)               → search prompt + quick routes
///
/// It is a passive renderer: navigation logic stays on the map screen and is
/// invoked through [onStopNavigation] / [onStartQuickRoute]. Entry-point
/// guidance is plain map-screen state, passed down as props.
class MapBottomSheet extends ConsumerStatefulWidget {
  final EntryPoint? guidanceEntryPoint;
  final double? guidanceEntryDistanceM;
  final VoidCallback onStopNavigation;
  final void Function(String fromId, String toId, String mode)
      onStartQuickRoute;

  const MapBottomSheet({
    super.key,
    required this.guidanceEntryPoint,
    required this.guidanceEntryDistanceM,
    required this.onStopNavigation,
    required this.onStartQuickRoute,
  });

  @override
  ConsumerState<MapBottomSheet> createState() => _MapBottomSheetState();
}

enum _SheetMode { idle, building, route }

class _MapBottomSheetState extends ConsumerState<MapBottomSheet> {
  final _controller = DraggableScrollableController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  _SheetMode _mode() {
    final route = ref.read(activeRouteProvider);
    if (route != null && route.length > 1) return _SheetMode.route;
    if (ref.read(selectedBuildingProvider) != null) return _SheetMode.building;
    return _SheetMode.idle;
  }

  void _syncSize() {
    if (!_controller.isAttached) return;
    final target = switch (_mode()) {
      _SheetMode.route => AppDims.sheetMid,
      _SheetMode.building => AppDims.sheetMid,
      _SheetMode.idle => AppDims.sheetIdle,
    };
    // Only grow toward, or collapse to, the target — never fight the user mid
    // drag if they've already pulled it further than the target.
    _controller.animateTo(
      target,
      duration: AppMotion.normal,
      curve: AppMotion.curve,
    );
  }

  @override
  Widget build(BuildContext context) {
    // Watch the providers that decide which mode the sheet is in so it rebuilds
    // on every contextual change; also resize on those transitions.
    ref.watch(selectedBuildingProvider);
    ref.watch(activeRouteProvider);
    ref.listen(selectedBuildingProvider, (_, __) => _syncSize());
    ref.listen(activeRouteProvider, (_, __) => _syncSize());

    final mediaBottom = MediaQuery.of(context).viewPadding.bottom;
    final navClear =
        AppDims.navBarHeight + (mediaBottom > 0 ? mediaBottom : 14) + 16;

    // Build the content here (during build) so the per-mode `ref.watch` calls
    // register correctly — never inside the sheet's deferred builder closure.
    final children = _content(context);

    return DraggableScrollableSheet(
      controller: _controller,
      initialChildSize: AppDims.sheetIdle,
      minChildSize: AppDims.sheetMin,
      maxChildSize: AppDims.sheetMax,
      snap: true,
      snapSizes: const [AppDims.sheetIdle, AppDims.sheetMid],
      builder: (context, scrollController) {
        return SheetSurface(
          controller: scrollController,
          padding: EdgeInsets.fromLTRB(
              AppSpacing.lg, AppSpacing.xs, AppSpacing.lg, navClear),
          children: children,
        );
      },
    );
  }

  List<Widget> _content(BuildContext context) {
    switch (_mode()) {
      case _SheetMode.route:
        return _routeContent(context);
      case _SheetMode.building:
        return _buildingContent(context);
      case _SheetMode.idle:
        return _idleContent(context);
    }
  }

  // --- Route + navigation ------------------------------------------------
  List<Widget> _routeContent(BuildContext context) {
    final route = ref.watch(activeRouteProvider);
    final distance = ref.watch(activeRouteDistanceProvider);
    final session = ref.watch(navigationSessionProvider);
    final walkingSpeed = ref.watch(walkingSpeedProvider);
    final buildings =
        ref.watch(buildingsProvider).valueOrNull ?? const <Building>[];
    final bridges =
        ref.watch(bridgesProvider).valueOrNull ?? const <Bridge>[];
    if (route == null || route.length < 2) return const [];

    final buildingMap = {for (final b in buildings) b.id: b};
    final fromName = buildingMap[route.first]?.name ?? route.first;
    final toName = buildingMap[route.last]?.name ?? route.last;
    final timeMin =
        AppConstants.estimateWalkTimeMinutes(distance, speedKmh: walkingSpeed);

    return [
      _routeSummary(context, fromName, toName, distance, timeMin,
          route.length - 1),
      if (session.isActive) ...[
        const SizedBox(height: AppSpacing.md),
        _navStatus(context, session, buildingMap),
      ],
      if (session.status == NavigationStatus.headingToEntry &&
          widget.guidanceEntryPoint != null) ...[
        const SizedBox(height: AppSpacing.sm),
        _nearestEntryRow(context),
      ],
      const SizedBox(height: AppSpacing.xl),
      StepList(path: route, buildings: buildings, bridges: bridges),
    ];
  }

  Widget _routeSummary(BuildContext context, String from, String to,
      double distance, double timeMin, int bridges) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(AppSpacing.sm),
          decoration: BoxDecoration(
            gradient: AppPalette.brandGradient,
            borderRadius: AppRadii.rChip,
          ),
          child: const Icon(Icons.navigation_rounded,
              color: Colors.white, size: 20),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$from → $to',
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                '${distance.toInt()} m · ~${timeMin.ceil()} min · '
                '$bridges bridge${bridges == 1 ? '' : 's'}',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        IconButton.filledTonal(
          onPressed: () {
            HapticFeedback.lightImpact();
            widget.onStopNavigation();
          },
          tooltip: 'Stop',
          icon: const Icon(Icons.close_rounded, size: 18),
        ),
      ],
    );
  }

  Widget _navStatus(BuildContext context, NavigationSession session,
      Map<String, Building> buildingMap) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final total = session.totalDistanceM <= 0 ? 1.0 : session.totalDistanceM;
    final progress =
        (1 - (session.remainingDistanceM / total)).clamp(0.0, 1.0);
    final nextName = session.nextNodeId == null
        ? null
        : buildingMap[session.nextNodeId!]?.name ?? session.nextNodeId;
    final destinationName = session.destinationId == null
        ? null
        : buildingMap[session.destinationId!]?.name ?? session.destinationId;

    final statusText = switch (session.status) {
      NavigationStatus.headingToEntry => 'Heading to nearest entry',
      NavigationStatus.rerouting => 'Re-routing on +15 network',
      NavigationStatus.arrived => 'Arrived at destination',
      NavigationStatus.onCourse => 'On course',
      NavigationStatus.inactive => 'Navigation inactive',
    };
    final accent = session.status == NavigationStatus.arrived
        ? AppPalette.origin
        : AppPalette.brand;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: (isDark ? Colors.white : AppPalette.brand)
            .withValues(alpha: isDark ? 0.04 : 0.05),
        borderRadius: AppRadii.rChip,
        border: Border.all(color: accent.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(shape: BoxShape.circle, color: accent),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(statusText,
                    style: theme.textTheme.labelLarge
                        ?.copyWith(fontWeight: FontWeight.w700)),
              ),
              Text('${(session.confidence * 100).round()}% conf',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          LinearProgressIndicator(
            value: progress,
            minHeight: 7,
            borderRadius: BorderRadius.circular(8),
            backgroundColor: isDark
                ? Colors.white.withValues(alpha: 0.12)
                : Colors.black.withValues(alpha: 0.06),
            valueColor: AlwaysStoppedAnimation(accent),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            nextName == null
                ? (destinationName ?? 'Destination')
                : 'Next: $nextName',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Widget _nearestEntryRow(BuildContext context) {
    final theme = Theme.of(context);
    final entry = widget.guidanceEntryPoint!;
    final distanceM = (widget.guidanceEntryDistanceM ?? 0).round();
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md, vertical: AppSpacing.sm + 2),
      decoration: BoxDecoration(
        color: AppPalette.origin.withValues(alpha: 0.10),
        borderRadius: AppRadii.rChip,
        border: Border.all(color: AppPalette.origin.withValues(alpha: 0.18)),
      ),
      child: Row(
        children: [
          const Icon(Icons.login_rounded, color: AppPalette.origin, size: 18),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              'Nearest entry: ${entry.name} ($distanceM m)',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  // --- Building detail ---------------------------------------------------
  List<Widget> _buildingContent(BuildContext context) {
    final building = ref.watch(selectedBuildingProvider);
    final shops = ref.watch(shopsProvider).valueOrNull ?? const <Shop>[];
    if (building == null) return const [];

    return [
      BuildingTooltip(
        embedded: true,
        building: building,
        shops: shops,
        onNavigateHere: () {
          ref.read(routeToProvider.notifier).state = building;
          ref.read(selectedBuildingProvider.notifier).state = null;
          context.go('/route');
        },
        onClose: () =>
            ref.read(selectedBuildingProvider.notifier).state = null,
      ),
    ];
  }

  // --- Idle --------------------------------------------------------------
  List<Widget> _idleContent(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final routines =
        ref.watch(savedRoutesProvider).where((r) => r.isRoutine).toList();
    final buildings =
        ref.watch(buildingsProvider).valueOrNull ?? const <Building>[];
    final buildingMap = {for (final b in buildings) b.id: b};
    final shops = ref.watch(shopsProvider).valueOrNull ?? const <Shop>[];
    // "Featured" = verified businesses (those with a website on file), capped
    // at 5 and clearly tagged — never injected into search ranking.
    final featured =
        shops.where((s) => s.website.trim().isNotEmpty).take(5).toList();

    return [
      _searchPrompt(context),
      const SizedBox(height: AppSpacing.xl),
      const SectionHeader('Quick destinations'),
      const SizedBox(height: AppSpacing.md),
      _quickDestinations(context),
      if (featured.isNotEmpty) ...[
        const SizedBox(height: AppSpacing.xl),
        const SectionHeader('Featured on the +15'),
        const SizedBox(height: AppSpacing.md),
        _featuredRow(context, featured, buildingMap),
      ],
      const SizedBox(height: AppSpacing.xl),
      const SectionHeader('Browse by category'),
      const SizedBox(height: AppSpacing.md),
      _categoryGrid(context),
      if (routines.isNotEmpty) ...[
        const SizedBox(height: AppSpacing.xl),
        const SectionHeader('Quick routes'),
        const SizedBox(height: AppSpacing.md),
        ...routines.take(4).map((r) {
          final toName = buildingMap[r.toId]?.name ?? r.name;
          final fromName = buildingMap[r.fromId]?.name ?? r.fromId;
          return Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Material(
              color: isDark ? AppPalette.cardDark : AppPalette.surfaceLight,
              borderRadius: AppRadii.rChip,
              child: InkWell(
                borderRadius: AppRadii.rChip,
                onTap: () {
                  HapticFeedback.mediumImpact();
                  widget.onStartQuickRoute(r.fromId, r.toId, r.routeType);
                },
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Row(
                    children: [
                      const Icon(Icons.bolt_rounded,
                          size: 18, color: AppPalette.warning),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(r.name,
                                style: theme.textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w700),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis),
                            Text('$fromName → $toName',
                                style: theme.textTheme.bodySmall,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis),
                          ],
                        ),
                      ),
                      Icon(Icons.chevron_right_rounded,
                          color: theme.textTheme.bodySmall?.color),
                    ],
                  ),
                ),
              ),
            ),
          );
        }),
      ],
      const SizedBox(height: AppSpacing.lg),
      Center(
        child: Text(
          'Tap a building for details, or plan a route from the Navigate tab.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall,
        ),
      ),
    ];
  }

  /// The downtown intents people actually have: a warm lunch, a washroom, the
  /// CTrain, or shops. Each jumps into Search pre-filtered to that category.
  Widget _quickDestinations(BuildContext context) {
    return Wrap(
      runSpacing: AppSpacing.sm,
      children: [
        AppPill(
            label: 'Food',
            selected: false,
            icon: Icons.restaurant_rounded,
            onTap: () => _goCategory('food')),
        AppPill(
            label: 'Washrooms',
            selected: false,
            icon: Icons.wc_rounded,
            onTap: () => _goCategory('washroom')),
        AppPill(
            label: 'Transit',
            selected: false,
            icon: Icons.train_rounded,
            onTap: () => _goCategory('transit')),
        AppPill(
            label: 'Shops',
            selected: false,
            icon: Icons.shopping_bag_rounded,
            onTap: () => _goCategory('retail')),
      ],
    );
  }

  Widget _categoryGrid(BuildContext context) {
    return Wrap(
      runSpacing: AppSpacing.sm,
      children: [
        for (final c in ShopCategory.values)
          AppPill(
            label: c.label,
            selected: false,
            icon: _catIcon(c),
            onTap: () => _goCategory(c.name),
          ),
      ],
    );
  }

  void _goCategory(String name) {
    HapticFeedback.selectionClick();
    ref.read(searchQueryProvider.notifier).state = '';
    ref.read(selectedCategoryProvider.notifier).state = name;
    context.go('/search');
  }

  Widget _featuredRow(BuildContext context, List<Shop> featured,
      Map<String, Building> buildingMap) {
    return SizedBox(
      height: 116,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.zero,
        itemCount: featured.length,
        itemBuilder: (_, i) {
          final shop = featured[i];
          final bName = buildingMap[shop.buildingId]?.name ?? 'Plus 15';
          return _featuredCard(context, shop, bName);
        },
      ),
    );
  }

  Widget _featuredCard(BuildContext context, Shop shop, String buildingName) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final color = AppPalette.categoryColor(shop.category.name);

    return GestureDetector(
      onTap: () => _showShopDetail(context, shop, buildingName),
      child: Container(
        width: 196,
        margin: const EdgeInsets.only(right: AppSpacing.sm),
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: isDark ? AppPalette.cardDark : Colors.white,
          borderRadius: AppRadii.rCard,
          border: Border.all(
              color: isDark ? AppPalette.borderDark : AppPalette.borderLight),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: AppRadii.rChip,
                  ),
                  child: Icon(_catIcon(shop.category), color: color, size: 18),
                ),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    gradient: AppPalette.brandGradient,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text('Featured',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.3)),
                ),
              ],
            ),
            const Spacer(),
            Text(shop.name,
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
            Text(buildingName,
                style: theme.textTheme.bodySmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }

  void _showShopDetail(BuildContext context, Shop shop, String buildingName) {
    HapticFeedback.lightImpact();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => ShopDetailSheet(shop: shop, buildingName: buildingName),
    );
  }

  IconData _catIcon(ShopCategory cat) {
    switch (cat) {
      case ShopCategory.food:
        return Icons.restaurant_rounded;
      case ShopCategory.retail:
        return Icons.shopping_bag_rounded;
      case ShopCategory.services:
        return Icons.business_center_rounded;
      case ShopCategory.transit:
        return Icons.train_rounded;
      case ShopCategory.washroom:
        return Icons.wc_rounded;
      case ShopCategory.hotel:
        return Icons.hotel_rounded;
      case ShopCategory.health:
        return Icons.local_hospital_rounded;
      case ShopCategory.entertainment:
        return Icons.theaters_rounded;
    }
  }

  Widget _searchPrompt(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Material(
      color: isDark ? AppPalette.cardDark : AppPalette.surfaceLight,
      borderRadius: AppRadii.rControl,
      child: InkWell(
        borderRadius: AppRadii.rControl,
        onTap: () {
          HapticFeedback.lightImpact();
          context.go('/search');
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md, vertical: AppSpacing.md + 2),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(
                  gradient: AppPalette.brandGradient,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.search_rounded,
                    color: Colors.white, size: 18),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Search the +15 network',
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w700)),
                    Text('Shops, food, services and buildings',
                        style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
