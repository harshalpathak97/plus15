import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:plus15_navigator/data/graph/pathfinder.dart';
import 'package:plus15_navigator/data/graph/plus15_graph.dart';
import 'package:plus15_navigator/data/models/bridge.dart';
import 'package:plus15_navigator/data/models/building.dart';
import 'package:plus15_navigator/data/models/entry_point.dart';
import 'package:plus15_navigator/features/map/services/course_tracker.dart';

void main() {
  final buildings = <Building>[
    const Building(id: 'b1', name: 'B1', lat: 51.0000, lng: -114.0000),
    const Building(id: 'b2', name: 'B2', lat: 51.0005, lng: -113.9990),
    const Building(id: 'b3', name: 'B3', lat: 51.0010, lng: -113.9980),
    const Building(id: 'b4', name: 'B4', lat: 50.9990, lng: -114.0010),
  ];

  final bridges = <Bridge>[
    const Bridge(
      id: 'br1',
      fromBuildingId: 'b1',
      toBuildingId: 'b2',
      distanceM: 120,
      isAccessible: true,
      status: 'open',
    ),
    const Bridge(
      id: 'br2',
      fromBuildingId: 'b2',
      toBuildingId: 'b3',
      distanceM: 110,
      isAccessible: true,
      status: 'open',
    ),
    const Bridge(
      id: 'br3',
      fromBuildingId: 'b1',
      toBuildingId: 'b4',
      distanceM: 100,
      isAccessible: false,
      status: 'open',
    ),
  ];

  final graph = Plus15Graph(buildings: buildings, bridges: bridges);
  final buildingMap = {for (final b in buildings) b.id: b};
  final tracker = CourseTracker(graph: graph, buildingMap: buildingMap);
  final pathfinder = Pathfinder(graph: graph, shops: const []);

  group('CourseTracker', () {
    test('detects on-route vs off-route with threshold', () {
      final nearRoute = const LatLng(51.00025, -113.9995);
      final farRoute = const LatLng(51.0040, -114.0100);
      expect(tracker.isOnRoute(nearRoute, const ['b1', 'b2', 'b3']), isTrue);
      expect(tracker.isOnRoute(farRoute, const ['b1', 'b2', 'b3']), isFalse);
    });

    test('nearest graph node chooses closest connected node', () {
      final user = const LatLng(51.0001, -114.0001);
      expect(tracker.nearestGraphNode(user), equals('b1'));
    });

    test('chooseBestEntryPoint respects accessibility mode', () {
      final entryPoints = <EntryPoint>[
        const EntryPoint(
          id: 'e1',
          name: 'Inaccessible but close',
          lat: 51.0000,
          lng: -114.0000,
          buildingId: 'b1',
          isAccessible: false,
          priority: 1,
        ),
        const EntryPoint(
          id: 'e2',
          name: 'Accessible',
          lat: 51.0006,
          lng: -113.9991,
          buildingId: 'b2',
          isAccessible: true,
          priority: 2,
        ),
      ];

      final user = const LatLng(51.0000, -114.0000);
      final choiceAccessible = tracker.chooseBestEntryPoint(
        user: user,
        entryPoints: entryPoints,
        destinationId: 'b3',
        pathfinder: pathfinder,
        accessibilityMode: true,
      );

      expect(choiceAccessible, isNotNull);
      expect(choiceAccessible!.entryPoint.id, equals('e2'));
    });
  });
}
