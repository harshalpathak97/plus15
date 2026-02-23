import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:plus15_navigator/data/models/map_overlay_config.dart';
import 'package:plus15_navigator/features/map/services/map_alignment_service.dart';

void main() {
  group('MapAlignmentService', () {
    test('fits affine transform and returns low residuals', () {
      const config = MapOverlayConfig(
        imageAsset: 'assets/maps/test.png',
        imageWidthPx: 200,
        imageHeightPx: 100,
        opacityLight: 0.8,
        opacityDark: 0.9,
        controlPoints: [
          OverlayControlPoint(
            id: 'a',
            pixelX: 0,
            pixelY: 0,
            lat: 51.0000,
            lng: -114.0000,
          ),
          OverlayControlPoint(
            id: 'b',
            pixelX: 200,
            pixelY: 0,
            lat: 51.0000,
            lng: -113.9800,
          ),
          OverlayControlPoint(
            id: 'c',
            pixelX: 0,
            pixelY: 100,
            lat: 50.9900,
            lng: -114.0000,
          ),
          OverlayControlPoint(
            id: 'd',
            pixelX: 200,
            pixelY: 100,
            lat: 50.9900,
            lng: -113.9800,
          ),
        ],
      );

      final alignment = const MapAlignmentService().compute(config);
      expect(alignment, isNotNull);
      expect(alignment!.rmseMeters, lessThan(0.5));

      const dist = Distance();
      expect(
        dist(alignment.topLeft, const LatLng(51.0000, -114.0000)),
        lessThan(1),
      );
      expect(
        dist(alignment.bottomLeft, const LatLng(50.9900, -114.0000)),
        lessThan(1),
      );
      expect(
        dist(alignment.bottomRight, const LatLng(50.9900, -113.9800)),
        lessThan(1),
      );
    });
  });
}
