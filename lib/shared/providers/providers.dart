import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import '../../data/datasources/map_data.dart';
import '../../data/datasources/local_storage.dart';
import '../../data/models/shop.dart';
import '../../data/models/saved_route.dart';
import '../../data/models/walkway_footprint.dart';
import '../../features/map/basemap.dart';
import '../../routing/conditions.dart';
import '../../routing/network.dart';
import '../../routing/router.dart';

final mapDataSourceProvider = Provider((_) => MapDataSource());
final localStorageProvider = Provider((_) => LocalStorage());

/// The routing network (assets/data/network.json): the single source of
/// truth for buildings, City walkway polygons, nodes and edges.
final networkProvider = FutureProvider<Plus15Network>((ref) {
  return ref.read(mapDataSourceProvider).loadNetwork();
});

final closuresProvider = FutureProvider<ClosureFeed>((ref) {
  return ref.read(mapDataSourceProvider).loadClosures();
});

final conditionsProvider = FutureProvider<Conditions>((ref) async {
  final net = await ref.watch(networkProvider.future);
  final feed = await ref.watch(closuresProvider.future);
  return Conditions(net, feed.closures);
});

final routerProvider = FutureProvider<Plus15Router>((ref) async {
  final net = await ref.watch(networkProvider.future);
  return Plus15Router(net, await ref.watch(conditionsProvider.future));
});

final buildingsProvider = FutureProvider<List<NetBuilding>>((ref) async {
  return (await ref.watch(networkProvider.future)).buildings;
});

final shopsProvider = FutureProvider<List<Shop>>((ref) {
  return ref.read(mapDataSourceProvider).loadShops();
});

/// City walkway footprints for the 3D view, from the same network data.
final walkwayFootprintsProvider =
    FutureProvider<List<WalkwayFootprint>>((ref) async {
  final net = await ref.watch(networkProvider.future);
  return [
    for (final r in net.regions)
      if (r.excluded == null) WalkwayFootprint.fromRegion(r)
  ];
});

final savedRoutesProvider =
    StateNotifierProvider<SavedRoutesNotifier, List<SavedRoute>>(
  (ref) => SavedRoutesNotifier(ref.read(localStorageProvider)),
);

class SavedRoutesNotifier extends StateNotifier<List<SavedRoute>> {
  final LocalStorage _storage;

  SavedRoutesNotifier(this._storage) : super([]) {
    _load();
  }

  void _load() {
    state = _storage.getSavedRoutes();
  }

  Future<void> add(SavedRoute route) async {
    await _storage.saveRoute(route);
    state = _storage.getSavedRoutes();
  }

  Future<void> remove(String id) async {
    await _storage.deleteRoute(id);
    state = _storage.getSavedRoutes();
  }

  Future<void> update(SavedRoute route) async {
    await _storage.updateRoute(route);
    state = _storage.getSavedRoutes();
  }
}

class WalkingSpeedNotifier extends StateNotifier<double> {
  final LocalStorage _storage;

  WalkingSpeedNotifier(this._storage)
      : super(_storage.getWalkingSpeed().clamp(2.0, 7.0).toDouble());

  Future<void> setSpeed(double speed) async {
    final normalized = speed.clamp(2.0, 7.0).toDouble();
    state = normalized;
    await _storage.setWalkingSpeed(normalized);
  }
}

final walkingSpeedProvider =
    StateNotifierProvider<WalkingSpeedNotifier, double>(
  (ref) => WalkingSpeedNotifier(ref.read(localStorageProvider)),
);

class AccessibilityModeNotifier extends StateNotifier<bool> {
  final LocalStorage _storage;

  AccessibilityModeNotifier(this._storage)
      : super(_storage.getAccessibilityMode());

  Future<void> setEnabled(bool value) async {
    state = value;
    await _storage.setAccessibilityMode(value);
  }
}

final accessibilityModeProvider =
    StateNotifierProvider<AccessibilityModeNotifier, bool>(
  (ref) => AccessibilityModeNotifier(ref.read(localStorageProvider)),
);

final selectedBuildingProvider = StateProvider<NetBuilding?>((ref) => null);

final searchQueryProvider = StateProvider<String>((ref) => '');

final selectedCategoryProvider = StateProvider<String?>((ref) => null);

final routeFromProvider = StateProvider<NetBuilding?>((ref) => null);
/// Start from the phone's location instead of [routeFromProvider].
final routeFromMyLocationProvider = StateProvider<bool>((ref) => false);
final routeToProvider = StateProvider<NetBuilding?>((ref) => null);

/// The route being shown/navigated: exactly the graph edges it uses.
final activeRouteProvider = StateProvider<PlannedRoute?>((ref) => null);

enum NavigationStatus {
  inactive,
  onCourse,
  rerouting,
  arrived,
}

class NavigationSession {
  final bool isActive;
  final String? destinationId;
  final RouteProfile profile;
  final NavigationStatus status;
  final double totalDistanceM;
  final double remainingDistanceM;
  /// Index into the active route's steps of the instruction to follow next.
  final int stepIndex;
  /// Distance from the drawn route at the last GPS fix.
  final double offRouteM;
  final int offRouteStrikes;

  const NavigationSession({
    this.isActive = false,
    this.destinationId,
    this.profile = RouteProfile.fastest,
    this.status = NavigationStatus.inactive,
    this.totalDistanceM = 0,
    this.remainingDistanceM = 0,
    this.stepIndex = 0,
    this.offRouteM = 0,
    this.offRouteStrikes = 0,
  });

