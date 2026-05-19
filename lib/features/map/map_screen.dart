import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import '../../core/constants/app_constants.dart';
import '../../data/models/building.dart';
import '../../data/models/bridge.dart';
import '../../data/models/entry_point.dart';
import '../../shared/providers/providers.dart';
import '../map_3d/iso_view.dart';
import '../map_3d/widgets/mode_toggle.dart';
import 'services/course_tracker.dart';
import 'services/map_alignment_service.dart';
import 'widgets/building_tooltip.dart';

class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen>
    with TickerProviderStateMixin {
  final MapController _mapController = MapController();
  final MapAlignmentService _mapAlignmentService = const MapAlignmentService();

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
  DateTime? _lastRerouteAt;
  LatLng? _smoothedUserLocation;
  LatLng? _lastRawLocation;
  double? _headingRadians;
  EntryPoint? _guidanceEntryPoint;
  double? _guidanceEntryDistanceM;

  static const _importantTypes = {
    'hotel',
    'retail',
    'landmark',
    'convention',
    'entertainment'
  };
  static const _importantAmenities = {'transit'};
  static const Distance _distance = Distance();

  @override
  void initState() => super.initState();

  bool _isBuildingImportant(Building b) {
    if (_importantTypes.contains(b.type)) return true;
    if (b.amenities.any((a) => _importantAmenities.contains(a))) return true;
    return false;
  }

  List<Building> _visibleBuildings(List<Building> buildings) {
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
    final latTween =
        Tween<double>(begin: cam.center.latitude, end: dest.latitude);
    final lngTween =
        Tween<double>(begin: cam.center.longitude, end: dest.longitude);
    final zoomTween = Tween<double>(begin: cam.zoom, end: zoom);

    final controller = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    final curve =
        CurvedAnimation(parent: controller, curve: Curves.easeInOutCubic);

    controller.addListener(() {
      _mapController.move(
        LatLng(latTween.evaluate(curve), lngTween.evaluate(curve)),
        zoomTween.evaluate(curve),
      );
    });

    controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) controller.dispose();
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

    final buildingsAsync = ref.watch(buildingsProvider);
    final bridgesAsync = ref.watch(bridgesProvider);
    final shopsAsync = ref.watch(shopsProvider);
    final overlayConfigAsync = ref.watch(overlayConfigProvider);
    final selectedBuilding = ref.watch(selectedBuildingProvider);
    final activeRoute = ref.watch(activeRouteProvider);
    final activeRouteDist = ref.watch(activeRouteDistanceProvider);
    final navigationSession = ref.watch(navigationSessionProvider);
    final walkingSpeed = ref.watch(walkingSpeedProvider);
    final userLocation = ref.watch(locationStreamProvider);
    final displayUserLocation =
        _smoothedUserLocation ?? userLocation.valueOrNull;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final overlayConfig = overlayConfigAsync.valueOrNull;
    final overlayAlignment = overlayConfig == null
        ? null
        : _mapAlignmentService.compute(overlayConfig);

    final viewMode = ref.watch(mapViewModeProvider);

    return Scaffold(
      body: buildingsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (buildings) => bridgesAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Error: $e')),
          data: (bridges) {
            final buildingMap = {for (final b in buildings) b.id: b};
            final visibleBuildings = _visibleBuildings(buildings);

            final flatStack = Stack(
              key: const ValueKey('flat'),
              children: [
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: _calgaryCenter,
                    initialZoom: _defaultZoom,
                    minZoom: 10,
                    maxZoom: 18,
                    cameraConstraint:
                        CameraConstraint.contain(bounds: _calgaryBounds),
                    onMapReady: () {
                      _mapReady = true;
                      final loc = displayUserLocation;
                      if (loc != null &&
                          _isInCalgaryBounds(loc.latitude, loc.longitude)) {
                        _animatedMove(loc, 16.0);
                      }
                    },
                    onPositionChanged: (pos, _) {
                      if (pos.zoom != _currentZoom) {
                        setState(() => _currentZoom = pos.zoom);
                        ref.read(mapZoomProvider.notifier).state = pos.zoom;
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
                      urlTemplate: isDark
                          ? 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}@2x.png'
                          : 'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}@2x.png',
                      subdomains: const ['a', 'b', 'c', 'd'],
                      userAgentPackageName: 'com.plus15.navigator',
                      maxZoom: 20,
                      tileDisplay: const TileDisplay.fadeIn(),
                      fallbackUrl:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    ),
                    if (overlayConfig != null && overlayAlignment != null)
                      OverlayImageLayer(
                        overlayImages: [
                          RotatedOverlayImage(
                            imageProvider: AssetImage(overlayConfig.imageAsset),
                            topLeftCorner: overlayAlignment.topLeft,
                            bottomLeftCorner: overlayAlignment.bottomLeft,
                            bottomRightCorner: overlayAlignment.bottomRight,
                            opacity: isDark
                                ? overlayConfig.opacityDark
                                : overlayConfig.opacityLight,
                            filterQuality: FilterQuality.high,
                          ),
                        ],
                      ),
                    PolylineLayer(
                      polylines: _buildBridgeLines(
                          bridges, buildingMap, activeRoute, isDark),
                    ),
                    if (activeRoute != null && activeRoute.length > 1)
                      PolylineLayer(
                        polylines: [
                          _buildRouteGlowPolyline(activeRoute, buildingMap),
                          _buildRoutePolyline(activeRoute, buildingMap)
                        ],
                      ),
                    if (_currentZoom >= 13.5)
                      MarkerLayer(
                        markers: _buildMarkers(visibleBuildings,
                            selectedBuilding, activeRoute, isDark),
                      ),
                    if (activeRoute != null && activeRoute.length > 1)
                      MarkerLayer(
                        markers: _buildRouteEndpoints(activeRoute, buildingMap),
                      ),
                    if (displayUserLocation != null)
                      MarkerLayer(
                        markers: [
                          _buildUserLocationMarker(displayUserLocation)
                        ],
                      ),
                  ],
                ),
                Positioned(
                  top: MediaQuery.of(context).padding.top + 12,
                  left: 16,
                  right: 16,
                  child: _buildHeader(context, isDark),
                ),
                Positioned(
                  right: 16,
                  bottom: selectedBuilding != null
                      ? 300
                      : (activeRoute != null ? 116 : 24),
                  child: _buildMapControls(context, isDark, userLocation),
                ),
                if (navigationSession.isActive)
                  Positioned(
                    top: MediaQuery.of(context).padding.top + 84,
                    left: 16,
                    right: 16,
                    child: _buildNavigationStatusCard(
                      context,
                      navigationSession,
                      buildingMap,
                    ),
                  ),
                if (_hasRoutineRoutes())
                  Positioned(
                    left: 16,
                    bottom: activeRoute != null ? 110 : 24,
                    child: _buildQuickRoutes(context, buildings),
                  ),
                if (navigationSession.status ==
                        NavigationStatus.headingToEntry &&
                    _guidanceEntryPoint != null &&
                    _guidanceEntryDistanceM != null)
                  Positioned(
                    left: 16,
                    right: 16,
                    bottom: activeRoute != null ? 118 : 26,
                    child: _buildEntryGuidanceChip(context),
                  ),
                if (activeRoute != null)
                  Positioned(
                    left: 16,
                    right: 16,
                    bottom: 24,
                    child: _buildRouteBar(
                      context,
                      navigationSession.isActive
                          ? navigationSession.remainingDistanceM
                          : activeRouteDist,
                      buildings,
                      activeRoute,
                      walkingSpeed,
                    ),
                  ),
                if (selectedBuilding != null)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: activeRoute != null ? 94 : 0,
                    child: shopsAsync.when(
                      data: (shops) => BuildingTooltip(
                        building: selectedBuilding,
                        shops: shops,
                        onNavigateHere: () {
                          ref.read(routeToProvider.notifier).state =
                              selectedBuilding;
                          ref.read(selectedBuildingProvider.notifier).state =
                              null;
                          context.go('/route');
                        },
                        onClose: () => ref
                            .read(selectedBuildingProvider.notifier)
                            .state = null,
                      ),
                      loading: () => const SizedBox.shrink(),
                      error: (_, __) => const SizedBox.shrink(),
                    ),
                  ),
              ],
            );

            return Stack(
              children: [
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 320),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  child: viewMode == MapViewMode.flat
                      ? flatStack
                      : IsoView(
                          key: const ValueKey('iso'),
                          buildings: buildings,
                          bridges: bridges,
                        ),
                ),
                Positioned(
                  top: MediaQuery.of(context).padding.top +
                      (viewMode == MapViewMode.flat ? 82 : 12),
                  right: 16,
                  child: ModeToggle(
                    mode: viewMode,
                    onChanged: (m) => ref
                        .read(mapViewModeProvider.notifier)
                        .state = m,
                  ).animate().fadeIn(duration: 400.ms, delay: 200.ms),
                ),
              ],
            );
          },
        ),
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

    if (_guidanceEntryPoint != null && _smoothedUserLocation != null) {
      _guidanceEntryDistanceM = distance(
        _smoothedUserLocation!,
        LatLng(_guidanceEntryPoint!.lat, _guidanceEntryPoint!.lng),
      );
    }

    if (mounted) setState(() {});

    final session = ref.read(navigationSessionProvider);
    if (_mapReady && session.isActive && _smoothedUserLocation != null) {
      final centerDistance =
          distance(_mapController.camera.center, _smoothedUserLocation!);
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
    if (!session.isActive ||
        session.destinationId == null ||
        route == null ||
        route.length < 2) {
      return;
    }

    final buildings = await ref.read(buildingsProvider.future);
    final bridges = await ref.read(bridgesProvider.future);
    final graph = await ref.read(graphProvider.future);
    final pathfinder = await ref.read(pathfinderProvider.future);
    final entryPoints = await ref.read(entryPointsProvider.future);
    final buildingMap = {for (final b in buildings) b.id: b};
    final tracker = CourseTracker(graph: graph, buildingMap: buildingMap);

    final liveSession = ref.read(navigationSessionProvider);
    if (!liveSession.isActive || liveSession.destinationId == null) return;
    final destinationId = liveSession.destinationId!;
    final onRoute = tracker.isOnRoute(user, route, thresholdM: 20);

    if (onRoute) {
      _offRouteStrikes = 0;
      final nearestNode = tracker.nearestRouteNode(user, route);
      final progress = nearestNode == null
          ? const RouteProgress(
              traveledM: 0,
              remainingM: 0,
              progress: 0,
              nextNodeId: null,
            )
          : tracker.computeProgress(route, nearestNode);

      final arrived = nearestNode == destinationId || progress.remainingM <= 25;

      ref.read(navigationSessionProvider.notifier).update(
            liveSession.copyWith(
              status: arrived
                  ? NavigationStatus.arrived
                  : NavigationStatus.onCourse,
              routePath: route,
              remainingDistanceM: arrived ? 0 : progress.remainingM,
              totalDistanceM: liveSession.totalDistanceM > 0
                  ? liveSession.totalDistanceM
                  : (progress.traveledM + progress.remainingM),
              nextNodeId: progress.nextNodeId,
              confidence: 0.95,
              offRouteStrikes: 0,
            ),
          );
      _guidanceEntryPoint = null;
      _guidanceEntryDistanceM = null;
      return;
    }

    _offRouteStrikes += 1;
    ref.read(navigationSessionProvider.notifier).update(
          liveSession.copyWith(
            status: NavigationStatus.rerouting,
            confidence: 0.45,
            offRouteStrikes: _offRouteStrikes,
          ),
        );

    if (_offRouteStrikes < 2) return;
    if (_lastRerouteAt != null &&
        DateTime.now().difference(_lastRerouteAt!) <
            const Duration(seconds: 4)) {
      return;
    }
    _lastRerouteAt = DateTime.now();

    final accessibility = ref.read(accessibilityModeProvider);
    final routeMode = accessibility ? 'accessible' : liveSession.mode;

    if (tracker.isNearNetwork(user, bridges, thresholdM: 60)) {
      final startNode = tracker.nearestGraphNode(user);
      if (startNode != null) {
        final reroute =
            pathfinder.findRoute(startNode, destinationId, mode: routeMode);
        if (reroute != null && reroute.path.length > 1) {
          ref.read(activeRouteProvider.notifier).state = reroute.path;
          ref.read(activeRouteDistanceProvider.notifier).state =
              reroute.totalDistance;
          ref.read(navigationSessionProvider.notifier).update(
                liveSession.copyWith(
                  status: NavigationStatus.rerouting,
                  routePath: reroute.path,
                  totalDistanceM: reroute.totalDistance,
                  remainingDistanceM: reroute.totalDistance,
                  confidence: 0.78,
                  offRouteStrikes: 0,
                  clearEntryPoint: true,
                ),
              );
          _offRouteStrikes = 0;
          _guidanceEntryPoint = null;
          _guidanceEntryDistanceM = null;
          if (mounted) setState(() {});
          return;
        }
      }
    }

    final choice = tracker.chooseBestEntryPoint(
      user: user,
      entryPoints: entryPoints,
      destinationId: destinationId,
      pathfinder: pathfinder,
      accessibilityMode: accessibility,
      mode: routeMode,
    );
    if (choice != null) {
      _guidanceEntryPoint = choice.entryPoint;
      _guidanceEntryDistanceM = choice.userToEntryM;

      ref.read(activeRouteProvider.notifier).state = choice.route.path;
      ref.read(activeRouteDistanceProvider.notifier).state =
          choice.route.totalDistance;
      ref.read(navigationSessionProvider.notifier).update(
            liveSession.copyWith(
              status: NavigationStatus.headingToEntry,
              entryPointId: choice.entryPoint.id,
              routePath: choice.route.path,
              totalDistanceM: choice.route.totalDistance,
              remainingDistanceM: choice.route.totalDistance,
              confidence: 0.85,
              offRouteStrikes: 0,
            ),
          );
      _offRouteStrikes = 0;
      if (mounted) setState(() {});
    }
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

  List<Polyline> _buildBridgeLines(List<Bridge> bridges,
      Map<String, Building> bMap, List<String>? activeRoute, bool isDark) {
    final zoomedIn = _currentZoom >= 15.0;
    final veryZoomed = _currentZoom >= 16.0;
    return bridges
        .where((b) =>
            bMap.containsKey(b.fromBuildingId) &&
            bMap.containsKey(b.toBuildingId))
        .map((bridge) {
      final from = bMap[bridge.fromBuildingId]!;
      final to = bMap[bridge.toBuildingId]!;
      final isOnRoute = activeRoute != null &&
          _isEdgeOnRoute(
              bridge.fromBuildingId, bridge.toBuildingId, activeRoute);

      final isClosed = bridge.status != 'open';
      final notAccessible = !bridge.isAccessible;

      Color color;
      double width;
      if (isClosed) {
        color = const Color(0xFFEF4444).withValues(alpha: 0.5);
        width = veryZoomed ? 2.5 : 1.5;
      } else if (notAccessible) {
        color = const Color(0xFFF59E0B).withValues(alpha: 0.45);
        width = veryZoomed ? 2.5 : 1.5;
      } else if (isDark) {
        color = const Color(0xFF38BDF8).withValues(
            alpha: veryZoomed
                ? 0.35
                : zoomedIn
                    ? 0.25
                    : 0.18);
        width = veryZoomed
            ? 3.0
            : zoomedIn
                ? 2.0
                : 1.5;
      } else {
        color = const Color(0xFF3B82F6).withValues(
            alpha: veryZoomed
                ? 0.35
                : zoomedIn
                    ? 0.25
                    : 0.2);
        width = veryZoomed
            ? 3.0
            : zoomedIn
                ? 2.0
                : 1.5;
      }

      return Polyline(
        points: [LatLng(from.lat, from.lng), LatLng(to.lat, to.lng)],
        strokeWidth: isOnRoute ? 0 : width,
        color: color,
      );
    }).toList();
  }

  Polyline _buildRoutePolyline(List<String> route, Map<String, Building> bMap) {
    final points = route
        .where((id) => bMap.containsKey(id))
        .map((id) => LatLng(bMap[id]!.lat, bMap[id]!.lng))
        .toList();

    return Polyline(
      points: points,
      strokeWidth: 5,
      color: const Color(0xFF3B82F6),
      borderStrokeWidth: 2,
      borderColor: const Color(0xFF3B82F6).withValues(alpha: 0.25),
    );
  }

  Polyline _buildRouteGlowPolyline(
      List<String> route, Map<String, Building> bMap) {
    final points = route
        .where((id) => bMap.containsKey(id))
        .map((id) => LatLng(bMap[id]!.lat, bMap[id]!.lng))
        .toList();

    return Polyline(
      points: points,
      strokeWidth: 10,
      color: const Color(0xFF22D3EE).withValues(alpha: 0.28),
      borderStrokeWidth: 0,
    );
  }

  List<Marker> _buildRouteEndpoints(
      List<String> route, Map<String, Building> bMap) {
    final markers = <Marker>[];
    final start = bMap[route.first];
    final end = bMap[route.last];

    if (start != null) {
      markers.add(Marker(
        point: LatLng(start.lat, start.lng),
        width: 30,
        height: 30,
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF10B981),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 3),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF10B981).withValues(alpha: 0.4),
                blurRadius: 10,
                spreadRadius: 2,
              ),
            ],
          ),
          child: const Icon(Icons.trip_origin, size: 12, color: Colors.white),
        ),
      ));
    }
    if (end != null) {
      markers.add(Marker(
        point: LatLng(end.lat, end.lng),
        width: 34,
        height: 34,
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFFEF4444),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 3),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFEF4444).withValues(alpha: 0.4),
                blurRadius: 10,
                spreadRadius: 2,
              ),
            ],
          ),
          child: const Icon(Icons.flag_rounded, size: 14, color: Colors.white),
        ),
      ));
    }
    return markers;
  }

  List<Marker> _buildMarkers(List<Building> buildings, Building? selected,
      List<String>? activeRoute, bool isDark) {
    final showChips = _currentZoom >= 16.1;
    final routeBuildings = activeRoute?.toSet() ?? {};
    final declutteredChipIds = showChips
        ? _declutteredChipIds(buildings, selected, routeBuildings)
        : const <String>{};

    final onRouteBuildings =
        buildings.where((b) => routeBuildings.contains(b.id)).toList();
    final nonRouteBuildings =
        buildings.where((b) => !routeBuildings.contains(b.id)).toList();

    final allVisible = [...nonRouteBuildings, ...onRouteBuildings];

    return allVisible.map((b) {
      final isSelected = b.id == selected?.id;
      final isOnRoute = routeBuildings.contains(b.id);

      final shouldShowChip =
          isSelected || isOnRoute || declutteredChipIds.contains(b.id);

      if (shouldShowChip) {
        return Marker(
          point: LatLng(b.lat, b.lng),
          width: isSelected ? 150 : 120,
          height: isSelected ? 40 : 32,
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
              isDark: isDark,
              type: b.type,
              hasFood: b.amenities.contains('food'),
              hasTransit: b.amenities.contains('transit'),
            ),
          ),
        );
      }

      return Marker(
        point: LatLng(b.lat, b.lng),
        width: 18,
        height: 18,
        child: GestureDetector(
          onTap: () {
            HapticFeedback.lightImpact();
            ref.read(selectedBuildingProvider.notifier).state = b;
            _animatedMove(LatLng(b.lat, b.lng), 16.0);
          },
          child: _BuildingDot(
            isDark: isDark,
            type: b.type,
            hasFood: b.amenities.contains('food'),
          ),
        ),
      );
    }).toList();
  }

  Set<String> _declutteredChipIds(List<Building> buildings, Building? selected,
      Set<String> routeBuildings) {
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
      final overlaps = occupied.any((existing) =>
          _distance.as(LengthUnit.Meter, existing, point) < spacingMeters);
      if (overlaps) continue;

      chosen.add(building.id);
      occupied.add(point);
    }

    return chosen;
  }

  int _chipPriority(Building b) {
    var score = 0;
    if (_importantTypes.contains(b.type)) score += 4;
    if (b.amenities.contains('transit')) score += 3;
    if (b.amenities.contains('food')) score += 1;
    if (b.type == 'office') score -= 1;
    return score;
  }

  double _chipSpacingMeters() {
    if (_currentZoom >= 17.0) return 70;
    if (_currentZoom >= 16.5) return 95;
    return 120;
  }

  int _maxChipCount() {
    if (_currentZoom >= 17.0) return 30;
    if (_currentZoom >= 16.5) return 22;
    return 16;
  }

  bool _isEdgeOnRoute(String fromId, String toId, List<String> route) {
    for (int i = 0; i < route.length - 1; i++) {
      if ((route[i] == fromId && route[i + 1] == toId) ||
          (route[i] == toId && route[i + 1] == fromId)) {
        return true;
      }
    }
    return false;
  }

  Widget _buildHeader(BuildContext context, bool isDark) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: (isDark ? const Color(0xFF0F0F14) : Colors.white)
            .withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.06)
              : const Color(0xFFE2E8F0),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.06),
            blurRadius: 24,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF3B82F6), Color(0xFF8B5CF6)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Text('+15',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.5)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Plus15 Navigator',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700)),
                Text('Calgary Skywalk Network',
                    style: theme.textTheme.bodySmall?.copyWith(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.5)
                            : const Color(0xFF94A3B8))),
              ],
            ),
          ),
          _zoomIndicator(),
        ],
      ),
    ).animate().fadeIn(duration: 400.ms).slideY(
        begin: -0.3, end: 0, duration: 400.ms, curve: Curves.easeOutCubic);
  }

  Widget _zoomIndicator() {
    final level = _currentZoom >= 16.0
        ? 'Detail'
        : _currentZoom >= 15.0
            ? 'Standard'
            : 'Overview';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF3B82F6).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        level,
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: Color(0xFF3B82F6),
        ),
      ),
    );
  }

  Widget _buildNavigationStatusCard(BuildContext context,
      NavigationSession session, Map<String, Building> buildingMap) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final nextName = session.nextNodeId == null
        ? null
        : buildingMap[session.nextNodeId!]?.name ?? session.nextNodeId;
    final destinationName = session.destinationId == null
        ? null
        : buildingMap[session.destinationId!]?.name ?? session.destinationId;
    final total = session.totalDistanceM <= 0 ? 1.0 : session.totalDistanceM;
    final progress = (1 - (session.remainingDistanceM / total)).clamp(0.0, 1.0);

    String statusText;
    switch (session.status) {
      case NavigationStatus.headingToEntry:
        statusText = 'Heading to nearest entry';
        break;
      case NavigationStatus.rerouting:
        statusText = 'Re-routing on +15 network';
        break;
      case NavigationStatus.arrived:
        statusText = 'Arrived at destination';
        break;
      case NavigationStatus.onCourse:
        statusText = 'On course';
        break;
      case NavigationStatus.inactive:
        statusText = 'Navigation inactive';
        break;
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: (isDark ? const Color(0xFF111827) : Colors.white)
            .withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.black.withValues(alpha: 0.06),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.28 : 0.08),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: session.status == NavigationStatus.arrived
                      ? const Color(0xFF10B981)
                      : const Color(0xFF3B82F6),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  statusText,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ),
              Text(
                '${(session.confidence * 100).round()}% conf',
                style: TextStyle(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.62)
                      : const Color(0xFF64748B),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: progress,
            minHeight: 7,
            borderRadius: BorderRadius.circular(8),
            backgroundColor: isDark
                ? Colors.white.withValues(alpha: 0.12)
                : const Color(0xFFE2E8F0),
            valueColor: const AlwaysStoppedAnimation(Color(0xFF3B82F6)),
          ),
          const SizedBox(height: 8),
          Text(
            nextName == null
                ? (destinationName ?? 'Destination')
                : 'Next: $nextName',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: isDark
                  ? Colors.white.withValues(alpha: 0.82)
                  : const Color(0xFF334155),
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 260.ms).slideY(begin: -0.06, end: 0);
  }

  Widget _buildEntryGuidanceChip(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final entry = _guidanceEntryPoint!;
    final distanceM = (_guidanceEntryDistanceM ?? 0).round();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: (isDark ? const Color(0xFF111827) : Colors.white)
            .withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.black.withValues(alpha: 0.06),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.24 : 0.08),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          const Icon(Icons.login_rounded, color: Color(0xFF22C55E), size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Nearest entry: ${entry.name} ($distanceM m)',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 220.ms).slideY(begin: 0.08, end: 0);
  }

  Widget _buildMapControls(
      BuildContext context, bool isDark, AsyncValue<LatLng?> userLocation) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _controlBtn(Icons.add_rounded, () {
          final z = _mapController.camera.zoom;
          _animatedMove(_mapController.camera.center, (z + 0.5).clamp(10, 18));
        }, isDark),
        const SizedBox(height: 8),
        _controlBtn(Icons.remove_rounded, () {
          final z = _mapController.camera.zoom;
          _animatedMove(_mapController.camera.center, (z - 0.5).clamp(10, 18));
        }, isDark),
        const SizedBox(height: 14),
        _controlBtn(Icons.location_city_rounded, () {
          _animatedMove(_plus15Center, 15.8);
        }, isDark),
        const SizedBox(height: 8),
        _controlBtn(
          Icons.my_location_rounded,
          () {
            final pos = _smoothedUserLocation ?? userLocation.valueOrNull;
            if (pos != null) {
              _animatedMove(pos, 16.5);
            } else {
              _animatedMove(_calgaryCenter, _defaultZoom);
            }
          },
          isDark,
          accent: true,
        ),
      ],
    )
        .animate()
        .fadeIn(duration: 400.ms, delay: 200.ms)
        .slideX(begin: 0.3, end: 0, curve: Curves.easeOutCubic);
  }

  Widget _controlBtn(IconData icon, VoidCallback onTap, bool isDark,
      {bool accent = false}) {
    return Material(
      color: accent
          ? const Color(0xFF3B82F6)
          : isDark
              ? const Color(0xFF18181B).withValues(alpha: 0.92)
              : Colors.white.withValues(alpha: 0.95),
      borderRadius: BorderRadius.circular(14),
      elevation: 0,
      child: InkWell(
        onTap: () {
          HapticFeedback.lightImpact();
          onTap();
        },
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: accent
                  ? Colors.transparent
                  : isDark
                      ? Colors.white.withValues(alpha: 0.08)
                      : Colors.black.withValues(alpha: 0.06),
            ),
            boxShadow: [
              BoxShadow(
                color: accent
                    ? const Color(0xFF3B82F6).withValues(alpha: 0.3)
                    : Colors.black.withValues(alpha: 0.08),
                blurRadius: 12,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Icon(icon,
              size: 20,
              color: accent
                  ? Colors.white
                  : isDark
                      ? const Color(0xFFA1A1AA)
                      : const Color(0xFF52525B)),
        ),
      ),
    );
  }

  bool _hasRoutineRoutes() {
    return ref.watch(savedRoutesProvider).any((r) => r.isRoutine);
  }

  Widget _buildQuickRoutes(BuildContext context, List<Building> buildings) {
    final routines =
        ref.watch(savedRoutesProvider).where((r) => r.isRoutine).toList();
    if (routines.isEmpty) return const SizedBox.shrink();

    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: routines.take(2).map((r) {
        final toBldg = buildings.where((b) => b.id == r.toId).firstOrNull;
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Material(
            color: (isDark ? const Color(0xFF18181B) : Colors.white)
                .withValues(alpha: 0.95),
            borderRadius: BorderRadius.circular(14),
            elevation: 0,
            child: InkWell(
              onTap: () => _startQuickRoute(r.fromId, r.toId, r.routeType),
              borderRadius: BorderRadius.circular(14),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.08)
                        : Colors.black.withValues(alpha: 0.06),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.bolt_rounded,
                        size: 16, color: Color(0xFFF59E0B)),
                    const SizedBox(width: 6),
                    Text(toBldg?.name ?? r.name,
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ),
          ),
        );
      }).toList(),
    ).animate().fadeIn(duration: 400.ms, delay: 400.ms);
  }

  void _startQuickRoute(String fromId, String toId, String mode) async {
    final pathfinder = await ref.read(pathfinderProvider.future);
    final result = pathfinder.findRoute(fromId, toId, mode: mode);
    if (result != null) {
      ref.read(activeRouteProvider.notifier).state = result.path;
      ref.read(activeRouteDistanceProvider.notifier).state =
          result.totalDistance;
      ref.read(navigationSessionProvider.notifier).start(
            destinationId: toId,
            mode: mode,
            routePath: result.path,
            totalDistanceM: result.totalDistance,
          );
      _guidanceEntryPoint = null;
      _guidanceEntryDistanceM = null;
    }
  }

  Widget _buildRouteBar(BuildContext context, double distance,
      List<Building> buildings, List<String> route, double walkingSpeedKmh) {
    final fromBldg = buildings.where((b) => b.id == route.first).firstOrNull;
    final toBldg = buildings.where((b) => b.id == route.last).firstOrNull;
    final timeMin = AppConstants.estimateWalkTimeMinutes(distance,
        speedKmh: walkingSpeedKmh);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF3B82F6), Color(0xFF2563EB)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF3B82F6).withValues(alpha: 0.35),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.navigation_rounded,
                color: Colors.white, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${fromBldg?.name ?? '?'} → ${toBldg?.name ?? '?'}',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Text(
                  '${distance.toInt()}m · ~${timeMin.ceil()} min · ${route.length - 1} bridges',
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.75),
                      fontSize: 12),
                ),
              ],
            ),
          ),
          Material(
            color: Colors.white.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              onTap: () {
                ref.read(activeRouteProvider.notifier).state = null;
                ref.read(activeRouteDistanceProvider.notifier).state = 0;
                ref.read(navigationSessionProvider.notifier).stop();
                _guidanceEntryPoint = null;
                _guidanceEntryDistanceM = null;
                _offRouteStrikes = 0;
              },
              borderRadius: BorderRadius.circular(10),
              child: const SizedBox(
                width: 36,
                height: 36,
                child: Icon(Icons.close_rounded, color: Colors.white, size: 18),
              ),
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 300.ms).slideY(
        begin: 0.3, end: 0, duration: 300.ms, curve: Curves.easeOutCubic);
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
    )..repeat();
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
                color: const Color(0xFF3B82F6)
                    .withValues(alpha: 0.15 * (1 - pulse)),
              ),
            ),
            Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF3B82F6),
                border: Border.all(color: Colors.white, width: 3),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF3B82F6).withValues(alpha: 0.4),
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

