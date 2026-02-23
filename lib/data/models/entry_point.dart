class EntryPoint {
  final String id;
  final String name;
  final double lat;
  final double lng;
  final String buildingId;
  final bool isAccessible;
  final int priority;
  final List<String> tags;

  const EntryPoint({
    required this.id,
    required this.name,
    required this.lat,
    required this.lng,
    required this.buildingId,
    this.isAccessible = true,
    this.priority = 3,
    this.tags = const [],
  });

  factory EntryPoint.fromJson(Map<String, dynamic> json) => EntryPoint(
        id: json['id'] as String,
        name: json['name'] as String,
        lat: (json['lat'] as num).toDouble(),
        lng: (json['lng'] as num).toDouble(),
        buildingId: json['buildingId'] as String,
        isAccessible: json['isAccessible'] as bool? ?? true,
        priority: json['priority'] as int? ?? 3,
        tags: List<String>.from(json['tags'] as List? ?? const []),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'lat': lat,
        'lng': lng,
        'buildingId': buildingId,
        'isAccessible': isAccessible,
        'priority': priority,
        'tags': tags,
      };
}
