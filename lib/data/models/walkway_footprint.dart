import '../../routing/network.dart';

/// One City of Calgary +15 walkway or bridge footprint ("Plus 15" open data,
/// 3u3x-hrc7), as drawn by the 3D view. Built from the routing network's
/// regions so display and routing share one source.
class WalkwayFootprint {
  /// Structure type from the City data: "Enclosed", "Bridge Enclosed",
  /// "Open to Sky", "Bridge Open to Sky" (or "Unrecorded").
  final String type;

  /// Rings of the footprint, each a closed list of [lng, lat] pairs.
  final List<List<List<double>>> rings;

  const WalkwayFootprint({required this.type, required this.rings});

  bool get isBridge => type.startsWith('Bridge');
  bool get isOpenToSky => type.contains('Open to Sky');

  factory WalkwayFootprint.fromRegion(NetRegion r) => WalkwayFootprint(
        type: r.type,
        rings: [
          for (final ring in r.rings) [for (final p in ring) [p[1], p[0]]]
        ],
      );
}
