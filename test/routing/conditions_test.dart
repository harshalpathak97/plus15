import 'package:flutter_test/flutter_test.dart';
import 'package:plus15_navigator/routing/conditions.dart';
import 'package:plus15_navigator/routing/router.dart';

import 'support.dart';

void main() {
  group('Alberta holidays', () {
    test('Good Friday from Easter', () {
      expect(goodFriday(2026), DateTime(2026, 4, 3));
      expect(goodFriday(2027), DateTime(2027, 3, 26));
      expect(goodFriday(2028), DateTime(2028, 4, 14));
    });
    test('fixed and Monday holidays', () {
      for (final d in [
        DateTime(2026, 1, 1),
        DateTime(2026, 2, 16), // Family Day (3rd Monday)
        DateTime(2026, 5, 18), // Victoria Day (Monday before May 25)
        DateTime(2026, 7, 1),
        DateTime(2026, 9, 7), // Labour Day
        DateTime(2026, 10, 12), // Thanksgiving
        DateTime(2026, 11, 11),
        DateTime(2026, 12, 25),
      ]) {
        expect(isAlbertaHoliday(d), isTrue, reason: '$d');
      }
      expect(isAlbertaHoliday(DateTime(2026, 9, 30)), isFalse); // not a stat in Alberta
      expect(isAlbertaHoliday(DateTime(2026, 12, 26)), isFalse); // Boxing Day is optional
      expect(isAlbertaHoliday(DateTime(2026, 8, 3)), isFalse); // Heritage Day is optional
    });
  });

  group('network hours (calgary.ca/plus15)', () {
    test('weekday 6 a.m. – 9 p.m.', () {
      expect(conditions.networkStatusAt(DateTime(2026, 10, 5, 5, 59)).open, isFalse);
      expect(conditions.networkStatusAt(DateTime(2026, 10, 5, 6)).open, isTrue);
      expect(conditions.networkStatusAt(DateTime(2026, 10, 5, 20, 59)).open, isTrue);
      expect(conditions.networkStatusAt(DateTime(2026, 10, 5, 21)).open, isFalse);
    });
    test('weekends 9 a.m. – 7 p.m.', () {
      final s = conditions.networkStatusAt(DateTime(2026, 10, 4, 8)); // Sunday
      expect(s.open, isFalse);
      expect(s.nextOpen, DateTime(2026, 10, 4, 9));
      expect(conditions.networkStatusAt(DateTime(2026, 10, 4, 18, 59)).open, isTrue);
      expect(conditions.networkStatusAt(DateTime(2026, 10, 4, 19)).open, isFalse);
    });
    test('statutory holidays use weekend hours', () {
      expect(conditions.networkStatusAt(DateTime(2027, 3, 26, 8)).open, isFalse); // Good Friday
      expect(conditions.networkStatusAt(DateTime(2027, 3, 26, 10)).open, isTrue);
    });
    test('closed all day on December 25', () {
      final s = conditions.networkStatusAt(DateTime(2026, 12, 25, 12));
      expect(s.open, isFalse);
      expect(s.nextOpen, DateTime(2026, 12, 26, 9)); // a Saturday
    });
    test('closed network: route is planned for the opening and is preview-only', () {
      final r = router.route(const RouteOrigin.building('bankers_hall'), 'the_bow',
          at: DateTime(2026, 10, 4, 8));
      expect(r.ok, isTrue);
      final route = r.route!;
      expect(route.opensAt, DateTime(2026, 10, 4, 9));
      expect(route.at, DateTime(2026, 10, 4, 9));
      expect(route.previewOnly, isTrue);
      expect(route.warnings.first, contains('closed now'));
      // Same path as planning for the opening time directly.
      expect(route.edgeIds,
          mustRoute('bankers_hall', 'the_bow', at: DateTime(2026, 10, 4, 9)).edgeIds);
      expect(mustRoute('bankers_hall', 'the_bow', at: DateTime(2026, 10, 4, 12)).previewOnly,
          isFalse);
    });
    test('weekend routes carry the City caveat about shorter bridge hours', () {
      final r = mustRoute('bankers_hall', 'the_bow', at: DateTime(2026, 10, 4, 12));
      expect(r.warnings.join(), contains('shorter hours'));
    });
  });

  group('closures (calgary.ca/plus15, retrieved 2026-09-30)', () {
    test('active on the published dates', () {
      Set<String> active(DateTime t) => {for (final c in conditions.activeAt(t)) c.id};
      expect(active(DateTime(2026, 9, 30, 12)), {'suncor-hanover', 'place-800', '640-fifth'});
      expect(active(DateTime(2026, 10, 31, 23)), {'suncor-hanover', 'place-800', '640-fifth'});
      expect(active(DateTime(2026, 11, 1, 6)), {'suncor-hanover'});
      expect(active(DateTime(2027, 1, 1, 6)), isEmpty);
    });
    test('a view-only route through closed bridges is offered for planning', () {
      final at = DateTime(2026, 9, 30, 12);
      final closed = conditions.closedEdgesAt(at);
      var found = 0;
      for (final a in network.buildings.where((b) => b.isRoutable)) {
        for (final b in network.buildings.where((b) => b.isRoutable && b.id != a.id)) {
          final r = router.route(RouteOrigin.building(a.id), b.id, at: at);
          final via = r.viaClosed;
          if (via == null) continue;
          found++;
          expect(via.previewOnly, isTrue);
          expect(via.throughClosures, isNotEmpty);
          expect(via.edgeIds.any(closed.containsKey), isTrue);
          expect(via.warnings.first, startsWith('Preview only'));
          if (r.ok) expect(r.route!.edgeIds.any(closed.containsKey), isFalse);
        }
      }
      expect(found, greaterThan(0));
    });
    test('calgaryNow follows Mountain time and its DST switches', () {
      expect(calgaryNow(DateTime.utc(2026, 7, 1, 18)), DateTime(2026, 7, 1, 12)); // MDT
      expect(calgaryNow(DateTime.utc(2026, 1, 15, 18)), DateTime(2026, 1, 15, 11)); // MST
      expect(calgaryNow(DateTime.utc(2026, 3, 8, 8, 59)), DateTime(2026, 3, 8, 1, 59));
      expect(calgaryNow(DateTime.utc(2026, 3, 8, 9)), DateTime(2026, 3, 8, 3));
      expect(calgaryNow(DateTime.utc(2026, 11, 1, 7, 59)), DateTime(2026, 11, 1, 1, 59));
      expect(calgaryNow(DateTime.utc(2026, 11, 1, 8)), DateTime(2026, 11, 1, 1));
    });
    test('closures remove edges from routing, not just display a warning', () {
      final closed = conditions.closedEdgesAt(closureDay);
      final numbers = {for (final id in closed.keys) network.edgeById[id]!.bridgeNumber};
      expect(numbers, containsAll(['1532', '1539', '1574', '1576', '1528', 'P1501']));
    });
    test('a route that would use a closed bridge is rerouted and says so', () {
      final r = mustRoute('736_sixth', 'amec_place', at: closureDay);
      expect(r.transitions, isNot(contains('bridge:1539')));
      expect(r.notes.join(), contains('Place 800'));
    });
    test('after an estimated reopening the route warns it is unconfirmed', () {
      final r = mustRoute('suncor_energy_centre', 'telus_sky', at: DateTime(2027, 1, 12, 12));
      expect(r.transitions, contains('bridge:1532'));
      expect(r.warnings.join(), contains('reopening not confirmed'));
    });
    test('time-restricted and elevator closures', () {
      final c = Conditions(network, [
        const Closure(
            id: 't', kind: 'time_restricted', bridges: ['1506'], openDaily: [600, 900], title: 'Test'),
        const Closure(
            id: 'e', kind: 'elevator_unavailable', buildings: ['bankers_hall'], title: 'Elevator'),
      ]);
      // Open daily 10:00–15:00 only.
      expect(c.closedEdgesAt(DateTime(2027, 6, 15, 11)).values.map((x) => x.id), isNot(contains('t')));
      expect(c.closedEdgesAt(DateTime(2027, 6, 15, 16)).values.map((x) => x.id), contains('t'));
      expect(c.elevatorOutagesAt(DateTime(2027, 6, 15, 12)), {'bankers_hall'});
    });
  });

  group('accessibility', () {
    test('accessible routes exclude the stairs-only Westin links', () {
      final r = router.route(const RouteOrigin.building('shell_centre'), 'the_westin',
          profile: RouteProfile.accessible, at: clearDay);
      // Both +15 links into the Westin are stairs-only and the Westin has no
      // elevator to the street (official map), so there is no step-free route.
      expect(r.ok, isFalse);
    });
    test('fastest may use stairs but says so', () {
      final r = mustRoute('shell_centre', 'the_westin');
      expect(r.stepFree, isFalse);
      expect(r.warnings.join(), contains('stairs-only'));
    });
    test('accessible street transfers avoid buildings without a street elevator', () {
      final r = router.route(const RouteOrigin.building('bankers_hall'), 'calgary_tower',
          profile: RouteProfile.accessible, at: clearDay);
      expect(r.ok, isTrue);
      for (final h in r.route!.hops.where((h) => h.edge.kind == 'street_exit')) {
        expect(router.streetExitBuilding(h.edge)!.noElevatorToStreet, isFalse);
      }
    });
  });
}
