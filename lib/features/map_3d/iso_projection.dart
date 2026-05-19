import 'dart:math' as math;
import 'dart:ui';

import 'package:latlong2/latlong.dart';

import 'iso_camera.dart';

/// Pure projection math. No Flutter dependencies beyond `Offset` / `Size`.
///
/// World convention:
///   x = east (meters from camera.center)
///   y = north (meters from camera.center)
///   z = up (meters above ground)
class IsoProjection {
  final IsoCamera camera;
  final Size viewport;

  IsoProjection({required this.camera, required this.viewport})
      : _cosYaw = math.cos(camera.yawRad),
        _sinYaw = math.sin(camera.yawRad),
        _cosTilt = math.cos(camera.tiltRad),
        _sinTilt = math.sin(camera.tiltRad);

  final double _cosYaw;
  final double _sinYaw;
  final double _cosTilt;
  final double _sinTilt;

  /// Convert lat/lng to meters relative to `camera.center`.
  /// Uses an equirectangular approximation — good enough across downtown.
  Offset latLngToWorld(LatLng p) {
    final cosLat = math.cos(camera.center.latitude * math.pi / 180);
    final xM = (p.longitude - camera.center.longitude) * 111000 * cosLat;
    final yM = (p.latitude - camera.center.latitude) * 111000;
    return Offset(xM, yM);
  }

  /// Project a world-space point `(xM, yM, zM)` to screen pixels.
  Offset project(double xM, double yM, double zM) {
    final scale = camera.effectiveScale;
    // Rotate around z.
    final rx = xM * _cosYaw - yM * _sinYaw;
    final ry = xM * _sinYaw + yM * _cosYaw;
    // Apply tilt: y compresses by cosTilt, z lifts upward by sinTilt.
    final sx = rx * scale + viewport.width / 2 + camera.panX;
    final sy = -(ry * _cosTilt - zM * _sinTilt) * scale +
        viewport.height / 2 +
        camera.panY;
    return Offset(sx, sy);
  }

  /// Convenience for lat/lng + height.
  Offset projectLatLng(LatLng p, {double heightM = 0}) {
    final world = latLngToWorld(p);
    return project(world.dx, world.dy, heightM);
  }

  /// Depth proxy used for painter's-algorithm back-to-front sorting.
  /// Returns higher values for points further from the viewer.
  double depth(double xM, double yM) {
    final ry = xM * _sinYaw + yM * _cosYaw;
    return -ry; // points with larger ry are further "back" in screen y
  }
}
