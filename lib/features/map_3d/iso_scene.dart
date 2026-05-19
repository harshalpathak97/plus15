import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../core/design/palette.dart';
import '../../data/models/building.dart';
import '../../data/models/bridge.dart';
import 'iso_projection.dart';

/// Pre-computed building geometry for the painter.
///
/// Each face is stored as a screen-space polygon so painting becomes
/// `canvas.drawPath` instead of repeated re-projection per frame.
class ProjectedBuilding {
  final String id;
  final Building source;
  final List<Offset> base;
  final List<Offset> top;
  final List<List<Offset>> sideFaces;
  final double depth;
  final Color colorTop;
  final Color colorLeft;
  final Color colorRight;
  final bool highlighted;
  final bool selected;
  final Offset topCentroid;

  const ProjectedBuilding({
    required this.id,
    required this.source,
    required this.base,
    required this.top,
    required this.sideFaces,
    required this.depth,
    required this.colorTop,
    required this.colorLeft,
    required this.colorRight,
    required this.highlighted,
    required this.selected,
    required this.topCentroid,
  });

  bool containsScreen(Offset p) {
    if (_pointInPolygon(p, top)) return true;
    if (_pointInPolygon(p, base)) return true;
    for (final f in sideFaces) {
      if (_pointInPolygon(p, f)) return true;
    }
    return false;
  }
}

class ProjectedBridge {
  final String id;
  final Bridge source;
  final List<Offset> samples; // bezier samples in screen space
  final double depth;
  final bool onRoute;
  final Color color;

  const ProjectedBridge({
    required this.id,
    required this.source,
    required this.samples,
    required this.depth,
    required this.onRoute,
    required this.color,
  });
}

class IsoScene {
  /// Buildings sorted back-to-front for painter's-algorithm rendering.
  final List<ProjectedBuilding> buildings;

  /// Bridges sorted by midpoint depth.
  final List<ProjectedBridge> bridges;

  /// Concatenated active-route polyline in screen space, for traveling-dot
  /// animation. Empty when no route.
  final List<Offset> routePolyline;

  /// Cumulative arc-length along `routePolyline` for `t`-to-point lookup.
  final List<double> routeCumulative;

  /// Endpoint highlight positions: start (green) and end (red).
  final Offset? routeStart;
  final Offset? routeEnd;

  const IsoScene({
    required this.buildings,
    required this.bridges,
    required this.routePolyline,
    required this.routeCumulative,
    this.routeStart,
    this.routeEnd,
  });

  static const _kHeightExaggeration = 1.25;
  static const _kPlus15HeightM = 6.0;
  static const _kFallbackFootprintM = 32.0;

