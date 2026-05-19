import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:plus15_navigator/data/models/bridge.dart';
import 'package:plus15_navigator/data/models/building.dart';

/// Smoke test that reads the bundled JSON directly from disk (faster and
/// works in plain `flutter test` without `ServicesBinding`) and asserts the
/// +15 graph remains well-connected. Fail this and the network is split.
void main() {
  test('Plus15 graph is mostly connected', () async {
    final buildings = _loadBuildings();
    final bridges = _loadBridges();

    final adj = <String, List<String>>{};
    for (final b in buildings) {
      adj[b.id] = [];
    }
    for (final br in bridges) {
      adj[br.fromBuildingId]?.add(br.toBuildingId);
      adj[br.toBuildingId]?.add(br.fromBuildingId);
    }

    // Anchor at The Bow — it's the most-connected landmark.
    expect(adj.containsKey('the_bow'), isTrue,
        reason: 'Anchor building missing');
    final visited = <String>{};
    final q = Queue<String>()..add('the_bow');
    while (q.isNotEmpty) {
      final n = q.removeFirst();
      if (!visited.add(n)) continue;
      for (final next in adj[n] ?? const []) {
        if (!visited.contains(next)) q.add(next);
      }
    }

    final ratio = visited.length / buildings.length;
    expect(ratio, greaterThanOrEqualTo(0.85),
        reason:
            'Only ${visited.length}/${buildings.length} buildings reachable '
            'from the_bow. Likely a missing bridge.');
  });

  test('every bridge endpoint exists in buildings.json', () {
    final buildings = _loadBuildings();
    final bridges = _loadBridges();
    final ids = buildings.map((b) => b.id).toSet();

    for (final br in bridges) {
      expect(ids.contains(br.fromBuildingId), isTrue,
          reason: '${br.id}: missing from-building ${br.fromBuildingId}');
      expect(ids.contains(br.toBuildingId), isTrue,
          reason: '${br.id}: missing to-building ${br.toBuildingId}');
    }
  });

  test('lat/lng are inside downtown Calgary bounds', () {
    final buildings = _loadBuildings();
    for (final b in buildings) {
      expect(b.lat, inInclusiveRange(50.90, 51.20),
          reason: '${b.id} lat ${b.lat} out of bounds');
      expect(b.lng, inInclusiveRange(-114.30, -113.85),
          reason: '${b.id} lng ${b.lng} out of bounds');
    }
  });
}

List<Building> _loadBuildings() {
  final raw = File('assets/data/buildings.json').readAsStringSync();
  final list = json.decode(raw) as List;
  return list
      .map((e) => Building.fromJson(e as Map<String, dynamic>))
      .toList();
}

List<Bridge> _loadBridges() {
  final raw = File('assets/data/bridges.json').readAsStringSync();
  final list = json.decode(raw) as List;
  return list
      .map((e) => Bridge.fromJson(e as Map<String, dynamic>))
      .toList();
}
