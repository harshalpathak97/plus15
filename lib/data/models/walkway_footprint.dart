/// One +15 walkway or bridge footprint from the City of Calgary's open
/// "Plus 15 Walkways" dataset (resource 3u3x-hrc7), pre-simplified into
/// assets/data/walkway_footprints.json.
class WalkwayFootprint {
  /// Structure type from the city data: "Enclosed", "Bridge Enclosed",
  /// "Open to Sky" or "Bridge Open to Sky".
  final String type;

  /// Outer rings of the footprint, each a closed list of [lng, lat] pairs.
  final List<List<List<double>>> rings;

  const WalkwayFootprint({required this.type, required this.rings});

  bool get isBridge => type.startsWith('Bridge');
  bool get isOpenToSky => type.contains('Open to Sky');

  factory WalkwayFootprint.fromJson(Map<String, dynamic> json) {
    final rings = (json['p'] as List)
        .map((ring) => (ring as List)
            .map((pt) => [
                  ((pt as List)[0] as num).toDouble(),
                  (pt[1] as num).toDouble(),
                ])
            .toList())
        .toList();
    return WalkwayFootprint(type: json['t'] as String, rings: rings);
  }
}
