import 'package:flutter_test/flutter_test.dart';
import 'package:plus15_navigator/routing/geo.dart';
import 'package:plus15_navigator/routing/streets.dart';

import 'support.dart';

void main() {
  group('street graph (OpenStreetMap sidewalks)', () {
    test('covers downtown and is one connected component', () {
      expect(streets.nodeCount, greaterThan(10000));
      expect(streets.edges.length, greaterThan(streets.nodeCount * 0.9));
    });

    test('every +15 street door is on or next to a sidewalk', () {
      final doors = network.nodes.where((n) => n.level == 'street');
      expect(doors.length, greaterThan(100));
      for (final n in doors) {
        final s = streets.snap(n.at, maxM: 60);
        expect(s, isNotNull, reason: '${n.id} ${n.label} is ${n.lat},${n.lng}');
        // Estimated doors sit on building outlines, up to a sidewalk's width away.
        expect(s!.offsetM, lessThanOrEqualTo(n.isMappedDoor ? 25 : 60),
            reason: '${n.id} ${n.label}');
      }
    });

    test('snap: nearest edge within range, nothing beyond it', () {
      // 8 Ave SW / 1 St SW (Stephen Avenue).
      final p = project(51.0455, -114.0640);
      final s = streets.snap(p)!;
      expect(s.offsetM, lessThan(30));
      expect(s.t, inInclusiveRange(0, 1));
      expect(streets.snap(p, maxM: 0.01), isNull);
      // Far outside the graph (Chestermere): nothing within range.
      expect(streets.snap(project(51.0400, -113.8200)), isNull);
    });

    test('walk follows streets: longer than the crow flies, not absurdly so', () {
      final a = streets.snap(project(51.0455, -114.0640))!;
      final b = streets.snap(project(51.0440, -114.0620))!; // 9 Ave SW, by the Tower
      final w = streets.walks(a, {'b': b})['b']!;
      final air = a.at.dist(b.at);
      expect(w.lengthM, greaterThanOrEqualTo(air));
      expect(w.lengthM, lessThan(air * 1.8));
      expect(w.geometry.length, greaterThan(2));
      expect(w.geometry.first, unproject(a.at));
      expect(w.geometry.last, unproject(b.at));
      // Consecutive points are adjacent sidewalk nodes, not jumps.
      for (var i = 1; i < w.geometry.length; i++) {
        final x = w.geometry[i - 1], y = w.geometry[i];
        expect(haversineM(x[0], x[1], y[0], y[1]), lessThan(320));
      }
    });

    test('targets on the origin edge, and the search reaching several targets at once', () {
      final a = streets.snap(project(51.0455, -114.0640))!;
      final same = StreetSnap(a.edge, (a.t + 0.3).clamp(0.0, 1.0), 0, a.at);
      final far = streets.snap(project(51.0470, -114.0750))!;
      final out = streets.walks(a, {'same': same, 'far': far});
      expect(out.keys, containsAll(['same', 'far']));
      expect(out['same']!.lengthM, lessThan(streets.lengthM[a.edge] + a.offsetM + 1));
      expect(out['far']!.lengthM, greaterThan(500));
    });

    test('maxM bounds the search; stairs are flagged and avoidable', () {
      final a = streets.snap(project(51.0455, -114.0640))!;
      final far = streets.snap(project(51.0470, -114.0750))!;
      expect(streets.walks(a, {'far': far}, maxM: 100), isEmpty);
      expect(streets.stairs, isNotEmpty);
      // A target right on a flight of steps: reachable, flagged; excluded
      // when avoiding stairs.
      final stepsEdge = streets.stairs.first;
      final (x, y) = streets.edges[stepsEdge];
      final mid = StreetSnap(stepsEdge, 0.5, 0, P((streets.at[x].x + streets.at[y].x) / 2,
          (streets.at[x].y + streets.at[y].y) / 2));
      final from = streets.snap(mid.at, maxM: 200);
      expect(from, isNotNull);
      final w = streets.walks(from!, {'s': mid});
      expect(w['s']?.stairs, isTrue);
      expect(streets.walks(from, {'s': mid}, avoidStairs: true), isEmpty);
    });
  });
}
