import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../../core/theme/app_palette.dart';
import '../../../routing/conditions.dart';
import '../../../routing/network.dart';
import '../../../routing/router.dart';

LatLng _ll(List<double> p) => LatLng(p[0], p[1]);

/// Display layer: the City of Calgary +15 walkway footprints themselves, with
/// bridges stroked on top so the network reads at overview zooms. Closed
/// bridges (per closures.json at [closedBridges]) are drawn in red.
List<Widget> networkLayers(
  Plus15Network net, {
  required Set<String> closedBridges,
  required double zoom,
  required bool isDark,
}) {
  final skywalk = isDark ? AppPalette.skywalkBright : AppPalette.skywalk;
  // Quieter when a route is shown so the route reads first.
  final polygons = <Polygon>[];
  for (final r in net.regions) {
    if (r.excluded != null) continue;
    final closed = r.bridgeNumber != null && closedBridges.contains(r.bridgeNumber);
    final color = closed
        ? AppPalette.danger
        : r.isBridge
            ? skywalk
            : skywalk.withValues(alpha: 0.55);
    polygons.add(Polygon(
      points: [for (final p in r.rings.first) _ll(p)],
      holePointsList: [
        for (final h in r.rings.skip(1)) [for (final p in h) _ll(p)]
      ],
      color: color.withValues(alpha: r.openToSky ? 0.18 : (r.isBridge ? 0.55 : 0.28)),
      borderColor: color.withValues(alpha: 0.8),
      borderStrokeWidth: r.isBridge ? 1.0 : 0.6,
    ));
  }
  final width = zoom >= 16.5 ? 3.0 : zoom >= 15 ? 2.6 : 2.0;
  final bridgeLines = <Polyline>[
    for (final e in net.edges)
      if (e.isBridgeLike)
        Polyline(
          points: [for (final p in e.geometry) _ll(p)],
          strokeWidth: width,
          color: e.bridgeNumber != null && closedBridges.contains(e.bridgeNumber)
              ? AppPalette.danger
              : e.stairsRequired
                  ? AppPalette.warning
                  : skywalk.withValues(alpha: 0.9),
          strokeCap: StrokeCap.round,
        ),
  ];
  return [
    if (zoom >= 13.5) PolygonLayer(polygons: polygons),
    if (zoom < 13.5 || zoom >= 15) PolylineLayer(polylines: bridgeLines),
  ];
}

/// Building outlines as grey blocks under the +15, like the City's map. Some
/// buildings share an outline (a hotel in an office tower); each draws once.
Widget buildingFootprints(Plus15Network net, {required bool isDark}) {
  final outlines = {
    for (final b in net.buildings)
      if (b.outline.isNotEmpty) '${b.outline}': b.outline,
  };
  return PolygonLayer(polygons: [
    for (final o in outlines.values)
      Polygon(
        points: [for (final p in o) _ll(p)],
        color: isDark ? const Color(0xFF34383F) : const Color(0xFFC4C6CB),
        borderColor: isDark ? const Color(0xFF6A707A) : const Color(0xFF4A4F57),
        borderStrokeWidth: 0.8,
      ),
  ]);
}

/// The route exactly as routed: each hop's edge geometry, no smoothing.
/// Street-level parts (outdoor transfers, GPS approach) and links not mapped
/// in detail are dashed. [reveal] (0–1) draws the route on along its length.
List<Widget> routeLayers(PlannedRoute route, {required bool isDark, double reveal = 1}) {
  final accent = isDark ? AppPalette.brandSoft : AppPalette.brand;
  final casing = isDark ? const Color(0xFF06302C) : Colors.white;
  final solid = <Polyline>[], dashed = <Polyline>[];
  final total = route.hops.fold(0.0, (a, h) => a + _len(h.geometry));
  var budget = reveal.clamp(0.0, 1.0) * total;
  for (final h in route.hops) {
    if (budget <= 0) break;
    final pts = <LatLng>[];
    final g = h.geometry;
    pts.add(_ll(g.first));
    for (var i = 1; i < g.length && budget > 0; i++) {
      final a = _ll(g[i - 1]), b = _ll(g[i]);
      final d = const Distance().as(LengthUnit.Meter, a, b);
      if (d <= budget) {
        pts.add(b);
        budget -= d;
      } else {
        final t = budget / d;
        pts.add(LatLng(a.latitude + (b.latitude - a.latitude) * t,
            a.longitude + (b.longitude - a.longitude) * t));
        budget = 0;
      }
    }
    if (pts.length < 2) continue;
    // Street level (walking outside, to a door or between the two +15
    // networks) is dotted; +15 links not mapped in detail are dashed.
    if (h.edge.isStreet && !h.edge.indoor) {
      dashed.add(Polyline(
        points: pts,
        strokeWidth: 5,
        color: AppPalette.warning,
        strokeCap: StrokeCap.round,
        pattern: const StrokePattern.dotted(spacingFactor: 1.8),
      ));
    } else if (h.edge.confidence == 'likely') {
      dashed.add(Polyline(
        points: pts,
        strokeWidth: 4.5,
        color: AppPalette.warning,
        strokeCap: StrokeCap.round,
        pattern: StrokePattern.dashed(segments: const [9.0, 7.0]),
      ));
    } else {
      solid.add(Polyline(
        points: pts,
        strokeWidth: 6,
        color: accent,
        strokeCap: StrokeCap.round,
        strokeJoin: StrokeJoin.round,
        borderStrokeWidth: 2.5,
        borderColor: casing,
      ));
    }
  }
  return [
    PolylineLayer(polylines: solid),
    PolylineLayer(polylines: dashed),
  ];
}

