import 'dart:ui';

import 'package:flutter/material.dart';

import '../../core/design/palette.dart';
import 'iso_scene.dart';

class IsoPainter extends CustomPainter {
  final IsoScene scene;
  final Brightness brightness;
  final double routeT;

  IsoPainter({
    required this.scene,
    required this.brightness,
    required this.routeT,
  });

  @override
  void paint(Canvas canvas, Size size) {
    _paintSky(canvas, size);
    _paintGroundGrid(canvas, size);

    for (final b in scene.buildings) {
      _paintBuilding(canvas, b);
    }
    for (final br in scene.bridges) {
      _paintBridge(canvas, br);
    }
    _paintRouteOverlay(canvas);
    _paintRouteEndpoints(canvas);
  }

  void _paintSky(Canvas canvas, Size size) {
    final gradient = brightness == Brightness.dark
        ? P15Palette.skyGradientDark
        : P15Palette.skyGradientLight;
    final rect = Offset.zero & size;
    final paint = Paint()..shader = gradient.createShader(rect);
    canvas.drawRect(rect, paint);
  }

  void _paintGroundGrid(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = (brightness == Brightness.dark
              ? Colors.white
              : Colors.black)
          .withValues(alpha: 0.05)
      ..strokeWidth = 0.6;

    const step = 36.0;
    for (var x = size.width / 2 % step; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (var y = size.height / 2 % step; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  void _paintBuilding(Canvas canvas, ProjectedBuilding b) {
    // Sort side faces by their centroid depth so back faces draw first.
    final sortedSides = [...b.sideFaces]..sort((a, c) {
        final ay = (a[0].dy + a[2].dy) / 2;
        final cy = (c[0].dy + c[2].dy) / 2;
        return ay.compareTo(cy);
      });

    // Back faces first (deeper in screen y means higher up the canvas).
    for (final face in sortedSides) {
      // Decide light vs dark side by face normal direction in screen space.
      final dx = (face[1].dx - face[0].dx);
      final lighter = dx < 0;
      final paint = Paint()
        ..color = lighter ? b.colorLeft : b.colorRight
        ..style = PaintingStyle.fill;
      canvas.drawPath(_polygonPath(face), paint);
    }

    final topPaint = Paint()..color = b.colorTop;
    final topPath = _polygonPath(b.top);
    canvas.drawPath(topPath, topPaint);

    if (b.highlighted || b.selected) {
      final outline = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = b.selected ? 2.2 : 1.4
        ..color = b.selected ? P15Palette.electricBlue : P15Palette.cyanGlow;
      canvas.drawPath(topPath, outline);

      if (b.selected) {
        canvas.drawPath(
          topPath,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 10
            ..color = P15Palette.electricBlue.withValues(alpha: 0.22)
            ..maskFilter = const MaskFilter.blur(BlurStyle.outer, 5),
        );
      }
    }
  }

  void _paintBridge(Canvas canvas, ProjectedBridge br) {
    final passes = br.onRoute
        ? const [(18.0, 0.28), (10.0, 0.55), (4.5, 1.0)]
        : const [(8.0, 0.18), (3.5, 0.55), (1.6, 1.0)];

    final path = _polylinePath(br.samples);
    for (final pass in passes) {
      final width = pass.$1;
      final alpha = pass.$2;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = width
        ..color = br.color.withValues(alpha: alpha);
      if (width > 4) {
        paint.maskFilter = MaskFilter.blur(BlurStyle.normal, width * 0.35);
      }
      canvas.drawPath(path, paint);
    }
  }

  void _paintRouteOverlay(Canvas canvas) {
    if (scene.routePolyline.length < 2) return;
    final path = _polylinePath(scene.routePolyline);

    // Animated traveling glow — a moving spotlight along the path.
    final total = scene.routeCumulative.isEmpty
        ? 0.0
        : scene.routeCumulative.last;
    if (total > 0) {
      final pos = _pointAlongPolyline(routeT * total);
      if (pos != null) {
        canvas.drawCircle(
          pos,
          14,
          Paint()
            ..color = P15Palette.cyanGlow.withValues(alpha: 0.55)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
        );
        canvas.drawCircle(
          pos,
          5.5,
          Paint()..color = Colors.white,
        );
        canvas.drawCircle(
          pos,
          3,
          Paint()..color = P15Palette.electricBlue,
        );
      }
    }

    // Bright top stroke on the route itself.
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = 2.2
        ..color = Colors.white.withValues(alpha: 0.85),
    );
  }

  Offset? _pointAlongPolyline(double distance) {
    if (scene.routePolyline.isEmpty) return null;
    final cum = scene.routeCumulative;
    if (cum.isEmpty) return scene.routePolyline.first;
    if (distance <= 0) return scene.routePolyline.first;
    if (distance >= cum.last) return scene.routePolyline.last;
    for (var i = 1; i < cum.length; i++) {
      if (cum[i] >= distance) {
        final segLength = cum[i] - cum[i - 1];
        if (segLength <= 0) return scene.routePolyline[i];
        final t = (distance - cum[i - 1]) / segLength;
        final a = scene.routePolyline[i - 1];
        final b = scene.routePolyline[i];
        return Offset(
          a.dx + (b.dx - a.dx) * t,
          a.dy + (b.dy - a.dy) * t,
        );
      }
    }
    return scene.routePolyline.last;
  }

  void _paintRouteEndpoints(Canvas canvas) {
    final start = scene.routeStart;
    final end = scene.routeEnd;
    if (start != null) {
      _paintPin(canvas, start, P15Palette.limeSuccess);
    }
    if (end != null) {
      _paintPin(canvas, end, P15Palette.danger);
    }
  }

  void _paintPin(Canvas canvas, Offset center, Color color) {
    canvas.drawCircle(
      center,
      14,
      Paint()
        ..color = color.withValues(alpha: 0.35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
    );
    canvas.drawCircle(center, 7, Paint()..color = Colors.white);
    canvas.drawCircle(center, 5, Paint()..color = color);
  }

  Path _polygonPath(List<Offset> poly) {
    final path = Path();
    if (poly.isEmpty) return path;
    path.moveTo(poly.first.dx, poly.first.dy);
    for (var i = 1; i < poly.length; i++) {
      path.lineTo(poly[i].dx, poly[i].dy);
    }
    path.close();
    return path;
  }

  Path _polylinePath(List<Offset> poly) {
    final path = Path();
    if (poly.isEmpty) return path;
    path.moveTo(poly.first.dx, poly.first.dy);
    for (var i = 1; i < poly.length; i++) {
      path.lineTo(poly[i].dx, poly[i].dy);
    }
    return path;
  }

  @override
  bool shouldRepaint(covariant IsoPainter oldDelegate) {
    return oldDelegate.scene != scene ||
        oldDelegate.routeT != routeT ||
        oldDelegate.brightness != brightness;
  }
}

