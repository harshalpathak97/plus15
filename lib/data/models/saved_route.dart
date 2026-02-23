class SavedRoute {
  final String id;
  final String name;
  final String fromId;
  final String toId;
  final String routeType;
  final DateTime createdAt;
  final bool isRoutine;

  const SavedRoute({
    required this.id,
    required this.name,
    required this.fromId,
    required this.toId,
    this.routeType = 'fastest',
    required this.createdAt,
    this.isRoutine = false,
  });

  SavedRoute copyWith({
    String? name,
    String? routeType,
    bool? isRoutine,
  }) =>
      SavedRoute(
        id: id,
        name: name ?? this.name,
        fromId: fromId,
        toId: toId,
        routeType: routeType ?? this.routeType,
        createdAt: createdAt,
        isRoutine: isRoutine ?? this.isRoutine,
      );

  factory SavedRoute.fromJson(Map<String, dynamic> json) => SavedRoute(
        id: json['id'] as String,
        name: json['name'] as String,
        fromId: json['fromId'] as String,
        toId: json['toId'] as String,
        routeType: json['routeType'] as String? ?? 'fastest',
        createdAt: DateTime.parse(json['createdAt'] as String),
        isRoutine: json['isRoutine'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'fromId': fromId,
        'toId': toId,
        'routeType': routeType,
        'createdAt': createdAt.toIso8601String(),
        'isRoutine': isRoutine,
      };
}
