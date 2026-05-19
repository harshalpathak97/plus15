import 'package:latlong2/latlong.dart';

class Building {
  final String id;
  final String name;
  final double lat;
  final double lng;
  final String address;
  final String type;
  final List<String> amenities;

  /// Building height in meters. Used by 3D extrusion and floor estimates.
  /// Defaults to 60m (~12 floors) when unknown.
  final double heightM;

  /// Number of above-ground floors. Defaults to roughly heightM / 4.
  final int floors;

  /// Which floor of the building the +15 corridor connects on. Most are
  /// level 2 (+15 = ~15ft above grade); some are 1 or 3.
  final int plus15FloorLevel;

  /// Optional polygon footprint (closed ring) in WGS84. Used by the 3D
  /// isometric renderer. Empty = renderer falls back to a square at the
  /// centroid.
  final List<LatLng> footprint;

  /// Optional opening hours for this building's +15 access. null = inherits
  /// the network-wide default schedule from `AppConstants`.
  final BuildingHours? hours;

  const Building({
    required this.id,
    required this.name,
    required this.lat,
    required this.lng,
    this.address = '',
    this.type = 'office',
    this.amenities = const [],
    this.heightM = 60,
    this.floors = 12,
    this.plus15FloorLevel = 2,
    this.footprint = const [],
    this.hours,
  });

  factory Building.fromJson(Map<String, dynamic> json) {
    final footprintRaw = json['footprint'] as List<dynamic>?;
    final footprint = footprintRaw == null
        ? const <LatLng>[]
        : footprintRaw
            .map((p) => LatLng(
                  (p[0] as num).toDouble(),
                  (p[1] as num).toDouble(),
                ))
            .toList(growable: false);

    final heightM = (json['heightM'] as num?)?.toDouble() ?? 60;
    final floors = json['floors'] as int? ?? (heightM / 4).round().clamp(2, 80);

    return Building(
      id: json['id'] as String,
      name: json['name'] as String,
      lat: (json['lat'] as num).toDouble(),
      lng: (json['lng'] as num).toDouble(),
      address: json['address'] as String? ?? '',
      type: json['type'] as String? ?? 'office',
      amenities: List<String>.from(json['amenities'] ?? const []),
      heightM: heightM,
      floors: floors,
      plus15FloorLevel: json['plus15FloorLevel'] as int? ?? 2,
      footprint: footprint,
      hours: json['hours'] == null
          ? null
          : BuildingHours.fromJson(json['hours'] as Map<String, dynamic>),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'lat': lat,
        'lng': lng,
        'address': address,
        'type': type,
        'amenities': amenities,
        'heightM': heightM,
        'floors': floors,
        'plus15FloorLevel': plus15FloorLevel,
        if (footprint.isNotEmpty)
          'footprint': footprint.map((p) => [p.latitude, p.longitude]).toList(),
        if (hours != null) 'hours': hours!.toJson(),
      };
}

class BuildingHours {
  final TimeOfDayMinutes weekdayOpen;
  final TimeOfDayMinutes weekdayClose;
  final TimeOfDayMinutes weekendOpen;
  final TimeOfDayMinutes weekendClose;

  const BuildingHours({
    required this.weekdayOpen,
    required this.weekdayClose,
    required this.weekendOpen,
    required this.weekendClose,
  });

  factory BuildingHours.fromJson(Map<String, dynamic> json) {
    final weekday = json['weekday'] as Map<String, dynamic>?;
    final weekend = json['weekend'] as Map<String, dynamic>?;
    return BuildingHours(
      weekdayOpen: TimeOfDayMinutes.parse(weekday?['open'] as String? ?? '06:00'),
      weekdayClose:
          TimeOfDayMinutes.parse(weekday?['close'] as String? ?? '18:00'),
      weekendOpen: TimeOfDayMinutes.parse(weekend?['open'] as String? ?? '09:00'),
      weekendClose:
          TimeOfDayMinutes.parse(weekend?['close'] as String? ?? '17:00'),
    );
  }

  bool isOpenAt(DateTime now) {
    final weekend = now.weekday >= DateTime.saturday;
    final open = weekend ? weekendOpen : weekdayOpen;
    final close = weekend ? weekendClose : weekdayClose;
    final minutes = now.hour * 60 + now.minute;
    return minutes >= open.minutes && minutes <= close.minutes;
  }

  Map<String, dynamic> toJson() => {
        'weekday': {
          'open': weekdayOpen.toString(),
          'close': weekdayClose.toString(),
        },
        'weekend': {
          'open': weekendOpen.toString(),
          'close': weekendClose.toString(),
        },
      };
}

class TimeOfDayMinutes {
  final int minutes;
  const TimeOfDayMinutes(this.minutes);

  factory TimeOfDayMinutes.parse(String hhmm) {
    final parts = hhmm.split(':');
    return TimeOfDayMinutes(
      int.parse(parts[0]) * 60 + int.parse(parts[1]),
    );
  }

  @override
  String toString() {
    final h = (minutes ~/ 60).toString().padLeft(2, '0');
    final m = (minutes % 60).toString().padLeft(2, '0');
    return '$h:$m';
  }
}
