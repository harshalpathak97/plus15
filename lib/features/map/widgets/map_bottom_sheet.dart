import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../routing/network.dart';
import '../../../data/models/shop.dart';
import '../../../shared/providers/providers.dart';
import '../../../shared/widgets/app_pill.dart';
import '../../../shared/widgets/section_header.dart';
import '../../../shared/widgets/sheet_surface.dart';
import '../../../routing/conditions.dart';
import '../../../routing/router.dart';
import '../../route_planner/widgets/step_list.dart';
import '../../shop_detail/shop_detail_sheet.dart';
import '../../ai/widgets/ai_concierge_sheet.dart';
import '../../ai/services/ai_service.dart' show aiConfigured;
import '../../transit/street_directions.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/brand_logo.dart';
import 'building_tooltip.dart';

/// The single draggable sheet that anchors the bottom of the map.
///
/// It is always present and swaps its content based on app state:
///   • a route/navigation in progress → summary + live status + steps
///   • a building selected            → place detail
///   • otherwise (idle)               → search prompt + quick routes
///
/// It is a passive renderer: navigation logic stays on the map screen and is
/// invoked through [onStopNavigation] / [onStartQuickRoute].
class MapBottomSheet extends ConsumerStatefulWidget {
  final VoidCallback onStopNavigation;
  final void Function(String fromId, String toId, String mode)
      onStartQuickRoute;

  const MapBottomSheet({
    super.key,
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
    if (ref.read(activeRouteProvider) != null) return _SheetMode.route;
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
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg, AppSpacing.xs, AppSpacing.lg, AppSpacing.xxl),
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
    final session = ref.watch(navigationSessionProvider);
    final walkingSpeed = ref.watch(walkingSpeedProvider);
    final buildings =
        ref.watch(buildingsProvider).valueOrNull ?? const <NetBuilding>[];
    if (route == null) return const [];

    final buildingMap = {for (final b in buildings) b.id: b};
    final fromName = route.originBuildingId == null
        ? 'My location'
        : buildingMap[route.originBuildingId]?.name ?? route.originBuildingId!;
    final toName =
        buildingMap[route.destinationBuildingId]?.name ?? route.destinationBuildingId;
    final distance = route.lengthM;
    final timeMin =
        AppConstants.estimateWalkTimeMinutes(distance, speedKmh: walkingSpeed);

    return [
      _routeSummary(context, fromName, toName, distance, timeMin,
          route.bridgeCount),
      if (route.previewOnly && !session.isActive) ...[
        const SizedBox(height: AppSpacing.md),
        PreviewBanner(route: route),
      ],
      if (session.isActive) ...[
        const SizedBox(height: AppSpacing.md),
        _navStatus(context, session, route),
      ],
      if (!session.isActive || session.stepIndex == 0) ...[
        const SizedBox(height: AppSpacing.md),
        WalkToEntranceCard(route: route),
      ],
      const SizedBox(height: AppSpacing.md),
      RouteNotices(route: route),
      const SizedBox(height: AppSpacing.xl),
      StepList(
          route: route,
          currentStep: session.isActive ? session.stepIndex : null,
          showDebug: ref.watch(debugGraphProvider)),
      if (ref.watch(debugGraphProvider)) RouteExplanation(route: route),
    ];
  }

