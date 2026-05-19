import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/design/palette.dart';

/// Animated traveling dot that runs along a route polyline.
///
/// Renders a [MarkerLayer] whose marker is positioned by interpolating along
/// [points] using a ticker-driven `t ∈ [0, 1]`. The dot is a small glowing
/// circle that completes one traversal every [period].
class RouteTravelLayer extends StatefulWidget {
  final List<LatLng> points;
  final Duration period;

  const RouteTravelLayer({
    super.key,
    required this.points,
    this.period = const Duration(seconds: 4),
  });

  @override
  State<RouteTravelLayer> createState() => _RouteTravelLayerState();
}

class _RouteTravelLayerState extends State<RouteTravelLayer>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  List<double>? _cumulative;
  double _totalMeters = 0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.period)
      ..repeat();
    _recomputeCumulative();
  }

  @override
  void didUpdateWidget(covariant RouteTravelLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.points != widget.points) {
      _recomputeCumulative();
    }
    if (oldWidget.period != widget.period) {
      _controller.duration = widget.period;
      _controller
        ..reset()
        ..repeat();
    }
  }

  void _recomputeCumulative() {
    final pts = widget.points;
    if (pts.length < 2) {
      _cumulative = null;
      _totalMeters = 0;
      return;
    }
    const distance = Distance();
    final cum = <double>[0];
    double acc = 0;
    for (var i = 1; i < pts.length; i++) {
      acc += distance(pts[i - 1], pts[i]);
      cum.add(acc);
    }
    _cumulative = cum;
    _totalMeters = acc;
  }

  LatLng? _pointAt(double meters) {
    final cum = _cumulative;
    if (cum == null || _totalMeters <= 0) return null;
    if (meters <= 0) return widget.points.first;
    if (meters >= _totalMeters) return widget.points.last;
    for (var i = 1; i < cum.length; i++) {
      if (cum[i] >= meters) {
        final segLen = cum[i] - cum[i - 1];
        final t = segLen <= 0 ? 0.0 : (meters - cum[i - 1]) / segLen;
        final a = widget.points[i - 1];
        final b = widget.points[i];
        return LatLng(
          a.latitude + (b.latitude - a.latitude) * t,
          a.longitude + (b.longitude - a.longitude) * t,
        );
      }
    }
    return widget.points.last;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.points.length < 2) return const SizedBox.shrink();
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final pos = _pointAt(_controller.value * _totalMeters);
        if (pos == null) return const SizedBox.shrink();
        return MarkerLayer(
          markers: [
            Marker(
              point: pos,
              width: 26,
              height: 26,
              child: const _TravelDot(),
            ),
          ],
        );
      },
    );
  }
}

class _TravelDot extends StatelessWidget {
  const _TravelDot();

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [
                P15Palette.cyanGlow.withValues(alpha: 0.6),
                P15Palette.cyanGlow.withValues(alpha: 0.0),
              ],
            ),
          ),
        ),
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: P15Palette.electricBlue.withValues(alpha: 0.55),
                blurRadius: 10,
                spreadRadius: 1,
              ),
            ],
          ),
        ),
        Container(
          width: 5,
          height: 5,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: P15Palette.electricBlue,
          ),
        ),
      ],
    );
  }
}
