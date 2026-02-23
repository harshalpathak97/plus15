import 'dart:math';
import 'package:latlong2/latlong.dart';
import '../../../data/models/map_overlay_config.dart';

class MapOverlayAlignment {
  final LatLng topLeft;
  final LatLng bottomLeft;
  final LatLng bottomRight;
  final double rmseMeters;

  const MapOverlayAlignment({
    required this.topLeft,
    required this.bottomLeft,
    required this.bottomRight,
    required this.rmseMeters,
  });
}

class MapAlignmentService {
  static const Distance _distance = Distance();

  const MapAlignmentService();

  MapOverlayAlignment? compute(MapOverlayConfig config) {
    if (config.controlPoints.length < 3) return null;

    final latCoefficients = _fitAffine(
      config.controlPoints.map((p) => p.pixelX).toList(),
      config.controlPoints.map((p) => p.pixelY).toList(),
      config.controlPoints.map((p) => p.lat).toList(),
    );

    final lngCoefficients = _fitAffine(
      config.controlPoints.map((p) => p.pixelX).toList(),
      config.controlPoints.map((p) => p.pixelY).toList(),
      config.controlPoints.map((p) => p.lng).toList(),
    );

    if (latCoefficients == null || lngCoefficients == null) {
      return null;
    }

    LatLng project(double x, double y) {
      final lat = _applyAffine(latCoefficients, x, y);
      final lng = _applyAffine(lngCoefficients, x, y);
      return LatLng(lat, lng);
    }

    final topLeft = project(0, 0);
    final bottomLeft = project(0, config.imageHeightPx.toDouble());
    final bottomRight = project(
      config.imageWidthPx.toDouble(),
      config.imageHeightPx.toDouble(),
    );

    final residuals = config.controlPoints.map((cp) {
      final estimated = project(cp.pixelX, cp.pixelY);
      return _distance(
        LatLng(cp.lat, cp.lng),
        LatLng(estimated.latitude, estimated.longitude),
      );
    }).toList();

    final rmse = residuals.isEmpty
        ? 0.0
        : sqrt(
            residuals.fold<double>(0, (sum, r) => sum + r * r) /
                residuals.length,
          );

    return MapOverlayAlignment(
      topLeft: topLeft,
      bottomLeft: bottomLeft,
      bottomRight: bottomRight,
      rmseMeters: rmse,
    );
  }

  List<double>? _fitAffine(List<double> x, List<double> y, List<double> z) {
    if (x.length != y.length || y.length != z.length || z.length < 3) {
      return null;
    }

    double sxx = 0;
    double sxy = 0;
    double sx = 0;
    double syy = 0;
    double sy = 0;
    final n = z.length.toDouble();

    double bx = 0;
    double by = 0;
    double b1 = 0;

    for (int i = 0; i < z.length; i++) {
      final xi = x[i];
      final yi = y[i];
      final zi = z[i];

      sxx += xi * xi;
      sxy += xi * yi;
      sx += xi;
      syy += yi * yi;
      sy += yi;

      bx += xi * zi;
      by += yi * zi;
      b1 += zi;
    }

    return _solve3x3(
      [
        [sxx, sxy, sx],
        [sxy, syy, sy],
        [sx, sy, n],
      ],
      [bx, by, b1],
    );
  }

  double _applyAffine(List<double> coeff, double x, double y) {
    return coeff[0] * x + coeff[1] * y + coeff[2];
  }

  List<double>? _solve3x3(List<List<double>> a, List<double> b) {
    final m = [
      [a[0][0], a[0][1], a[0][2], b[0]],
      [a[1][0], a[1][1], a[1][2], b[1]],
      [a[2][0], a[2][1], a[2][2], b[2]],
    ];

    for (int col = 0; col < 3; col++) {
      int pivot = col;
      for (int row = col + 1; row < 3; row++) {
        if (m[row][col].abs() > m[pivot][col].abs()) {
          pivot = row;
        }
      }

      if (m[pivot][col].abs() < 1e-12) {
        return null;
      }

      if (pivot != col) {
        final temp = m[col];
        m[col] = m[pivot];
        m[pivot] = temp;
      }

      final divisor = m[col][col];
      for (int j = col; j < 4; j++) {
        m[col][j] /= divisor;
      }

      for (int row = 0; row < 3; row++) {
        if (row == col) continue;
        final factor = m[row][col];
        for (int j = col; j < 4; j++) {
          m[row][j] -= factor * m[col][j];
        }
      }
    }

    return [m[0][3], m[1][3], m[2][3]];
  }
}
