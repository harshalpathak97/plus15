import 'dart:convert';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/saved_route.dart';

class LocalStorage {
  static const _routesBox = 'saved_routes';
  static const _prefsBox = 'preferences';
  static const _placesBox = 'saved_places';

  Future<void> init() async {
    await Hive.initFlutter();
    await _open<String>(_routesBox);
    await _open<dynamic>(_prefsBox);
    await _open<String>(_placesBox);
  }

  /// A corrupt box must not keep the app on the splash screen: drop it and
  /// start that box empty.
  static Future<void> _open<T>(String name) async {
    try {
      await Hive.openBox<T>(name);
    } catch (_) {
      await Hive.deleteBoxFromDisk(name);
      await Hive.openBox<T>(name);
    }
  }

  /// 'light' (default) or 'dark'.
  String getThemeMode() {
    if (!Hive.isBoxOpen(_prefsBox)) return 'light';
    return Hive.box<dynamic>(_prefsBox).get('themeMode', defaultValue: 'light') as String;
  }

  Future<void> setThemeMode(String mode) =>
      Hive.box<dynamic>(_prefsBox).put('themeMode', mode);

  /// Saved places (shop ids).
  Set<String> getSavedPlaces() {
    if (!Hive.isBoxOpen(_placesBox)) return {};
    return Hive.box<String>(_placesBox).keys.cast<String>().toSet();
  }

  Future<void> setPlaceSaved(String shopId, bool saved) {
    final box = Hive.box<String>(_placesBox);
    return saved ? box.put(shopId, shopId) : box.delete(shopId);
  }

  List<SavedRoute> getSavedRoutes() {
    final box = Hive.box<String>(_routesBox);
    final routes = <SavedRoute>[];
    for (final e in box.values) {
      try {
        routes.add(SavedRoute.fromJson(json.decode(e)));
      } catch (_) {
        // Skip an entry this version can't read rather than lose them all.
      }
    }
    return routes
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  Future<void> saveRoute(SavedRoute route) async {
    final box = Hive.box<String>(_routesBox);
    await box.put(route.id, json.encode(route.toJson()));
  }

  Future<void> deleteRoute(String id) async {
    final box = Hive.box<String>(_routesBox);
    await box.delete(id);
  }

  Future<void> updateRoute(SavedRoute route) async {
    await saveRoute(route);
  }

  double getWalkingSpeed() {
    final box = Hive.box<dynamic>(_prefsBox);
    return box.get('walkingSpeed', defaultValue: 4.5) as double;
  }

  Future<void> setWalkingSpeed(double speed) async {
    final box = Hive.box<dynamic>(_prefsBox);
    await box.put('walkingSpeed', speed);
  }

  bool getAccessibilityMode() {
    final box = Hive.box<dynamic>(_prefsBox);
    return box.get('accessibilityMode', defaultValue: false) as bool;
  }

  Future<void> setAccessibilityMode(bool value) async {
    final box = Hive.box<dynamic>(_prefsBox);
    await box.put('accessibilityMode', value);
  }

  String? getBasemap() {
    final box = Hive.box<dynamic>(_prefsBox);
    return box.get('basemap') as String?;
  }

  Future<void> setBasemap(String name) async {
    final box = Hive.box<dynamic>(_prefsBox);
    await box.put('basemap', name);
  }

  bool getDebugGraph() {
    final box = Hive.box<dynamic>(_prefsBox);
    return box.get('debugGraph', defaultValue: false) as bool;
  }

  Future<void> setDebugGraph(bool value) async {
    final box = Hive.box<dynamic>(_prefsBox);
    await box.put('debugGraph', value);
  }

  /// The user agreed to send Ask +15 questions to the AI provider.
  bool getAiConsent() =>
      Hive.box<dynamic>(_prefsBox).get('aiConsent', defaultValue: false) as bool;

  Future<void> setAiConsent(bool value) =>
      Hive.box<dynamic>(_prefsBox).put('aiConsent', value);

  bool getOnboardingComplete() {
    final box = Hive.box<dynamic>(_prefsBox);
    return box.get('onboardingComplete', defaultValue: false) as bool;
  }

  Future<void> setOnboardingComplete(bool value) async {
    final box = Hive.box<dynamic>(_prefsBox);
    await box.put('onboardingComplete', value);
  }
}
