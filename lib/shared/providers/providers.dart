import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import '../../data/datasources/map_data.dart';
import '../../data/datasources/local_storage.dart';
import '../../data/models/building.dart';
import '../../data/models/bridge.dart';
import '../../data/models/entry_point.dart';
import '../../data/models/map_overlay_config.dart';
import '../../data/models/shop.dart';
import '../../data/models/saved_route.dart';
import '../../data/graph/plus15_graph.dart';
import '../../data/graph/pathfinder.dart';

final mapDataSourceProvider = Provider((_) => MapDataSource());
final localStorageProvider = Provider((_) => LocalStorage());

final buildingsProvider = FutureProvider<List<Building>>((ref) {
  return ref.read(mapDataSourceProvider).loadBuildings();
});

final bridgesProvider = FutureProvider<List<Bridge>>((ref) {
  return ref.read(mapDataSourceProvider).loadBridges();
});

final shopsProvider = FutureProvider<List<Shop>>((ref) {
  return ref.read(mapDataSourceProvider).loadShops();
});

final entryPointsProvider = FutureProvider<List<EntryPoint>>((ref) {
  return ref.read(mapDataSourceProvider).loadEntryPoints();
});

final overlayConfigProvider = FutureProvider<MapOverlayConfig>((ref) {
  return ref.read(mapDataSourceProvider).loadOverlayConfig();
});

final graphProvider = FutureProvider<Plus15Graph>((ref) async {
  final buildings = await ref.watch(buildingsProvider.future);
  final bridges = await ref.watch(bridgesProvider.future);
  return Plus15Graph(buildings: buildings, bridges: bridges);
});

final pathfinderProvider = FutureProvider<Pathfinder>((ref) async {
  final graph = await ref.watch(graphProvider.future);
  final shops = await ref.watch(shopsProvider.future);
  return Pathfinder(graph: graph, shops: shops);
});

final themeModeProvider = StateNotifierProvider<ThemeModeNotifier, ThemeMode>(
  (ref) => ThemeModeNotifier(ref.read(localStorageProvider)),
);

class ThemeModeNotifier extends StateNotifier<ThemeMode> {
  final LocalStorage _storage;

  ThemeModeNotifier(this._storage) : super(ThemeMode.system) {
    _load();
  }

  void _load() {
    final mode = _storage.getThemeMode();
    state = _fromString(mode);
  }

  Future<void> setMode(ThemeMode mode) async {
    state = mode;
    await _storage.setThemeMode(_toString(mode));
  }

  ThemeMode _fromString(String s) {
    switch (s) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  String _toString(ThemeMode m) {
    switch (m) {
      case ThemeMode.light:
        return 'light';
      case ThemeMode.dark:
        return 'dark';
      default:
        return 'system';
    }
  }
}

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

final selectedBuildingProvider = StateProvider<Building?>((ref) => null);

final searchQueryProvider = StateProvider<String>((ref) => '');

final selectedCategoryProvider = StateProvider<String?>((ref) => null);

final routeFromProvider = StateProvider<Building?>((ref) => null);
final routeToProvider = StateProvider<Building?>((ref) => null);
final routeModeProvider = StateProvider<String>((ref) => 'fastest');

final activeRouteProvider = StateProvider<List<String>?>((ref) => null);
final activeRouteDistanceProvider = StateProvider<double>((ref) => 0);

enum NavigationStatus {
  inactive,
  headingToEntry,
  onCourse,
  rerouting,
  arrived,
}

class NavigationSession {
  final bool isActive;
  final String? destinationId;
  final String mode;
  final NavigationStatus status;
  final String? entryPointId;
  final List<String>? routePath;
  final double totalDistanceM;
  final double remainingDistanceM;
  final String? nextNodeId;
  final double confidence;
  final int offRouteStrikes;

  const NavigationSession({
    this.isActive = false,
    this.destinationId,
    this.mode = 'fastest',
    this.status = NavigationStatus.inactive,
    this.entryPointId,
    this.routePath,
    this.totalDistanceM = 0,
    this.remainingDistanceM = 0,
    this.nextNodeId,
    this.confidence = 0,
    this.offRouteStrikes = 0,
  });

  NavigationSession copyWith({
    bool? isActive,
    String? destinationId,
    String? mode,
    NavigationStatus? status,
    String? entryPointId,
    List<String>? routePath,
    double? totalDistanceM,
    double? remainingDistanceM,
    String? nextNodeId,
    double? confidence,
    int? offRouteStrikes,
    bool clearEntryPoint = false,
    bool clearRoute = false,
    bool clearNextNode = false,
  }) {
    return NavigationSession(
      isActive: isActive ?? this.isActive,
      destinationId: destinationId ?? this.destinationId,
      mode: mode ?? this.mode,
      status: status ?? this.status,
      entryPointId:
          clearEntryPoint ? null : (entryPointId ?? this.entryPointId),
      routePath: clearRoute ? null : (routePath ?? this.routePath),
      totalDistanceM: totalDistanceM ?? this.totalDistanceM,
      remainingDistanceM: remainingDistanceM ?? this.remainingDistanceM,
      nextNodeId: clearNextNode ? null : (nextNodeId ?? this.nextNodeId),
      confidence: confidence ?? this.confidence,
      offRouteStrikes: offRouteStrikes ?? this.offRouteStrikes,
    );
  }
}

class NavigationSessionNotifier extends StateNotifier<NavigationSession> {
  NavigationSessionNotifier() : super(const NavigationSession());

  void start({
    required String destinationId,
    required String mode,
    required List<String> routePath,
    required double totalDistanceM,
  }) {
    state = NavigationSession(
      isActive: true,
      destinationId: destinationId,
      mode: mode,
      status: NavigationStatus.onCourse,
      routePath: routePath,
      totalDistanceM: totalDistanceM,
      remainingDistanceM: totalDistanceM,
      confidence: 1,
      offRouteStrikes: 0,
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

final userLocationProvider = Provider<AsyncValue<LatLng?>>((ref) {
  return ref.watch(locationStreamProvider);
});

final mapZoomProvider = StateProvider<double>((ref) => 15.2);
