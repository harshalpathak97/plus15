import 'dart:convert';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/saved_route.dart';

class LocalStorage {
  static const _routesBox = 'saved_routes';
  static const _prefsBox = 'preferences';

  Future<void> init() async {
    await Hive.initFlutter();
    await Hive.openBox<String>(_routesBox);
    await Hive.openBox<dynamic>(_prefsBox);
  }

  List<SavedRoute> getSavedRoutes() {
    final box = Hive.box<String>(_routesBox);
    return box.values
        .map((e) => SavedRoute.fromJson(json.decode(e)))
        .toList()
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

  String getThemeMode() {
    final box = Hive.box<dynamic>(_prefsBox);
    return box.get('themeMode', defaultValue: 'system') as String;
  }

  Future<void> setThemeMode(String mode) async {
    final box = Hive.box<dynamic>(_prefsBox);
    await box.put('themeMode', mode);
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

  bool getOnboardingComplete() {
    final box = Hive.box<dynamic>(_prefsBox);
    return box.get('onboardingComplete', defaultValue: false) as bool;
  }

  Future<void> setOnboardingComplete(bool value) async {
    final box = Hive.box<dynamic>(_prefsBox);
    await box.put('onboardingComplete', value);
  }
}
