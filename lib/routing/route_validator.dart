import 'conditions.dart';
import 'geo.dart';
import 'network.dart';
import 'router.dart';

/// Checks a route against the graph it came from. Returns problems; empty
/// means the route is consistent. Used by tests and the debug overlay.
List<String> validateRoute(Plus15Network net, Conditions cond, PlannedRoute r) {
  final problems = <String>[];
  final hops = r.hops;
  final closed = cond.closedEdgesAt(r.at);

  if (!cond.networkStatusAt(r.at).open) problems.add('routed while the network is closed');

  for (var i = 0; i < hops.length; i++) {
    final h = hops[i], e = h.edge;
    if (e.kind != 'virtual') {
      final real = net.edgeById[e.id];
      if (real == null) {
        problems.add('hop $i uses unknown edge ${e.id}');
        continue;
      }
      final ends = {real.from, real.to};
      if (!ends.contains(h.fromNode) || !ends.contains(h.toNode) || h.fromNode == h.toNode) {
        problems.add('hop $i (${e.id}) does not join ${h.fromNode}→${h.toNode}');
      }
      if (real.oneWay && real.from != h.fromNode) problems.add('hop $i walks one-way ${e.id} backwards');
    }
    if (i > 0 && hops[i - 1].toNode != h.fromNode) {
      problems.add('hops ${i - 1} and $i are not consecutive');
    }
    if (closed.containsKey(e.id)) problems.add('hop $i uses closed edge ${e.id} (${closed[e.id]!.title})');
    if (e.confidence == 'unverified') problems.add('hop $i uses unverified edge ${e.id}');
    if (e.isStreet && e.kind != 'virtual' && !r.usesStreet) {
      problems.add('hop $i is a street edge but the route claims +15 only');
    }
    if (r.profile == RouteProfile.accessible && e.stairsRequired) {
      problems.add('accessible route uses stairs-only edge ${e.id}');
    }
    // Geometry continuity: each hop starts where the previous one ended.
    if (i > 0) {
      final a = hops[i - 1].geometry.last, b = h.geometry.first;
      final gap = haversineM(a[0], a[1], b[0], b[1]);
      if (gap > 0.5) problems.add('geometry jumps ${gap.toStringAsFixed(1)} m between hops ${i - 1} and $i');
    }
    for (var k = 1; k < h.geometry.length; k++) {
      final a = h.geometry[k - 1], b = h.geometry[k];
      final seg = haversineM(a[0], a[1], b[0], b[1]);
      if (seg > 320) problems.add('hop $i has a ${seg.round()} m straight segment');
    }
    final n = net.nodeById[h.toNode];
    if (n != null) {
      final end = h.geometry.last;
      if (haversineM(end[0], end[1], n.lat, n.lng) > 0.5) {
        problems.add('hop $i geometry does not end at node ${n.id}');
      }
    }
  }

  if (hops.isNotEmpty) {
    final start = hops.first.edge.kind == 'virtual' ? hops.first.toNode : hops.first.fromNode;
    if (!r.originNodes.contains(start)) problems.add('route does not start at an origin node');
    if (!r.destinationNodes.contains(hops.last.toNode)) {
      problems.add('route does not end at a destination node');
    }
  }

  // Instructions cover every hop exactly once, in order.
  final covered = [for (final s in r.steps) ...s.hopIndices];
  if (covered.length != hops.length ||
      [for (var i = 0; i < covered.length; i++) covered[i] == i].contains(false)) {
    problems.add('steps cover hops $covered, expected 0..${hops.length - 1}');
  }
  if (r.steps.isEmpty || r.steps.last.kind != 'arrive') problems.add('last step is not an arrival');
  for (final s in r.steps) {
    if (s.kind == 'bridge' &&
        !s.hopIndices.every((i) => hops[i].edge.isBridgeLike)) {
      problems.add('bridge step "${s.text}" covers non-bridge hops');
    }
  }
  return problems;
}

/// Straight-line distance between two buildings' +15 locations.
double crowFliesM(NetBuilding a, NetBuilding b) =>
    project(a.lat, a.lng).dist(project(b.lat, b.lng));
