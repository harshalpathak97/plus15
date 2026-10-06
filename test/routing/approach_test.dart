import 'package:flutter_test/flutter_test.dart';
import 'package:plus15_navigator/routing/geo.dart';
import 'package:plus15_navigator/routing/router.dart';

import 'support.dart';

void main() {
  group('GPS start outside the +15', () {
    test('a fix 1 km away walks to a nearby door, then routes through the +15', () {
      // Beltline, ~1 km south of the core.
      const o = RouteOrigin.location(51.0380, -114.0700);
      final r = router.route(o, 'the_bow', at: clearDay);
      expect(r.ok, isTrue, reason: r.unavailableReason);
      final first = r.route!.hops.first;
      expect(first.edge.kind, 'virtual');
      expect(first.edge.indoor, isFalse);
      // Drawn from the fix to the door, then up into the building.
      expect(first.geometry.first, [51.0380, -114.0700]);
      expect(first.geometry.length, 3);
      // The door chosen is among the nearest ones.
      final doors = router.approachDoors(o);
      final door = first.geometry[1];
      final d = project(door[0], door[1]).dist(project(o.lat!, o.lng!));
      expect(d, lessThanOrEqualTo(doors.first.distanceM + 250));
      expect(r.route!.steps.first.kind, 'approach');
      expect(r.route!.steps.first.text, contains('outdoors to'));
    });

    test('mapped OpenStreetMap doors are walked to exactly', () {
      final mapped = network.nodes.where((n) => n.isMappedDoor).toList();
      expect(mapped.length, greaterThan(40));
      final n = mapped.first;
      // Standing 40 m south of a mapped door.
      final o = RouteOrigin.location(n.lat - 0.00036, n.lng);
      final doors = router.approachDoors(o);
      expect(doors.first.mapped || doors.first.distanceM < 40, isTrue);
    });

    test('too far away: the router says so instead of guessing', () {
      final r = router.route(const RouteOrigin.location(51.0000, -114.0700), 'the_bow',
          at: clearDay);
      expect(r.ok, isFalse);
      expect(r.unavailableReason, contains('km from the +15'));
    });

    test('outdoor transfers between the two +15 networks join street doors', () {
      final transfers = network.edges.where((e) => e.kind == 'street_transfer');
      expect(transfers, isNotEmpty);
      for (final e in transfers) {
        expect(network.nodeById[e.from]!.level, 'street');
        expect(network.nodeById[e.to]!.level, 'street');
        expect(network.streetOwner[e.from], isNotNull);
        expect(network.streetOwner[e.to], isNotNull);
      }
    });
  });
}
