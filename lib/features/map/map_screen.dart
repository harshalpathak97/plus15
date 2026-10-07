import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_palette.dart';
import '../../core/theme/app_spacing.dart';
import '../../routing/network.dart';
import '../../routing/router.dart';
import '../../data/models/saved_route.dart';
import '../../shared/providers/providers.dart';
import 'services/course_tracker.dart';
import 'widgets/map_bottom_sheet.dart';
import 'basemap.dart';
import '../../shared/widgets/location_prompt.dart';
import 'widgets/network_layers.dart';
import '../ai/widgets/ai_concierge_sheet.dart';
import '../ai/services/ai_service.dart' show aiConfigured;
import '../../routing/conditions.dart';

class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> with TickerProviderStateMixin {
  final MapController _mapController = MapController();

  static const _calgaryCenter = LatLng(51.0478, -114.0670);
  static const _plus15Center = LatLng(51.0478, -114.0670);
  static final _calgaryBounds = LatLngBounds(
    const LatLng(50.88, -114.30),
    const LatLng(51.20, -113.85),
  );
  static const _defaultZoom = 15.5;

  double _currentZoom = _defaultZoom;
  bool _mapReady = false;
  int _offRouteStrikes = 0;
  int _arrivalHits = 0;
  DateTime? _lastRerouteAt;
  LatLng? _smoothedUserLocation;
  LatLng? _lastRawLocation;
  double? _headingRadians;
  CourseTracker? _tracker;

  PlannedRoute? _presentedRoute;

