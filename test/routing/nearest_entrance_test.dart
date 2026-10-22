import 'package:flutter_test/flutter_test.dart';
import 'package:plus15_navigator/routing/geo.dart';
import 'package:plus15_navigator/routing/route_validator.dart';
import 'package:plus15_navigator/routing/router.dart';

import 'support.dart';

void main() {
  group('nearest +15 entrance', () {
    // 9 Ave SW by the Calgary Tower, outdoors.
    const tower = RouteOrigin.location(51.0440, -114.0620);

    test('ranks doors by the walk along sidewalks, not the straight line', () {
      final e = router.nearestEntrances(tower, at: clearDay);
      expect(e.ok, isTrue, reason: e.unavailableReason);
      expect(e.approximate, isFalse);
      expect(e.routes.length, 5);
      final walks = [for (final r in e.routes) r.lengthM];
      expect(walks, orderedEquals([...walks]..sort()));
      final air = [
        for (final r in e.routes)
          project(r.doorPoint![0], r.doorPoint![1]).dist(project(tower.lat!, tower.lng!))
      ];
      // At least one nearer-by-air door ranks lower because it is a longer walk.
      expect(air, isNot(orderedEquals([...air]..sort())));
      for (var i = 0; i < walks.length; i++) {
        expect(walks[i], greaterThanOrEqualTo(air[i] - 1), reason: 'route $i');
      }
      // Each is a complete, valid one-hop route to a street door.
      for (final r in e.routes) {
        expect(r.isEntranceRoute, isTrue);
        expect(network.nodeById[r.hops.single.toNode]!.level, 'street');
        if (r.lengthM > directWalkM) expect(r.hops.single.edge.sources, contains('osm_streets'));
        expect(r.steps.first.kind, 'approach');
        expect(r.steps.last.kind, 'arrive');
        expect(r.steps.last.text, startsWith('Enter '));
        expect(validateRoute(network, conditions, r), isEmpty);
      }
    });

    test('standing at a building: a few steps straight to it, not around the block', () {
      // 5 m from the Fairmont Palliser outline.
      final e = router.nearestEntrances(tower, at: clearDay);
      final first = e.routes.first;
      expect(first.destinationBuildingId, 'palliser_hotel');
      expect(first.lengthM, lessThan(directWalkM));
      expect(first.hops.single.edge.sources, isNot(contains('osm_streets')));
      expect(first.notes.join(), isNot(contains('straight-line')));
      expect(e.routes[1].hops.single.edge.sources, contains('osm_streets'));
    });

    test('an OpenStreetMap door ends the walk at the door itself', () {
      final e = router.nearestEntrances(tower, at: clearDay);
      final mapped = e.routes.firstWhere((r) => network.nodeById[r.hops.single.toNode]!.isMappedDoor);
      final n = network.nodeById[mapped.hops.single.toNode]!;
      expect(mapped.doorPoint, [n.lat, n.lng]);
      expect(mapped.hops.single.geometry.last, [n.lat, n.lng]);
      expect(mapped.steps.last.text, contains(n.label!));
    });

    test('re-routing keeps the chosen door', () {
      final first = router.nearestEntrances(tower, at: clearDay).routes.first;
      final door = first.hops.single.toNode;
      final again = router.nearestEntrances(const RouteOrigin.location(51.0438, -114.0612),
          at: clearDay, limit: 1, doorNodeId: door);
      expect(again.routes.single.hops.single.toNode, door);
    });

    test('closed network: planned for the next opening, preview only', () {
      final e = router.nearestEntrances(tower, at: DateTime(2027, 6, 15, 23));
      expect(e.ok, isTrue);
      expect(e.nextOpen, DateTime(2027, 6, 16, 6));
      expect(e.routes.first.previewOnly, isTrue);
      expect(e.routes.first.warnings.join(), contains('closed now'));
    });

    test('already inside the +15: says so instead of walking you outside', () {
      final e = router.nearestEntrances(const RouteOrigin.location(51.0453, -114.0690),
          at: clearDay);
      expect(e.ok, isFalse);
      expect(e.insideLabel, 'Bankers Hall');
    });

    test('too far away: honest message, no guess', () {
      final e = router.nearestEntrances(const RouteOrigin.location(51.0000, -114.0700),
          at: clearDay);
      expect(e.ok, isFalse);
      expect(e.unavailableReason, contains('km from the +15'));
    });

    test('off the mapped street grid: straight-line estimates, labelled', () {
      // Just outside the street graph's coverage, still within 3 km.
      final e = router.nearestEntrances(const RouteOrigin.location(51.0310, -114.0700),
          at: clearDay);
      expect(e.ok, isTrue);
      expect(e.approximate, isTrue);
      expect(e.routes.first.notes.join(), contains('straight-line'));
      expect(e.routes.first.hops.single.edge.sources, isNot(contains('osm_streets')));
      expect(validateRoute(network, conditions, e.routes.first), isEmpty);
    });

    test('accessible: no building without a street elevator, no wheelchair=no door, no steps', () {
      for (final o in [tower, const RouteOrigin.location(51.0424, -114.0784)]) {
        final e = router.nearestEntrances(o, profile: RouteProfile.accessible, at: clearDay);
        expect(e.ok, isTrue, reason: e.unavailableReason);
        for (final r in e.routes) {
          final b = network.buildingById[r.destinationBuildingId]!;
          expect(b.noElevatorToStreet, isFalse, reason: b.id);
          expect(network.nodeById[r.hops.single.toNode]!.wheelchair, isNot('no'));
          expect(r.notes.join(), isNot(contains('steps')));
          expect(r.warnings.join(), contains('Elevator access'));
        }
      }
    });

    test('closed buildings are skipped', () {
      // Place 800 is closed on closureDay (closures.json): never offered.
      final near = router.nearestEntrances(const RouteOrigin.location(51.0480, -114.0795),
          at: closureDay);
      expect(near.ok, isTrue);
      expect(near.routes.map((r) => r.destinationBuildingId), isNot(contains('place_800')));
    });

    test('doors of buildings sharing a +15 junction count too', () {
      final doors = router.approachDoors(const RouteOrigin.location(51.0458, -114.0675));
      final buildings = doors.map((d) => d.building.id).toSet();
      expect(buildings, contains('td_square'));
    });

    test('buildings sharing an outline are listed once', () {
      final e = router.nearestEntrances(const RouteOrigin.location(51.0455, -114.0640),
          at: clearDay);
      final points = e.routes.map((r) => '${r.doorPoint}').toList();
      expect(points.toSet().length, points.length);
    });
  });
}