  Widget _routeSummary(BuildContext context, String from, String to,
      double distance, double timeMin, int bridges) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer,
            borderRadius: AppRadii.rChip,
          ),
          child: Icon(Icons.directions_walk_rounded,
              color: theme.colorScheme.onPrimaryContainer),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                to,
                style: theme.textTheme.titleMedium,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                '${timeMin.ceil()} min · ${distance.round()} m · from $from',
                style: theme.textTheme.bodySmall
                    ?.copyWith(fontFeatures: AppTheme.tabular),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
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
          tooltip: 'Close route',
          icon: const Icon(Icons.close_rounded),
        ),
      ],
    );
  }

  Widget _navStatus(BuildContext context, NavigationSession session, PlannedRoute route) {
    final theme = Theme.of(context);
    final total = session.totalDistanceM <= 0 ? 1.0 : session.totalDistanceM;
    final progress =
        (1 - (session.remainingDistanceM / total)).clamp(0.0, 1.0);
    final step = route.steps[session.stepIndex.clamp(0, route.steps.length - 1)];

    final statusText = switch (session.status) {
      NavigationStatus.rerouting =>
        'Off the route by ~${session.offRouteM.round()} m — re-routing',
      NavigationStatus.arrived => 'Arrived at destination',
      NavigationStatus.onCourse => '${session.remainingDistanceM.round()} m to go',
      NavigationStatus.inactive => 'Navigation inactive',
    };
    final accent = session.status == NavigationStatus.arrived
        ? AppPalette.origin
        : session.status == NavigationStatus.rerouting
            ? AppPalette.warning
            : AppPalette.brand;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: AppRadii.rCard,
        border: Border.all(color: accent.withValues(alpha: 0.3)),
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
                    style: theme.textTheme.labelLarge),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          LinearProgressIndicator(
            value: progress,
            minHeight: 7,
            borderRadius: BorderRadius.circular(8),
            backgroundColor: theme.colorScheme.surfaceContainerHigh,
            valueColor: AlwaysStoppedAnimation(accent),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            step.text,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: 4),
          Text(
            'GPS is approximate indoors. Follow the +15 signs named in each step.',
            style: theme.textTheme.bodySmall,
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
        building: building,
        shops: shops,
        networkStatus: ref.watch(conditionsProvider).valueOrNull?.networkStatusAt(calgaryNow()),
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
    final routines =
        ref.watch(savedRoutesProvider).where((r) => r.isRoutine).toList();
    final buildings =
        ref.watch(buildingsProvider).valueOrNull ?? const <NetBuilding>[];
    final buildingMap = {for (final b in buildings) b.id: b};
    final shops = ref.watch(shopsProvider).valueOrNull ?? const <Shop>[];

    return [
      Text('Explore the +15', style: theme.textTheme.titleLarge),
      const SizedBox(height: 2),
      Text('Calgary’s 16 km of heated skywalks, shops and food.',
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
      const SizedBox(height: AppSpacing.lg),
      _quickDestinations(context),
      const SizedBox(height: AppSpacing.xl),
      const SectionHeader('Popular on the +15'),
      const SizedBox(height: AppSpacing.md),
      _popularBrands(context, shops),
      const SizedBox(height: AppSpacing.xl),
      if (aiConfigured) _askAiCard(context),
      if (routines.isNotEmpty) ...[
        const SizedBox(height: AppSpacing.xl),
        const SectionHeader('Quick routes'),
        const SizedBox(height: AppSpacing.sm),
        ...routines.take(4).map((r) {
          final toName = buildingMap[r.toId]?.name ?? r.name;
          final fromName = buildingMap[r.fromId]?.name ?? r.fromId;
          return ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.bolt_rounded, color: theme.colorScheme.primary),
            title: Text(r.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text('$fromName → $toName', maxLines: 1, overflow: TextOverflow.ellipsis),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () {
              HapticFeedback.mediumImpact();
              widget.onStartQuickRoute(r.fromId, r.toId, r.routeType);
            },
          );
        }),
      ],
    ];
  }

  /// The downtown intents people actually have. Each opens Search filtered.
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
            label: 'Coffee',
            selected: false,
            icon: Icons.local_cafe_rounded,
            onTap: () => _goQuery('coffee')),
        AppPill(
            label: 'Washrooms',
            selected: false,
            icon: Icons.wc_rounded,
            onTap: () => _goCategory('washroom')),
        AppPill(
            label: 'Pharmacy & health',
            selected: false,
            icon: Icons.local_pharmacy_rounded,
            onTap: () => _goCategory('health')),
        AppPill(
            label: 'Banks & services',
            selected: false,
            icon: Icons.account_balance_rounded,
            onTap: () => _goCategory('services')),
        AppPill(
            label: 'Hotels',
            selected: false,
            icon: Icons.hotel_rounded,
            onTap: () => _goCategory('hotel')),
      ],
    );
  }

  void _goCategory(String name) {
    HapticFeedback.selectionClick();
    ref.read(searchQueryProvider.notifier).state = '';
    ref.read(selectedCategoryProvider.notifier).state = name;
    context.go('/search');
  }

  void _goQuery(String q) {
    HapticFeedback.selectionClick();
    ref.read(selectedCategoryProvider.notifier).state = null;
    ref.read(searchQueryProvider.notifier).state = q;
    context.go('/search');
  }

  /// Brands with the most +15 locations, each opening Search for that brand.
  Widget _popularBrands(BuildContext context, List<Shop> shops) {
    final theme = Theme.of(context);
    final byLogo = <String, List<Shop>>{};
    for (final s in shops) {
      if (s.logo != null && s.category != ShopCategory.washroom) {
        byLogo.putIfAbsent(s.logo!, () => []).add(s);
      }
    }
    final brands = byLogo.values.toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    return SizedBox(
      // Logo and padding are fixed; the two text lines grow with text size.
      height: 80 + MediaQuery.textScalerOf(context).scale(32),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: brands.length.clamp(0, 10),
        separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.sm),
        itemBuilder: (context, i) {
          final group = brands[i];
          final shop = group.first;
          final name = shop.name.split(' - ').first;
          return SizedBox(
            width: 96,
            child: Material(
              color: theme.colorScheme.surface,
              shape: RoundedRectangleBorder(
                borderRadius: AppRadii.rCard,
                side: BorderSide(color: theme.colorScheme.outlineVariant),
              ),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => group.length == 1 ? showShopDetail(context, shop) : _goQuery(name),
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  child: Column(
                    children: [
                      BrandLogo(shop: shop, size: 48),
                      const SizedBox(height: 6),
                      Text(name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelMedium),
                      Text(group.length == 1 ? '1 location' : '${group.length} locations',
                          maxLines: 1,
                          style: theme.textTheme.labelSmall),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _askAiCard(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Material(
      color: scheme.primaryContainer,
      borderRadius: AppRadii.rCard,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => showAiConcierge(context),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Row(
            children: [
              Icon(Icons.auto_awesome_rounded, color: scheme.onPrimaryContainer),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Ask +15',
                        style: theme.textTheme.titleMedium
                            ?.copyWith(color: scheme.onPrimaryContainer)),
                    Text('“Where’s coffee near Bankers Hall?”',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: scheme.onPrimaryContainer)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: scheme.onPrimaryContainer),
            ],
          ),
        ),
      ),
    );
  }
}