  /// Draws a new route on along its length (and eases the camera to it).
  late final AnimationController _routeReveal = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
    value: 1,
  );

  /// The map sheet's current size, so the controls ride just above it.
  final _sheetExtent = ValueNotifier<double>(AppDims.sheetIdle);

  /// The camera move in flight; a new move replaces it.
  AnimationController? _move;

  /// Rebuilds once a minute so "Open until 9 p.m." and closures stay current.
  late final Timer _clock = Timer.periodic(const Duration(minutes: 1), (_) {
    if (mounted) setState(() {});
  });

  @override
  void initState() {
    super.initState();
    _clock;
  }

  @override
  void dispose() {
    _clock.cancel();
    _move?.dispose();
    _sheetExtent.dispose();
    _routeReveal.dispose();
    super.dispose();
  }

  void _presentRoute(PlannedRoute route) {
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final g = route.geometry;
    if (_mapReady && g.length >= 2) {
      final size = MediaQuery.of(context).size;
      final fit = CameraFit.bounds(
        bounds: LatLngBounds.fromPoints([for (final p in g) LatLng(p[0], p[1])]),
        padding: EdgeInsets.fromLTRB(48, 170, 72, size.height * AppDims.sheetMid + 24),
        maxZoom: 17.5,
      ).fit(_mapController.camera);
      _animatedMove(fit.center, fit.zoom);
    }
    if (reduceMotion) {
      _routeReveal.value = 1;
    } else {
      _routeReveal.forward(from: 0);
    }
  }

  static const _importantTypes = {'hotel', 'retail', 'landmark', 'convention', 'entertainment'};
  static const _importantAmenities = {'transit'};
  static const Distance _distance = Distance();

  bool _isBuildingImportant(NetBuilding b) {
    if (_importantTypes.contains(b.type)) return true;
    if (b.amenities.any((a) => _importantAmenities.contains(a))) return true;
    return false;
  }

  List<NetBuilding> _visibleBuildings(List<NetBuilding> buildings) {
    if (_currentZoom >= 16.0) return buildings;
    if (_currentZoom >= 15.0) {
      return buildings.where((b) => _isBuildingImportant(b)).toList();
    }
    if (_currentZoom >= 13.5) {
      return buildings
          .where((b) =>
              b.type == 'hotel' ||
              b.type == 'landmark' ||
              b.type == 'retail' ||
              b.amenities.contains('transit'))
          .toList();
    }
    return [];
  }

  void _animatedMove(LatLng dest, double zoom) {
    if (!_mapReady) return;
    final cam = _mapController.camera;
    final latTween = Tween<double>(begin: cam.center.latitude, end: dest.latitude);
    final lngTween = Tween<double>(begin: cam.center.longitude, end: dest.longitude);
    final zoomTween = Tween<double>(begin: cam.zoom, end: zoom);

    _move?.dispose();
    final controller = _move = AnimationController(
      duration: const Duration(milliseconds: 650),
      vsync: this,
    );
    final curve = CurvedAnimation(parent: controller, curve: Curves.easeInOutCubic);

    controller.addListener(() {
      _mapController.move(
        LatLng(latTween.evaluate(curve), lngTween.evaluate(curve)),
        zoomTween.evaluate(curve),
      );
    });

    controller.forward();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<LatLng?>>(locationStreamProvider, (previous, next) {
      next.whenData((pos) {
        if (pos != null) {
          _handleLocationUpdate(pos);
        }
      });
    });

    // Frame and draw each new route once, including one set before this
    // screen mounted (e.g. "Preview on map" from the planner).
    final pending = ref.watch(activeRouteProvider);
    if (pending != null && !identical(pending, _presentedRoute) && _mapReady) {
      _presentedRoute = pending;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _presentRoute(pending);
      });
    }

    // Celebrate arrival exactly once on the transition into the arrived state.
    ref.listen(navigationSessionProvider.select((s) => s.status), (prev, next) {
      if (next == NavigationStatus.arrived && prev != NavigationStatus.arrived) {
        HapticFeedback.heavyImpact();
      }
    });

    final networkAsync = ref.watch(networkProvider);
    final conditions = ref.watch(conditionsProvider).valueOrNull;
    final selectedBuilding = ref.watch(selectedBuildingProvider);
    final activeRoute = ref.watch(activeRouteProvider);
    final session = ref.watch(navigationSessionProvider);
    final debugGraph = ref.watch(debugGraphProvider);
    final basemap = ref.watch(basemapProvider);
    // Overlay styling follows the base map's surface, not just the theme
    // (e.g. light streets/terrain tiles in dark mode, dark satellite imagery).
    final darkSurface = basemap.darkSurface(Theme.of(context).brightness == Brightness.dark);
    final arrived = session.status == NavigationStatus.arrived;
    final userLocation = ref.watch(locationStreamProvider);
    final displayUserLocation = _smoothedUserLocation ?? userLocation.valueOrNull;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: networkAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text("Couldn't load the +15 map."),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => ref.invalidate(networkProvider),
              child: const Text('Try again'),
            ),
          ]),
        ),
        data: (network) {
          final buildings = network.buildings;
          final buildingMap = network.buildingById;
          final visibleBuildings = _visibleBuildings(buildings);
          final now = calgaryNow();
          final closedEdges = conditions?.closedEdgesAt(now) ?? const {};
          final closedBridges = {
            for (final id in closedEdges.keys)
              if (network.edgeById[id]?.bridgeNumber != null) network.edgeById[id]!.bridgeNumber!
          };
          final closuresCount = conditions?.activeAt(now).length ?? 0;
          final nearestName = _nearestBuildingName(buildings, displayUserLocation);
          final routeBuildings = activeRoute == null
              ? const <String>{}
              : {
                  for (final h in activeRoute.hops)
                    for (final n in [h.fromNode, h.toNode])
                      for (final b in network.buildingsAtNode[n] ?? const <NetBuilding>[]) b.id,
                  activeRoute.destinationBuildingId,
                  if (activeRoute.originBuildingId != null) activeRoute.originBuildingId!,
                };

          return LayoutBuilder(builder: (context, box) {
            // Controls and attribution ride just above the sheet, and step
            // aside when the sheet leaves too little room for them.
            Widget aboveSheet(Widget child, {double? left, double? right, double needs = 0}) =>
                ValueListenableBuilder<double>(
                  valueListenable: _sheetExtent,
                  builder: (context, extent, child) {
                    final bottom = box.maxHeight * extent + 12;
                    final show = box.maxHeight - bottom - 140 > needs;
                    return Positioned(
                      left: left,
                      right: right,
                      bottom: bottom,
                      child: IgnorePointer(
                        ignoring: !show,
                        child: AnimatedOpacity(
                            opacity: show ? 1 : 0, duration: AppMotion.fast, child: child),
                      ),
                    );
                  },
                  child: child,
                );
            return Stack(
              children: [
                // Map labels live in fixed-size markers; cap their growth so
                // large system text doesn't clip them (the rest of the UI scales).
                MediaQuery.withClampedTextScaling(
                  maxScaleFactor: 1.15,
                  child: FlutterMap(
                    mapController: _mapController,
                    options: MapOptions(
                      initialCenter: _calgaryCenter,
                      initialZoom: _defaultZoom,
                      minZoom: 10,
                      maxZoom: 19,
                      cameraConstraint: CameraConstraint.contain(bounds: _calgaryBounds),
                      onMapReady: () {
                        _mapReady = true;
                        // A route set before the map existed gets framed now.
                        final r = ref.read(activeRouteProvider);
                        if (r != null) {
                          _presentedRoute = r;
                          _presentRoute(r);
                          return;
                        }
                        final loc = displayUserLocation;
                        if (loc != null && _isInCalgaryBounds(loc.latitude, loc.longitude)) {
                          _animatedMove(loc, 16.0);
                        }
                      },
                      onPositionChanged: (pos, _) {
                        if (pos.zoom != _currentZoom) {
                          setState(() => _currentZoom = pos.zoom);
                        }
                      },
                      onTap: (_, __) {
                        ref.read(selectedBuildingProvider.notifier).state = null;
                      },
                      interactionOptions: const InteractionOptions(
                        flags: InteractiveFlag.all,
                      ),
                    ),
                    children: [
                      TileLayer(
                        // Keyless Esri basemaps (CARTO now watermarks "API KEY
                        // REQUIRED"); style chosen with the layers control.
                        key: ValueKey('${basemap.name}-$isDark'),
                        urlTemplate: basemap.url(isDark),
                        userAgentPackageName: 'com.plus15.plus15_navigator',
                        maxNativeZoom: basemap.maxNativeZoom,
                        maxZoom: 20,
                        // No fade: a layer rebuilt while the map is hidden (theme switched in
                        // Settings) never ran its fade and stayed blank until a pan.
                        tileDisplay: const TileDisplay.instantaneous(),
                        fallbackUrl: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      ),
                      // Display layer: the City's +15 walkway footprints.
                      ...networkLayers(network,
                          closedBridges: closedBridges, zoom: _currentZoom, isDark: darkSurface),
                      if (debugGraph)
                        GraphDebugLayer(
                            network: network, closedEdges: closedEdges, zoom: _currentZoom),
                      // The route exactly as routed (graph edge geometry).
                      if (activeRoute != null)
                        AnimatedBuilder(
                          animation: _routeReveal,
                          builder: (context, _) => Stack(
                            children: routeLayers(activeRoute,
                                isDark: darkSurface,
                                reveal: Curves.easeInOutCubic.transform(_routeReveal.value)),
                          ),
                        ),
                      // Building markers step aside while a route is shown so the
                      // route reads first; the sheet names both ends.
                      if (_currentZoom >= 13.5 && !debugGraph && activeRoute == null)
                        MarkerLayer(
                          markers: _buildMarkers(
                              visibleBuildings, selectedBuilding, routeBuildings, isDark),
                        ),
                      if (activeRoute == null && _currentZoom >= 17 && !debugGraph)
                        MarkerLayer(markers: doorMarkers(network, isDark: darkSurface)),
                      if (activeRoute != null && activeRoute.hops.isNotEmpty)
                        MarkerLayer(
                          markers: [
                            ..._buildRouteEndpoints(activeRoute, arrived),
                            ...routeDoorMarkers(activeRoute, network),
                          ],
                        ),
                      if (displayUserLocation != null)
                        MarkerLayer(
                          markers: [_buildUserLocationMarker(displayUserLocation)],
                        ),
                    ],
                  ),
                ),
                Positioned(
                  top: MediaQuery.of(context).padding.top + 12,
                  left: 16,
                  right: 16,
                  // Floating chrome over the map caps text growth so the map
                  // stays usable; the sheet and other screens scale fully.
                  child: MediaQuery.withClampedTextScaling(
                    maxScaleFactor: 1.3,
                    child: _buildHeader(
                        context,
                        closuresCount,
                        nearestName,
                        conditions?.networkStatusAt(now),
                        userLocation.hasValue && userLocation.value == null),
                  ),
                ),
                aboveSheet(_buildMapControls(context, userLocation), right: 16, needs: 300),
                // Tile attribution (required by the providers).
                aboveSheet(
                  left: 16,
                  right: 80,
                  IgnorePointer(
                    child: Align(
                      alignment: Alignment.bottomLeft,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: (darkSurface ? Colors.black : Colors.white).withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          child: Text(
                            basemap.attribution,
                            maxLines: 3,
                            textScaler: MediaQuery.textScalerOf(context)
                                .clamp(maxScaleFactor: 1.3),
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                fontSize: 10, color: darkSurface ? Colors.white70 : Colors.black87),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                NotificationListener<DraggableScrollableNotification>(
                  onNotification: (n) {
                    _sheetExtent.value = n.extent;
                    return false;
                  },
                  child: MapBottomSheet(
                    onStopNavigation: _stopNavigation,
                    onStartQuickRoute: _startQuickRoute,
                  ),
                ),
                if (arrived) _buildArrivalCard(context, session, buildingMap, isDark),
              ],
            );
          });
        },
      ),
    );
  }

  bool _isInCalgaryBounds(double lat, double lng) {
    return lat > 50.9 && lat < 51.2 && lng > -114.3 && lng < -113.9;
  }

  Marker _buildUserLocationMarker(LatLng pos) {
    return Marker(
      point: pos,
      width: 40,
      height: 40,
      child: _PulsingLocationDot(headingRadians: _headingRadians),
    );
  }

  Future<void> _handleLocationUpdate(LatLng rawPosition) async {
    const distance = Distance();
    if (_lastRawLocation != null) {
      final moved = distance(_lastRawLocation!, rawPosition);
      if (moved >= 2) {
        _headingRadians = _bearingRadians(_lastRawLocation!, rawPosition);
      }
    }
    _lastRawLocation = rawPosition;

    final prev = _smoothedUserLocation;
    if (prev == null) {
      _smoothedUserLocation = rawPosition;
    } else {
      _smoothedUserLocation = LatLng(
        (prev.latitude * 0.78) + (rawPosition.latitude * 0.22),
        (prev.longitude * 0.78) + (rawPosition.longitude * 0.22),
      );
    }

    if (mounted) setState(() {});

    final session = ref.read(navigationSessionProvider);
    if (_mapReady && session.isActive && _smoothedUserLocation != null) {
      final centerDistance = distance(_mapController.camera.center, _smoothedUserLocation!);
      if (centerDistance > 180) {
        _animatedMove(
          _smoothedUserLocation!,
          _mapController.camera.zoom.clamp(15.2, 17.0),
        );
      }
    }

    await _updateNavigationFromLocation(rawPosition);
  }

  Future<void> _updateNavigationFromLocation(LatLng user) async {
    final session = ref.read(navigationSessionProvider);
    final route = ref.read(activeRouteProvider);
    if (!session.isActive || session.destinationId == null || route == null) {
      return;
    }
    // Arrival sticks until the user closes the route.
    if (session.status == NavigationStatus.arrived) return;
    if (_tracker?.route != route) {
      _tracker = CourseTracker(route);
      _arrivalHits = 0;
    }
    final progress = _tracker!.progressAt(user);

    // Indoor GPS downtown is often 20–40 m off; only treat clearly distant
    // fixes as off-route.
    if (progress.offRouteM <= 35) {
      _offRouteStrikes = 0;
      // Two fixes in a row near the end, so one stray fix can't "arrive".
      _arrivalHits = progress.remainingM <= 20 ? _arrivalHits + 1 : 0;
      final arrived = _arrivalHits >= 2;
      ref.read(navigationSessionProvider.notifier).update(
            session.copyWith(
              status: arrived ? NavigationStatus.arrived : NavigationStatus.onCourse,
              remainingDistanceM: arrived ? 0 : progress.remainingM,
              stepIndex: arrived ? route.steps.length - 1 : progress.stepIndex,
              offRouteM: progress.offRouteM,
              offRouteStrikes: 0,
            ),
          );
      return;
    }

    _offRouteStrikes += 1;
    ref.read(navigationSessionProvider.notifier).update(
          session.copyWith(
            status: NavigationStatus.rerouting,
            offRouteM: progress.offRouteM,
            offRouteStrikes: _offRouteStrikes,
          ),
        );
    if (_offRouteStrikes < 2) return;
    // A vague fix (common indoors) would reroute you out onto the street.
    if (user is LocationFix && user.accuracyM > 25) return;
    if (_lastRerouteAt != null &&
        DateTime.now().difference(_lastRerouteAt!) < const Duration(seconds: 4)) {
      return;
    }
    _lastRerouteAt = DateTime.now();

    // Re-route from the GPS fix: the router starts inside the +15 polygon you
    // are in, or from the nearest building if you are outside the network.
    final router = await ref.read(routerProvider.future);
    final result = router.route(
      RouteOrigin.location(user.latitude, user.longitude),
      session.destinationId!,
      profile: session.profile,
      at: calgaryNow(),
    );
    final reroute = result.route;
    if (reroute == null || reroute.previewOnly) {
      // Keep the current route; say why instead of "re-routing" forever.
      ref
          .read(navigationSessionProvider.notifier)
          .update(session.copyWith(status: NavigationStatus.onCourse, offRouteStrikes: 0));
      _offRouteStrikes = 0;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(reroute == null
                ? (result.unavailableReason ?? "Can't find a new route from here.")
                : "Can't re-route right now. Head back to the line on the map.")));
      }
      return;
    }
    ref.read(activeRouteProvider.notifier).state = reroute;
    ref.read(navigationSessionProvider.notifier).update(
          session.copyWith(
            status: NavigationStatus.onCourse,
            totalDistanceM: reroute.lengthM,
            remainingDistanceM: reroute.lengthM,
            stepIndex: 0,
            offRouteM: 0,
            offRouteStrikes: 0,
          ),
        );
    _offRouteStrikes = 0;
    if (mounted) setState(() {});
  }

  double _bearingRadians(LatLng from, LatLng to) {
    const degToRad = pi / 180.0;
    final lat1 = from.latitude * degToRad;
    final lat2 = to.latitude * degToRad;
    final dLon = (to.longitude - from.longitude) * degToRad;
    final y = sin(dLon) * cos(lat2);
    final x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon);
    return atan2(y, x);
  }

  /// Start and end markers sit on the route's real first and last points.
  List<Marker> _buildRouteEndpoints(PlannedRoute route, bool arrived) {
    final g = route.geometry;
    final start = LatLng(g.first[0], g.first[1]);
    final end = LatLng(g.last[0], g.last[1]);
    final shadow = BoxShadow(
      color: Colors.black.withValues(alpha: 0.28),
      blurRadius: 6,
      offset: const Offset(0, 2),
    );

    // Start: a quiet ring. End: the destination pin, which lands as the
    // route finishes drawing.
    final startDot = Container(
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        border: Border.all(color: AppPalette.ink, width: 4),
        boxShadow: [shadow],
      ),
    );
    final endColor = arrived ? AppPalette.origin : AppPalette.destination;
    Widget endPin = Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        color: endColor,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: [shadow],
      ),
      child:
          Icon(arrived ? Icons.check_rounded : Icons.flag_rounded, size: 15, color: Colors.white),
    );
    final still = MediaQuery.disableAnimationsOf(context);
    endPin = still
        ? endPin
        : arrived
            ? endPin
                .animate(onPlay: (c) => c.repeat(reverse: true))
                .scaleXY(begin: 1.0, end: 1.08, duration: 900.ms, curve: Curves.easeInOut)
            : endPin
                .animate(key: ValueKey(route))
                .scaleXY(
                    begin: 0.4, end: 1, delay: 850.ms, duration: 380.ms, curve: Curves.easeOutBack)
                .fadeIn(delay: 850.ms, duration: 200.ms);
    return [
      Marker(point: start, width: 22, height: 22, child: startDot),
      Marker(point: end, width: 34, height: 34, child: endPin),
    ];
  }

  List<Marker> _buildMarkers(
      List<NetBuilding> buildings, NetBuilding? selected, Set<String> routeBuildings, bool isDark) {
    final showChips = _currentZoom >= 16.1;
    final declutteredChipIds =
        showChips ? _declutteredChipIds(buildings, selected, routeBuildings) : const <String>{};

    final onRouteBuildings = buildings.where((b) => routeBuildings.contains(b.id)).toList();
    final nonRouteBuildings = buildings.where((b) => !routeBuildings.contains(b.id)).toList();

    final allVisible = [...nonRouteBuildings, ...onRouteBuildings];

    return allVisible.map((b) {
      final isSelected = b.id == selected?.id;
      final isOnRoute = routeBuildings.contains(b.id);

      final shouldShowChip = isSelected || isOnRoute || declutteredChipIds.contains(b.id);

      if (shouldShowChip) {
        return Marker(
          point: LatLng(b.lat, b.lng),
          width: isSelected ? 190 : 150,
          height: 36,
          child: Semantics(
            button: true,
            label: b.name,
            excludeSemantics: true,
            child: GestureDetector(
              onTap: () {
                HapticFeedback.lightImpact();
                ref.read(selectedBuildingProvider.notifier).state = b;
                _animatedMove(LatLng(b.lat, b.lng), _mapController.camera.zoom);
              },
              child: _BuildingChip(
                name: b.name,
                isSelected: isSelected,
                isOnRoute: isOnRoute,
                type: b.type,
                hasFood: b.amenities.contains('food'),
              ),
            ),
          ),
        );
      }

      // A 12 px dot with a 44 px touch area.
      return Marker(
        point: LatLng(b.lat, b.lng),
        width: 44,
        height: 44,
        child: Semantics(
          button: true,
          label: b.name,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              HapticFeedback.lightImpact();
              ref.read(selectedBuildingProvider.notifier).state = b;
              _animatedMove(LatLng(b.lat, b.lng), 16.0);
            },
            child: _BuildingDot(type: b.type, hasFood: b.amenities.contains('food')),
          ),
        ),
      );
    }).toList();
  }

  Set<String> _declutteredChipIds(
      List<NetBuilding> buildings, NetBuilding? selected, Set<String> routeBuildings) {
    if (buildings.isEmpty) return const <String>{};

    final spacingMeters = _chipSpacingMeters();
    final maxChips = _maxChipCount();
    final selectedId = selected?.id;
    final buildingMap = {for (final b in buildings) b.id: b};

    final occupied = <LatLng>[];
    if (selectedId != null) {
      final selectedBuilding = buildingMap[selectedId];
      if (selectedBuilding != null) {
        occupied.add(LatLng(selectedBuilding.lat, selectedBuilding.lng));
      }
    }
    for (final id in routeBuildings) {
      final routeBuilding = buildingMap[id];
      if (routeBuilding != null) {
        occupied.add(LatLng(routeBuilding.lat, routeBuilding.lng));
      }
    }

    final candidates = [...buildings]..sort((a, b) {
        final score = _chipPriority(b).compareTo(_chipPriority(a));
        if (score != 0) return score;
        return a.name.compareTo(b.name);
      });

    final chosen = <String>{};
    for (final building in candidates) {
      if (building.id == selectedId || routeBuildings.contains(building.id)) {
        continue;
      }
      if (chosen.length >= maxChips) break;

      final point = LatLng(building.lat, building.lng);
      final overlaps = occupied
          .any((existing) => _distance.as(LengthUnit.Meter, existing, point) < spacingMeters);
      if (overlaps) continue;

      chosen.add(building.id);
      occupied.add(point);
    }

    return chosen;
  }

  int _chipPriority(NetBuilding b) {
    var score = 0;
    if (_importantTypes.contains(b.type)) score += 4;
    if (b.amenities.contains('transit')) score += 3;
    if (b.amenities.contains('food')) score += 1;
    if (b.type == 'office') score -= 1;
    return score;
  }

  /// Chips are ~150 px wide: keep their anchors about that far apart on screen.
  double _chipSpacingMeters() {
    final metresPerPx = 156543.03 * cos(51.05 * pi / 180) / pow(2, _currentZoom);
    return metresPerPx * 120;
  }

  int _maxChipCount() {
    if (_currentZoom >= 17.0) return 30;
    if (_currentZoom >= 16.5) return 22;
    return 16;
  }

  /// Nearest building name for the "You're near …" context line. Only resolves
  /// when we have a fix inside the downtown bounds.
  String? _nearestBuildingName(List<NetBuilding> buildings, LatLng? loc) {
    if (loc == null || buildings.isEmpty) return null;
    if (!_isInCalgaryBounds(loc.latitude, loc.longitude)) return null;
    NetBuilding? best;
    double bestM = double.infinity;
    for (final b in buildings) {
      final d = _distance(loc, LatLng(b.lat, b.lng));
      if (d < bestM) {
        bestM = d;
        best = b;
      }
    }
    if (best == null) return null;
    // "Near X" only when plausibly at or in the building; otherwise how far
    // the +15 is (routes from here walk you to the nearest door).
    if (bestM <= 220) return 'Near ${best.name}';
    return bestM < 1000
        ? '${(bestM / 10).round() * 10} m from the +15'
        : '${(bestM / 1000).toStringAsFixed(1)} km from the +15';
  }

  Widget _buildHeader(BuildContext context, int closuresCount, String? nearest,
      NetworkStatus? status, bool locationOff) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final muted = scheme.onSurfaceVariant;

    return Column(
      children: [
        Row(
          children: [
            _FloatingSurface(
              child: SizedBox.square(
                dimension: 48,
                child: Center(
                  child: Image.asset(AppConstants.logoMark,
                      width: 30, color: scheme.onSurface, semanticLabel: AppConstants.appName),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(child: _contextChip(context, nearest, status, locationOff)),
            const SizedBox(width: AppSpacing.sm),
            _headerButton(
              context,
              icon: Icons.notifications_none_rounded,
              tooltip: closuresCount == 0 ? 'Network status' : '$closuresCount closures',
              badge: closuresCount,
              onTap: () => context.push('/alerts'),
            ),
            const SizedBox(width: AppSpacing.sm),
            _headerButton(
              context,
              icon: Icons.settings_outlined,
              tooltip: 'Settings & help',
              onTap: () => context.push('/help'),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        // The primary way to find a place, with Ask +15 alongside.
        _FloatingSurface(
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 52),
            child: Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      context.go('/search');
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: 14),
                      child: Row(
                        children: [
                          Icon(Icons.search_rounded, color: muted),
                          const SizedBox(width: AppSpacing.md),
                          Expanded(
                            child: Text(
                              'Search the +15',
                              style: theme.textTheme.bodyLarge?.copyWith(color: muted),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (aiConfigured)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: TextButton.icon(
                      onPressed: () => showAiConcierge(context),
                      icon: const Icon(Icons.auto_awesome_rounded, size: 18),
                      label: const Text('Ask +15'),
                      style: TextButton.styleFrom(
                        backgroundColor: scheme.primaryContainer,
                        foregroundColor: scheme.onPrimaryContainer,
                        minimumSize: const Size(0, 44),
                        tapTargetSize: MaterialTapTargetSize.padded,
                        shape: const StadiumBorder(),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    ).animate().fadeIn(duration: 300.ms);
  }

  /// Where you are and whether the +15 is open right now.
  Widget _contextChip(
      BuildContext context, String? nearest, NetworkStatus? status, bool locationOff) {
    final theme = Theme.of(context);
    final open = status?.open ?? true;
    final statusColor = open ? AppPalette.origin : AppPalette.danger;
    final dark = theme.brightness == Brightness.dark;
    final statusText = open && !dark ? AppPalette.originText : statusColor;
    return _FloatingSurface(
      child: InkWell(
        onTap: () => context.push('/alerts'),
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 6),
          child: Row(
            children: [
              Icon(Icons.circle, size: 9, color: statusColor),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      status == null ? '+15 network' : status.label,
                      style: theme.textTheme.labelMedium?.copyWith(color: statusText),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      nearest ?? (locationOff ? 'Downtown Calgary' : 'Finding your location…'),
                      style: theme.textTheme.titleSmall,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _headerButton(
    BuildContext context, {
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
    int badge = 0,
  }) {
    return _FloatingSurface(
      child: IconButton(
        tooltip: tooltip,
        constraints: const BoxConstraints.tightFor(width: 48, height: 48),
        onPressed: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        icon: Badge(
          isLabelVisible: badge > 0,
          label: ExcludeSemantics(child: Text('$badge')), // the tooltip says it
          backgroundColor: AppPalette.danger,
          child: Icon(icon),
        ),
      ),
    );
  }

  /// Tears down an active route + navigation session.
  void _stopNavigation() {
    ref.read(activeRouteProvider.notifier).state = null;
    ref.read(navigationSessionProvider.notifier).stop();
    _tracker = null;
    _offRouteStrikes = 0;
    if (mounted) setState(() {});
  }

  /// The arrival moment — a calm, celebratory card that slides up over the map
  /// when navigation completes. Tasteful, no confetti (per the design spec).
  Widget _buildArrivalCard(
      BuildContext context, NavigationSession session, Map<String, NetBuilding> bMap, bool isDark) {
    final theme = Theme.of(context);
    final dest = session.destinationId == null ? null : bMap[session.destinationId!];
    final destName = dest?.name ?? 'your destination';
    return Positioned(
      left: 16,
      right: 16,
      bottom: AppSpacing.lg,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: AppRadii.rCard,
          border: Border.all(color: AppPalette.origin.withValues(alpha: 0.3)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.14),
              blurRadius: 28,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppPalette.origin.withValues(alpha: 0.14),
                  ),
                  child: const Icon(Icons.check_circle_rounded, color: AppPalette.origin, size: 26),
                ).animate().scale(duration: 360.ms, curve: Curves.easeOutBack),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("You've arrived", style: theme.textTheme.titleLarge),
                      Text(destName,
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(color: theme.textTheme.bodySmall?.color),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _saveArrival(session),
                    icon: const Icon(Icons.bookmark_add_outlined, size: 18),
                    label: const Text('Save route'),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: FilledButton(
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      _stopNavigation();
                    },
                    child: const Text('Done'),
                  ),
                ),
              ],
            ),
          ],
        ),
      )
          .animate()
          .fadeIn(duration: AppMotion.normal)
          .slideY(begin: 0.3, end: 0, curve: Curves.easeOutCubic),
    );
  }

  void _saveArrival(NavigationSession session) {
    final route = ref.read(activeRouteProvider);
    final network = ref.read(networkProvider).valueOrNull;
    // Trips from "My location" save from the first +15 building walked through.
    final fromId = route?.originBuildingId ??
        (route == null || route.hops.isEmpty
            ? null
            : network?.buildingsAtNode[route.hops.first.fromNode]?.firstOrNull?.id ??
                network?.buildingsAtNode[route.hops.first.toNode]?.firstOrNull?.id);
    if (route == null || fromId == null || fromId == route.destinationBuildingId) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content:
                Text("This trip has no start building to save. Plan it in Navigate to save it.")));
      }
      _stopNavigation();
      return;
    }
    final bMap = network?.buildingById ?? const {};
    final toId = route.destinationBuildingId;
    final now = calgaryNow();
    ref.read(savedRoutesProvider.notifier).add(
          SavedRoute(
            id: '${fromId}_${toId}_${now.millisecondsSinceEpoch}',
            name: '${bMap[fromId]?.name ?? fromId} → ${bMap[toId]?.name ?? toId}',
            fromId: fromId,
            toId: toId,
            routeType: session.profile.name,
            createdAt: now,
          ),
        );
    HapticFeedback.mediumImpact();
    if (mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Saved to your routes.')));
    }
    _stopNavigation();
  }

  Widget _buildMapControls(BuildContext context, AsyncValue<LatLng?> userLocation) {
    final divider = Divider(height: 1, color: Theme.of(context).colorScheme.outlineVariant);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _FloatingSurface(
          child: Column(
            children: [
              _controlBtn(Icons.add_rounded, 'Zoom in', () {
                final z = _mapController.camera.zoom;
                _animatedMove(_mapController.camera.center, (z + 1).clamp(10, 19));
              }),
              divider,
              _controlBtn(Icons.remove_rounded, 'Zoom out', () {
                final z = _mapController.camera.zoom;
                _animatedMove(_mapController.camera.center, (z - 1).clamp(10, 19));
              }),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        _FloatingSurface(
          child: Column(
            children: [
              _controlBtn(Icons.layers_outlined, 'Map style', () => _showBasemapPicker(context)),
              divider,
              _controlBtn(Icons.view_in_ar_rounded, '3D view', () => context.push('/map3d')),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        _FloatingSurface(
          child: _controlBtn(Icons.my_location_rounded, 'My location', () async {
            final pos = _smoothedUserLocation ?? userLocation.valueOrNull;
            if (pos != null && _isInCalgaryBounds(pos.latitude, pos.longitude)) {
              _animatedMove(pos, 16.5);
              return;
            }
            if (pos == null && !await ensureLocation(this.context, ref)) return;
            if (!mounted) return;
            if (pos != null) {
              ScaffoldMessenger.of(this.context).showSnackBar(const SnackBar(
                  content: Text("You're outside downtown. Showing the +15 network.")));
            }
            _animatedMove(_plus15Center, 15.8);
          }, accent: true),
        ),
      ],
    ).animate().fadeIn(duration: 300.ms, delay: 150.ms);
  }

  /// Map style picker: Map / Streets / Satellite / Terrain.
  void _showBasemapPicker(BuildContext context) {
    HapticFeedback.selectionClick();
    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      showDragHandle: true,
      builder: (ctx) => Consumer(builder: (ctx, ref, _) {
        final theme = Theme.of(ctx);
        final dark = theme.brightness == Brightness.dark;
        final current = ref.watch(basemapProvider);
        final accent = dark ? AppPalette.brandSoft : AppPalette.brand;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Map style', style: theme.textTheme.titleLarge),
                const SizedBox(height: 14),
                Row(
                  children: [
                    for (final b in Basemap.values) ...[
                      Expanded(
                        child: Semantics(
                          button: true,
                          selected: b == current,
                          label: '${b.label} map style',
                          child: GestureDetector(
                            onTap: () {
                              HapticFeedback.selectionClick();
                              ref.read(basemapProvider.notifier).select(b);
                              Navigator.of(ctx).pop();
                            },
                            child: AnimatedContainer(
                              duration: AppMotion.fast,
                              curve: AppMotion.curve,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              decoration: BoxDecoration(
                                color: b == current
                                    ? accent.withValues(alpha: dark ? 0.12 : 0.07)
                                    : (dark ? AppPalette.cardDark : AppPalette.cardLight),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: b == current
                                      ? accent
                                      : (dark ? AppPalette.borderDark : AppPalette.borderLight),
                                  width: b == current ? 1.6 : 1,
                                ),
                              ),
                              child: Column(
                                children: [
                                  Icon(b.icon,
                                      color:
                                          b == current ? accent : theme.textTheme.bodySmall?.color),
                                  const SizedBox(height: 6),
                                  Text(b.label,
                                      style: theme.textTheme.labelLarge?.copyWith(
                                          color: b == current ? accent : null,
                                          fontWeight: FontWeight.w700)),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      if (b != Basemap.values.last) const SizedBox(width: 8),
                    ],
                  ],
                ),
                const SizedBox(height: 12),
                Text(current.attribution, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
        );
      }),
    );
  }

  Widget _controlBtn(IconData icon, String tooltip, VoidCallback onTap, {bool accent = false}) {
    final scheme = Theme.of(context).colorScheme;
    return IconButton(
      tooltip: tooltip,
      constraints: const BoxConstraints.tightFor(width: 48, height: 48),
      color: accent ? scheme.primary : scheme.onSurface,
      onPressed: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      icon: Icon(icon),
    );
  }

  Future<void> _startQuickRoute(String fromId, String toId, String mode) async {
    final router = await ref.read(routerProvider.future);
    final result = router.route(RouteOrigin.building(fromId), toId,
        profile: profileFromName(mode), at: calgaryNow());
    if (!mounted) return;
    final route = result.route ?? result.viaClosed;
    if (route == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(result.unavailableReason!)));
      return;
    }
    ref.read(activeRouteProvider.notifier).state = route;
    if (route.previewOnly) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(route.opensAt != null
              ? 'The +15 is closed now. Showing the route so you can plan ahead.'
              : 'This route goes through a closed bridge. Preview only.')));
      return;
    }
    ref.read(navigationSessionProvider.notifier).start(route: route);
  }
}

class _PulsingLocationDot extends StatefulWidget {
  final double? headingRadians;

  const _PulsingLocationDot({this.headingRadians});

  @override
  State<_PulsingLocationDot> createState() => _PulsingLocationDotState();
}

class _PulsingLocationDotState extends State<_PulsingLocationDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // "Remove animations" in system settings: hold a still ring instead.
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.value = 0.5;
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final pulse = _controller.value;
        return Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: 28 + (pulse * 16),
              height: 28 + (pulse * 16),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppPalette.brand.withValues(alpha: 0.15 * (1 - pulse)),
              ),
            ),
            Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppPalette.brand,
                border: Border.all(color: Colors.white, width: 3),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.18),
                    blurRadius: 8,
                    spreadRadius: 1,
                  ),
                ],
              ),
            ),
            if (widget.headingRadians != null)
              Transform.rotate(
                angle: widget.headingRadians!,
                child: const Icon(
                  Icons.navigation_rounded,
                  size: 12,
                  color: Colors.white,
                ),
              ),
          ],
        );
      },
    );
  }
}

