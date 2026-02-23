import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import '../../data/datasources/map_data.dart';
import '../../data/datasources/local_storage.dart';
import '../../data/models/building.dart';
import '../../data/models/bridge.dart';
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

final selectedBuildingProvider = StateProvider<Building?>((ref) => null);

final searchQueryProvider = StateProvider<String>((ref) => '');

final selectedCategoryProvider = StateProvider<String?>((ref) => null);

final routeFromProvider = StateProvider<Building?>((ref) => null);
final routeToProvider = StateProvider<Building?>((ref) => null);
final routeModeProvider = StateProvider<String>((ref) => 'fastest');

final activeRouteProvider = StateProvider<List<String>?>((ref) => null);
final activeRouteDistanceProvider = StateProvider<double>((ref) => 0);

final userLocationProvider =
    StateNotifierProvider<UserLocationNotifier, AsyncValue<LatLng?>>(
  (ref) => UserLocationNotifier(),
);

class UserLocationNotifier extends StateNotifier<AsyncValue<LatLng?>> {
  UserLocationNotifier() : super(const AsyncValue.data(null));

  Future<void> fetchLocation() async {
    state = const AsyncValue.loading();
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        state = const AsyncValue.data(null);
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied ||
            permission == LocationPermission.deniedForever) {
          state = const AsyncValue.data(null);
          return;
        }
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );
      state = AsyncValue.data(LatLng(position.latitude, position.longitude));
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }
}

final mapZoomProvider = StateProvider<double>((ref) => 15.2);
