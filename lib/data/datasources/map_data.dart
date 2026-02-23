import 'dart:convert';
import 'package:flutter/services.dart';
import '../models/building.dart';
import '../models/bridge.dart';
import '../models/shop.dart';

class MapDataSource {
  List<Building>? _buildings;
  List<Bridge>? _bridges;
  List<Shop>? _shops;

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
}
