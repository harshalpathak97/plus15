class Bridge {
  final String id;
  final String fromBuildingId;
  final String toBuildingId;
  final double distanceM;
  final bool hasElevator;
  final bool hasStairs;
  final bool isAccessible;
  final String status;

  const Bridge({
    required this.id,
    required this.fromBuildingId,
    required this.toBuildingId,
    required this.distanceM,
    this.hasElevator = true,
    this.hasStairs = true,
    this.isAccessible = true,
    this.status = 'open',
  });

  factory Bridge.fromJson(Map<String, dynamic> json) => Bridge(
        id: json['id'] as String,
        fromBuildingId: json['fromBuildingId'] as String,
        toBuildingId: json['toBuildingId'] as String,
        distanceM: (json['distanceM'] as num).toDouble(),
        hasElevator: json['hasElevator'] as bool? ?? true,
        hasStairs: json['hasStairs'] as bool? ?? true,
        isAccessible: json['isAccessible'] as bool? ?? true,
        status: json['status'] as String? ?? 'open',
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'fromBuildingId': fromBuildingId,
        'toBuildingId': toBuildingId,
        'distanceM': distanceM,
        'hasElevator': hasElevator,
        'hasStairs': hasStairs,
        'isAccessible': isAccessible,
        'status': status,
      };
}
