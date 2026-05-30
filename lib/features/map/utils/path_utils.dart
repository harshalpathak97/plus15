import 'package:latlong2/latlong.dart';

/// Catmull-Rom spline subdivision over a list of [LatLng] points.
/// Returns [points] unchanged when there are fewer than 3 nodes (a 2-point
/// segment has no interior curvature to compute).
/// [segmentsPerSpan] controls density; 8 is a good visual default.
List<LatLng> catmullRomSmooth(List<LatLng> points, {int segmentsPerSpan = 8}) {
  if (points.length < 3) return points;
  final out = <LatLng>[points.first];
  for (var i = 0; i < points.length - 1; i++) {
    final p0 = points[i == 0 ? 0 : i - 1];
    final p1 = points[i];
    final p2 = points[i + 1];
    final p3 = points[i + 2 < points.length ? i + 2 : points.length - 1];
    for (var s = 1; s <= segmentsPerSpan; s++) {
      final t = s / segmentsPerSpan;
      out.add(_catmullPoint(p0, p1, p2, p3, t));
    }
  }
  return out;
}

LatLng _catmullPoint(LatLng p0, LatLng p1, LatLng p2, LatLng p3, double t) {
  final t2 = t * t;
  final t3 = t2 * t;
  double c(double a, double b, double cc, double d) =>
      0.5 *
      ((2 * b) +
          (-a + cc) * t +
          (2 * a - 5 * b + 4 * cc - d) * t2 +
          (-a + 3 * b - 3 * cc + d) * t3);
  return LatLng(
    c(p0.latitude, p1.latitude, p2.latitude, p3.latitude),
    c(p0.longitude, p1.longitude, p2.longitude, p3.longitude),
  );
}

/// Returns an L-shaped intermediate waypoint for a bridge between [from] and
/// [to] when the bridge is diagonal (not axis-aligned on the Calgary grid).
/// Returns an empty list for axis-aligned bridges (ratio outside 0.2–5.0).
///
/// The bend is placed at the nearest street-corner intersection:
/// - If the horizontal span is larger, go horizontal first (bend at from.lat, to.lng).
/// - Otherwise go vertical first (bend at to.lat, from.lng).
List<LatLng> inferGridWaypoint(LatLng from, LatLng to) {
  final dlat = (to.latitude - from.latitude).abs();
  final dlng = (to.longitude - from.longitude).abs();
  if (dlng == 0) return const [];
  final ratio = dlat / dlng;
  if (ratio < 0.2 || ratio > 5.0) return const [];
  if (dlng >= dlat) {
    return [LatLng(from.latitude, to.longitude)];
  } else {
    return [LatLng(to.latitude, from.longitude)];
  }
}
