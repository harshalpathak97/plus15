import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:plus15_navigator/features/map3d/scene3d.dart';

void main() {
  group('Scene3D projection', () {
    test('origin maps to local (0,0)', () {
      final p = Scene3D.toLocal(Scene3D.originLat, Scene3D.originLng);
      expect(p.dx, closeTo(0, 0.001));
      expect(p.dy, closeTo(0, 0.001));
    });

    test('one degree north is ~111 km, east scales by cos(lat)', () {
      final north = Scene3D.toLocal(Scene3D.originLat + 0.01, Scene3D.originLng);
      expect(north.dy, closeTo(1111.32, 1));
      final east = Scene3D.toLocal(Scene3D.originLat, Scene3D.originLng + 0.01);
      expect(east.dx, closeTo(1113.20 * math.cos(51.0478 * math.pi / 180), 2));
    });
  });

  group('CameraFrame', () {
    test('the look-at target projects to the screen centre', () {
      final cam = OrbitCamera(
          target: const Offset(100, 50), targetZ: 5, yaw: 0.7, distance: 300);
      final frame = CameraFrame(cam, const Size(400, 800));
      final p = frame.project(100, 50, 5);
      expect(p, isNotNull);
      expect(p!.dx, closeTo(200, 0.5));
      expect(p.dy, closeTo(400, 0.5));
    });

    test('points behind the camera return null', () {
      final cam = OrbitCamera(target: Offset.zero, yaw: 0, distance: 200);
      final frame = CameraFrame(cam, const Size(400, 800));
      // Camera sits south of the target looking north; far south is behind it.
      expect(frame.project(0, -5000, 0), isNull);
    });

    test('nearer points are bigger (perspective)', () {
      final cam = OrbitCamera(
          target: Offset.zero, yaw: 0, pitch: 0.6, distance: 300);
      final frame = CameraFrame(cam, const Size(400, 800));
      // Two points 10 m apart at different depths along the view.
      final nearA = frame.project(-5, -100, 5)!;
      final nearB = frame.project(5, -100, 5)!;
      final farA = frame.project(-5, 200, 5)!;
      final farB = frame.project(5, 200, 5)!;
      expect((nearB.dx - nearA.dx).abs(),
          greaterThan((farB.dx - farA.dx).abs()));
    });
  });

  group('RoutePath3D', () {
    final path = RoutePath3D.fromLatLng([
      const LatLng(51.0478, -114.0670),
      const LatLng(51.0487, -114.0670), // ~100 m north
      const LatLng(51.0487, -114.0656), // ~100 m east
    ]);

    test('total length is the sum of both legs', () {
      expect(path.total, closeTo(198, 6));
    });

    test('pointAt interpolates along the path', () {
      final start = path.pointAt(0);
      final mid = path.pointAt(0.5);
      final end = path.pointAt(1);
      expect(start.dy, closeTo(0, 0.01));
      // Halfway is at the corner (end of the ~100 m north leg).
      expect(mid.dy, closeTo(path.points[1].dy, 2));
      expect(end.dx, closeTo(path.points[2].dx, 0.01));
    });

    test('headingAt points north on the first leg, east on the second', () {
      expect(path.headingAt(0.1), closeTo(0, 0.15)); // north
      expect(path.headingAt(0.8), closeTo(math.pi / 2, 0.15)); // east
    });

    test('nearestT finds the closest position on the path', () {
      // A point just west of the midpoint of the first leg.
      final probe = Offset(-10, path.points[1].dy / 2);
      final t = path.nearestT(probe);
      expect(t, closeTo(0.25, 0.05));
    });
  });

  group('lerpAngle', () {
    test('takes the short way around', () {
      final result = lerpAngle(0.1, 2 * math.pi - 0.1, 0.5);
      expect(math.sin(result), closeTo(0, 0.01));
      expect(math.cos(result), closeTo(1, 0.01));
    });
  });
}
