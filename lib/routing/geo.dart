import 'dart:math';

/// Planar geometry in local metres. Downtown Calgary spans ~3 km, so an
/// equirectangular projection around 51.047°N is accurate to well under 0.1%.
const double originLat = 51.047;
const double originLng = -114.065;
const double _mPerDegLat = 110540.0;
final double _mPerDegLng = 111320.0 * cos(originLat * pi / 180);

class P {
  final double x, y;
  const P(this.x, this.y);
  P operator +(P o) => P(x + o.x, y + o.y);
  P operator -(P o) => P(x - o.x, y - o.y);
  P operator *(double k) => P(x * k, y * k);
  double get len => sqrt(x * x + y * y);
  double dist(P o) => (this - o).len;
  double dot(P o) => x * o.x + y * o.y;
  double cross(P o) => x * o.y - y * o.x;
  @override
  String toString() => '(${x.toStringAsFixed(2)}, ${y.toStringAsFixed(2)})';
}

P project(double lat, double lng) =>
    P((lng - originLng) * _mPerDegLng, (lat - originLat) * _mPerDegLat);

/// Returns [lat, lng].
List<double> unproject(P p) =>
    [p.y / _mPerDegLat + originLat, p.x / _mPerDegLng + originLng];

double haversineM(double lat1, double lng1, double lat2, double lng2) {
  const r = 6371000.0;
  final dLat = (lat2 - lat1) * pi / 180;
  final dLng = (lng2 - lng1) * pi / 180;
  final a = sin(dLat / 2) * sin(dLat / 2) +
      cos(lat1 * pi / 180) * cos(lat2 * pi / 180) * sin(dLng / 2) * sin(dLng / 2);
  return 2 * r * asin(sqrt(a));
}

/// Closest point to [p] on segment [a]-[b].
P closestOnSegment(P p, P a, P b) {
  final d = b - a;
  final l2 = d.dot(d);
  if (l2 == 0) return a;
  final t = ((p - a).dot(d) / l2).clamp(0.0, 1.0);
  return a + d * t;
}

double pointSegmentDist(P p, P a, P b) => p.dist(closestOnSegment(p, a, b));

/// True if segments ab and cd cross at a single interior point of both.
bool properlyIntersect(P a, P b, P c, P d) {
  final d1 = (b - a).cross(c - a), d2 = (b - a).cross(d - a);
  final d3 = (d - c).cross(a - c), d4 = (d - c).cross(b - c);
  const eps = 1e-9;
  return ((d1 > eps && d2 < -eps) || (d1 < -eps && d2 > eps)) &&
      ((d3 > eps && d4 < -eps) || (d3 < -eps && d4 > eps));
}

double polylineLength(List<P> pts) {
  var s = 0.0;
  for (var i = 1; i < pts.length; i++) {
    s += pts[i - 1].dist(pts[i]);
  }
  return s;
}

/// Heading in degrees clockwise from north of the vector a→b.
double headingDeg(P a, P b) {
  final h = atan2(b.x - a.x, b.y - a.y) * 180 / pi;
  return (h + 360) % 360;
}

/// Signed turn from heading h1 to h2 in degrees, in (-180, 180]; positive = right.
double turnDeg(double h1, double h2) {
  var d = (h2 - h1) % 360;
  if (d > 180) d -= 360;
  return d;
}

/// A polygon with optional holes. Rings are closed (first == last).
class Polygon {
  final List<List<P>> rings; // rings[0] = outer, rest = holes

  Polygon(this.rings);

  Iterable<(P, P)> get edges sync* {
    for (final r in rings) {
      for (var i = 0; i + 1 < r.length; i++) {
        yield (r[i], r[i + 1]);
      }
    }
  }

