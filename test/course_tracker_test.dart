import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:plus15_navigator/features/map/services/course_tracker.dart';

import 'routing/support.dart';

void main() {
  final route = mustRoute('the_bow', 'bankers_hall');
  final g = route.geometry;
  late CourseTracker tracker;
  setUp(() => tracker = CourseTracker(route));

  test('on the drawn route: zero offset, progress along the edges', () {
    final mid = g[g.length ~/ 2];
    final p = tracker.progressAt(LatLng(mid[0], mid[1]));
    expect(p.offRouteM, lessThan(0.5));
    expect(p.traveledM, greaterThan(0));
    expect(p.remainingM, lessThan(route.lengthM));
    expect(p.traveledM + p.remainingM, closeTo(route.lengthM, 1));
  });

  test('start and end of the route', () {
    expect(tracker.progressAt(LatLng(g.first[0], g.first[1])).traveledM, lessThan(1));
    final end = tracker.progressAt(LatLng(g.last[0], g.last[1]));
    expect(end.remainingM, lessThan(1));
    expect(end.stepIndex, route.steps.length - 1);
  });

  test('a fix one block away is reported off-route', () {
    final p = tracker.progressAt(LatLng(g.first[0] + 0.0012, g.first[1])); // ~130 m north
    expect(p.offRouteM, greaterThan(60));
  });

  test('next instruction advances with progress', () {
    final early = tracker.progressAt(LatLng(g[1][0], g[1][1])).stepIndex;
    final late = tracker.progressAt(LatLng(g[g.length - 2][0], g[g.length - 2][1])).stepIndex;
    expect(late, greaterThan(early));
  });

  test('progress never jumps back to an earlier part of the route', () {
    tracker.progressAt(LatLng(g.last[0], g.last[1]));
    final p = tracker.progressAt(LatLng(g.first[0], g.first[1]));
    expect(p.remainingM, lessThan(route.lengthM / 2));
  });

  test('a zero-hop route (same building) is already arrived, never infinite', () {
    final same = mustRoute('the_bow', 'the_bow');
    final p = CourseTracker(same).progressAt(const LatLng(51.05, -114.06));
    expect(p.offRouteM, 0);
    expect(p.remainingM, 0);
    expect(p.offRouteM.isFinite, isTrue);
  });
}