/// The street doors a route uses: where to go in from the street ("Enter")
/// and where it leaves the +15 for an outdoor walk ("Exit").
List<Marker> routeDoorMarkers(PlannedRoute route, Plus15Network net) {
  final out = <Marker>[];
  Marker door(List<double> at, String label, bool mapped) => Marker(
        point: _ll(at),
        width: 124,
        height: 30,
        alignment: Alignment.topCenter,
        child: _DoorChip(label: label, mapped: mapped),
      );
  for (final h in route.hops) {
    if (h.edge.kind == 'virtual' && !h.edge.indoor && h.geometry.length >= 3) {
      out.add(door(h.geometry[1], 'Enter here', h.edge.via != null &&
          h.edge.via != net.buildingById[h.edge.buildingIds.firstOrNull]?.name));
    } else if (h.edge.kind == 'street_exit') {
      final leaving = net.nodeById[h.toNode]?.level == 'street';
      final n = net.nodeById[leaving ? h.toNode : h.fromNode];
      if (n != null) out.add(door([n.lat, n.lng], leaving ? 'Exit' : 'Enter', n.isMappedDoor));
    }
  }
  return out;
}

/// Every street door mapped in OpenStreetMap, for close-up zooms.
List<Marker> doorMarkers(Plus15Network net, {required bool isDark}) => [
      for (final n in net.nodes)
        if (n.isMappedDoor)
          Marker(
            point: LatLng(n.lat, n.lng),
            width: 18,
            height: 18,
            child: Tooltip(
              message: n.label ?? 'Street entrance',
              child: Container(
                decoration: BoxDecoration(
                  color: isDark ? AppPalette.cardDark : Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppPalette.skywalk, width: 1.5),
                ),
                child: const Icon(Icons.door_front_door_outlined, size: 11, color: AppPalette.skywalk),
              ),
            ),
          ),
    ];

class _DoorChip extends StatelessWidget {
  final String label;
  final bool mapped;
  const _DoorChip({required this.label, required this.mapped});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppPalette.warning, width: 1.5),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.18), blurRadius: 6, offset: const Offset(0, 2)),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(mapped ? Icons.door_front_door_rounded : Icons.door_front_door_outlined,
                size: 14, color: AppPalette.warning),
            const SizedBox(width: 4),
            Flexible(
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium),
            ),
          ],
        ),
      ),
    );
  }
}

double _len(List<List<double>> g) {
  var s = 0.0;
  for (var i = 1; i < g.length; i++) {
    s += const Distance().as(LengthUnit.Meter, _ll(g[i - 1]), _ll(g[i]));
  }
  return s;
}

/// Debug overlay: every routing node and edge, tappable for its attributes,
/// sources and confidence.
class GraphDebugLayer extends StatefulWidget {
  final Plus15Network network;
  final Map<String, Closure> closedEdges;
  final double zoom;

  const GraphDebugLayer({
    super.key,
    required this.network,
    required this.closedEdges,
    required this.zoom,
  });

  @override
  State<GraphDebugLayer> createState() => _GraphDebugLayerState();
}

class _GraphDebugLayerState extends State<GraphDebugLayer> {
  final LayerHitNotifier<String> _edgeHits = ValueNotifier(null);
  final LayerHitNotifier<String> _nodeHits = ValueNotifier(null);

  static Color edgeColor(NetEdge e, bool closed) {
    if (closed) return AppPalette.danger;
    return switch (e.confidence) {
      'verified' => const Color(0xFF0EA5E9),
      'likely' => AppPalette.warning,
      'estimate' => const Color(0xFF94A3B8),
      _ => AppPalette.inkMuted,
    };
  }

  static Color nodeColor(String type) => switch (type) {
        'bridge_end' => AppPalette.ink,
        'junction' => const Color(0xFF059669),
        'terminal' => const Color(0xFFDC2626),
        'street' => const Color(0xFF64748B),
        _ => const Color(0xFFF59E0B),
      };

