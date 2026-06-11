import 'dart:math' as math;
import 'dart:ui';

import 'package:latlong2/latlong.dart';

/// Local tangent-plane projection and a simple orbit camera for the 3D view.
///
/// World space is metres around downtown Calgary: x east, y north, z up.
/// This is pure Dart (no widgets) so the projection math stays unit-testable.
class Scene3D {
  Scene3D._();

  /// Projection origin — the same downtown centre the 2D map uses.
  static const originLat = 51.0478;
  static const originLng = -114.0670;

  static final double _mPerDegLat = 111132.0;
  static final double _mPerDegLng =
      111320.0 * math.cos(originLat * math.pi / 180);

  static Offset toLocal(double lat, double lng) => Offset(
        (lng - originLng) * _mPerDegLng,
        (lat - originLat) * _mPerDegLat,
      );

  static Offset latLngToLocal(LatLng p) => toLocal(p.latitude, p.longitude);
}

/// A point in world space (metres).
class Vec3 {
  final double x, y, z;
  const Vec3(this.x, this.y, this.z);
}

/// Orbit camera: looks at [target] from [distance] away, rotated by [yaw]
/// around the vertical axis and tilted down by [pitch].
class OrbitCamera {
  Offset target; // ground position the camera looks at
  double targetZ;
  double yaw; // radians, 0 = looking north
  double pitch; // radians above horizon, clamped (0.99 ≈ straight down)
  double distance; // metres from target
  double fovY; // vertical field of view, radians

  OrbitCamera({
    this.target = Offset.zero,
    this.targetZ = 5,
    this.yaw = 0,
    this.pitch = 0.9,
    this.distance = 400,
    this.fovY = 0.9,
  });

  static const minPitch = 0.25;
  static const maxPitch = 1.45;
  static const minDistance = 60.0;
  static const maxDistance = 2600.0;

  void clampOrbit() {
    pitch = pitch.clamp(minPitch, maxPitch);
    distance = distance.clamp(minDistance, maxDistance);
    target = Offset(
      target.dx.clamp(-2200.0, 2200.0),
      target.dy.clamp(-2200.0, 2200.0),
    );
  }

  Vec3 get eye {
    final horiz = distance * math.cos(pitch);
    return Vec3(
      target.dx - horiz * math.sin(yaw),
      target.dy - horiz * math.cos(yaw),
      targetZ + distance * math.sin(pitch),
    );
  }
}

/// A camera "frame": precomputed basis vectors + screen params for one paint.
class CameraFrame {
  final Vec3 eye;
  final double rx, ry, rz; // right
  final double ux, uy, uz; // up
  final double fx, fy, fz; // forward
  final double focal;
  final Offset center;
  static const near = 2.0;

  CameraFrame._(this.eye, this.rx, this.ry, this.rz, this.ux, this.uy,
      this.uz, this.fx, this.fy, this.fz, this.focal, this.center);

  factory CameraFrame(OrbitCamera cam, Size size) {
    final eye = cam.eye;
    // forward = normalize(target - eye)
    var fx = cam.target.dx - eye.x;
    var fy = cam.target.dy - eye.y;
    var fz = cam.targetZ - eye.z;
    final fl = math.sqrt(fx * fx + fy * fy + fz * fz);
    fx /= fl;
    fy /= fl;
    fz /= fl;
    // right = normalize(forward × worldUp)
    var rx = fy * 1 - fz * 0; // cross(f, (0,0,1))
    var ry = fz * 0 - fx * 1;
    final rl = math.sqrt(rx * rx + ry * ry);
    rx /= rl;
    ry /= rl;
    // up = right × forward
    final ux = ry * fz - 0 * fy;
    final uy = 0 * fx - rx * fz;
    final uz = rx * fy - ry * fx;
    final focal = (size.height / 2) / math.tan(cam.fovY / 2);
    return CameraFrame._(eye, rx, ry, 0, ux, uy, uz, fx, fy, fz, focal,
        Offset(size.width / 2, size.height / 2));
  }

