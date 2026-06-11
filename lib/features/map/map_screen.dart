import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import '../../core/theme/app_palette.dart';
import '../../core/theme/app_spacing.dart';
import '../../data/models/building.dart';
import '../../data/models/bridge.dart';
import '../../data/models/entry_point.dart';
import '../../data/models/saved_route.dart';
import '../../shared/providers/providers.dart';
import 'services/course_tracker.dart';
import 'widgets/map_bottom_sheet.dart';

class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen>
    with TickerProviderStateMixin {
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

    // Celebrate arrival exactly once on the transition into the arrived state.
    ref.listen(navigationSessionProvider.select((s) => s.status),
        (prev, next) {
      if (next == NavigationStatus.arrived &&
          prev != NavigationStatus.arrived) {
        HapticFeedback.heavyImpact();
      }
    });

    final buildingsAsync = ref.watch(buildingsProvider);
    final bridgesAsync = ref.watch(bridgesProvider);
    final selectedBuilding = ref.watch(selectedBuildingProvider);
    final activeRoute = ref.watch(activeRouteProvider);
    final session = ref.watch(navigationSessionProvider);
    final arrived = session.status == NavigationStatus.arrived;
    final bridgePaths = ref.watch(bridgePathsProvider).valueOrNull ?? {};
    final smoothedRoute = ref.watch(smoothedRouteProvider);
    final userLocation = ref.watch(locationStreamProvider);
    final displayUserLocation =
        _smoothedUserLocation ?? userLocation.valueOrNull;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // The map fills the screen; controls ride just above the sheet's resting
    // (idle) peek, which itself clears the floating nav bar.
    final controlsBottom =
        MediaQuery.of(context).size.height * AppDims.sheetIdle + 12;

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
            final closuresCount = bridges
                .where((b) => b.status != 'open' || !b.isAccessible)
                .length;
            final nearestName =
                _nearestBuildingName(buildings, displayUserLocation);

            return Stack(
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
                    // The +15 network — grid-following paths imprinted on the
                    // map. A glow pass beneath bold skywalk lines; each bridge
                    // follows the street grid rather than cutting diagonally.
                    PolylineLayer(
                      polylines:
                          _buildNetworkGlow(bridges, bridgePaths),
                    ),
                    PolylineLayer(
                      polylines: _buildBridgeLines(
                          bridges, bridgePaths, isDark),
                    ),
                    if (smoothedRoute.length > 1)
                      PolylineLayer(
                        polylines: [
                          _buildRouteGlowPolyline(smoothedRoute),
                          _buildRoutePolyline(smoothedRoute),
                        ],
                      ),
                    if (_currentZoom >= 13.5)
                      MarkerLayer(
                        markers: _buildMarkers(visibleBuildings,
                            selectedBuilding, activeRoute, isDark),
                      ),
                    if (activeRoute != null && activeRoute.length > 1)
                      MarkerLayer(
                        markers: _buildRouteEndpoints(
                            activeRoute, buildingMap, arrived),
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
                  child: _buildHeader(
                      context, isDark, closuresCount, nearestName),
                ),
                Positioned(
                  right: 16,
                  bottom: controlsBottom,
                  child: _buildMapControls(context, isDark, userLocation),
                ),
                MapBottomSheet(
                  guidanceEntryPoint: _guidanceEntryPoint,
                  guidanceEntryDistanceM: _guidanceEntryDistanceM,
                  onStopNavigation: _stopNavigation,
                  onStartQuickRoute: _startQuickRoute,
                ),
                if (arrived)
                  _buildArrivalCard(context, session, buildingMap, isDark),
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

  /// Width of a skywalk line, scaled so the network reads as a clean schematic
  /// when zoomed out and gains presence as you zoom in.
  double _networkWidth() {
    if (_currentZoom >= 16.5) return 5.0;
    if (_currentZoom >= 16.0) return 4.2;
    if (_currentZoom >= 15.0) return 3.4;
    if (_currentZoom >= 13.5) return 2.6;
    return 2.0;
  }

  /// Crisp skywalk lines using real grid-following geometry. Color encodes
  /// status: teal = open, amber = stairs-only / limited access, red = closed.
  List<Polyline> _buildBridgeLines(
    List<Bridge> bridges,
    Map<String, List<LatLng>> bridgePaths,
    bool isDark,
  ) {
    final width = _networkWidth();
    final lines = <Polyline>[];

    for (final bridge in bridges) {
      final points = bridgePaths[bridge.id];
      if (points == null || points.length < 2) continue;

      final isClosed = bridge.status != 'open';
      final notAccessible = !bridge.isAccessible;

      Color color;
      if (isClosed) {
        color = AppPalette.danger.withValues(alpha: 0.85);
      } else if (notAccessible) {
        color = AppPalette.warning.withValues(alpha: 0.9);
      } else {
        color = isDark
            ? AppPalette.skywalkBright.withValues(alpha: 0.92)
            : AppPalette.skywalk;
      }

      lines.add(Polyline(
        points: points,
        strokeWidth: isClosed ? width * 0.7 : width,
        color: color,
        strokeCap: StrokeCap.round,
        strokeJoin: StrokeJoin.round,
        borderStrokeWidth: 1.0,
        borderColor: (isDark ? Colors.black : Colors.white)
            .withValues(alpha: isDark ? 0.35 : 0.7),
      ));
    }
    return lines;
  }

  /// Soft luminous halo beneath open skywalk lines using grid-following paths.
  List<Polyline> _buildNetworkGlow(
    List<Bridge> bridges,
    Map<String, List<LatLng>> bridgePaths,
  ) {
    if (_currentZoom < 13.0) return const [];
    final width = _networkWidth() * 1.9;
    final glow = <Polyline>[];

    for (final bridge in bridges) {
      if (bridge.status != 'open') continue;
      final points = bridgePaths[bridge.id];
      if (points == null || points.length < 2) continue;

      glow.add(Polyline(
        points: points,
        strokeWidth: width,
        strokeCap: StrokeCap.round,
        strokeJoin: StrokeJoin.round,
        color: AppPalette.skywalk.withValues(alpha: 0.10),
      ));
    }
    return glow;
  }

  Polyline _buildRoutePolyline(List<LatLng> smoothedPoints) {
    return Polyline(
      points: smoothedPoints,
      strokeWidth: 6.5,
      color: AppPalette.brand,
      strokeCap: StrokeCap.round,
      strokeJoin: StrokeJoin.round,
      gradientColors: const [AppPalette.brand, AppPalette.skywalk],
      borderStrokeWidth: 2.5,
      borderColor: Colors.white.withValues(alpha: 0.85),
    );
  }

  Polyline _buildRouteGlowPolyline(List<LatLng> smoothedPoints) {
    return Polyline(
      points: smoothedPoints,
      strokeWidth: 16,
      strokeCap: StrokeCap.round,
      strokeJoin: StrokeJoin.round,
      color: AppPalette.skywalkBright.withValues(alpha: 0.32),
      borderStrokeWidth: 0,
    );
  }

  List<Marker> _buildRouteEndpoints(
      List<String> route, Map<String, Building> bMap, bool arrived) {
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
      final endColor =
          arrived ? AppPalette.origin : const Color(0xFFEF4444);
      Widget endDot = Container(
        decoration: BoxDecoration(
          color: endColor,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 3),
          boxShadow: [
            BoxShadow(
              color: endColor.withValues(alpha: 0.4),
              blurRadius: 10,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Icon(arrived ? Icons.check_rounded : Icons.flag_rounded,
            size: 16, color: Colors.white),
      );
      if (arrived) {
        // Signature arrival detail: a gentle spring-bounce on the destination.
        endDot = endDot
            .animate(onPlay: (c) => c.repeat(reverse: true))
            .scaleXY(
                begin: 1.0,
                end: 1.18,
                duration: 700.ms,
                curve: Curves.easeInOut);
      }
      markers.add(Marker(
        point: LatLng(end.lat, end.lng),
        width: 36,
        height: 36,
        child: endDot,
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


  /// Nearest building name for the "You're near …" context line. Only resolves
  /// when we have a fix inside the downtown bounds.
  String? _nearestBuildingName(List<Building> buildings, LatLng? loc) {
    if (loc == null || buildings.isEmpty) return null;
    if (!_isInCalgaryBounds(loc.latitude, loc.longitude)) return null;
    Building? best;
    double bestM = double.infinity;
    for (final b in buildings) {
      final d = _distance(loc, LatLng(b.lat, b.lng));
      if (d < bestM) {
        bestM = d;
        best = b;
      }
    }
    // Only claim "near" if we're plausibly at/in a building.
    if (best == null || bestM > 220) return null;
    return best.name;
  }

  Widget _buildHeader(
      BuildContext context, bool isDark, int closuresCount, String? nearest) {
    final theme = Theme.of(context);
    final surface =
        (isDark ? AppPalette.cardDark : Colors.white).withValues(alpha: 0.82);
    final border = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.black.withValues(alpha: 0.05);

    return Column(
      children: [
        Row(
          children: [
            // Compact brand mark.
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                gradient: AppPalette.brandGradient,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: AppPalette.brand.withValues(alpha: 0.35),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: const Center(
                child: Text('+15',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.5)),
              ),
            ),
            const SizedBox(width: 10),
            // Live context line — the single biggest fix for "where am I?".
            Expanded(child: _contextChip(context, isDark, nearest)),
            const SizedBox(width: 10),
            _circleButton(
              context,
              isDark,
              icon: Icons.notifications_none_rounded,
              badge: closuresCount,
              onTap: () {
                HapticFeedback.lightImpact();
                context.push('/alerts');
              },
            ),
            const SizedBox(width: 8),
            _circleButton(
              context,
              isDark,
              icon: Icons.person_outline_rounded,
              onTap: () {
                HapticFeedback.lightImpact();
                context.go('/settings');
              },
            ),
          ],
        ),
        const SizedBox(height: 10),
        // Tappable search command bar — the primary way to find a place.
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Material(
              color: surface,
              child: InkWell(
                onTap: () {
                  HapticFeedback.lightImpact();
                  context.go('/search');
                },
                child: Container(
                  height: 48,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: border),
                    boxShadow: [
                      BoxShadow(
                        color:
                            Colors.black.withValues(alpha: isDark ? 0.32 : 0.08),
                        blurRadius: 20,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.search_rounded,
                          size: 20,
                          color: isDark
                              ? AppPalette.inkMutedDark
                              : AppPalette.inkMuted),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Search the +15 network',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: isDark
                                ? AppPalette.inkMutedDark
                                : AppPalette.inkMuted,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      _zoomIndicator(),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    ).animate().fadeIn(duration: 400.ms).slideY(
        begin: -0.3, end: 0, duration: 400.ms, curve: Curves.easeOutCubic);
  }

  /// "You're near …" glass pill. Falls back to a network label without a fix.
  Widget _contextChip(BuildContext context, bool isDark, String? nearest) {
    final theme = Theme.of(context);
    final surface =
        (isDark ? AppPalette.cardDark : Colors.white).withValues(alpha: 0.82);
    final border = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.black.withValues(alpha: 0.05);
    final muted = isDark ? AppPalette.inkMutedDark : AppPalette.inkMuted;
    final located = nearest != null;

    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: border),
          ),
          child: Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: located ? AppPalette.origin : AppPalette.warning,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      located ? "You're near" : 'Calgary +15',
                      style: theme.textTheme.labelSmall?.copyWith(
                          color: muted,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.4),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      located ? nearest : 'Finding you…',
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700, height: 1.1),
                      maxLines: 1,
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

  Widget _circleButton(
    BuildContext context,
    bool isDark, {
    required IconData icon,
    required VoidCallback onTap,
    int badge = 0,
  }) {
    final surface =
        (isDark ? AppPalette.cardDark : Colors.white).withValues(alpha: 0.82);
    final border = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.black.withValues(alpha: 0.05);
    final iconColor = isDark ? AppPalette.inkDark : AppPalette.ink;

    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Material(
          color: surface,
          child: InkWell(
            onTap: onTap,
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: border),
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Icon(icon, size: 20, color: iconColor),
                  if (badge > 0)
                    Positioned(
                      top: 8,
                      right: 9,
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        constraints:
                            const BoxConstraints(minWidth: 16, minHeight: 16),
                        decoration: BoxDecoration(
                          color: AppPalette.danger,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: isDark
                                  ? AppPalette.surfaceDark
                                  : Colors.white,
                              width: 1.5),
                        ),
                        child: Text(
                          '$badge',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              height: 1),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _zoomIndicator() {
    final level = _currentZoom >= 16.0
        ? 'Detail'
        : _currentZoom >= 15.0
            ? 'Standard'
            : 'Overview';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: AppPalette.skywalk.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        level,
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: AppPalette.skywalk,
        ),
      ),
    );
  }

  /// Tears down an active route + navigation session. Mirrors the provider
  /// writes the old route banner's close button performed, including resetting
  /// the entry-point guidance held on this State.
  void _stopNavigation() {
    ref.read(activeRouteProvider.notifier).state = null;
    ref.read(activeRouteDistanceProvider.notifier).state = 0;
    ref.read(navigationSessionProvider.notifier).stop();
    _guidanceEntryPoint = null;
    _guidanceEntryDistanceM = null;
    _offRouteStrikes = 0;
    if (mounted) setState(() {});
  }

  /// The arrival moment — a calm, celebratory card that slides up over the map
  /// when navigation completes. Tasteful, no confetti (per the design spec).
  Widget _buildArrivalCard(BuildContext context, NavigationSession session,
      Map<String, Building> bMap, bool isDark) {
    final theme = Theme.of(context);
    final dest =
        session.destinationId == null ? null : bMap[session.destinationId!];
    final destName = dest?.name ?? 'your destination';
    final bottomInset = MediaQuery.of(context).padding.bottom;

    return Positioned(
      left: 16,
      right: 16,
      bottom: AppDims.navBarHeight + (bottomInset > 0 ? bottomInset : 14) + 24,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: isDark ? AppPalette.cardDark : Colors.white,
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
                  child: const Icon(Icons.check_circle_rounded,
                      color: AppPalette.origin, size: 26),
                )
                    .animate()
                    .scale(duration: 360.ms, curve: Curves.easeOutBack),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("You've arrived",
                          style: theme.textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w800)),
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
                    label: const Text('Save place'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppPalette.brand,
                      side: BorderSide(
                          color: AppPalette.brand.withValues(alpha: 0.4)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: AppRadii.rControl),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: FilledButton(
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      _stopNavigation();
                    },
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: AppRadii.rControl),
                    ),
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
    if (route == null || route.length < 2) {
      _stopNavigation();
      return;
    }
    final buildings =
        ref.read(buildingsProvider).valueOrNull ?? const <Building>[];
    final bMap = {for (final b in buildings) b.id: b};
    final fromName = bMap[route.first]?.name ?? route.first;
    final toName = bMap[route.last]?.name ?? route.last;
    final now = DateTime.now();
    ref.read(savedRoutesProvider.notifier).add(
          SavedRoute(
            id: '${route.first}_${route.last}_${now.millisecondsSinceEpoch}',
            name: '$fromName → $toName',
            fromId: route.first,
            toId: route.last,
            routeType: session.mode,
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
          ? const Color(0xFF4F46E5)
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
                    ? const Color(0xFF4F46E5).withValues(alpha: 0.3)
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
                color: const Color(0xFF4F46E5)
                    .withValues(alpha: 0.15 * (1 - pulse)),
              ),
            ),
            Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF4F46E5),
                border: Border.all(color: Colors.white, width: 3),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF4F46E5).withValues(alpha: 0.4),
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
        ? const Color(0xFF4F46E5)
        : isOnRoute
            ? const Color(0xFF4F46E5).withValues(alpha: 0.9)
            : isDark
                ? const Color(0xFF18181B).withValues(alpha: 0.92)
                : Colors.white.withValues(alpha: 0.95);

    final textColor = isSelected || isOnRoute
        ? Colors.white
        : isDark
            ? const Color(0xFFE4E4E7)
            : const Color(0xFF27272A);

    final borderColor = isSelected
        ? const Color(0xFF4F46E5)
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
                color: const Color(0xFF4F46E5).withValues(alpha: 0.3),
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
