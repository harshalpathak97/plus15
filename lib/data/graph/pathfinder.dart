import 'dart:math';

import 'package:collection/collection.dart';
import 'package:latlong2/latlong.dart';

import '../models/building.dart';
import '../models/bridge.dart';
import '../models/shop.dart';
import 'cost_models.dart';
import 'plus15_graph.dart';

class RouteSegment {
  final Bridge bridge;
  final Building from;
  final Building to;
  final double distanceM;
  final int floorDelta;

  const RouteSegment({
    required this.bridge,
    required this.from,
    required this.to,
    required this.distanceM,
    required this.floorDelta,
  });
}

class RouteResult {
  final List<String> path;
  final List<RouteSegment> segments;
  final double totalDistanceM;
  final int bridgeCount;
  final int floorChanges;
  final bool fullyAccessible;
  final double scenicScore;
  final List<LatLng> geometry;
  final String modeName;

  const RouteResult({
    required this.path,
    required this.segments,
    required this.totalDistanceM,
    required this.bridgeCount,
    required this.floorChanges,
    required this.fullyAccessible,
    required this.scenicScore,
    required this.geometry,
    required this.modeName,
  });

  // Legacy field alias used in older call sites.
  double get totalDistance => totalDistanceM;
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

  /// Built-in cost models keyed by symbolic name. Callers that still pass
  /// `mode: 'fastest'` resolve through this map.
  late final Map<String, CostModel> _models = {
    'fastest': const FastestCost(),
    'accessible': const AccessibleCost(),
    'scenic': const ScenicCost(),
    'explorer': ExplorerCost(
      shopCountFor: (id) => _shopCountByBuilding[id] ?? 0,
    ),
  };

  CostModel? costModel(String name) => _models[name];

  /// Convenience for legacy callers — resolves [mode] to a built-in
  /// `CostModel`. Prefer `findRouteWith(cost: ...)` in new code.
  RouteResult? findRoute(
    String fromId,
    String toId, {
    String mode = 'fastest',
    bool respectClosures = true,
    DateTime? at,
  }) {
    final model = _models[mode] ?? const FastestCost();
    return findRouteWith(
      fromId,
      toId,
      cost: model,
      respectClosures: respectClosures,
      at: at,
    );
  }

