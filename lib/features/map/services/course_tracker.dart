import 'dart:math';
import 'package:latlong2/latlong.dart';
import '../../../data/models/building.dart';
import '../../../data/models/bridge.dart';
import '../../../data/models/entry_point.dart';
import '../../../data/graph/pathfinder.dart';
import '../../../data/graph/plus15_graph.dart';

class RouteProgress {
  final double traveledM;
  final double remainingM;
  final double progress;
  final String? nextNodeId;

  const RouteProgress({
    required this.traveledM,
    required this.remainingM,
    required this.progress,
    required this.nextNodeId,
  });
}

class EntryRouteChoice {
  final EntryPoint entryPoint;
  final RouteResult route;
  final double scoreM;
  final double userToEntryM;

  const EntryRouteChoice({
    required this.entryPoint,
    required this.route,
    required this.scoreM,
    required this.userToEntryM,
  });
}

class CourseTracker {
  final Plus15Graph graph;
  final Map<String, Building> buildingMap;

  const CourseTracker({
    required this.graph,
    required this.buildingMap,
  });

  double distanceToRouteM(LatLng user, List<String> route) {
    if (route.length < 2) return double.infinity;

    var best = double.infinity;
    for (int i = 0; i < route.length - 1; i++) {
      final from = buildingMap[route[i]];
      final to = buildingMap[route[i + 1]];
      if (from == null || to == null) continue;
      final d = _distanceToSegmentM(
        user,
        LatLng(from.lat, from.lng),
        LatLng(to.lat, to.lng),
      );
      if (d < best) best = d;
    }
    return best;
  }

  bool isOnRoute(
    LatLng user,
    List<String> route, {
    double thresholdM = 20,
  }) {
    return distanceToRouteM(user, route) <= thresholdM;
  }

  double distanceToNetworkM(LatLng user, List<Bridge> bridges) {
    var best = double.infinity;
    for (final br in bridges) {
      if (br.status != 'open') continue;
      final from = buildingMap[br.fromBuildingId];
      final to = buildingMap[br.toBuildingId];
      if (from == null || to == null) continue;
      final d = _distanceToSegmentM(
        user,
        LatLng(from.lat, from.lng),
        LatLng(to.lat, to.lng),
      );
      if (d < best) best = d;
    }
    return best;
  }

  bool isNearNetwork(
    LatLng user,
    List<Bridge> bridges, {
    double thresholdM = 60,
  }) {
    return distanceToNetworkM(user, bridges) <= thresholdM;
  }

  String? nearestRouteNode(LatLng user, List<String> route) {
    var bestId = null as String?;
    var best = double.infinity;

    for (final nodeId in route) {
      final b = buildingMap[nodeId];
      if (b == null) continue;
      final d = _distance(user.latitude, user.longitude, b.lat, b.lng);
      if (d < best) {
        best = d;
        bestId = nodeId;
      }
    }

    return bestId;
  }

  String? nearestGraphNode(LatLng user) {
    var bestId = null as String?;
    var best = double.infinity;

    for (final b in buildingMap.values) {
      final edges = graph.adjacency[b.id] ?? const [];
      if (edges.where((e) => e.bridge.status == 'open').isEmpty) {
        continue;
      }
      final d = _distance(user.latitude, user.longitude, b.lat, b.lng);
      if (d < best) {
        best = d;
        bestId = b.id;
      }
    }

    return bestId;
  }

  RouteProgress computeProgress(List<String> route, String nearestNodeId) {
    if (route.isEmpty) {
      return const RouteProgress(
        traveledM: 0,
        remainingM: 0,
        progress: 0,
        nextNodeId: null,
      );
    }

    final nearestIndex = route.indexOf(nearestNodeId);
    if (nearestIndex == -1) {
      return const RouteProgress(
        traveledM: 0,
        remainingM: 0,
        progress: 0,
        nextNodeId: null,
      );
    }

    double total = 0;
    final cumulative = <double>[0];

    for (int i = 0; i < route.length - 1; i++) {
      final bridge = graph.getBridge(route[i], route[i + 1]);
      final segment = bridge?.distanceM ??
          _distanceBetweenBuildings(route[i], route[i + 1]);
      total += segment;
      cumulative.add(total);
    }

    final traveled = cumulative[nearestIndex].clamp(0.0, total).toDouble();
    final remaining = (total - traveled).clamp(0.0, total).toDouble();
    final progress = total <= 0 ? 0.0 : (traveled / total).clamp(0.0, 1.0);

    return RouteProgress(
      traveledM: traveled,
      remainingM: remaining,
      progress: progress,
      nextNodeId:
          nearestIndex < route.length - 1 ? route[nearestIndex + 1] : null,
    );
  }

  EntryRouteChoice? chooseBestEntryPoint({
    required LatLng user,
    required List<EntryPoint> entryPoints,
    required String destinationId,
    required Pathfinder pathfinder,
    required bool accessibilityMode,
    String mode = 'fastest',
  }) {
    EntryRouteChoice? best;

    for (final entry in entryPoints) {
      if (accessibilityMode && !entry.isAccessible) continue;
      final result = pathfinder.findRoute(entry.buildingId, destinationId,
          mode: accessibilityMode ? 'accessible' : mode);
      if (result == null || result.path.isEmpty) continue;

      final userToEntry =
          _distance(user.latitude, user.longitude, entry.lat, entry.lng);
      final score = userToEntry + result.totalDistance - (entry.priority * 12);

      if (best == null || score < best.scoreM) {
        best = EntryRouteChoice(
          entryPoint: entry,
          route: result,
          scoreM: score,
          userToEntryM: userToEntry,
        );
      }
    }

    return best;
  }

  double _distanceBetweenBuildings(String fromId, String toId) {
    final from = buildingMap[fromId];
    final to = buildingMap[toId];
    if (from == null || to == null) return 0;
    return _distance(from.lat, from.lng, to.lat, to.lng);
  }

  double _distance(double lat1, double lng1, double lat2, double lng2) {
    return _distanceFn(lat1, lng1, lat2, lng2);
  }

  double _distanceToSegmentM(LatLng p, LatLng a, LatLng b) {
    final ax = a.longitude;
    final ay = a.latitude;
    final bx = b.longitude;
    final by = b.latitude;
    final px = p.longitude;
    final py = p.latitude;

    final abx = bx - ax;
    final aby = by - ay;
    final abLenSq = abx * abx + aby * aby;
    if (abLenSq <= 0) {
      return _distance(py, px, ay, ax);
    }

    final apx = px - ax;
    final apy = py - ay;
    final t = ((apx * abx + apy * aby) / abLenSq).clamp(0.0, 1.0);

    final cx = ax + abx * t;
    final cy = ay + aby * t;

    return _distance(py, px, cy, cx);
  }

  double _distanceFn(double lat1, double lng1, double lat2, double lng2) {
    final dLat = (lat1 - lat2) * 111000;
    final dLng = (lng1 - lng2) * 111000 * cos(lat1 * pi / 180);
    return sqrt(dLat * dLat + dLng * dLng);
  }
}