  /// Depth (distance along the view axis) of a world point. <= near means
  /// behind / too close to the camera.
  double depth(double x, double y, double z) {
    final px = x - eye.x, py = y - eye.y, pz = z - eye.z;
    return px * fx + py * fy + pz * fz;
  }

  /// Projects a world point to screen. Returns null when behind the camera.
  Offset? project(double x, double y, double z) {
    final px = x - eye.x, py = y - eye.y, pz = z - eye.z;
    final d = px * fx + py * fy + pz * fz;
    if (d <= near) return null;
    final sx = px * rx + py * ry; // rz is always 0 (right is horizontal)
    final sy = px * ux + py * uy + pz * uz;
    return Offset(
      center.dx + focal * sx / d,
      center.dy - focal * sy / d,
    );
  }
}

/// A polyline in local metres with precomputed cumulative distances, so a
/// fly-through can ask "where is the point 37% of the way along the route?".
class RoutePath3D {
  final List<Offset> points;
  final List<double> cumulative;
  final double total;

  RoutePath3D._(this.points, this.cumulative, this.total);

  factory RoutePath3D.fromLatLng(List<LatLng> latLngs) {
    final pts = latLngs.map(Scene3D.latLngToLocal).toList();
    final cum = <double>[0];
    var total = 0.0;
    for (var i = 1; i < pts.length; i++) {
      total += (pts[i] - pts[i - 1]).distance;
      cum.add(total);
    }
    return RoutePath3D._(pts, cum, total);
  }

  bool get isUsable => points.length >= 2 && total > 1;

  /// Point at [t] in 0..1 along the path.
  Offset pointAt(double t) {
    final d = (t.clamp(0.0, 1.0)) * total;
    var i = _segmentIndex(d);
    final segLen = cumulative[i + 1] - cumulative[i];
    final f = segLen <= 0 ? 0.0 : (d - cumulative[i]) / segLen;
    return Offset.lerp(points[i], points[i + 1], f)!;
  }

  /// Heading (radians, 0 = north, clockwise) at [t], averaged over a short
  /// look-ahead window so the camera doesn't snap on corners.
  double headingAt(double t) {
    final ahead = pointAt(t + 0.03);
    final here = pointAt(t);
    final d = ahead - here;
    if (d.distance < 0.5) {
      // End of route: fall back to the last segment direction.
      final a = points[points.length - 2], b = points.last;
      return math.atan2(b.dx - a.dx, b.dy - a.dy);
    }
    return math.atan2(d.dx, d.dy);
  }

  /// Fraction 0..1 of the path nearest to a local-metre position.
  double nearestT(Offset p) {
    var bestD = double.infinity;
    var bestT = 0.0;
    for (var i = 0; i < points.length - 1; i++) {
      final a = points[i], b = points[i + 1];
      final ab = b - a;
      final len2 = ab.dx * ab.dx + ab.dy * ab.dy;
      final f = len2 <= 0
          ? 0.0
          : (((p - a).dx * ab.dx + (p - a).dy * ab.dy) / len2)
              .clamp(0.0, 1.0);
      final q = a + ab * f;
      final d = (p - q).distance;
      if (d < bestD) {
        bestD = d;
        bestT = (cumulative[i] + (cumulative[i + 1] - cumulative[i]) * f) /
            total;
      }
    }
    return bestT;
  }

  int _segmentIndex(double d) {
    var lo = 0, hi = cumulative.length - 2;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      if (cumulative[mid] <= d) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return lo;
  }
}

/// Interpolates angles along the shortest arc.
double lerpAngle(double a, double b, double t) {
  var diff = (b - a) % (2 * math.pi);
  if (diff > math.pi) diff -= 2 * math.pi;
  if (diff < -math.pi) diff += 2 * math.pi;
  return a + diff * t;
}