class _BuildingDot extends StatelessWidget {
  final bool isDark;
  final String type;
  final bool hasFood;

  const _BuildingDot({
    required this.isDark,
    required this.type,
    required this.hasFood,
  });

  @override
  Widget build(BuildContext context) {
    Color dotColor;
    if (type == 'hotel') {
      dotColor = const Color(0xFFF59E0B);
    } else if (type == 'retail' || type == 'entertainment') {
      dotColor = const Color(0xFF8B5CF6);
    } else if (type == 'landmark') {
      dotColor = const Color(0xFFEF4444);
    } else if (hasFood) {
      dotColor = const Color(0xFFEF4444);
    } else {
      dotColor = isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8);
    }

    return Center(
      child: Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(
          color: dotColor,
          shape: BoxShape.circle,
          border: Border.all(
            color: isDark ? const Color(0xFF1E293B) : Colors.white,
            width: 2,
          ),
          boxShadow: [
            BoxShadow(
              color: dotColor.withValues(alpha: 0.3),
              blurRadius: 4,
              spreadRadius: 0,
            ),
          ],
        ),
      ),
    );
  }
}

class _BuildingChip extends StatelessWidget {
  final String name;
  final bool isSelected;
  final bool isOnRoute;
  final bool isDark;
  final String type;
  final bool hasFood;
  final bool hasTransit;

