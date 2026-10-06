import 'package:latlong2/latlong.dart';
import '../../../routing/geo.dart';
import '../../../routing/router.dart';

class RouteProgress {
  final double traveledM;
  final double remainingM;
  final double offRouteM;
  /// Index into the route's steps of the next instruction to follow.
  final int stepIndex;

  const RouteProgress({
    required this.traveledM,
    required this.remainingM,
    required this.offRouteM,
    required this.stepIndex,
  });
}

/// Tracks a GPS position against the route *as drawn*: the exact geometry of
/// the graph edges the route uses (not building centroids).
class CourseTracker {
  final PlannedRoute route;
  final List<P> _pts;
  final List<double> _cum; // distance along the route at each point
  final List<double> _stepEnds; // distance at the end of each step

  CourseTracker(this.route)
      : _pts = [for (final p in route.geometry) project(p[0], p[1])],
        _cum = [],
        _stepEnds = [] {
    var acc = 0.0;
    for (var i = 0; i < _pts.length; i++) {
      if (i > 0) acc += _pts[i - 1].dist(_pts[i]);
      _cum.add(acc);
    }
    var s = 0.0;
    for (final step in route.steps) {
      s += step.distanceM;
      _stepEnds.add(s);
    }
  }

  double get totalM => _cum.isEmpty ? 0 : _cum.last;

  RouteProgress progressAt(LatLng user) {
    final u = project(user.latitude, user.longitude);
    if (_pts.length < 2) {
      return RouteProgress(
          traveledM: 0,
          remainingM: 0,
          offRouteM: _pts.isEmpty ? double.infinity : u.dist(_pts.first),
          stepIndex: route.steps.length - 1);
    }
    var best = double.infinity;
    var along = 0.0;
    for (var i = 1; i < _pts.length; i++) {
      final c = closestOnSegment(u, _pts[i - 1], _pts[i]);
      final d = c.dist(u);
      if (d < best) {
        best = d;
        along = _cum[i - 1] + _pts[i - 1].dist(c);
      }
    }
    // Route geometry lengths and step distances can differ by a few metres
    // (street exits add a nominal level change), so scale to step distances.
    final scale = totalM <= 0 || _stepEnds.isEmpty ? 1.0 : _stepEnds.last / totalM;
    final travelled = along * scale;
    var step = _stepEnds.indexWhere((e) => e > travelled + 3);
    if (step < 0) step = route.steps.length - 1;
    return RouteProgress(
      traveledM: travelled,
      remainingM: ((_stepEnds.isEmpty ? 0 : _stepEnds.last) - travelled).clamp(0, double.infinity),
      offRouteM: best,
      stepIndex: step,
    );
  }
}
