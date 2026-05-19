import 'plus15_graph.dart';

/// Cost-model strategy for the pathfinder. Different modes (fastest,
/// accessible, scenic, explorer) plug in here without touching A*.
abstract class CostModel {
  /// Symbolic name used to label this mode in the UI.
  String get name;

  /// Returns the traversal weight for [edge] given the previously taken
  /// [previous] edge (for floor-transition penalties) and the current
  /// time of day [now].
  ///
  /// Return `double.infinity` to hard-reject the edge.
  double weight(GraphEdge edge, GraphEdge? previous, DateTime now);

  /// Optional binary gate. Most cost models return `true` and encode
  /// constraints in `weight`, but accessibility mode uses this for clean
  /// rejection.
  bool allows(GraphEdge edge, DateTime now) => true;
}

double _bridgeLength(GraphEdge edge) {
  final geom = edge.bridge.geometry;
  if (geom.isEmpty) return edge.bridge.distanceM;
  return edge.bridge.distanceM > 0 ? edge.bridge.distanceM : 0;
}

int _absFloorDelta(GraphEdge edge, GraphEdge? previous) {
  final delta = edge.bridge.floorChange.abs();
  if (previous == null) return delta;
  // Penalize redundant up-down hopping.
  final prevDelta = previous.bridge.floorChange;
  if (prevDelta.sign != 0 &&
      prevDelta.sign == -edge.bridge.floorChange.sign) {
    return delta + 1;
  }
  return delta;
}

class FastestCost implements CostModel {
  const FastestCost();

  static const _floorPenaltyM = 25.0;

  @override
  String get name => 'fastest';

  @override
  double weight(GraphEdge edge, GraphEdge? previous, DateTime now) {
    return _bridgeLength(edge) +
        _absFloorDelta(edge, previous) * _floorPenaltyM;
  }

  @override
  bool allows(GraphEdge edge, DateTime now) => true;
}

class AccessibleCost implements CostModel {
  const AccessibleCost();

  static const _floorPenaltyM = 60.0;

  @override
  String get name => 'accessible';

  @override
  double weight(GraphEdge edge, GraphEdge? previous, DateTime now) {
    final base = _bridgeLength(edge);
    final delta = _absFloorDelta(edge, previous);
    // If we need to change floors we strongly prefer continuous elevator
    // sequences. Stairs-only is allowed only on the same floor.
    if (delta > 0 && !edge.bridge.hasElevator) return double.infinity;
    return base + delta * _floorPenaltyM;
  }

  @override
  bool allows(GraphEdge edge, DateTime now) => edge.bridge.isAccessible;
}

class ScenicCost implements CostModel {
  const ScenicCost({this.alpha = 0.6});

  final double alpha;

  @override
  String get name => 'scenic';

  @override
  double weight(GraphEdge edge, GraphEdge? previous, DateTime now) {
    final base = _bridgeLength(edge);
    return base * (1 + alpha * (1 - edge.bridge.scenicScore.clamp(0, 1)));
  }

  @override
  bool allows(GraphEdge edge, DateTime now) => true;
}

class ExplorerCost implements CostModel {
  const ExplorerCost({required this.shopCountFor});

  /// Closure returning the number of shops/amenities at the target
  /// building of an edge. Wired up from the pathfinder so we don't
  /// reload data here.
  final int Function(String buildingId) shopCountFor;

  @override
  String get name => 'explorer';

  @override
  double weight(GraphEdge edge, GraphEdge? previous, DateTime now) {
    final base = _bridgeLength(edge);
    final shopBonus = shopCountFor(edge.targetId) * 8.0;
    // Never drive the cost negative or zero — that breaks A* optimality.
    return (base - shopBonus).clamp(1.0, double.infinity);
  }
}
