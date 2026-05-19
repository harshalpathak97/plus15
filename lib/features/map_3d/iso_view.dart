import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:latlong2/latlong.dart';

import '../../core/design/glass.dart';
import '../../core/design/palette.dart';
import '../../data/models/building.dart';
import '../../data/models/bridge.dart';
import '../../shared/providers/providers.dart';
import 'iso_camera.dart';
import 'iso_painter.dart';
import 'iso_projection.dart';
import 'iso_scene.dart';

class IsoView extends ConsumerStatefulWidget {
  final List<Building> buildings;
  final List<Bridge> bridges;

  const IsoView({
    super.key,
    required this.buildings,
    required this.bridges,
  });

  @override
  ConsumerState<IsoView> createState() => _IsoViewState();
}

class _IsoViewState extends ConsumerState<IsoView>
    with SingleTickerProviderStateMixin {
  static const _kCenter = LatLng(51.0476, -114.0668);
  IsoCamera _camera = const IsoCamera(center: _kCenter);
  late Ticker _ticker;
  double _t = 0;
  DateTime? _lastTick;

  // Gesture session
  IsoCamera? _gestureStart;
  Offset? _focalStart;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
  }

  void _onTick(Duration elapsed) {
    final now = DateTime.now();
    final last = _lastTick;
    _lastTick = now;
    if (last == null) return;
    final dt = (now.difference(last).inMicroseconds) / 1e6;
    setState(() {
      _t = (_t + dt / 4.5) % 1.0;
    });
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _onScaleStart(ScaleStartDetails details) {
    _gestureStart = _camera;
    _focalStart = details.localFocalPoint;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    final start = _gestureStart;
    final focal = _focalStart;
    if (start == null || focal == null) return;

    final delta = details.localFocalPoint - focal;
    setState(() {
      _camera = start.copyWith(
        panX: start.panX + delta.dx,
        panY: start.panY + delta.dy,
        zoom: start.zoom * details.scale,
        yawRad: start.yawRad + details.rotation,
      );
    });
  }

  void _onScaleEnd(ScaleEndDetails details) {
    _gestureStart = null;
    _focalStart = null;
  }

  void _onTapUp(TapUpDetails details, IsoScene scene) {
    final tap = details.localPosition;
    for (final b in scene.buildings.reversed) {
      if (b.containsScreen(tap)) {
        HapticFeedback.selectionClick();
        ref.read(selectedBuildingProvider.notifier).state = b.source;
        return;
      }
    }
    ref.read(selectedBuildingProvider.notifier).state = null;
  }

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final selected = ref.watch(selectedBuildingProvider);
    final activeRoute = ref.watch(activeRouteProvider);

    return LayoutBuilder(
      builder: (context, constraints) {
        final viewport = Size(constraints.maxWidth, constraints.maxHeight);
        final projection = IsoProjection(camera: _camera, viewport: viewport);
        final scene = IsoScene.build(
          projection: projection,
          buildings: widget.buildings,
          bridges: widget.bridges,
          brightness: brightness,
          activeRoute: activeRoute,
          selectedBuildingId: selected?.id,
        );

        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onScaleStart: _onScaleStart,
                onScaleUpdate: _onScaleUpdate,
                onScaleEnd: _onScaleEnd,
                onTapUp: (d) => _onTapUp(d, scene),
                child: RepaintBoundary(
                  child: CustomPaint(
                    size: viewport,
                    painter: IsoPainter(
                      scene: scene,
                      brightness: brightness,
                      routeT: _t,
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              right: 16,
              bottom: 24,
              child: _Iso3DControls(
                onTiltUp: () => setState(() {
                  _camera = _camera.copyWith(
                    tiltRad: _camera.tiltRad + 0.08,
                  );
                }),
                onTiltDown: () => setState(() {
                  _camera = _camera.copyWith(
                    tiltRad: _camera.tiltRad - 0.08,
                  );
                }),
                onRotateLeft: () => setState(() {
                  _camera = _camera.copyWith(
                    yawRad: _camera.yawRad - 0.18,
                  );
                }),
                onRotateRight: () => setState(() {
                  _camera = _camera.copyWith(
                    yawRad: _camera.yawRad + 0.18,
                  );
                }),
                onZoomIn: () => setState(() {
                  _camera = _camera.copyWith(zoom: _camera.zoom * 1.2);
                }),
                onZoomOut: () => setState(() {
                  _camera = _camera.copyWith(zoom: _camera.zoom / 1.2);
                }),
                onReset: () => setState(() {
                  _camera = const IsoCamera(center: _kCenter);
                }),
              ),
            ),
            if (selected != null)
              Positioned(
                left: 16,
                right: 16,
                bottom: 24,
                child: _IsoBuildingPeek(
                  building: selected,
                  onClose: () =>
                      ref.read(selectedBuildingProvider.notifier).state =
                          null,
                ).animate().fadeIn(duration: 220.ms).slideY(begin: 0.1),
              ),
          ],
        );
      },
    );
  }
}

class _Iso3DControls extends StatelessWidget {
  final VoidCallback onTiltUp;
  final VoidCallback onTiltDown;
  final VoidCallback onRotateLeft;
  final VoidCallback onRotateRight;
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onReset;

  const _Iso3DControls({
    required this.onTiltUp,
    required this.onTiltDown,
    required this.onRotateLeft,
    required this.onRotateRight,
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onReset,
  });

  @override
  Widget build(BuildContext context) {
    return GlassContainer(
      borderRadius: BorderRadius.circular(20),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _btn(Icons.add_rounded, onZoomIn),
          _btn(Icons.remove_rounded, onZoomOut),
          const SizedBox(height: 8),
          _btn(Icons.keyboard_arrow_up_rounded, onTiltUp),
          _btn(Icons.keyboard_arrow_down_rounded, onTiltDown),
          const SizedBox(height: 8),
          _btn(Icons.rotate_left_rounded, onRotateLeft),
          _btn(Icons.rotate_right_rounded, onRotateRight),
          const SizedBox(height: 8),
          _btn(Icons.center_focus_strong_rounded, onReset),
        ],
      ),
    );
  }

  Widget _btn(IconData icon, VoidCallback onTap) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: SizedBox(
          width: 36,
          height: 36,
          child: Icon(icon, size: 18),
        ),
      ),
    );
  }
}

class _IsoBuildingPeek extends StatelessWidget {
  final Building building;
  final VoidCallback onClose;

  const _IsoBuildingPeek({
    required this.building,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return GlassContainer(
      borderRadius: BorderRadius.circular(22),
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: P15Palette.colorForType(building.type)
                  .withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              _iconForType(building.type),
              color: P15Palette.colorForType(building.type),
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  building.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${building.heightM.round()}m · ${building.floors} floors · ${building.type}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: Theme.of(context).hintColor,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded, size: 18),
            onPressed: onClose,
          ),
        ],
      ),
    );
  }

  IconData _iconForType(String type) {
    switch (type) {
      case 'hotel':
        return Icons.hotel_rounded;
      case 'retail':
        return Icons.shopping_bag_rounded;
      case 'landmark':
        return Icons.star_rounded;
      case 'government':
        return Icons.account_balance_rounded;
      case 'convention':
        return Icons.groups_rounded;
      case 'residential':
        return Icons.apartment_rounded;
      case 'parking':
        return Icons.local_parking_rounded;
      case 'entertainment':
        return Icons.theaters_rounded;
      case 'park':
        return Icons.park_rounded;
      default:
        return Icons.location_city_rounded;
    }
  }
}
