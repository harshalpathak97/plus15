import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_palette.dart';
import '../../data/models/building.dart';
import '../../data/models/walkway_footprint.dart';
import '../../shared/providers/providers.dart';
import 'scene3d.dart';

/// A 3D view of the +15 network, built from the City of Calgary's real
/// walkway footprints extruded to skywalk height (15 ft above street level).
///
/// Three behaviours, picked automatically:
///  * no route        → free orbit over the whole network
///  * planned route   → cinematic fly-through along the route (play/scrub)
///  * live navigation → the camera tracks your actual progress
class Map3DScreen extends ConsumerStatefulWidget {
  const Map3DScreen({super.key});

  @override
  ConsumerState<Map3DScreen> createState() => _Map3DScreenState();
}

enum _Mode { free, flythrough, live }

class _Map3DScreenState extends ConsumerState<Map3DScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ticker;
  Duration _lastElapsed = Duration.zero;

  final OrbitCamera _camera = OrbitCamera(
    target: Offset.zero,
    yaw: 0.6,
    pitch: 0.95,
    distance: 1500,
  );

  _Mode _mode = _Mode.free;
  RoutePath3D? _routePath;
  double _t = 0; // progress along the route, 0..1
  bool _playing = true;
  bool _interacted = false;
  bool _showHint = true;

  // Gesture bookkeeping.
  double _startDistance = 0;
  double _startYaw = 0;

  // Smoothed live-progress target so the camera glides, not jumps.
  double _liveT = 0;

  @override
  void initState() {
    super.initState();
    _ticker = AnimationController(vsync: this, duration: const Duration(days: 1))
      ..addListener(_advance)
      ..forward();
    Future.delayed(const Duration(seconds: 5), () {
      if (mounted) setState(() => _showHint = false);
    });
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  /// Per-frame camera motion. Mutates [_camera] directly; the painter listens
  /// to [_ticker] so this never rebuilds the widget tree.
  void _advance() {
    final elapsed = _ticker.lastElapsedDuration ?? Duration.zero;
    var dt = (elapsed - _lastElapsed).inMicroseconds / 1e6;
    _lastElapsed = elapsed;
    if (dt <= 0 || dt > 0.25) dt = 0.016;

    final path = _routePath;
    switch (_mode) {
      case _Mode.free:
        if (!_interacted) _camera.yaw += dt * 0.05; // slow idle orbit
      case _Mode.flythrough:
        if (path == null) break;
        if (_playing) {
          // Cover the whole route in ~30s regardless of its length, but never
          // faster than a brisk glide.
          final speed = math.max(path.total / 30.0, 18.0);
          _t = (_t + dt * speed / path.total).clamp(0.0, 1.0);
          if (_t >= 1.0) _playing = false;
        }
        _followRoute(path, dt);
      case _Mode.live:
        if (path == null) break;
        final session = ref.read(navigationSessionProvider);
        if (session.totalDistanceM > 0) {
          _liveT = (1 - session.remainingDistanceM / session.totalDistanceM)
              .clamp(0.0, 1.0);
        }
        // Glide toward the live position.
        _t += (_liveT - _t) * math.min(1.0, dt * 2.0);
        _followRoute(path, dt);
    }
    _camera.clampOrbit();
  }

  void _followRoute(RoutePath3D path, double dt) {
    final p = path.pointAt(_t);
    final ease = math.min(1.0, dt * 4.0);
    _camera.target = Offset.lerp(_camera.target, p, ease)!;
    _camera.targetZ += (6.0 - _camera.targetZ) * ease;
    if (!_interacted) {
      _camera.yaw =
          lerpAngle(_camera.yaw, path.headingAt(_t), math.min(1.0, dt * 2.2));
    }
  }

  void _enterRouteMode(RoutePath3D path, bool live) {
    _routePath = path;
    _mode = live ? _Mode.live : _Mode.flythrough;
    _camera
      ..target = path.pointAt(0)
      ..targetZ = 6
      ..yaw = path.headingAt(0)
      ..pitch = 0.62
      ..distance = 140;
    if (live) {
      final session = ref.read(navigationSessionProvider);
      if (session.totalDistanceM > 0) {
        _t = (1 - session.remainingDistanceM / session.totalDistanceM)
            .clamp(0.0, 1.0);
        _liveT = _t;
        _camera.target = path.pointAt(_t);
      }
    }
  }

  void _resetCamera() {
    HapticFeedback.lightImpact();
    _interacted = false;
    final path = _routePath;
    if (path != null) {
      _t = _mode == _Mode.live ? _liveT : 0.0;
      _playing = true;
      _camera
        ..target = path.pointAt(_t)
        ..yaw = path.headingAt(_t)
        ..pitch = 0.62
        ..distance = 140;
    } else {
      _camera
        ..target = Offset.zero
        ..targetZ = 5
        ..yaw = 0.6
        ..pitch = 0.95
        ..distance = 1500;
    }
    setState(() {});
  }

  // --- Gestures ------------------------------------------------------------

  void _onScaleStart(ScaleStartDetails d) {
    _interacted = true;
    _startDistance = _camera.distance;
    _startYaw = _camera.yaw;
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    if (d.pointerCount >= 2) {
      _camera.distance = _startDistance / d.scale;
      _camera.yaw = _startYaw - d.rotation;
      _camera.pitch += d.focalPointDelta.dy * 0.005;
    }
    if (d.pointerCount == 1) {
      if (_mode == _Mode.free) {
        // Pan the ground target in the camera's frame.
        final k = _camera.distance * 0.0016;
        final dx = -d.focalPointDelta.dx * k;
        final dy = d.focalPointDelta.dy * k;
        final sinY = math.sin(_camera.yaw), cosY = math.cos(_camera.yaw);
        _camera.target += Offset(
          dx * cosY + dy * sinY,
          -dx * sinY + dy * cosY,
        );
      } else {
        // Orbit around the followed point.
        _camera.yaw -= d.focalPointDelta.dx * 0.008;
        _camera.pitch += d.focalPointDelta.dy * 0.006;
      }
    }
    _camera.clampOrbit();
  }

  // --- Build ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final footprints =
        ref.watch(walkwayFootprintsProvider).valueOrNull ?? const [];
    final buildings =
        ref.watch(buildingsProvider).valueOrNull ?? const <Building>[];

    // Pick the mode from app state on every build (cheap, idempotent).
    final smoothed = ref.watch(smoothedRouteProvider);
    final session = ref.watch(navigationSessionProvider);
    final wantLive = session.isActive && smoothed.length >= 2;
    final wantRoute = smoothed.length >= 2;
    if (wantRoute && _routePath == null) {
      final path = RoutePath3D.fromLatLng(smoothed);
      if (path.isUsable) _enterRouteMode(path, wantLive);
    } else if (wantLive && _mode == _Mode.flythrough) {
      _mode = _Mode.live;
    }

    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF080A14) : const Color(0xFFEEF1F7),
      body: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onScaleStart: _onScaleStart,
              onScaleUpdate: _onScaleUpdate,
              onDoubleTap: _resetCamera,
              child: CustomPaint(
                painter: _NetworkPainter(
                  repaint: _ticker,
                  camera: _camera,
                  footprints: footprints,
                  labelBuildings: _labelBuildings(buildings),
                  routePath: _routePath,
                  progressT: () => _mode == _Mode.free ? null : _t,
                  showPuck: () => _mode != _Mode.free,
                  isDark: isDark,
                ),
                isComplex: true,
                willChange: true,
              ),
            ),
          ),
          _topBar(context, theme, isDark),
          if (_showHint) _hint(theme, isDark),
          if (_mode == _Mode.flythrough && _routePath != null)
            _flythroughControls(theme, isDark),
          if (_mode == _Mode.live) _liveBadge(theme, isDark),
        ],
      ),
    );
  }

  List<Building> _labelBuildings(List<Building> all) {
    const ids = {
      'the_core', 'bankers_hall', 'suncor_energy_centre', 'bow_valley_square',
      'brookfield_place', 'stephen_ave_place', 'fifth_avenue_place',
      'gulf_canada_square', 'eighth_avenue_place', 'city_hall',
      'calgary_tower', 'glenbow_museum', 'arts_commons', 'the_bow',
      'eau_claire_tower', 'hudsons_bay', 'palliser_hotel', 'centennial_place',
    };
    return all.where((b) => ids.contains(b.id)).toList(growable: false);
  }

  Widget _topBar(BuildContext context, ThemeData theme, bool isDark) {
    final surface =
        (isDark ? AppPalette.cardDark : Colors.white).withValues(alpha: 0.9);
    final subtitle = switch (_mode) {
      _Mode.free => 'The whole network, 15 feet up',
      _Mode.flythrough => 'Route fly-through',
      _Mode.live => 'Following your walk',
    };
    return Positioned(
      top: MediaQuery.of(context).padding.top + 8,
      left: 16,
      right: 16,
      child: Row(
        children: [
          _roundButton(
            isDark,
            icon: Icons.arrow_back_rounded,
            onTap: () => context.pop(),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              decoration: BoxDecoration(
                color: surface,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.1),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('+15 in 3D',
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w800)),
                  Text(subtitle,
                      style: theme.textTheme.bodySmall, maxLines: 1),
                ],
              ),
            ),
          ),
          const SizedBox(width: 10),
          _roundButton(
            isDark,
            icon: Icons.center_focus_strong_rounded,
            onTap: _resetCamera,
          ),
        ],
      ).animate().fadeIn(duration: 300.ms),
    );
  }

  Widget _roundButton(bool isDark,
      {required IconData icon, required VoidCallback onTap}) {
    return Material(
      color: (isDark ? AppPalette.cardDark : Colors.white)
          .withValues(alpha: 0.9),
      shape: const CircleBorder(),
      elevation: 2,
      shadowColor: Colors.black38,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 42,
          height: 42,
          child: Icon(icon,
              size: 20,
              color: isDark ? AppPalette.inkDark : AppPalette.ink),
        ),
      ),
    );
  }

  Widget _hint(ThemeData theme, bool isDark) {
    return Positioned(
      bottom: 120,
      left: 0,
      right: 0,
      child: IgnorePointer(
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: (isDark ? AppPalette.cardDark : Colors.white)
                  .withValues(alpha: 0.88),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              _mode == _Mode.free
                  ? 'Drag to move · pinch to zoom · double-tap to reset'
                  : 'Drag to look around · pinch to zoom',
              style: theme.textTheme.bodySmall,
            ),
          ),
        ).animate().fadeIn(duration: 400.ms, delay: 600.ms),
      ),
    );
  }

  Widget _flythroughControls(ThemeData theme, bool isDark) {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    return Positioned(
      left: 16,
      right: 16,
      bottom: (bottomInset > 0 ? bottomInset : 14) + 10,
      child: Container(
        padding: const EdgeInsets.fromLTRB(8, 4, 14, 4),
        decoration: BoxDecoration(
          color: (isDark ? AppPalette.cardDark : Colors.white)
              .withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.12),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: AnimatedBuilder(
          animation: _ticker,
          builder: (context, _) => Row(
            children: [
              IconButton(
                icon: Icon(
                  _playing && _t < 1
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded,
                  color: AppPalette.brand,
                ),
                onPressed: () {
                  HapticFeedback.lightImpact();
                  setState(() {
                    if (_t >= 1.0) _t = 0;
                    _playing = !_playing;
                  });
                },
              ),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 3,
                    thumbShape:
                        const RoundSliderThumbShape(enabledThumbRadius: 7),
                    overlayShape:
                        const RoundSliderOverlayShape(overlayRadius: 14),
                    activeTrackColor: AppPalette.brand,
                    thumbColor: AppPalette.brand,
                    inactiveTrackColor: AppPalette.brand.withValues(alpha: 0.15),
                  ),
                  child: Slider(
                    value: _t,
                    onChanged: (v) {
                      _playing = false;
                      _t = v;
                    },
                  ),
                ),
              ),
              Text(
                '${(_routePath!.total * _t).round()} m',
                style: theme.textTheme.labelSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      ).animate().fadeIn(duration: 300.ms).slideY(begin: 0.4, end: 0),
    );
  }

  Widget _liveBadge(ThemeData theme, bool isDark) {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    return Positioned(
      left: 0,
      right: 0,
      bottom: (bottomInset > 0 ? bottomInset : 14) + 12,
      child: IgnorePointer(
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              color: (isDark ? AppPalette.cardDark : Colors.white)
                  .withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                      shape: BoxShape.circle, color: AppPalette.origin),
                ),
                const SizedBox(width: 8),
                Text('Live — following your progress',
                    style: theme.textTheme.labelMedium
                        ?.copyWith(fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Painter
// ---------------------------------------------------------------------------

class _Prism {
  final List<List<Offset>> rings; // local metres
  final Offset centroid;
  final bool isBridge;
  final bool isOpenToSky;
  const _Prism(this.rings, this.centroid, this.isBridge, this.isOpenToSky);
}

class _Face {
  final double depth;
  final Path path;
  final Color color;
  final Color? stroke;
  const _Face(this.depth, this.path, this.color, this.stroke);
}

class _NetworkPainter extends CustomPainter {
  final OrbitCamera camera;
  final List<WalkwayFootprint> footprints;
  final List<Building> labelBuildings;
  final RoutePath3D? routePath;
  final double? Function() progressT;
  final bool Function() showPuck;
  final bool isDark;

  static const _floorZ = 4.6; // 15 ft, the whole point of the name
  static const _roofZ = 8.2;

  // Static caches: footprint geometry never changes, so convert it once.
  static List<_Prism>? _prismCache;
  static int _prismCacheKey = -1;
  final Map<String, TextPainter> _labelCache = {};

  _NetworkPainter({
    required Listenable repaint,
    required this.camera,
    required this.footprints,
    required this.labelBuildings,
    required this.routePath,
    required this.progressT,
    required this.showPuck,
    required this.isDark,
  }) : super(repaint: repaint);

  List<_Prism> get _prisms {
    if (_prismCache != null && _prismCacheKey == footprints.length) {
      return _prismCache!;
    }
    final prisms = <_Prism>[];
    for (final f in footprints) {
      final rings = <List<Offset>>[];
      var cx = 0.0, cy = 0.0, n = 0;
      for (final ring in f.rings) {
        final pts = <Offset>[];
        for (final p in ring) {
          final o = Scene3D.toLocal(p[1], p[0]);
          pts.add(o);
          cx += o.dx;
          cy += o.dy;
          n++;
        }
        rings.add(pts);
      }
      if (n == 0) continue;
      prisms.add(
          _Prism(rings, Offset(cx / n, cy / n), f.isBridge, f.isOpenToSky));
    }
    _prismCache = prisms;
    _prismCacheKey = footprints.length;
    return prisms;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final frame = CameraFrame(camera, size);

    _paintGrid(canvas, frame);
    _paintNetwork(canvas, frame);
    _paintRoute(canvas, frame);
    _paintLabels(canvas, frame);
  }

  // Street-grid hint on the ground plane, fading out with distance.
  void _paintGrid(Canvas canvas, CameraFrame frame) {
    const spacing = 150.0;
    const radius = 1200.0;
    final color = isDark ? const Color(0xFF151A2A) : const Color(0xFFDDE2EE);
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;

    final cx = (camera.target.dx / spacing).round();
    final cy = (camera.target.dy / spacing).round();
    final steps = (radius / spacing).round();
    for (var i = -steps; i <= steps; i++) {
      final x = (cx + i) * spacing;
      final a = frame.project(x, camera.target.dy - radius, 0);
      final b = frame.project(x, camera.target.dy + radius, 0);
      if (a != null && b != null) canvas.drawLine(a, b, paint);
      final y = (cy + i) * spacing;
      final c = frame.project(camera.target.dx - radius, y, 0);
      final d = frame.project(camera.target.dx + radius, y, 0);
      if (c != null && d != null) canvas.drawLine(c, d, paint);
    }
  }

  void _paintNetwork(Canvas canvas, CameraFrame frame) {
    // Theme-resolved flat fills. Bridges get the skywalk teal identity.
    final topEnclosed = isDark ? const Color(0xFF252B45) : Colors.white;
    final sideEnclosed =
        isDark ? const Color(0xFF161A2C) : const Color(0xFFC7CCDD);
    final topBridge = isDark ? const Color(0xFF11424C) : const Color(0xFFD7F1F5);
    final sideBridge =
        isDark ? const Color(0xFF0A2B32) : const Color(0xFF9CC8D1);
    final bridgeEdge = (isDark ? AppPalette.skywalkBright : AppPalette.skywalk)
        .withValues(alpha: 0.55);
    final shadow = Colors.black.withValues(alpha: isDark ? 0.3 : 0.06);

    final faces = <_Face>[];
    final shadowPaint = Paint()..color = shadow;

    for (final prism in _prisms) {
      final d = frame.depth(prism.centroid.dx, prism.centroid.dy, _floorZ);
      if (d <= CameraFrame.near || d > 2400) continue;

      final top = prism.isBridge ? topBridge : topEnclosed;
      final side = prism.isBridge ? sideBridge : sideEnclosed;
      final topColor =
          prism.isOpenToSky ? top.withValues(alpha: 0.55) : top;
      final detailed = d < 600;

      for (final ring in prism.rings) {
        // Project the roof ring (always) and the floor ring (near only).
        final topPts = <Offset?>[];
        final botPts = <Offset?>[];
        var visible = false;
        for (final p in ring) {
          final tp = frame.project(p.dx, p.dy, _roofZ);
          topPts.add(tp);
          if (tp != null) visible = true;
          botPts.add(detailed ? frame.project(p.dx, p.dy, _floorZ) : null);
        }
        if (!visible) continue;

        // Ground shadow, only nearby — cheap grounding cue.
        if (detailed) {
          final sh = Path();
          var started = false;
          for (final p in ring) {
            final sp = frame.project(p.dx, p.dy, 0.05);
            if (sp == null) {
              started = false;
              continue;
            }
            if (!started) {
              sh.moveTo(sp.dx, sp.dy);
              started = true;
            } else {
              sh.lineTo(sp.dx, sp.dy);
            }
          }
          canvas.drawPath(sh, shadowPaint);
        }

        // Side walls.
        if (detailed) {
          for (var i = 0; i < ring.length - 1; i++) {
            final a = topPts[i], b = topPts[i + 1];
            final a0 = botPts[i], b0 = botPts[i + 1];
            if (a == null || b == null || a0 == null || b0 == null) continue;
            final mid = (ring[i] + ring[i + 1]) / 2;
            final fd = frame.depth(mid.dx, mid.dy, (_floorZ + _roofZ) / 2);
            final path = Path()
              ..moveTo(a0.dx, a0.dy)
              ..lineTo(b0.dx, b0.dy)
              ..lineTo(b.dx, b.dy)
              ..lineTo(a.dx, a.dy)
              ..close();
            faces.add(_Face(fd, path, side, null));
          }
        }

        // Roof.
        final roof = Path();
        var moved = false;
        var depthSum = 0.0;
        var count = 0;
        for (var i = 0; i < ring.length; i++) {
          final tp = topPts[i];
          if (tp == null) continue;
          if (!moved) {
            roof.moveTo(tp.dx, tp.dy);
            moved = true;
          } else {
            roof.lineTo(tp.dx, tp.dy);
          }
          depthSum += frame.depth(ring[i].dx, ring[i].dy, _roofZ);
          count++;
        }
        if (!moved || count == 0) continue;
        roof.close();
        faces.add(_Face(
          depthSum / count - 0.8, // small bias so roofs draw over own walls
          roof,
          topColor,
          prism.isBridge ? bridgeEdge : null,
        ));
      }
    }

    faces.sort((a, b) => b.depth.compareTo(a.depth));
    final fill = Paint()..style = PaintingStyle.fill;
    final strokePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    for (final f in faces) {
      fill.color = f.color;
      canvas.drawPath(f.path, fill);
      if (f.stroke != null) {
        strokePaint.color = f.stroke!;
        canvas.drawPath(f.path, strokePaint);
      }
    }
  }

  void _paintRoute(Canvas canvas, CameraFrame frame) {
    final path = routePath;
    if (path == null || !path.isUsable) return;
    const z = _roofZ + 0.9;
    final routeColor = isDark ? AppPalette.brandSoft : AppPalette.brand;

    final screen = Path();
    var started = false;
    for (final p in path.points) {
      final sp = frame.project(p.dx, p.dy, z);
      if (sp == null) {
        started = false;
        continue;
      }
      if (!started) {
        screen.moveTo(sp.dx, sp.dy);
        started = true;
      } else {
        screen.lineTo(sp.dx, sp.dy);
      }
    }

    canvas.drawPath(
      screen,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 9
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = (isDark ? Colors.black : Colors.white)
            .withValues(alpha: 0.65),
    );
    canvas.drawPath(
      screen,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = routeColor,
    );

    // Endpoints.
    final start = frame.project(path.points.first.dx, path.points.first.dy, z);
    final end = frame.project(path.points.last.dx, path.points.last.dy, z);
    if (start != null) {
      canvas.drawCircle(start, 7, Paint()..color = Colors.white);
      canvas.drawCircle(start, 5, Paint()..color = AppPalette.origin);
    }
    if (end != null) {
      canvas.drawCircle(end, 8, Paint()..color = Colors.white);
      canvas.drawCircle(end, 6, Paint()..color = AppPalette.destination);
    }

    // Progress puck.
    final t = progressT();
    if (t != null && showPuck()) {
      final p = path.pointAt(t);
      final sp = frame.project(p.dx, p.dy, z + 0.4);
      if (sp != null) {
        canvas.drawCircle(
            sp,
            13,
            Paint()
              ..color = routeColor.withValues(alpha: 0.25));
        canvas.drawCircle(sp, 9, Paint()..color = Colors.white);
        canvas.drawCircle(sp, 6.5, Paint()..color = routeColor);
      }
    }
  }

  void _paintLabels(Canvas canvas, CameraFrame frame) {
    final pillColor = (isDark ? AppPalette.cardDark : Colors.white)
        .withValues(alpha: 0.85);
    final placed = <Rect>[];

    // Nearest labels win declutter priority.
    final entries = <(double, Offset, Building)>[];
    for (final b in labelBuildings) {
      final local = Scene3D.toLocal(b.lat, b.lng);
      final d = frame.depth(local.dx, local.dy, _roofZ);
      if (d <= CameraFrame.near || d > 1100) continue;
      final sp = frame.project(local.dx, local.dy, _roofZ + 14);
      if (sp == null) continue;
      entries.add((d, sp, b));
    }
    entries.sort((a, b) => a.$1.compareTo(b.$1));

    for (final (d, sp, b) in entries) {
      final alpha = (1.2 - d / 1000).clamp(0.25, 1.0);
      final tp = _labelCache.putIfAbsent('${b.id}|$isDark', () {
        final painter = TextPainter(
          text: TextSpan(
            text: b.name,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.1,
              color: isDark ? AppPalette.inkDark : AppPalette.ink,
            ),
          ),
          textDirection: TextDirection.ltr,
          maxLines: 1,
          ellipsis: '…',
        )..layout(maxWidth: 150);
        return painter;
      });

      final rect = Rect.fromCenter(
        center: sp,
        width: tp.width + 18,
        height: tp.height + 10,
      );
      if (placed.any((r) => r.overlaps(rect.inflate(6)))) continue;
      placed.add(rect);

      canvas.saveLayer(rect.inflate(2), Paint()..color = Colors.white.withValues(alpha: alpha));
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(9)),
        Paint()..color = pillColor,
      );
      tp.paint(canvas, rect.topLeft + const Offset(9, 5));
      canvas.restore();

      // Anchor stem down toward the building.
      final stemEnd = sp + const Offset(0, 18);
      canvas.drawLine(
        Offset(sp.dx, rect.bottom),
        stemEnd,
        Paint()
          ..color = (isDark ? Colors.white : Colors.black)
              .withValues(alpha: 0.18 * alpha)
          ..strokeWidth = 1,
      );
    }
  }

  @override
  bool shouldRepaint(_NetworkPainter old) =>
      old.isDark != isDark ||
      old.footprints.length != footprints.length ||
      old.routePath != routePath;
}
