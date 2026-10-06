import 'package:flutter_test/flutter_test.dart';
import 'package:plus15_navigator/routing/conditions.dart';
import 'package:plus15_navigator/routing/network.dart';
import 'package:plus15_navigator/routing/router.dart';

/// Explicit, testable weights on a tiny synthetic network:
///
///   A ──X (100 m, stairs)── B
///   A ──L (90 m, likely)─── B
///   A ──Y (60 m)── C ──Z (60 m, open-air)── B
///   A ──U (10 m, unverified)── B
///   D is only reachable at street level.
NetEdge _e(String id, String a, String b, double m,
        {String kind = 'bridge',
        String conf = 'verified',
        bool stairs = false,
        bool indoor = true,
        String? bridge}) =>
    NetEdge(
      id: id,
      from: a,
      to: b,
      kind: kind,
      bridgeNumber: bridge ?? id,
      lengthM: m,
      indoor: indoor,
      stairsRequired: stairs,
      confidence: conf,
      sources: const ['test'],
      geometry: const [[51.0, -114.0], [51.0001, -114.0]],
    );

NetNode _n(String id, {String level = '+15'}) => NetNode(
    id: id, lat: 51.0, lng: -114.0, type: level == '+15' ? 'junction' : 'street',
    level: level, regionIds: const [], label: id, source: 'test', confidence: 'verified');

Plus15Network _net(List<NetEdge> edges) => Plus15Network(
      nodes: [for (final id in ['a', 'b', 'c', 'd', 'sa', 'sd']) _n(id, level: id.startsWith('s') ? 'street' : '+15')],
      edges: edges,
      buildings: const [
        NetBuilding(id: 'A', name: 'A', lat: 51.0, lng: -114.0, nodeIds: ['a'], streetNodeId: 'sa'),
        NetBuilding(id: 'B', name: 'B', lat: 51.0, lng: -114.0, nodeIds: ['b']),
        NetBuilding(id: 'C', name: 'C', lat: 51.0, lng: -114.0, nodeIds: ['c']),
        NetBuilding(id: 'D', name: 'D', lat: 51.0, lng: -114.0, nodeIds: ['d'], streetNodeId: 'sd'),
      ],
      bridges: const [],
      regions: const [],
      hours: const NetworkHours(
          weekday: [0, 1440], weekendHoliday: [0, 1440], closedDates: [], note: ''),
    );

final _edges = [
  _e('X', 'a', 'b', 100, stairs: true),
  _e('L', 'a', 'b', 90, conf: 'likely', kind: 'manual_link', bridge: ''),
  _e('Y', 'a', 'c', 60),
  _e('Z', 'c', 'b', 60, indoor: false),
  _e('U', 'a', 'b', 10, conf: 'unverified'),
  _e('xa', 'a', 'sa', 10, kind: 'street_exit', conf: 'estimate', indoor: false),
  _e('xd', 'd', 'sd', 10, kind: 'street_exit', conf: 'estimate', indoor: false),
  _e('T', 'sa', 'sd', 100, kind: 'street_transfer', conf: 'estimate', indoor: false),
];

void main() {
  final at = DateTime(2027, 6, 15, 12);
  List<String> ids(Plus15Router r, String to, RouteProfile p, {String from = 'A'}) => [
        for (final h in r.route(RouteOrigin.building(from), to, profile: p, at: at).route!.hops)
          h.edge.id
      ];

  final net = _net(_edges);
  final router = Plus15Router(net, Conditions(net, const []));

  test('unverified edges are never routed, even when shortest', () {
    expect(ids(router, 'B', RouteProfile.fastest), isNot(contains('U')));
  });

  test('fastest takes the shortest verified link even with stairs', () {
    expect(ids(router, 'B', RouteProfile.fastest), ['X']); // 100 < 90×1.25 < 120
  });

  test('accessible excludes stairs; likely costs ×1.25', () {
    expect(ids(router, 'B', RouteProfile.accessible), ['L']); // 112.5 < 120
  });

  test('mostly indoors penalises open-air ×3', () {
    final noX = _net(_edges.where((e) => e.id != 'X').toList());
    final r = Plus15Router(noX, Conditions(noX, const []));
    expect(ids(r, 'B', RouteProfile.mostlyIndoors), ['L']); // 112.5 < 60 + 180
    expect(ids(r, 'B', RouteProfile.fastest), ['L']); // 112.5 < 120
    final noL = _net(_edges.where((e) => e.id != 'X' && e.id != 'L').toList());
    expect(ids(Plus15Router(noL, Conditions(noL, const [])), 'B', RouteProfile.mostlyIndoors), ['Y', 'Z']);
  });

  test('a closed edge is removed from routing', () {
    final c = Conditions(net, const [Closure(id: 'x', kind: 'bridge_closed', bridges: ['X'], title: 'X')]);
    expect(ids(Plus15Router(net, c), 'B', RouteProfile.fastest), ['L']);
  });

  test('street transfer only when no +15 route exists', () {
    final r = router.route(const RouteOrigin.building('A'), 'D', at: at).route!;
    expect(r.usesStreet, isTrue);
    expect([for (final h in r.hops) h.edge.id], ['xa', 'T', 'xd']);
    expect(r.cost, closeTo((10 + 60) + 100 * 2.5 + (10 + 60), 0.01));
    expect(router.route(const RouteOrigin.building('A'), 'B', at: at).route!.usesStreet, isFalse);
  });

  test('same building is a zero-length route', () {
    final r = router.route(const RouteOrigin.building('A'), 'A', at: at).route!;
    expect(r.hops, isEmpty);
    expect(r.steps.single.kind, 'arrive');
  });

  test('unknown or unmapped destinations are unavailable, not guessed', () {
    expect(router.route(const RouteOrigin.building('A'), 'nowhere', at: at).ok, isFalse);
  });
}