  static IsoScene build({
    required IsoProjection projection,
    required List<Building> buildings,
    required List<Bridge> bridges,
    required Brightness brightness,
    List<String>? activeRoute,
    String? selectedBuildingId,
  }) {
    final routeSet = activeRoute?.toSet() ?? const <String>{};

    final projected = <ProjectedBuilding>[];
    for (final b in buildings) {
      final pb = _projectBuilding(
        b,
        projection,
        brightness,
        routeSet.contains(b.id),
        b.id == selectedBuildingId,
      );
      if (pb != null) projected.add(pb);
    }
    projected.sort((a, b) => a.depth.compareTo(b.depth));

    final byId = {for (final b in buildings) b.id: b};
    final projectedBridges = <ProjectedBridge>[];
    for (final br in bridges) {
      if (br.status != 'open') continue;
      final from = byId[br.fromBuildingId];
      final to = byId[br.toBuildingId];
      if (from == null || to == null) continue;
      final onRoute = _edgeOnRoute(br.fromBuildingId, br.toBuildingId, activeRoute);
      projectedBridges.add(_projectBridge(
        br,
        from,
        to,
        projection,
        brightness,
        onRoute,
      ));
    }
    projectedBridges.sort((a, b) => a.depth.compareTo(b.depth));

    // Compute route polyline by walking the activeRoute edges in order.
    final routePoints = <Offset>[];
    Offset? start;
    Offset? end;
    if (activeRoute != null && activeRoute.length > 1) {
      ProjectedBridge? findEdge(String fromId, String toId) {
        for (final e in projectedBridges) {
          final s = e.source;
          if ((s.fromBuildingId == fromId && s.toBuildingId == toId) ||
              (s.fromBuildingId == toId && s.toBuildingId == fromId)) {
            return e;
          }
        }
        return null;
      }

      for (var i = 0; i < activeRoute.length - 1; i++) {
        final fromId = activeRoute[i];
        final toId = activeRoute[i + 1];
        final br = findEdge(fromId, toId);
        if (br == null) continue;
        final reverse = br.source.fromBuildingId != fromId;
        final samples =
            reverse ? br.samples.reversed.toList() : br.samples;
        for (var j = 0; j < samples.length; j++) {
          if (i == 0 && j == 0) {
            routePoints.add(samples[j]);
            continue;
          }
          if (j == 0) continue; // skip duplicated shared endpoint
          routePoints.add(samples[j]);
        }
      }

      if (routePoints.isNotEmpty) {
        start = routePoints.first;
        end = routePoints.last;
      }
    }

    final cumulative = <double>[];
    double acc = 0;
    for (var i = 0; i < routePoints.length; i++) {
      if (i == 0) {
        cumulative.add(0);
      } else {
        acc += (routePoints[i] - routePoints[i - 1]).distance;
        cumulative.add(acc);
      }
    }

    return IsoScene(
      buildings: projected,
      bridges: projectedBridges,
      routePolyline: routePoints,
      routeCumulative: cumulative,
      routeStart: start,
      routeEnd: end,
    );
  }

  static ProjectedBuilding? _projectBuilding(
    Building b,
    IsoProjection p,
    Brightness brightness,
    bool onRoute,
    bool selected,
  ) {
    final centerWorld = p.latLngToWorld(LatLng(b.lat, b.lng));
    final heightM = (b.heightM <= 0 ? 60.0 : b.heightM) * _kHeightExaggeration;

    final footprintWorld = b.footprint.isNotEmpty
        ? b.footprint.map((ll) {
            final w = p.latLngToWorld(ll);
            return Offset(w.dx, w.dy);
          }).toList()
        : _squareFootprint(centerWorld, _kFallbackFootprintM);

    final base = footprintWorld
        .map((w) => p.project(w.dx, w.dy, 0))
        .toList(growable: false);
    final top = footprintWorld
        .map((w) => p.project(w.dx, w.dy, heightM))
        .toList(growable: false);

    final sideFaces = <List<Offset>>[];
    for (var i = 0; i < footprintWorld.length; i++) {
      final next = (i + 1) % footprintWorld.length;
      sideFaces.add([base[i], base[next], top[next], top[i]]);
    }

    final baseColor = _buildingColor(b, brightness, onRoute, selected);
    final colorTop = Color.lerp(baseColor, Colors.white, 0.22)!;
    final colorLeft = baseColor;
    final colorRight = Color.lerp(baseColor, Colors.black, 0.28)!;

    return ProjectedBuilding(
      id: b.id,
      source: b,
      base: base,
      top: top,
      sideFaces: sideFaces,
      depth: p.depth(centerWorld.dx, centerWorld.dy),
      colorTop: colorTop,
      colorLeft: colorLeft,
      colorRight: colorRight,
      highlighted: onRoute,
      selected: selected,
      topCentroid: _centroid(top),
    );
  }

  static Color _buildingColor(
    Building b,
    Brightness brightness,
    bool onRoute,
    bool selected,
  ) {
    var color = P15Palette.colorForType(b.type);
    if (b.amenities.contains('transit')) color = P15Palette.typeTransit;
    if (selected) {
      color = Color.lerp(color, P15Palette.electricBlue, 0.7)!;
    } else if (onRoute) {
      color = Color.lerp(color, P15Palette.cyanGlow, 0.45)!;
    }
    if (brightness == Brightness.dark) {
      color = Color.lerp(color, Colors.black, 0.18)!;
    }
    return color;
  }

