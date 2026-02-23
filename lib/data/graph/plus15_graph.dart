import '../models/building.dart';
import '../models/bridge.dart';

class GraphEdge {
  final String targetId;
  final Bridge bridge;

  const GraphEdge({required this.targetId, required this.bridge});
}

class Plus15Graph {
  final List<Building> buildings;
  final List<Bridge> bridges;
  final Map<String, Building> buildingMap;
  final Map<String, List<GraphEdge>> adjacency;

  Plus15Graph({required this.buildings, required this.bridges})
      : buildingMap = {for (final b in buildings) b.id: b},
        adjacency = _buildAdjacency(buildings, bridges);

  static Map<String, List<GraphEdge>> _buildAdjacency(
      List<Building> buildings, List<Bridge> bridges) {
    final adj = <String, List<GraphEdge>>{};
    for (final b in buildings) {
      adj[b.id] = [];
    }
    for (final br in bridges) {
      adj[br.fromBuildingId]?.add(
        GraphEdge(targetId: br.toBuildingId, bridge: br),
      );
      adj[br.toBuildingId]?.add(
        GraphEdge(targetId: br.fromBuildingId, bridge: br),
      );
    }
    return adj;
  }

  List<String> getNeighbors(String buildingId) {
    return adjacency[buildingId]?.map((e) => e.targetId).toList() ?? [];
  }

  Bridge? getBridge(String fromId, String toId) {
    final edges = adjacency[fromId];
    if (edges == null) return null;
    for (final e in edges) {
      if (e.targetId == toId) return e.bridge;
    }
    return null;
  }

  Building? getBuilding(String id) => buildingMap[id];
}