  NavigationSession copyWith({
    NavigationStatus? status,
    double? totalDistanceM,
    double? remainingDistanceM,
    int? stepIndex,
    double? offRouteM,
    int? offRouteStrikes,
  }) {
    return NavigationSession(
      isActive: isActive,
      destinationId: destinationId,
      profile: profile,
      status: status ?? this.status,
      totalDistanceM: totalDistanceM ?? this.totalDistanceM,
      remainingDistanceM: remainingDistanceM ?? this.remainingDistanceM,
      stepIndex: stepIndex ?? this.stepIndex,
      offRouteM: offRouteM ?? this.offRouteM,
      offRouteStrikes: offRouteStrikes ?? this.offRouteStrikes,
    );
  }
}

class NavigationSessionNotifier extends StateNotifier<NavigationSession> {
  NavigationSessionNotifier() : super(const NavigationSession());

  void start({required PlannedRoute route}) {
    state = NavigationSession(
      isActive: true,
      destinationId: route.destinationBuildingId,
      profile: route.profile,
      status: NavigationStatus.onCourse,
      totalDistanceM: route.lengthM,
      remainingDistanceM: route.lengthM,
    );
  }

  void update(NavigationSession session) {
    state = session;
  }

  void stop() {
    state = const NavigationSession();
  }
}

final navigationSessionProvider =
    StateNotifierProvider<NavigationSessionNotifier, NavigationSession>(
  (ref) => NavigationSessionNotifier(),
);

Future<bool> _hasLocationPermission() async {
  final serviceEnabled = await Geolocator.isLocationServiceEnabled();
  if (!serviceEnabled) return false;

  var permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
  }
  return permission == LocationPermission.always ||
      permission == LocationPermission.whileInUse;
}

final locationStreamProvider = StreamProvider<LatLng?>((ref) async* {
  final isNavigationActive =
      ref.watch(navigationSessionProvider.select((s) => s.isActive));
  final allowed = await _hasLocationPermission();
  if (!allowed) {
    yield null;
    return;
  }

  final activeSettings = const LocationSettings(
    accuracy: LocationAccuracy.bestForNavigation,
    distanceFilter: 4,
  );
  final passiveSettings = const LocationSettings(
    accuracy: LocationAccuracy.high,
    distanceFilter: 30,
  );
  final settings = isNavigationActive ? activeSettings : passiveSettings;

  try {
    final initial = await Geolocator.getCurrentPosition(
      locationSettings: settings,
    );
    yield LatLng(initial.latitude, initial.longitude);
  } catch (_) {
    yield null;
  }

  yield* Geolocator.getPositionStream(locationSettings: settings).map(
    (pos) => LatLng(pos.latitude, pos.longitude),
  );
});

/// The base map style under the +15 overlay (persisted).
class BasemapNotifier extends StateNotifier<Basemap> {
  final LocalStorage _storage;
  BasemapNotifier(this._storage) : super(Basemap.fromName(_storage.getBasemap()));

  Future<void> select(Basemap b) async {
    state = b;
    await _storage.setBasemap(b.name);
  }
}

final basemapProvider = StateNotifierProvider<BasemapNotifier, Basemap>(
  (ref) => BasemapNotifier(ref.read(localStorageProvider)),
);

/// Shows the routing graph (nodes, edges, sources, confidence) on the map.
class DebugGraphNotifier extends StateNotifier<bool> {
  final LocalStorage _storage;
  DebugGraphNotifier(this._storage) : super(_storage.getDebugGraph());

  Future<void> setEnabled(bool value) async {
    state = value;
    await _storage.setDebugGraph(value);
  }
}

final debugGraphProvider = StateNotifierProvider<DebugGraphNotifier, bool>(
  (ref) => DebugGraphNotifier(ref.read(localStorageProvider)),
);

/// Profile to plan with by default: Accessible when the user asked for
/// step-free routes.
RouteProfile defaultProfile(bool accessibilityMode) =>
    accessibilityMode ? RouteProfile.accessible : RouteProfile.fastest;

/// Saved routes store the old mode names; map them onto today's profiles.
RouteProfile profileFromName(String name) => switch (name) {
      'accessible' => RouteProfile.accessible,
      'mostlyIndoors' => RouteProfile.mostlyIndoors,
      _ => RouteProfile.fastest, // 'fastest' and the retired 'explorer'
    };

/// Light by default; dark only when the user turns it on in Settings.
class ThemeModeNotifier extends StateNotifier<ThemeMode> {
  final LocalStorage _storage;
  ThemeModeNotifier(this._storage)
      : super(_storage.getThemeMode() == 'dark' ? ThemeMode.dark : ThemeMode.light);

  Future<void> setDark(bool dark) async {
    state = dark ? ThemeMode.dark : ThemeMode.light;
    await _storage.setThemeMode(dark ? 'dark' : 'light');
  }
}

final themeModeProvider = StateNotifierProvider<ThemeModeNotifier, ThemeMode>(
  (ref) => ThemeModeNotifier(ref.read(localStorageProvider)),
);

/// Saved places (shop ids), persisted.
class SavedPlacesNotifier extends StateNotifier<Set<String>> {
  final LocalStorage _storage;
  SavedPlacesNotifier(this._storage) : super(_storage.getSavedPlaces());

  bool isSaved(String id) => state.contains(id);

  Future<void> toggle(String id) async {
    final saved = !state.contains(id);
    state = saved ? {...state, id} : ({...state}..remove(id));
    await _storage.setPlaceSaved(id, saved);
  }
}

final savedPlacesProvider = StateNotifierProvider<SavedPlacesNotifier, Set<String>>(
  (ref) => SavedPlacesNotifier(ref.read(localStorageProvider)),
);