  bool contains(P p) {
    var inside = false;
    for (final (a, b) in edges) {
      if ((a.y > p.y) != (b.y > p.y) &&
          p.x < (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x) {
        inside = !inside;
      }
    }
    return inside;
  }

  double boundaryDist(P p) {
    var m = double.infinity;
    for (final (a, b) in edges) {
      final d = pointSegmentDist(p, a, b);
      if (d < m) m = d;
    }
    return m;
  }

  P closestBoundaryPoint(P p) {
    var best = rings[0][0];
    var m = double.infinity;
    for (final (a, b) in edges) {
      final c = closestOnSegment(p, a, b);
      final d = c.dist(p);
      if (d < m) {
        m = d;
        best = c;
      }
    }
    return best;
  }

  /// Inside, or within [tol] metres of the boundary.
  bool covers(P p, {double tol = 0.05}) => contains(p) || boundaryDist(p) <= tol;

  double get area {
    var a = 0.0;
    for (var k = 0; k < rings.length; k++) {
      final r = rings[k];
      var s = 0.0;
      for (var i = 0; i + 1 < r.length; i++) {
        s += r[i].cross(r[i + 1]);
      }
      a += k == 0 ? s.abs() / 2 : -s.abs() / 2;
    }
    return a;
  }

  double get perimeter => rings.fold(0.0, (s, r) => s + polylineLength(r));

  P get centroid {
    final r = rings[0];
    var cx = 0.0, cy = 0.0, a = 0.0;
    for (var i = 0; i + 1 < r.length; i++) {
      final c = r[i].cross(r[i + 1]);
      a += c;
      cx += (r[i].x + r[i + 1].x) * c;
      cy += (r[i].y + r[i + 1].y) * c;
    }
    if (a.abs() < 1e-9) return r[0];
    return P(cx / (3 * a), cy / (3 * a));
  }

  (double, double, double, double) get bbox {
    var x0 = double.infinity, y0 = double.infinity;
    var x1 = -double.infinity, y1 = -double.infinity;
    for (final p in rings[0]) {
      x0 = min(x0, p.x);
      y0 = min(y0, p.y);
      x1 = max(x1, p.x);
      y1 = max(y1, p.y);
    }
    return (x0, y0, x1, y1);
  }

  /// A point strictly inside the polygon near [p] (moves [p] up to 3 m inward).
  P nudgeInside(P p) {
    if (contains(p) && boundaryDist(p) > 0.25) return p;
    final c = closestBoundaryPoint(p);
    for (final step in [0.3, 0.6, 1.0, 1.5, 2.5]) {
      for (var k = 0; k < 16; k++) {
        final ang = k * pi / 8;
        final q = c + P(cos(ang), sin(ang)) * step;
        if (contains(q) && boundaryDist(q) > 0.2) return q;
      }
    }
    return p;
  }

  /// True if the straight segment a-b stays inside the polygon.
  bool segmentInside(P a, P b) {
    for (final (c, d) in edges) {
      if (properlyIntersect(a, b, c, d)) return false;
    }
    final n = max(2, (a.dist(b) / 0.75).ceil());
    for (var i = 1; i < n; i++) {
      final q = a + (b - a) * (i / n);
      if (!covers(q)) return false;
    }
    return true;
  }

  /// Shortest path inside the polygon between two interior points, via a
  /// visibility graph over the ring vertices. Returns null if none is found.
  List<P>? geodesic(P a, P b) {
    if (segmentInside(a, b)) return [a, b];
    // Candidate waypoints: ring vertices nudged slightly inside.
    final verts = <P>[];
    for (final r in rings) {
      for (var i = 0; i + 1 < r.length; i++) {
        final q = nudgeInside(r[i]);
        if (contains(q)) verts.add(q);
      }
    }
    final pts = [a, b, ...verts];
    final n = pts.length;
    final dist = List.filled(n, double.infinity);
    final prev = List.filled(n, -1);
    final done = List.filled(n, false);
    dist[0] = 0;
    final vis = <int, bool>{};
    bool visible(int i, int j) {
      final key = i < j ? i * n + j : j * n + i;
      return vis[key] ??= segmentInside(pts[i], pts[j]);
    }

    for (var iter = 0; iter < n; iter++) {
      var u = -1;
      for (var i = 0; i < n; i++) {
        if (!done[i] && (u == -1 || dist[i] < dist[u])) u = i;
      }
      if (u == -1 || dist[u] == double.infinity) break;
      if (u == 1) break;
      done[u] = true;
      for (var v = 0; v < n; v++) {
        if (done[v] || v == u) continue;
        final nd = dist[u] + pts[u].dist(pts[v]);
        if (nd < dist[v] && visible(u, v)) {
          dist[v] = nd;
          prev[v] = u;
        }
      }
    }
    if (dist[1] == double.infinity) return null;
    final path = <P>[];
    for (var v = 1; v != -1; v = prev[v]) {
      path.insert(0, pts[v]);
    }
    return path;
  }
}