  static List<Offset> _squareFootprint(Offset centerWorld, double sizeM) {
    final h = sizeM / 2;
    return [
      Offset(centerWorld.dx - h, centerWorld.dy - h),
      Offset(centerWorld.dx + h, centerWorld.dy - h),
      Offset(centerWorld.dx + h, centerWorld.dy + h),
      Offset(centerWorld.dx - h, centerWorld.dy + h),
    ];
  }

  static Offset _centroid(List<Offset> poly) {
    if (poly.isEmpty) return Offset.zero;
    double sx = 0, sy = 0;
    for (final p in poly) {
      sx += p.dx;
      sy += p.dy;
    }
    return Offset(sx / poly.length, sy / poly.length);
  }

  static bool _edgeOnRoute(String fromId, String toId, List<String>? route) {
    if (route == null) return false;
    for (var i = 0; i < route.length - 1; i++) {
      if ((route[i] == fromId && route[i + 1] == toId) ||
          (route[i] == toId && route[i + 1] == fromId)) {
        return true;
      }
    }
    return false;
  }

  static ProjectedBridge _projectBridge(
    Bridge bridge,
    Building from,
    Building to,
    IsoProjection p,
    Brightness brightness,
    bool onRoute,
  ) {
    final fromHeight = (from.heightM <= 0 ? 60.0 : from.heightM) *
            _kHeightExaggeration +
        _kPlus15HeightM;
    final toHeight =
        (to.heightM <= 0 ? 60.0 : to.heightM) * _kHeightExaggeration +
            _kPlus15HeightM;
    final fromW = p.latLngToWorld(LatLng(from.lat, from.lng));
    final toW = p.latLngToWorld(LatLng(to.lat, to.lng));

    // Control point lifts slightly above the midpoint for a gentle arc.
    final midX = (fromW.dx + toW.dx) / 2;
    final midY = (fromW.dy + toW.dy) / 2;
    final maxH = math.max(fromHeight, toHeight);
    final controlZ = maxH + 8;

    const samplesCount = 16;
    final samples = <Offset>[];
    for (var i = 0; i <= samplesCount; i++) {
      final t = i / samplesCount;
      final mt = 1 - t;
      final wx = mt * mt * fromW.dx + 2 * mt * t * midX + t * t * toW.dx;
      final wy = mt * mt * fromW.dy + 2 * mt * t * midY + t * t * toW.dy;
      final zStart = mt * mt * fromHeight;
      final zEnd = t * t * toHeight;
      final zCtrl = 2 * mt * t * controlZ;
      samples.add(p.project(wx, wy, zStart + zCtrl + zEnd));
    }

    final color = onRoute
        ? P15Palette.cyanGlow
        : (brightness == Brightness.dark
            ? const Color(0xFF60A5FA)
            : const Color(0xFF3B82F6));

    final midScreenIdx = samples.length ~/ 2;
    final midX2 = samples[midScreenIdx].dy;

    return ProjectedBridge(
      id: bridge.id,
      source: bridge,
      samples: samples,
      depth: midX2,
      onRoute: onRoute,
      color: color,
    );
  }
}

bool _pointInPolygon(Offset p, List<Offset> poly) {
  if (poly.length < 3) return false;
  var inside = false;
  for (var i = 0, j = poly.length - 1; i < poly.length; j = i++) {
    final xi = poly[i].dx, yi = poly[i].dy;
    final xj = poly[j].dx, yj = poly[j].dy;
    final intersect = ((yi > p.dy) != (yj > p.dy)) &&
        (p.dx < (xj - xi) * (p.dy - yi) / ((yj - yi) == 0 ? 1e-9 : (yj - yi)) + xi);
    if (intersect) inside = !inside;
  }
  return inside;
}
