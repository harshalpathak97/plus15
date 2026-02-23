class Building {
  final String id;
  final String name;
  final double lat;
  final double lng;
  final String address;
  final String type;
  final List<String> amenities;

  const Building({
    required this.id,
    required this.name,
    required this.lat,
    required this.lng,
    this.address = '',
    this.type = 'office',
    this.amenities = const [],
  });

  factory Building.fromJson(Map<String, dynamic> json) => Building(
        id: json['id'] as String,
        name: json['name'] as String,
        lat: (json['lat'] as num).toDouble(),
        lng: (json['lng'] as num).toDouble(),
        address: json['address'] as String? ?? '',
        type: json['type'] as String? ?? 'office',
        amenities: List<String>.from(json['amenities'] ?? []),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'lat': lat,
        'lng': lng,
        'address': address,
        'type': type,
        'amenities': amenities,
      };
}