/// The floating chrome over the map: theme surface, hairline border and one
/// soft shadow. Every header control and map button sits on one of these.
class _FloatingSurface extends StatelessWidget {
  final Widget child;
  const _FloatingSurface({required this.child});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: AppRadii.rControl,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: dark ? 0.35 : 0.10),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: scheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadii.rControl,
          side: BorderSide(color: scheme.outlineVariant),
        ),
        clipBehavior: Clip.antiAlias,
        child: child,
      ),
    );
  }
}

Color _markerColor(String type, bool hasFood, ColorScheme scheme) => switch (type) {
      'hotel' ||
      'retail' ||
      'entertainment' ||
      'landmark' ||
      'transit' =>
        AppPalette.typeColor(type),
      _ => hasFood ? AppPalette.amenityColor('food') : scheme.outline,
    };

class _BuildingDot extends StatelessWidget {
  final String type;
  final bool hasFood;

  const _BuildingDot({required this.type, required this.hasFood});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(
          color: _markerColor(type, hasFood, scheme),
          shape: BoxShape.circle,
          border: Border.all(color: scheme.surface, width: 2),
        ),
      ),
    );
  }
}

class _BuildingChip extends StatelessWidget {
  final String name;
  final bool isSelected;
  final bool isOnRoute;
  final String type;
  final bool hasFood;

  const _BuildingChip({
    required this.name,
    required this.isSelected,
    required this.isOnRoute,
    required this.type,
    required this.hasFood,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final strong = isSelected || isOnRoute;
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: strong ? scheme.primary : scheme.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: strong ? scheme.primary : scheme.outlineVariant),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.14),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.circle,
                size: 7, color: strong ? scheme.onPrimary : _markerColor(type, hasFood, scheme)),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelMedium
                    ?.copyWith(color: strong ? scheme.onPrimary : scheme.onSurface),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
