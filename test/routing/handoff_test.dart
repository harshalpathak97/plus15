import 'package:flutter_test/flutter_test.dart';
import 'package:plus15_navigator/routing/geo.dart';
import 'package:plus15_navigator/routing/route_validator.dart';
import 'package:plus15_navigator/routing/router.dart';

import 'support.dart';

void main() {
  group('maps-app handoff for a far-away fix', () {
    // About 9 km north of downtown, well past the 3 km walking limit.
    const far = RouteOrigin.location(51.1250, -114.0700);

    test('the walking planner still refuses, the handoff does not', () {
      final r = router.route(far, 'palliser_hotel', at: clearDay);
      expect(r.ok, isFalse);
      expect(r.unavailableReason, contains('km from the +15'));
      final h = router.planHandoff(far, 'palliser_hotel', at: clearDay);
      expect(h.ok, isTrue, reason: h.unavailableReason);
    });

    test('plans are valid, one per building, best first', () {
      final h = router.planHandoff(far, 'palliser_hotel', at: clearDay);
      expect(h.plans.length, inInclusiveRange(1, 3));
      expect(h.plans.map((p) => p.door.building.id).toSet().length, h.plans.length);
      final scores = [for (final p in h.plans) p.score];
      expect(scores, orderedEquals([...scores]..sort()));
      for (final p in h.plans) {
        expect(p.indoor.destinationBuildingId, 'palliser_hotel');
        expect(p.indoor.originBuildingId, p.door.building.id);
        expect(p.door.distanceM, greaterThan(maxApproachM));
        expect(validateRoute(network, conditions, p.indoor), isEmpty);
      }
    });

    test('the best entrance is the cheapest of every door, not just the pool', () {
      final h = router.planHandoff(far, 'palliser_hotel', at: clearDay);
      var best = double.infinity;
      for (final d in router.approachDoors(far, maxM: double.infinity)) {
        final r = router.route(RouteOrigin.building(d.building.id), 'palliser_hotel',
            at: clearDay);
        if (r.ok) best = best < d.distanceM + r.route!.lengthM ? best : d.distanceM + r.route!.lengthM;
      }
      expect(h.plans.first.score, closeTo(best, 0.5));
    });

    test('accessible: only step-free doors of buildings with a street elevator', () {
      final h = router.planHandoff(far, 'palliser_hotel',
          profile: RouteProfile.accessible, at: clearDay);
      expect(h.ok, isTrue, reason: h.unavailableReason);
      for (final p in h.plans) {
        expect(p.door.building.noElevatorToStreet, isFalse, reason: p.door.building.id);
        expect(network.nodeById[p.door.nodeId]!.wheelchair, isNot('no'));
        expect(p.indoor.stepFree, isTrue);
      }
    });

    test('closed buildings are never the entrance', () {
      // Place 800 is closed on closureDay (closures.json).
      final h = router.planHandoff(const RouteOrigin.location(51.1250, -114.1000), 'the_bow',
          at: closureDay);
      expect(h.ok, isTrue, reason: h.unavailableReason);
      expect(h.plans.map((p) => p.door.building.id), isNot(contains('place_800')));
      for (final p in h.plans) {
        expect(validateRoute(network, conditions, p.indoor), isEmpty);
      }
    });

    test('closed overnight: plans are for the next opening, preview only', () {
      final h = router.planHandoff(far, 'palliser_hotel', at: DateTime(2027, 6, 15, 3));
      expect(h.ok, isTrue, reason: h.unavailableReason);
      for (final p in h.plans) {
        expect(p.indoor.previewOnly, isTrue);
      }
    });

    test('a destination in the entrance building needs no walk inside', () {
      final h = router.planHandoff(far, 'palliser_hotel', at: clearDay);
      final inside = h.plans.where((p) => p.door.building.id == 'palliser_hotel');
      for (final p in inside) {
        expect(p.indoor.lengthM, 0);
      }
    });

    test('unknown destination: honest reason', () {
      final h = router.planHandoff(far, 'nowhere', at: clearDay);
      expect(h.ok, isFalse);
      expect(h.unavailableReason, isNotNull);
    });

    test('fast enough to run on a tap', () {
      final sw = Stopwatch()..start();
      router.planHandoff(far, 'the_bow', at: clearDay);
      expect(sw.elapsedMilliseconds, lessThan(1500));
    });

    test('door distances are measured from the fix', () {
      final h = router.planHandoff(far, 'the_bow', at: clearDay);
      final p = project(far.lat!, far.lng!);
      for (final plan in h.plans) {
        final d = project(plan.door.lat, plan.door.lng).dist(p);
        expect(d, closeTo(plan.door.distanceM, 1));
      }
    });
  });
}
