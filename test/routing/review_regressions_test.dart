import 'package:flutter_test/flutter_test.dart';
import 'package:plus15_navigator/routing/router.dart';

import 'support.dart';

/// Defects found in the adversarial review (2026-10-01), pinned so they stay
/// fixed. Each test names the behaviour a pedestrian would rely on.
void main() {
  final buildings = network.buildings.where((b) => b.isRoutable).toList();

  test('accessible GPS starts never go up through a building with no street elevator', () {
    for (var lat = 51.0430; lat <= 51.0520; lat += 0.0010) {
      for (var lng = -114.0820; lng <= -114.0560; lng += 0.0015) {
        final r = router.route(RouteOrigin.location(lat, lng), 'the_core',
            profile: RouteProfile.accessible, at: clearDay);
        if (!r.ok || r.route!.hops.isEmpty) continue;
        final first = r.route!.hops.first.edge;
        if (first.kind == 'virtual' && !first.indoor) {
          final b = network.buildingById[first.buildingIds.single]!;
          expect(b.noElevatorToStreet, isFalse, reason: '($lat, $lng) via ${b.id}');
        }
      }
    }
    // The nearest building (9 Ave SW South Side) has no street elevator: the
    // route walks a little further outdoors to one that has.
    final far = router.route(const RouteOrigin.location(51.0424, -114.0784), 'the_core',
        profile: RouteProfile.accessible, at: clearDay);
    expect(far.ok, isTrue);
    final via = network.buildingById[far.route!.hops.first.edge.buildingIds.single]!;
    expect(via.noElevatorToStreet, isFalse, reason: via.id);
  });

  test('outdoor walks only join places with no +15 connection between them', () {
    for (final a in buildings.where((b) => b.id.hashCode % 4 == 0)) {
      for (final b in buildings) {
        final r = router.route(RouteOrigin.building(a.id), b.id, at: clearDay).route;
        if (r == null || !r.usesStreet) continue;
        for (final h in r.hops.where((h) => h.edge.kind == 'street_transfer')) {
          final x = network.streetOwner[h.fromNode]!, y = network.streetOwner[h.toNode]!;
          final direct = router.route(RouteOrigin.building(x.id), y.id, at: clearDay).route!;
          expect(direct.usesStreet, isTrue,
              reason: '${a.id}→${b.id} walks outside ${x.id}→${y.id}, which are +15-connected');
        }
      }
    }
  });

  test('warns when the walk would not finish before the +15 closes', () {
    final r = mustRoute('sandman_hotel', '736_sixth', at: DateTime(2026, 10, 15, 20, 58));
    expect(r.warnings.join(), contains('may not finish before closing'));
    expect(mustRoute('bankers_hall', 'gulf_canada_square', at: DateTime(2026, 10, 15, 20, 58))
        .warnings
        .join(), isNot(contains('may not finish')));
  });

  test('exit and enter steps name the building whose street exit is used', () {
    for (final pair in [
      ['bvc_north', 'gulf_canada_square'],
      ['mcdougall_parkade', 'palliser_south'],
      ['bankers_hall', 'calgary_tower'],
    ]) {
      final r = mustRoute(pair[0], pair[1]);
      for (final s in r.steps.where((s) => s.kind == 'exit' || s.kind == 'enter')) {
        final h = r.hops[s.hopIndices.single];
        final street = network.nodeById[h.toNode]!.level == 'street' ? h.toNode : h.fromNode;
        expect(s.text, contains(network.streetOwner[street]!.name), reason: s.text);
      }
    }
  });

  test('short connectors are not described as street crossings', () {
    final steps = mustRoute('hsbc_building', 'bankers_hall').steps.map((s) => s.text).join(' ');
    expect('over 3 St SW'.allMatches(steps).length, 1);
    expect(mustRoute('plains_midstream', 'centennial_parkade').steps[1].text,
        startsWith('Take the +15 link'));
    expect(mustRoute('brookfield_place', 'stephen_ave_place').steps[1].text,
        contains('over 7 Ave SW'));
  });

  test('a GPS fix under a bridge is treated as street level; inside the destination is arrival', () {
    final under = router.route(const RouteOrigin.location(51.045743, -114.069511), 'the_core',
        at: clearDay).route!;
    expect(under.steps.first.kind, 'approach');
    expect(under.hops.first.edge.indoor, isFalse);
    final inside = router.route(const RouteOrigin.location(51.045262, -114.069345), 'bankers_hall',
        at: clearDay).route!;
    expect(inside.hops, isEmpty);
    expect(inside.steps.single.text, contains('You are in Bankers Hall'));
  });

  test('accessible routes warn at endpoints with no elevator to the street', () {
    final r = mustRoute('ave9_south_side', 'western_canadian_place', profile: RouteProfile.accessible);
    expect(r.warnings.join(), contains('no elevator between the street and the +15'));
  });

  test('wording: no self-referential or doubled-article steps anywhere', () {
    final selfRef = RegExp(r'Walk through (.+?) to the \+15 bridge toward \1\.');
    for (final a in buildings) {
      for (final b in buildings.where((b) => b.id.hashCode % 3 == 0)) {
        final r = router.route(RouteOrigin.building(a.id), b.id, at: clearDay).route;
        if (r == null) continue;
        for (final s in r.steps) {
          expect(s.text, isNot(contains('the The ')), reason: s.text);
          expect(selfRef.hasMatch(s.text), isFalse, reason: s.text);
          expect(s.text, isNot(contains('in , ')), reason: s.text);
        }
      }
    }
  });

  test('a closure that forces an outdoor walk says so instead of quoting extra metres', () {
    final r = mustRoute('the_core', 'place_800', at: closureDay);
    expect(r.usesStreet, isTrue);
    expect(r.notes.join(), contains('no +15 route while it is closed'));
  });
}
