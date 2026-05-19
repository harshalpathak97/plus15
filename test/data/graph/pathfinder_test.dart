import 'package:flutter_test/flutter_test.dart';
import 'package:plus15_navigator/data/graph/cost_models.dart';
import 'package:plus15_navigator/data/graph/pathfinder.dart';
import 'package:plus15_navigator/data/graph/plus15_graph.dart';
import 'package:plus15_navigator/data/models/bridge.dart';
import 'package:plus15_navigator/data/models/building.dart';

Plus15Graph _miniGraph() {
  final buildings = [
    const Building(id: 'a', name: 'A', lat: 51.05, lng: -114.07, type: 'office'),
    const Building(id: 'b', name: 'B', lat: 51.05, lng: -114.069, type: 'office'),
    const Building(id: 'c', name: 'C', lat: 51.05, lng: -114.068, type: 'office'),
    const Building(id: 'd', name: 'D', lat: 51.05, lng: -114.067, type: 'office'),
  ];
  final bridges = [
    const Bridge(
        id: 'ab',
        fromBuildingId: 'a',
        toBuildingId: 'b',
        distanceM: 100,
        isAccessible: true),
    const Bridge(
        id: 'bc',
        fromBuildingId: 'b',
        toBuildingId: 'c',
        distanceM: 60,
        isAccessible: false,
        hasElevator: false),
    const Bridge(
        id: 'cd',
        fromBuildingId: 'c',
        toBuildingId: 'd',
        distanceM: 80,
        isAccessible: true),
    const Bridge(
        id: 'ad',
        fromBuildingId: 'a',
        toBuildingId: 'd',
        distanceM: 320,
        isAccessible: true,
        scenicScore: 0.95),
    const Bridge(
        id: 'ac_closed',
        fromBuildingId: 'a',
        toBuildingId: 'c',
        distanceM: 120,
        isAccessible: true,
        status: 'closed'),
  ];
  return Plus15Graph(buildings: buildings, bridges: bridges);
}

void main() {
  group('Pathfinder', () {
    test('fastest picks shortest distance path', () {
      final pf = Pathfinder(graph: _miniGraph(), shops: const []);
      final r = pf.findRouteWith('a', 'd', cost: const FastestCost());
      expect(r, isNotNull);
      // a->b->c->d totals 240 vs direct a->d at 320 — A* should prefer the chain
      expect(r!.path, equals(['a', 'b', 'c', 'd']));
      expect(r.bridgeCount, 3);
    });

    test('accessible mode rejects non-accessible bridges', () {
      final pf = Pathfinder(graph: _miniGraph(), shops: const []);
      final r = pf.findRouteWith('a', 'd', cost: const AccessibleCost());
      expect(r, isNotNull);
      // b->c is non-accessible, so we must route via a->d directly.
      expect(r!.path, equals(['a', 'd']));
      expect(r.fullyAccessible, isTrue);
    });

    test('respectClosures hides closed bridges', () {
      final pf = Pathfinder(graph: _miniGraph(), shops: const []);
      final r =
          pf.findRouteWith('a', 'c', cost: const FastestCost());
      expect(r, isNotNull);
      // a->c closed: must go a->b->c
      expect(r!.path, equals(['a', 'b', 'c']));
    });

    test('scenic mode prefers the high-scenic edge', () {
      final pf = Pathfinder(graph: _miniGraph(), shops: const []);
      final r = pf.findRouteWith('a', 'd', cost: const ScenicCost());
      expect(r, isNotNull);
      // The direct a->d edge has scenicScore=0.95 which makes its
      // weighted cost competitive with the chained 240m route.
      expect(r!.path, equals(['a', 'd']));
    });

    test('Pareto returns non-dominated routes', () {
      final pf = Pathfinder(graph: _miniGraph(), shops: const []);
      final routes = pf.findParetoRoutes('a', 'd');
      expect(routes, isNotEmpty);
      for (final a in routes) {
        for (final b in routes) {
          if (identical(a, b)) continue;
          final dominates = a.totalDistanceM <= b.totalDistanceM &&
              a.bridgeCount <= b.bridgeCount &&
              a.floorChanges <= b.floorChanges &&
              (a.totalDistanceM < b.totalDistanceM ||
                  a.bridgeCount < b.bridgeCount ||
                  a.floorChanges < b.floorChanges);
          expect(dominates, isFalse,
              reason: 'Route ${a.modeName} dominates ${b.modeName}');
        }
      }
    });
  });
}
