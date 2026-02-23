import 'dart:math';
import 'dart:collection';
import '../models/building.dart';
import '../models/shop.dart';
import 'plus15_graph.dart';

class RouteResult {
  final List<String> path;
  final double totalDistance;
  final int bridgeCount;
  final bool fullyAccessible;

  const RouteResult({
    required this.path,
    required this.totalDistance,
    required this.bridgeCount,
    required this.fullyAccessible,
  });
}

class Pathfinder {
  final Plus15Graph graph;
  final List<Shop> shops;
  final Map<String, int> _shopCountByBuilding;

  Pathfinder({required this.graph, required this.shops})
      : _shopCountByBuilding = _countShops(shops);

  static Map<String, int> _countShops(List<Shop> shops) {
    final map = <String, int>{};
    for (final s in shops) {
      map[s.buildingId] = (map[s.buildingId] ?? 0) + 1;
    }
    return map;
  }

  RouteResult? findRoute(String fromId, String toId,
      {String mode = 'fastest'}) {
    if (fromId == toId) {
      return RouteResult(
          path: [fromId],
          totalDistance: 0,
          bridgeCount: 0,
          fullyAccessible: true);
    }

    final fromBuilding = graph.getBuilding(fromId);
    final toBuilding = graph.getBuilding(toId);
    if (fromBuilding == null || toBuilding == null) return null;

    final gScore = <String, double>{};
    final fScore = <String, double>{};
    final cameFrom = <String, String>{};
    final open = SplayTreeSet<String>((a, b) {
      final cmp = (fScore[a] ?? double.infinity)
          .compareTo(fScore[b] ?? double.infinity);
      return cmp != 0 ? cmp : a.compareTo(b);
    });
    final closed = <String>{};

    gScore[fromId] = 0;
    fScore[fromId] = _heuristic(fromBuilding, toBuilding);
    open.add(fromId);

    while (open.isNotEmpty) {
      final current = open.first;
      open.remove(current);

      if (current == toId) {
        return _reconstructPath(cameFrom, current);
      }

      closed.add(current);
      final edges = graph.adjacency[current] ?? [];

      for (final edge in edges) {
        if (closed.contains(edge.targetId)) continue;
        if (edge.bridge.status != 'open') continue;

        final edgeCost = _edgeCost(edge, mode);
        final tentativeG = (gScore[current] ?? double.infinity) + edgeCost;

        if (tentativeG < (gScore[edge.targetId] ?? double.infinity)) {
          cameFrom[edge.targetId] = current;
          gScore[edge.targetId] = tentativeG;

          final target = graph.getBuilding(edge.targetId);
          fScore[edge.targetId] = tentativeG +
              (target != null ? _heuristic(target, toBuilding) : 0);

          open.remove(edge.targetId);
          open.add(edge.targetId);
        }
      }
    }

    return null;
  }

  double _heuristic(Building a, Building b) {
    final dLat = (a.lat - b.lat) * 111000;
    final dLng = (a.lng - b.lng) * 111000 * cos(a.lat * pi / 180);
    return sqrt(dLat * dLat + dLng * dLng);
  }

  double _edgeCost(GraphEdge edge, String mode) {
    final base = edge.bridge.distanceM;

    switch (mode) {
      case 'accessible':
        if (!edge.bridge.isAccessible || !edge.bridge.hasElevator) {
          return base + 999999;
        }
        return base;

      case 'explorer':
        final shopBonus = (_shopCountByBuilding[edge.targetId] ?? 0) * 15.0;
        return max(base - shopBonus, 1);

      case 'fastest':
      default:
        return base;
    }
  }

  RouteResult _reconstructPath(Map<String, String> cameFrom, String current) {
    final path = <String>[current];
    while (cameFrom.containsKey(current)) {
      current = cameFrom[current]!;
      path.insert(0, current);
    }

    double totalDist = 0;
    int bridgeCount = 0;
    bool accessible = true;

    for (int i = 0; i < path.length - 1; i++) {
      final bridge = graph.getBridge(path[i], path[i + 1]);
      if (bridge != null) {
        totalDist += bridge.distanceM;
        bridgeCount++;
        if (!bridge.isAccessible) accessible = false;
      }
    }

    return RouteResult(
      path: path,
      totalDistance: totalDist,
      bridgeCount: bridgeCount,
      fullyAccessible: accessible,
    );
  }

  List<RouteResult> findAllRoutes(String fromId, String toId) {
    final results = <RouteResult>[];
    for (final mode in ['fastest', 'accessible', 'explorer']) {
      final r = findRoute(fromId, toId, mode: mode);
      if (r != null) results.add(r);
    }
    return results;
  }
}
