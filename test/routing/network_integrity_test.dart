import 'package:flutter_test/flutter_test.dart';
import 'package:plus15_navigator/routing/geo.dart';
import 'package:plus15_navigator/routing/network.dart';

import 'support.dart';

/// Topology integrity of assets/data/network.json. Known, documented gaps are
/// pinned here so that any *new* issue fails the build.
void main() {
  final net = network;
  final active = net.edges.where((e) => !e.isStreet).toList();

  test('the build reported no errors', () {
    expect(net.issues['errors'], isEmpty);
  });

  test('known unresolved items have not changed', () {
    expect(net.issues['officialMapLinksMissingFromCityData'], isEmpty);
    expect(net.issues['cityLinksNotOnOfficialMap'], isEmpty);
    expect(
      [for (final b in net.issues['unresolvedBuildings'] as List) b['id']]..sort(),
      ['520_fifth', 'london_house'],
    );
    expect(net.buildings.where((b) => !b.isRoutable), isEmpty);
    expect(
      [for (final e in net.edges) if (e.confidence == 'likely') e.kind],
      ['manual_link'],
      reason: 'only the Castell Building ↔ Bow Valley College South link is map-only',
    );
  });

  test('every edge joins two existing, distinct nodes', () {
    for (final e in net.edges) {
      expect(net.nodeById[e.from], isNotNull, reason: e.id);
      expect(net.nodeById[e.to], isNotNull, reason: e.id);
      expect(e.from, isNot(e.to), reason: e.id);
    }
  });

  test('no orphan nodes', () {
    for (final n in net.nodes) {
      expect(net.edgesAt[n.id], isNotEmpty, reason: '${n.id} has no edges');
    }
  });

  test('no duplicate +15 nodes', () {
    final pts = net.nodes.where((n) => n.level == '+15').toList();
    for (var i = 0; i < pts.length; i++) {
      for (var j = i + 1; j < pts.length; j++) {
        expect(pts[i].at.dist(pts[j].at), greaterThan(0.5),
            reason: '${pts[i].id} and ${pts[j].id} coincide');
      }
    }
  });

  test('every edge has a source, a confidence and a positive length', () {
    for (final e in net.edges) {
      expect(e.sources, isNotEmpty, reason: e.id);
      expect(['verified', 'likely', 'estimate'], contains(e.confidence), reason: e.id);
      expect(e.lengthM, greaterThan(0), reason: e.id);
    }
  });

  test('street edges are estimates and never indoor', () {
    for (final e in net.edges.where((e) => e.isStreet)) {
      expect(e.confidence, 'estimate', reason: e.id);
      expect(e.indoor, isFalse, reason: e.id);
    }
  });

  test('edge geometry starts and ends on its nodes', () {
    for (final e in net.edges) {
      final a = net.nodeById[e.from]!, b = net.nodeById[e.to]!;
      expect(haversineM(e.geometry.first[0], e.geometry.first[1], a.lat, a.lng), lessThan(0.5),
          reason: e.id);
      expect(haversineM(e.geometry.last[0], e.geometry.last[1], b.lat, b.lng), lessThan(0.5),
          reason: e.id);
    }
  });

  test('+15 edge geometry stays inside its City walkway polygon', () {
    for (final e in active.where((e) => e.regionId != null)) {
      final poly = net.regionById[e.regionId]!.polygon;
      for (var k = 0; k < e.geometry.length - 1; k++) {
        final a = project(e.geometry[k][0], e.geometry[k][1]);
        final b = project(e.geometry[k + 1][0], e.geometry[k + 1][1]);
        final n = (a.dist(b) / 1.0).ceil().clamp(1, 1000);
        for (var s = 0; s <= n; s++) {
          final q = a + (b - a) * (s / n);
          expect(poly.covers(q, tol: 0.6), isTrue,
              reason: '${e.id} leaves ${e.regionId} at $q');
        }
      }
    }
  });

  test('no suspiciously long indoor edge', () {
    for (final e in active) {
      expect(e.lengthM, lessThan(250), reason: '${e.id} is ${e.lengthM} m');
    }
  });

  test('edges in different polygons never cross without a shared node', () {
    final segs = <(NetEdge, P, P)>[];
    for (final e in active.where((e) => e.regionId != null)) {
      for (var k = 0; k < e.geometry.length - 1; k++) {
        segs.add((e, project(e.geometry[k][0], e.geometry[k][1]),
            project(e.geometry[k + 1][0], e.geometry[k + 1][1])));
      }
    }
    for (var i = 0; i < segs.length; i++) {
      for (var j = i + 1; j < segs.length; j++) {
        final (e1, a, b) = segs[i];
        final (e2, c, d) = segs[j];
        if (e1.regionId == e2.regionId) continue; // same open space
        if ({e1.from, e1.to}.intersection({e2.from, e2.to}).isNotEmpty) continue;
        expect(properlyIntersect(a, b, c, d), isFalse,
            reason: '${e1.id} (${e1.regionId}) crosses ${e2.id} (${e2.regionId})');
      }
    }
  });

  test('every active City bridge has at least two ends in the graph', () {
    for (final br in net.bridges.where((b) => b.excluded == null)) {
      final ends = {
        for (final e in net.edges)
          if (e.bridgeNumber == br.number) ...[e.from, e.to]
      };
      expect(ends.length, greaterThanOrEqualTo(2), reason: 'bridge ${br.number}');
    }
  });

  test('every routable building has nodes that exist', () {
    for (final b in net.buildings.where((b) => b.isRoutable)) {
      for (final n in b.nodeIds) {
        expect(net.nodeById[n], isNotNull, reason: '${b.id} → $n');
      }
    }
  });

  test('every active +15 polygon belongs to a building or is a bridge', () {
    for (final r in net.regions.where((r) => r.excluded == null && !r.isBridge)) {
      expect(r.buildingIds, isNotEmpty, reason: r.id);
    }
  });

  test('closure targets exist', () {
    for (final c in closures) {
      for (final b in c.bridges) {
        expect(net.bridgeByNumber[b], isNotNull, reason: '${c.id}: bridge $b');
      }
      for (final b in c.buildings) {
        expect(net.buildingById[b], isNotNull, reason: '${c.id}: building $b');
        expect(net.bridgesOfBuilding(b), isNotEmpty, reason: '${c.id}: $b has no bridges');
      }
      for (final e in c.edges) {
        expect(net.edgeById[e], isNotNull, reason: '${c.id}: edge $e');
      }
      for (final n in c.nodes) {
        expect(net.nodeById[n], isNotNull, reason: '${c.id}: node $n');
      }
    }
  });

  test('closure "bridges connected to" resolves to the City bridge records', () {
    expect(net.bridgesOfBuilding('place_800'), {'1539', '1574'});
    expect(net.bridgesOfBuilding('640_fifth'), {'1576', '1528', 'P1501'});
  });

  test('stairs-only links come from the official map', () {
    final stairs = {for (final e in net.edges) if (e.stairsRequired) e.bridgeNumber};
    expect(stairs, {'1527', '1522'});
  });

  test('every building name sits inside its outline on the map', () {
    for (final b in net.buildings.where((b) => b.outline.isNotEmpty)) {
      final [y, x] = b.labelAt;
      var inside = false;
      final o = b.outline;
      for (var i = 1; i < o.length; i++) {
        if ((o[i - 1][0] > y) != (o[i][0] > y) &&
            x < o[i - 1][1] + (y - o[i - 1][0]) * (o[i][1] - o[i - 1][1]) / (o[i][0] - o[i - 1][0])) {
          inside = !inside;
        }
      }
      expect(inside, isTrue, reason: b.name);
    }
  });
}
