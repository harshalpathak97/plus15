import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:plus15_navigator/routing/route_validator.dart';
import 'package:plus15_navigator/routing/router.dart';

import 'support.dart';

/// Golden journeys (test/routing/golden_routes.json), both directions,
/// each direction routed and checked independently.
void main() {
  final spec = jsonDecode(File('test/routing/golden_routes.json').readAsStringSync())
      as Map<String, dynamic>;
  for (final g in (spec['routes'] as List).cast<Map<String, dynamic>>()) {
    final profile = RouteProfile.values.byName(g['profile'] as String? ?? 'fastest');
    final at = g['at'] == null ? clearDay : DateTime.parse(g['at'] as String);
    final expected = (g['bridges'] as List?)?.cast<String>();
    final anyOf = (g['anyOf'] as List?)?.map((l) => (l as List).cast<String>()).toList();
    final avoids = (g['avoids'] as List?)?.cast<String>() ?? const [];

    for (final reverse in [false, true]) {
      final from = (reverse ? g['to'] : g['from']) as String;
      final to = (reverse ? g['from'] : g['to']) as String;
      test('$from → $to (${profile.name}, ${at.toIso8601String().substring(0, 10)})', () {
        final res = router.route(RouteOrigin.building(from), to, profile: profile, at: at);
        expect(res.ok, isTrue, reason: res.unavailableReason);
        final r = res.route!;
        expect(validateRoute(network, conditions, r), isEmpty);

        final bridges = [for (final t in r.transitions) t.substring('bridge:'.length)];
        List<String> dir(List<String> l) => reverse ? l.reversed.toList() : l;
        if (expected != null) expect(bridges, dir(expected));
        if (anyOf != null) expect(anyOf.map(dir), anyElement(equals(bridges)));
        for (final b in avoids) {
          expect(bridges, isNot(contains(b)), reason: 'closed bridge $b used');
        }
        if (g['street'] == true) {
          expect(r.usesStreet, isTrue);
          final outdoor = r.hops
              .where((h) => h.edge.kind == 'street_transfer')
              .fold(0.0, (s, h) => s + h.lengthM);
          if (g['maxOutdoorM'] != null) {
            expect(outdoor, lessThanOrEqualTo((g['maxOutdoorM'] as num).toDouble()));
          }
        } else {
          expect(r.usesStreet, isFalse, reason: 'unexpected outdoor leg');
        }
        if (g['maxM'] != null) expect(r.lengthM, lessThanOrEqualTo((g['maxM'] as num).toDouble()));
        if (g['minM'] != null) expect(r.lengthM, greaterThanOrEqualTo((g['minM'] as num).toDouble()));
      });
    }
  }
}
