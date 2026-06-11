import 'package:flutter_test/flutter_test.dart';
import 'package:plus15_navigator/data/models/building.dart';
import 'package:plus15_navigator/data/models/bridge.dart';
import 'package:plus15_navigator/data/graph/plus15_graph.dart';
import 'package:plus15_navigator/data/graph/pathfinder.dart';

/// Synthetic downtown: A — B — C in a line, plus a short *inaccessible* direct
/// A–C shortcut, and an isolated E with no bridges.
///
///   A --100,acc--> B --100,acc--> C
///   A ----------50,NOT acc------> C
List<Building> _buildings() => const [
      Building(id: 'A', name: 'A', lat: 51.050, lng: -114.070),
      Building(id: 'B', name: 'B', lat: 51.050, lng: -114.069),
      Building(id: 'C', name: 'C', lat: 51.050, lng: -114.068),
      Building(id: 'E', name: 'E', lat: 51.060, lng: -114.050),
    ];

Bridge _br(String id, String from, String to, double m,
        {bool accessible = true, String status = 'open'}) =>
    Bridge(
      id: id,
      fromBuildingId: from,
      toBuildingId: to,
      distanceM: m,
      isAccessible: accessible,
      hasElevator: accessible,
      status: status,
    );

Pathfinder _finder(List<Bridge> bridges) {
  final graph = Plus15Graph(buildings: _buildings(), bridges: bridges);
  return Pathfinder(graph: graph, shops: const []);
}

void main() {
  group('Plus15Graph', () {
    test('adjacency is bidirectional', () {
      final g = Plus15Graph(
        buildings: _buildings(),
        bridges: [_br('ab', 'A', 'B', 100)],
      );
      expect(g.getNeighbors('A'), contains('B'));
      expect(g.getNeighbors('B'), contains('A'));
    });

    test('getBridge resolves in both directions', () {
      final g = Plus15Graph(
        buildings: _buildings(),
        bridges: [_br('ab', 'A', 'B', 100)],
      );
      expect(g.getBridge('A', 'B')?.id, 'ab');
      expect(g.getBridge('B', 'A')?.id, 'ab');
      expect(g.getBridge('A', 'C'), isNull);
    });
  });

  group('Pathfinder', () {
    final fullBridges = [
      _br('ab', 'A', 'B', 100),
      _br('bc', 'B', 'C', 100),
      _br('ac', 'A', 'C', 50, accessible: false),
    ];

    test('same origin and destination is a zero-length route', () {
      final r = _finder(fullBridges).findRoute('A', 'A');
      expect(r, isNotNull);
      expect(r!.path, ['A']);
      expect(r.totalDistance, 0);
      expect(r.bridgeCount, 0);
    });

    test('fastest takes the short inaccessible shortcut', () {
      final r = _finder(fullBridges).findRoute('A', 'C', mode: 'fastest');
      expect(r, isNotNull);
      expect(r!.path, ['A', 'C']);
      expect(r.totalDistance, 50);
      expect(r.bridgeCount, 1);
      expect(r.fullyAccessible, isFalse);
    });

    test('accessible mode avoids the inaccessible shortcut', () {
      final r = _finder(fullBridges).findRoute('A', 'C', mode: 'accessible');
      expect(r, isNotNull);
      expect(r!.path, ['A', 'B', 'C']);
      expect(r.totalDistance, 200);
      expect(r.bridgeCount, 2);
      expect(r.fullyAccessible, isTrue);
    });

    test('closed bridges are never routed through', () {
      final bridges = [
        _br('ab', 'A', 'B', 100),
        _br('bc', 'B', 'C', 100),
        _br('ac', 'A', 'C', 50, status: 'closed'),
      ];
      final r = _finder(bridges).findRoute('A', 'C', mode: 'fastest');
      expect(r, isNotNull);
      expect(r!.path, ['A', 'B', 'C']);
      expect(r.totalDistance, 200);
    });

    test('returns null when destination is unreachable', () {
      expect(_finder(fullBridges).findRoute('A', 'E'), isNull);
    });

    test('returns null for unknown buildings', () {
      expect(_finder(fullBridges).findRoute('A', 'Z'), isNull);
    });

    test('findAllRoutes yields one result per mode', () {
      final all = _finder(fullBridges).findAllRoutes('A', 'C');
      expect(all.length, 3);
    });
  });
}