  @override
  Widget build(BuildContext context) {
    final net = widget.network;
    final showStreet = widget.zoom >= 16.5;
    return Stack(
      children: [
        GestureDetector(
          onTap: () {
            final id = _edgeHits.value?.hitValues.firstOrNull;
            if (id != null) _showEdge(context, net.edgeById[id]!);
          },
          child: PolylineLayer<String>(
            hitNotifier: _edgeHits,
            polylines: [
              for (final e in net.edges)
                if (showStreet || !e.isStreet)
                  Polyline<String>(
                    points: [for (final p in e.geometry) _ll(p)],
                    strokeWidth: e.isBridgeLike ? 2.2 : 1.2,
                    color: edgeColor(e, widget.closedEdges.containsKey(e.id))
                        .withValues(alpha: e.isStreet ? 0.5 : 0.85),
                    pattern: e.isStreet
                        ? StrokePattern.dashed(segments: const [6.0, 6.0])
                        : const StrokePattern.solid(),
                    hitValue: e.id,
                  ),
            ],
          ),
        ),
        GestureDetector(
          onTap: () {
            final id = _nodeHits.value?.hitValues.firstOrNull;
            if (id != null) _showNode(context, net.nodeById[id]!);
          },
          child: CircleLayer<String>(
            hitNotifier: _nodeHits,
            circles: [
              for (final n in net.nodes)
                if (showStreet || n.type != 'street')
                  CircleMarker<String>(
                    point: LatLng(n.lat, n.lng),
                    radius: widget.zoom >= 17 ? 5 : 3.5,
                    color: nodeColor(n.type),
                    borderColor: Colors.white,
                    borderStrokeWidth: 1,
                    hitValue: n.id,
                  ),
            ],
          ),
        ),
        if (widget.zoom >= 17.5)
          MarkerLayer(markers: [
            for (final n in net.nodes)
              if (n.type != 'street')
                Marker(
                  point: LatLng(n.lat, n.lng),
                  width: 44,
                  height: 14,
                  alignment: Alignment.topCenter,
                  child: IgnorePointer(
                    child: Text(n.id,
                        style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700)),
                  ),
                ),
          ]),
      ],
    );
  }

  void _showEdge(BuildContext context, NetEdge e) {
    final net = widget.network;
    final bridge = net.bridgeByNumber[e.bridgeNumber];
    final closure = widget.closedEdges[e.id];
    _sheet(context, 'Edge ${e.id}', {
      'Kind': e.kind,
      'From → to': '${e.from} → ${e.to}${e.oneWay ? ' (one-way)' : ' (both directions)'}',
      'Length': '${e.lengthM.toStringAsFixed(1)} m',
      if (e.regionId != null) 'City polygon': '${e.regionId} (${net.regionById[e.regionId]?.type})',
      if (bridge != null) 'City bridge': '${bridge.number}: ${bridge.name}',
      if (bridge?.crossing != null) 'Crosses': bridge!.crossing!,
      if (e.buildingIds.isNotEmpty) 'Buildings': e.buildingIds.join(', '),
      'Indoor': e.indoor ? 'yes' : 'no (open-air or street)',
      'Stairs required': e.stairsRequired ? 'yes (official map)' : 'not known',
      'Closure': closure == null ? 'open' : '${closure.title} — ${closure.cityText}',
      'Confidence': e.confidence,
      'Sources': e.sources.map((s) => _sourceName(net, s)).join('; '),
      if (e.note != null) 'Note': e.note!,
      'Geometry': '${e.geometry.first[0]}, ${e.geometry.first[1]} → '
          '${e.geometry.last[0]}, ${e.geometry.last[1]} (${e.geometry.length} pts)',
    });
  }

  void _showNode(BuildContext context, NetNode n) {
    final net = widget.network;
    _sheet(context, 'Node ${n.id}', {
      'Type': n.type,
      'Level': n.level,
      'Coordinates': '${n.lat}, ${n.lng}',
      'City polygons': n.regionIds.join(', '),
      'Buildings': (net.buildingsAtNode[n.id] ?? const []).map((b) => b.name).join(', '),
      if (n.label != null) 'Label': n.label!,
      'Edges': '${net.edgesAt[n.id]?.length ?? 0}',
      'Confidence': n.confidence,
      'Source': _sourceName(net, n.source),
    });
  }

  static String _sourceName(Plus15Network net, String key) {
    final s = net.sources[key];
    if (s is Map) return '${s['title']} (retrieved ${s['retrieved']})';
    return switch (key) {
      'estimate' => 'Estimate (straight line; not in City data)',
      'gps' => 'Your GPS position',
      _ => key,
    };
  }

  void _sheet(BuildContext context, String title, Map<String, String> rows) {
    showModalBottomSheet(
      context: context,
      // Above the shell's floating nav bar.
      useRootNavigator: true,
      isScrollControlled: true,
      showDragHandle: true,
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.75),
      builder: (ctx) => SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          shrinkWrap: true,
          children: [
            Text(title, style: Theme.of(ctx).textTheme.titleLarge),
            const SizedBox(height: 8),
            for (final r in rows.entries)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                        width: 120,
                        child: Text(r.key,
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12))),
                    Expanded(child: SelectableText(r.value, style: const TextStyle(fontSize: 12))),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