  const _BuildingChip({
    required this.name,
    required this.isSelected,
    required this.isOnRoute,
    required this.isDark,
    required this.type,
    required this.hasFood,
    required this.hasTransit,
  });

  @override
  Widget build(BuildContext context) {
    final bgColor = isSelected
        ? const Color(0xFF3B82F6)
        : isOnRoute
            ? const Color(0xFF3B82F6).withValues(alpha: 0.9)
            : isDark
                ? const Color(0xFF18181B).withValues(alpha: 0.92)
                : Colors.white.withValues(alpha: 0.95);

    final textColor = isSelected || isOnRoute
        ? Colors.white
        : isDark
            ? const Color(0xFFE4E4E7)
            : const Color(0xFF27272A);

    final borderColor = isSelected
        ? const Color(0xFF3B82F6)
        : isOnRoute
            ? const Color(0xFF60A5FA)
            : isDark
                ? Colors.white.withValues(alpha: 0.08)
                : Colors.black.withValues(alpha: 0.06);

    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: borderColor, width: isSelected ? 1.5 : 1),
          boxShadow: [
            if (isSelected)
              BoxShadow(
                color: const Color(0xFF3B82F6).withValues(alpha: 0.3),
                blurRadius: 14,
                spreadRadius: 1,
              )
            else
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.08),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (type == 'hotel')
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Icon(Icons.hotel_rounded,
                    size: 11,
                    color: isSelected ? Colors.white : const Color(0xFFF59E0B)),
              ),
            if (type == 'retail' || type == 'entertainment')
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Icon(
                    type == 'entertainment'
                        ? Icons.theaters_rounded
                        : Icons.shopping_bag_rounded,
                    size: 11,
                    color: isSelected ? Colors.white : const Color(0xFF8B5CF6)),
              ),
            if (hasTransit)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Icon(Icons.train_rounded,
                    size: 11,
                    color: isSelected ? Colors.white : const Color(0xFF10B981)),
              ),
            if (type == 'landmark')
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Icon(Icons.star_rounded,
                    size: 11,
                    color: isSelected ? Colors.white : const Color(0xFFF59E0B)),
              ),
            Flexible(
              child: Text(
                name,
                style: TextStyle(
                  fontSize: isSelected ? 11 : 10,
                  fontWeight: isSelected || isOnRoute
                      ? FontWeight.w700
                      : FontWeight.w500,
                  color: textColor,
                  letterSpacing: -0.2,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (hasFood && !isSelected)
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Container(
                  width: 5,
                  height: 5,
                  decoration: const BoxDecoration(
                    color: Color(0xFFEF4444),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