  RouteResult? findRouteWith(
    String fromId,
    String toId, {
    required CostModel cost,
    bool respectClosures = true,
    DateTime? at,
  }) {
    if (fromId == toId) {
      final b = graph.getBuilding(fromId);
      if (b == null) return null;
      return RouteResult(
        path: [fromId],
        segments: const [],
        totalDistanceM: 0,
        bridgeCount: 0,
        floorChanges: 0,
        fullyAccessible: true,
        scenicScore: 0,
        geometry: [LatLng(b.lat, b.lng)],
        modeName: cost.name,
      );
    }

    final fromBuilding = graph.getBuilding(fromId);
    final toBuilding = graph.getBuilding(toId);
    if (fromBuilding == null || toBuilding == null) return null;

    final now = at ?? DateTime.now();

    final gScore = <String, double>{fromId: 0};
    final cameFrom = <String, _StepBack>{};
    final closed = <String>{};

    final heap = HeapPriorityQueue<_AStarNode>(
      (a, b) => a.fScore.compareTo(b.fScore),
    );
    heap.add(_AStarNode(fromId, _heuristic(fromBuilding, toBuilding)));

    while (heap.isNotEmpty) {
      final current = heap.removeFirst();
      if (current.id == toId) {
        return _reconstructPath(cameFrom, current.id, cost.name);
      }
      if (!closed.add(current.id)) continue;

      final edges = graph.adjacency[current.id] ?? const [];
      for (final edge in edges) {
        if (closed.contains(edge.targetId)) continue;
        if (respectClosures && edge.bridge.status != 'open') continue;
        if (!cost.allows(edge, now)) continue;

        final previous = cameFrom[current.id]?.edge;
        final w = cost.weight(edge, previous, now);
        if (!w.isFinite) continue;

        final tentativeG = (gScore[current.id] ?? double.infinity) + w;
        if (tentativeG < (gScore[edge.targetId] ?? double.infinity)) {
          cameFrom[edge.targetId] =
              _StepBack(parent: current.id, edge: edge);
          gScore[edge.targetId] = tentativeG;
          final target = graph.getBuilding(edge.targetId);
          final f = tentativeG +
              (target != null ? _heuristic(target, toBuilding) : 0);
          heap.add(_AStarNode(edge.targetId, f));
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

  RouteResult _reconstructPath(
    Map<String, _StepBack> cameFrom,
    String current,
    String modeName,
  ) {
    final reversed = <String>[current];
    final edges = <GraphEdge>[];
    while (cameFrom.containsKey(current)) {
      final step = cameFrom[current]!;
      edges.insert(0, step.edge);
      current = step.parent;
      reversed.insert(0, current);
    }

    final segments = <RouteSegment>[];
    final geometry = <LatLng>[];
    double totalDist = 0;
    int floorChanges = 0;
    bool accessible = true;
    double scenicSum = 0;

    final firstBuilding = graph.getBuilding(reversed.first);
    if (firstBuilding != null) {
      geometry.add(LatLng(firstBuilding.lat, firstBuilding.lng));
    }

    for (int i = 0; i < edges.length; i++) {
      final edge = edges[i];
      final from = graph.getBuilding(reversed[i]);
      final to = graph.getBuilding(reversed[i + 1]);
      if (from == null || to == null) continue;
      final dist = edge.bridge.distanceM;
      totalDist += dist;
      if (edge.bridge.floorChange != 0) floorChanges++;
      if (!edge.bridge.isAccessible) accessible = false;
      scenicSum += edge.bridge.scenicScore;

      segments.add(RouteSegment(
        bridge: edge.bridge,
        from: from,
        to: to,
        distanceM: dist,
        floorDelta: edge.bridge.floorChange,
      ));

      if (edge.bridge.geometry.isNotEmpty) {
        // Skip the first point of bridge geometry to avoid double-pushing the
        // shared endpoint.
        for (var j = 1; j < edge.bridge.geometry.length; j++) {
          geometry.add(edge.bridge.geometry[j]);
        }
      } else {
        geometry.add(LatLng(to.lat, to.lng));
      }
    }

    final scenicAvg = edges.isEmpty ? 0.0 : scenicSum / edges.length;

    return RouteResult(
      path: reversed,
      segments: segments,
      totalDistanceM: totalDist,
      bridgeCount: edges.length,
      floorChanges: floorChanges,
      fullyAccessible: accessible,
      scenicScore: scenicAvg,
      geometry: geometry,
      modeName: modeName,
    );
  }

  /// Runs all built-in cost models, then filters out dominated routes
  /// across (distance, bridges, floorChanges). Returns at most 4
  /// non-dominated variants sorted by distance ascending.
  List<RouteResult> findParetoRoutes(
    String fromId,
    String toId, {
    DateTime? at,
    bool respectClosures = true,
    bool includeExplorer = true,
    bool includeScenic = true,
  }) {
    final models = <CostModel>[
      const FastestCost(),
      const AccessibleCost(),
      if (includeScenic) const ScenicCost(),
      if (includeExplorer)
        ExplorerCost(shopCountFor: (id) => _shopCountByBuilding[id] ?? 0),
    ];

    final results = <RouteResult>[];
    for (final m in models) {
      final r = findRouteWith(
        fromId,
        toId,
        cost: m,
        respectClosures: respectClosures,
        at: at,
      );
      if (r != null) results.add(r);
    }

    final unique = <String, RouteResult>{};
    for (final r in results) {
      final key = r.path.join('>');
      final existing = unique[key];
      if (existing == null) {
        unique[key] = r;
      }
    }
    final list = unique.values.toList();

    bool dominates(RouteResult a, RouteResult b) {
      final lte = a.totalDistanceM <= b.totalDistanceM &&
          a.bridgeCount <= b.bridgeCount &&
          a.floorChanges <= b.floorChanges;
      final lt = a.totalDistanceM < b.totalDistanceM ||
          a.bridgeCount < b.bridgeCount ||
          a.floorChanges < b.floorChanges;
      return lte && lt;
    }

    final pareto = <RouteResult>[];
    for (final candidate in list) {
      final dominated = list.any((other) =>
          !identical(other, candidate) && dominates(other, candidate));
      if (!dominated) pareto.add(candidate);
    }

    pareto.sort((a, b) => a.totalDistanceM.compareTo(b.totalDistanceM));
    return pareto.take(4).toList();
  }

  /// Legacy compatibility shim — returns up to 3 routes (fastest, accessible,
  /// explorer) without Pareto filtering. Kept for any caller that still
  /// expects the old ordering.
  List<RouteResult> findAllRoutes(String fromId, String toId) {
    final results = <RouteResult>[];
    for (final mode in ['fastest', 'accessible', 'explorer']) {
      final r = findRoute(fromId, toId, mode: mode);
      if (r != null) results.add(r);
    }
    return results;
  }
}

class _AStarNode {
  final String id;
  final double fScore;
  const _AStarNode(this.id, this.fScore);
}

class _StepBack {
  final String parent;
  final GraphEdge edge;
  const _StepBack({required this.parent, required this.edge});
}
