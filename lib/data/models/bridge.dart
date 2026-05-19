import 'package:latlong2/latlong.dart';

class Bridge {
  final String id;
  final String fromBuildingId;
  final String toBuildingId;
  final double distanceM;
  final bool hasElevator;
  final bool hasStairs;
  final bool isAccessible;
  final String status;

  /// Optional bridge polyline (WGS84). When present, this is the actual
  /// path of the corridor and should be preferred over a straight line
  /// between endpoints for both routing distance and 3D rendering.
  final List<LatLng> geometry;

  /// Floor levels at each endpoint. Defaults to 2 (typical +15 deck).
  final int fromFloor;
  final int toFloor;

  /// 0 = same floor, positive = up, negative = down. Used by routing
  /// to penalize floor transitions.
  final int floorChange;

  /// Subjective scenic score in [0, 1]. Higher = better views (over
  /// Stephen Avenue, glass-walled bridges, etc.). Used by "scenic" mode.
  final double scenicScore;

  const Bridge({
    required this.id,
    required this.fromBuildingId,
    required this.toBuildingId,
    required this.distanceM,
    this.hasElevator = true,
    this.hasStairs = true,
    this.isAccessible = true,
    this.status = 'open',
    this.geometry = const [],
    this.fromFloor = 2,
    this.toFloor = 2,
    this.floorChange = 0,
    this.scenicScore = 0.35,
  });

  factory Bridge.fromJson(Map<String, dynamic> json) {
    final geomRaw = json['geometry'] as List<dynamic>?;
    final geometry = geomRaw == null
        ? const <LatLng>[]
        : geomRaw
            .map((p) => LatLng(
                  (p[0] as num).toDouble(),
                  (p[1] as num).toDouble(),
                ))
            .toList(growable: false);

    final fromFloor = json['fromFloor'] as int? ?? 2;
    final toFloor = json['toFloor'] as int? ?? 2;

    return Bridge(
      id: json['id'] as String,
      fromBuildingId: json['fromBuildingId'] as String,
      toBuildingId: json['toBuildingId'] as String,
      distanceM: (json['distanceM'] as num).toDouble(),
      hasElevator: json['hasElevator'] as bool? ?? true,
      hasStairs: json['hasStairs'] as bool? ?? true,
      isAccessible: json['isAccessible'] as bool? ?? true,
      status: json['status'] as String? ?? 'open',
      geometry: geometry,
      fromFloor: fromFloor,
      toFloor: toFloor,
      floorChange:
          json['floorChange'] as int? ?? (toFloor - fromFloor),
      scenicScore: (json['scenicScore'] as num?)?.toDouble() ?? 0.35,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'fromBuildingId': fromBuildingId,
        'toBuildingId': toBuildingId,
        'distanceM': distanceM,
        'hasElevator': hasElevator,
        'hasStairs': hasStairs,
        'isAccessible': isAccessible,
        'status': status,
        if (geometry.isNotEmpty)
          'geometry': geometry.map((p) => [p.latitude, p.longitude]).toList(),
        'fromFloor': fromFloor,
        'toFloor': toFloor,
        'floorChange': floorChange,
        'scenicScore': scenicScore,
      };
}
