class OverlayControlPoint {
  final String id;
  final double pixelX;
  final double pixelY;
  final double lat;
  final double lng;

  const OverlayControlPoint({
    required this.id,
    required this.pixelX,
    required this.pixelY,
    required this.lat,
    required this.lng,
  });

  factory OverlayControlPoint.fromJson(Map<String, dynamic> json) =>
      OverlayControlPoint(
        id: json['id'] as String,
        pixelX: (json['pixelX'] as num).toDouble(),
        pixelY: (json['pixelY'] as num).toDouble(),
        lat: (json['lat'] as num).toDouble(),
        lng: (json['lng'] as num).toDouble(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'pixelX': pixelX,
        'pixelY': pixelY,
        'lat': lat,
        'lng': lng,
      };
}

class MapOverlayConfig {
  final String imageAsset;
  final int imageWidthPx;
  final int imageHeightPx;
  final double opacityLight;
  final double opacityDark;
  final List<OverlayControlPoint> controlPoints;

  const MapOverlayConfig({
    required this.imageAsset,
    required this.imageWidthPx,
    required this.imageHeightPx,
    required this.controlPoints,
    this.opacityLight = 0.9,
    this.opacityDark = 0.95,
  });

  factory MapOverlayConfig.fromJson(Map<String, dynamic> json) =>
      MapOverlayConfig(
        imageAsset: json['imageAsset'] as String,
        imageWidthPx: json['imageWidthPx'] as int,
        imageHeightPx: json['imageHeightPx'] as int,
        opacityLight: (json['opacityLight'] as num?)?.toDouble() ?? 0.9,
        opacityDark: (json['opacityDark'] as num?)?.toDouble() ?? 0.95,
        controlPoints: (json['controlPoints'] as List)
            .map((e) => OverlayControlPoint.fromJson(e))
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        'imageAsset': imageAsset,
        'imageWidthPx': imageWidthPx,
        'imageHeightPx': imageHeightPx,
        'opacityLight': opacityLight,
        'opacityDark': opacityDark,
        'controlPoints': controlPoints.map((e) => e.toJson()).toList(),
      };
}
