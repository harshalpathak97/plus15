import 'package:collection/collection.dart';

import 'geo.dart';
import 'network.dart';

/// The walkable street graph downtown (assets/data/streets.json, built from
/// OpenStreetMap pedestrian ways by tool/build_network.dart). Used for the
/// outdoor leg of a route: from a GPS fix along sidewalks to a +15 door.
/// Pure Dart: shared by the app, tool and tests.

/// Where a point lands on the graph: the nearest edge, how far along it
/// (0–1 from edge end a), and how far off it the point is.
class StreetSnap {
  final int edge;
  final double t, offsetM;
  final P at; // the point on the edge
  const StreetSnap(this.edge, this.t, this.offsetM, this.at);
}

/// A shortest walk along the graph, from the snapped origin to a target.
class StreetWalk {
  final double lengthM; // including the offsets off the graph at both ends
  final LatLngList geometry; // origin → graph → target
  final bool stairs; // uses a highway=steps edge
  /// A straight line: the target is a few steps away, so the sidewalk graph
  /// would only add a detour via the nearest mapped edges.
  final bool direct;
  const StreetWalk(this.lengthM, this.geometry, this.stairs, {this.direct = false});
}

class StreetGraph {
  final List<P> at;
  final LatLngList latLng;
  final List<(int, int)> edges;
  final List<double> lengthM;
  final Set<int> stairs;
  final List<List<int>> edgesAt; // node → edge indices

  StreetGraph._(this.at, this.latLng, this.edges, this.lengthM, this.stairs, this.edgesAt);

  factory StreetGraph.fromJson(Map<String, dynamic> j) {
    final latLng = [
      for (final n in j['nodes'] as List) [(n[0] as num).toDouble(), (n[1] as num).toDouble()]
    ];
    final at = [for (final n in latLng) project(n[0], n[1])];
    final edges = [for (final e in j['edges'] as List) ((e[0] as num).toInt(), (e[1] as num).toInt())];
    final lengthM = [for (final e in edges) at[e.$1].dist(at[e.$2])];
    final edgesAt = List.generate(at.length, (_) => <int>[]);
    for (var i = 0; i < edges.length; i++) {
      edgesAt[edges[i].$1].add(i);
      edgesAt[edges[i].$2].add(i);
    }
    final stairs = {for (final s in (j['stairs'] as List? ?? const [])) (s as num).toInt()};
    return StreetGraph._(at, latLng, edges, lengthM, stairs, edgesAt);
  }

  int get nodeCount => at.length;

  /// The nearest edge to [p] within [maxM], or null (inside a block or park).
  // ponytail: linear scan over ~20k edges (~1 ms); add a grid index if profiling says so.
  StreetSnap? snap(P p, {double maxM = 60}) {
    StreetSnap? best;
    for (var i = 0; i < edges.length; i++) {
      final a = at[edges[i].$1], b = at[edges[i].$2];
      final c = closestOnSegment(p, a, b);
      final d = p.dist(c);
      if (d > maxM || (best != null && d >= best.offsetM)) continue;
      final l = lengthM[i];
      best = StreetSnap(i, l == 0 ? 0 : a.dist(c) / l, d, c);
    }
    return best;
  }

  /// Shortest walks from [from] to each of [to]; a missing key is unreachable
  /// within [maxM] (or at all, e.g. only via stairs with [avoidStairs]).
  Map<K, StreetWalk> walks<K>(StreetSnap from, Map<K, StreetSnap> to,
      {bool avoidStairs = false, double maxM = double.infinity}) {
    final out = <K, StreetWalk>{};
    if (to.isEmpty) return out;
    final (fa, fb) = edges[from.edge];
    final fl = lengthM[from.edge];
    if (avoidStairs && stairs.contains(from.edge)) return out;
    // Targets on the origin's own edge: walk along it.
    final pending = <K, StreetSnap>{};
    to.forEach((k, s) {
      if (s.edge == from.edge) {
        final along = (s.t - from.t).abs() * fl;
        out[k] = StreetWalk(from.offsetM + along + s.offsetM,
            [_ll(from), _ll(s)], stairs.contains(from.edge));
      } else if (!(avoidStairs && stairs.contains(s.edge))) {
        pending[k] = s;
      }
    });
    if (pending.isEmpty) return out;

    final dist = <int, double>{};
    final prev = <int, (int, int)>{}; // node → (previous node, edge)
    final pq = PriorityQueue<(double, int)>((x, y) => x.$1.compareTo(y.$1));
    dist[fa] = from.offsetM + from.t * fl;
    dist[fb] = from.offsetM + (1 - from.t) * fl;
    pq.add((dist[fa]!, fa));
    pq.add((dist[fb]!, fb));
    // Nodes that end a pending target's edge, so the search can stop early.
    final wanted = <int, int>{};
    for (final s in pending.values) {
      wanted[edges[s.edge].$1] = (wanted[edges[s.edge].$1] ?? 0) + 1;
      wanted[edges[s.edge].$2] = (wanted[edges[s.edge].$2] ?? 0) + 1;
    }
    var remaining = wanted.length;
    final settled = <int>{};
    while (pq.isNotEmpty && remaining > 0) {
      final (d, u) = pq.removeFirst();
      if (d > (dist[u] ?? double.infinity) || !settled.add(u)) continue;
      if (d > maxM) break;
      if (wanted.containsKey(u)) remaining--;
      for (final ei in edgesAt[u]) {
        if (avoidStairs && stairs.contains(ei)) continue;
        final e = edges[ei];
        final v = e.$1 == u ? e.$2 : e.$1;
        final nd = d + lengthM[ei];
        if (nd < (dist[v] ?? double.infinity)) {
          dist[v] = nd;
          prev[v] = (u, ei);
          pq.add((nd, v));
        }
      }
    }

    pending.forEach((k, s) {
      final (a, b) = edges[s.edge];
      final l = lengthM[s.edge];
      final viaA = (dist[a] ?? double.infinity) + s.t * l;
      final viaB = (dist[b] ?? double.infinity) + (1 - s.t) * l;
      final end = viaA <= viaB ? a : b;
      final total = (viaA <= viaB ? viaA : viaB) + s.offsetM;
      if (total.isInfinite || total > maxM) return;
      // Walk the node chain back to the origin edge.
      final chain = <int>[end];
      var usesStairs = stairs.contains(s.edge);
      var n = end;
      while (prev.containsKey(n)) {
        final (p, ei) = prev[n]!;
        if (stairs.contains(ei)) usesStairs = true;
        chain.add(p);
        n = p;
      }
      if (stairs.contains(from.edge)) usesStairs = true;
      final geometry = <List<double>>[
        _ll(from),
        for (final c in chain.reversed) latLng[c],
        _ll(s),
      ];
      out[k] = StreetWalk(total, geometry, usesStairs);
    });
    return out;
  }

  static List<double> _ll(StreetSnap s) => unproject(s.at);
}
