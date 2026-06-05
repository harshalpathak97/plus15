import 'dart:convert';
import 'package:flutter/services.dart';
import '../models/building.dart';
import '../models/bridge.dart';
import '../models/entry_point.dart';
import '../models/shop.dart';

class MapDataSource {
  List<Building>? _buildings;
  List<Bridge>? _bridges;
  List<Shop>? _shops;
  List<EntryPoint>? _entryPoints;

  Future<List<Building>> loadBuildings() async {
    if (_buildings != null) return _buildings!;
    final raw = await rootBundle.loadString('assets/data/buildings.json');
    final list = json.decode(raw) as List;
    _buildings = list.map((e) => Building.fromJson(e)).toList();
    return _buildings!;
  }

  Future<List<Bridge>> loadBridges() async {
    if (_bridges != null) return _bridges!;
    final raw = await rootBundle.loadString('assets/data/bridges.json');
    final list = json.decode(raw) as List;
    _bridges = list.map((e) => Bridge.fromJson(e)).toList();
    return _bridges!;
  }

  Future<List<Shop>> loadShops() async {
    if (_shops != null) return _shops!;
    final raw = await rootBundle.loadString('assets/data/shops.json');
    final list = json.decode(raw) as List;
    _shops = list.map((e) => Shop.fromJson(e)).toList();
    return _shops!;
  }

  Future<List<EntryPoint>> loadEntryPoints() async {
    if (_entryPoints != null) return _entryPoints!;
    final raw = await rootBundle.loadString('assets/data/entry_points.json');
    final list = json.decode(raw) as List;
    _entryPoints = list.map((e) => EntryPoint.fromJson(e)).toList();
    return _entryPoints!;
  }

  /// Returns the per-bridge intermediate waypoints from bridge_geometry.json.
  /// Keys are bridge IDs; each value is a list of [lat, lng] pairs.
  Future<Map<String, List<List<double>>>> loadBridgeGeometry() async {
    final raw =
        await rootBundle.loadString('assets/data/bridge_geometry.json');
    final map = json.decode(raw) as Map<String, dynamic>;
    return map.map((id, waypoints) {
      final pts = (waypoints as List)
          .map((p) => [(p as List)[0] as double, p[1] as double])
          .toList();
      return MapEntry(id, pts);
    });
  }
}
