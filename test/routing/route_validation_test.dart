import 'package:flutter_test/flutter_test.dart';
import 'package:plus15_navigator/routing/route_validator.dart';
import 'package:plus15_navigator/routing/router.dart';

import 'support.dart';

/// Every routable building to every other, both directions, every profile,
/// on a clear weekday and while today's closures are in effect.
void main() {
  final buildings = network.buildings.where((b) => b.isRoutable).toList();

  for (final at in [clearDay, closureDay]) {
    for (final profile in RouteProfile.values) {
      test('all pairs valid: ${profile.name} at ${at.toIso8601String().substring(0, 10)}', () {
        final problems = <String>[];
        var routed = 0, unavailable = 0, street = 0;
        for (final a in buildings) {
          for (final b in buildings) {
            final res = router.route(RouteOrigin.building(a.id), b.id, profile: profile, at: at);
            if (!res.ok) {
              unavailable++;
              continue;
            }
            routed++;
            final r = res.route!;
            if (r.usesStreet) street++;
            for (final p in validateRoute(network, conditions, r)) {
              problems.add('${a.id} → ${b.id}: $p');
            }
          }
        }
        expect(problems, isEmpty, reason: problems.take(20).join('\n'));
        // Fastest always finds something: the street fallback joins networks.
        if (profile == RouteProfile.fastest) expect(unavailable, 0);
        expect(routed, greaterThan(buildings.length * buildings.length * 0.8));
        // Most trips stay inside the +15.
        expect(street, lessThan(routed * 0.5));
      });
    }
  }

  test('A→B and B→A cost the same (symmetric graph) but are generated independently', () {
    for (var i = 0; i < buildings.length; i += 3) {
      for (var j = i + 1; j < buildings.length; j += 5) {
        final a = buildings[i].id, b = buildings[j].id;
        final ab = router.route(RouteOrigin.building(a), b, at: clearDay).route!;
        final ba = router.route(RouteOrigin.building(b), a, at: clearDay).route!;
        expect(ab.cost, closeTo(ba.cost, 0.01), reason: '$a ↔ $b');
        if (ab.hops.isEmpty) continue; // already there: a single arrival step
        expect(ab.steps.first.kind, 'start');
        expect(ba.steps.first.kind, 'start');
        expect(ab.steps.last.text, contains(network.buildingById[b]!.name));
        expect(ba.steps.last.text, contains(network.buildingById[a]!.name));
      }
    }
  });

  test('no huge detours between buildings joined by one City bridge', () {
    final detours = <String>[];
    for (final br in network.bridges.where((x) => x.excluded == null)) {
      final ends = {
        for (final e in network.edges)
          if (e.bridgeNumber == br.number)
            for (final n in [e.from, e.to])
              for (final b in network.buildingsAtNode[n] ?? const []) b.id
      }.toList();
      for (var i = 0; i < ends.length; i++) {
        for (var j = i + 1; j < ends.length; j++) {
          final r = mustRoute(ends[i], ends[j]);
          final a = network.buildingById[ends[i]]!, b = network.buildingById[ends[j]]!;
          if (r.lengthM > 2 * crowFliesM(a, b) + 120) {
            detours.add('${a.id} ↔ ${b.id} via ${br.number}: ${r.lengthM.round()} m');
          }
        }
      }
    }
    expect(detours, isEmpty, reason: detours.join('\n'));
  });

  test('closed bridges are never used while closed', () {
    for (final a in buildings) {
      for (final b in buildings.take(40)) {
        final r = router.route(RouteOrigin.building(a.id), b.id, at: closureDay).route;
        if (r == null) continue;
        for (final h in r.hops) {
          expect(['1532', '1539', '1574', '1576', '1528', 'P1501'], isNot(contains(h.edge.bridgeNumber)),
              reason: '${a.id} → ${b.id}');
        }
      }
    }
  });
}
