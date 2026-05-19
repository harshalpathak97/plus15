import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

/// Stateless camera description for the isometric scene.
///
/// All projections are pure functions of the camera; the view layer mutates
/// it via `copyWith` and rebuilds the scene.
class IsoCamera {
  /// Anchor in the world. World meters are computed relative to this point.
  final LatLng center;

  /// Base meters-per-pixel before `zoom` is applied.
  final double scale;

  /// Rotation around the up axis. 0 = north up.
  final double yawRad;

  /// Tilt from top-down. 0 = top-down (everything flat), π/2 = horizon.
  /// Stylized isometric sits comfortably around π/6.
  final double tiltRad;

  /// Multiplicative zoom factor applied to `scale`.
  final double zoom;

  /// Screen-space pan offset (pixels).
  final double panX;
  final double panY;

  const IsoCamera({
    required this.center,
    this.scale = 1.6,
    this.yawRad = 0.0,
    this.tiltRad = math.pi / 6,
    this.zoom = 1.0,
    this.panX = 0,
    this.panY = 0,
  });

  static const _kZoomMin = 0.45;
  static const _kZoomMax = 4.2;
  static const _kTiltMin = math.pi / 8; // ~22.5°
  static const _kTiltMax = math.pi / 3; // ~60°

  IsoCamera copyWith({
    LatLng? center,
    double? scale,
    double? yawRad,
    double? tiltRad,
    double? zoom,
    double? panX,
    double? panY,
  }) {
    return IsoCamera(
      center: center ?? this.center,
      scale: scale ?? this.scale,
      yawRad: yawRad ?? this.yawRad,
      tiltRad: (tiltRad ?? this.tiltRad).clamp(_kTiltMin, _kTiltMax),
      zoom: (zoom ?? this.zoom).clamp(_kZoomMin, _kZoomMax),
      panX: panX ?? this.panX,
      panY: panY ?? this.panY,
    );
  }

  double get effectiveScale => scale * zoom;
}
