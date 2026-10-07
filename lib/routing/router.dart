import 'dart:math';

import 'package:collection/collection.dart';

import 'conditions.dart';
import 'directions.dart';
import 'geo.dart';
import 'network.dart';

/// PlannedRoute profiles. Weights are explicit and tested (test/router_test.dart).
enum RouteProfile {
  // Prefers City-verified links (see RouteWeights.likelyFactor), so it isn't
  // always the shortest: labelled for what it is.
  fastest('Recommended'),
  accessible('Accessible'),
  mostlyIndoors('Mostly indoors');

  final String label;
  const RouteProfile(this.label);
}

/// Furthest the app will walk you outdoors to reach the +15.
const maxApproachM = 3000.0;

/// A street door you can walk to from a GPS fix.
class ApproachDoor {
  final NetBuilding building;
  final String nodeId; // the street node (door) in the graph
  final double lat, lng; // where to walk to
  final double distanceM; // straight line from the fix
  final String label;
  final bool mapped; // an OpenStreetMap door, not an outline estimate
  const ApproachDoor(
      this.building, this.nodeId, this.lat, this.lng, this.distanceM, this.label, this.mapped);
}

class RouteWeights {
  static const likelyFactor = 1.25; // prefer verified connections
  static const streetTransferFactor = 2.5; // outdoor walking is a last resort
  static const streetExitPenaltyM = 60.0; // leaving/entering the +15 level
  static const openAirFactorMostlyIndoors = 3.0;
  /// For "will this finish before the +15 closes" (≈4.3 km/h, unhurried).
  static const walkingSpeedMps = 1.2;
}

/// Where a route starts: a building, or a GPS fix.
class RouteOrigin {
  final String? buildingId;
  final double? lat, lng;
  const RouteOrigin.building(String this.buildingId)
      : lat = null,
        lng = null;
  const RouteOrigin.location(double this.lat, double this.lng) : buildingId = null;
  bool get isLocation => buildingId == null;
}

/// One traversal of an edge, oriented in the direction walked.
class RouteHop {
  final NetEdge edge;
  final String fromNode, toNode;
  final LatLngList geometry;
  final double cost;
  final String costNote;
  const RouteHop(this.edge, this.fromNode, this.toNode, this.geometry, this.cost, this.costNote);
  double get lengthM => edge.lengthM;
}

class PlannedRoute {
  final List<RouteHop> hops;
  final String? originBuildingId;
  final String destinationBuildingId;
  final RouteProfile profile;
  final DateTime at;
  final bool usesStreet;
  final List<String> warnings;
  final List<String> notes; // e.g. closures avoided
  final Set<String> originNodes, destinationNodes;
  /// Set when the +15 is closed at the requested time: the route is planned
  /// for this opening time and can be browsed, not walked, until then.
  final DateTime? opensAt;
  /// Non-empty for a view-only route through bridges that are closed now.
  final List<Closure> throughClosures;
  late final List<RouteStep> steps;

  PlannedRoute({
    required this.hops,
    required this.originBuildingId,
    required this.destinationBuildingId,
    required this.profile,
    required this.at,
    required this.usesStreet,
    required this.warnings,
    required this.notes,
    required this.originNodes,
    required this.destinationNodes,
    this.opensAt,
    this.throughClosures = const [],
  });

  /// Can be browsed and previewed but not started as live navigation.
  bool get previewOnly => opensAt != null || throughClosures.isNotEmpty;

  double get lengthM => hops.fold(0.0, (s, h) => s + h.lengthM);
  double get cost => hops.fold(0.0, (s, h) => s + h.cost);
  int get bridgeCount =>
      hops.map((h) => h.edge.bridgeNumber).whereType<String>().toSet().length;
  bool get usesLikely => hops.any((h) => h.edge.confidence == 'likely');
  bool get stepFree => !hops.any((h) => h.edge.stairsRequired);
  List<String> get edgeIds => [for (final h in hops) h.edge.id];

  LatLngList get geometry {
    final out = <List<double>>[];
    for (final h in hops) {
      for (final p in h.geometry) {
        if (out.isEmpty || out.last[0] != p[0] || out.last[1] != p[1]) out.add(p);
      }
    }
    return out;
  }

  /// Major transitions for golden tests: building ids and bridge numbers.
  List<String> get transitions {
    final out = <String>[];
    for (final h in hops) {
      final b = h.edge.bridgeNumber;
      if (b != null && (out.isEmpty || out.last != 'bridge:$b')) out.add('bridge:$b');
    }
    return out;
  }
}

class RouteResult {
  final PlannedRoute? route;
  final String? unavailableReason;
  final DateTime? nextOpen;
  /// View-only: the route the closures currently block, for planning.
  final PlannedRoute? viaClosed;
  const RouteResult.ok(PlannedRoute this.route, {this.viaClosed})
      : unavailableReason = null,
        nextOpen = null;
  const RouteResult.unavailable(String this.unavailableReason, {this.nextOpen, this.viaClosed})
      : route = null;
  bool get ok => route != null;
}

class Plus15Router {
  final Plus15Network network;
  final Conditions conditions;

  /// Street node → the +15 node its street exit leads to.
  final Map<String, String> _entryOf;

  Plus15Router(this.network, this.conditions)
      : _entryOf = {
          for (final e in network.edges)
            if (e.kind == 'street_exit')
              if (network.nodeById[e.to]?.level == 'street') e.to: e.from else e.from: e.to
        };

  /// The building a street exit edge belongs to.
  NetBuilding? streetExitBuilding(NetEdge e) =>
      network.streetOwner[e.from] ?? network.streetOwner[e.to];

  RouteResult route(
    RouteOrigin origin,
    String destinationId, {
    RouteProfile profile = RouteProfile.fastest,
    required DateTime at,
  }) {
    final dest = network.buildingById[destinationId];
    if (dest == null) return const RouteResult.unavailable('Unknown destination.');
    if (!dest.isRoutable) {
      return RouteResult.unavailable('${dest.name}: its +15 entry is not mapped.');
    }
    // Closed now: plan for the next opening so the route can still be browsed.
    final status = conditions.networkStatusAt(at);
    if (!status.open && status.nextOpen == null) {
      return RouteResult.unavailable('The +15 network is closed (${status.label}).');
    }
    final opensAt = status.open ? null : status.nextOpen;
    final closedLabel = status.label;
    at = opensAt ?? at;
    PlannedRoute finish(List<RouteHop> hops, bool usesStreet, List<String> notes,
            Set<String> originNodes, Set<String> targets, Map<String, Closure> closed,
            {List<Closure> through = const []}) =>
        _finish(hops, origin, dest, profile, at, usesStreet, notes, originNodes, targets, closed,
            opensAt: opensAt, closedLabel: closedLabel, through: through);
    final closed = conditions.closedEdgesAt(at);
    final elevatorsOut = conditions.elevatorOutagesAt(at);
    final accessible = profile == RouteProfile.accessible;
    for (final c in conditions.activeAt(at)) {
      if (c.kind == 'building_closed' && c.buildings.contains(dest.id)) {
        return RouteResult.unavailable('${dest.name} is closed: ${c.title}.');
      }
    }
    final targets = dest.nodeIds.toSet();

    // A GPS fix inside the destination's own +15 walkway: already there.
    if (origin.isLocation &&
        (regionAt(origin)?.buildingIds.contains(dest.id) ?? false)) {
      return RouteResult.ok(finish([], false, [], const {}, targets, closed));
    }
    final from = _sources(origin, accessible: accessible, elevatorsOut: elevatorsOut);
    if (from == null) {
      final o = network.buildingById[origin.buildingId];
      return RouteResult.unavailable(origin.isLocation
          ? (accessible
              ? 'No building within ${(maxApproachM / 1000).toStringAsFixed(0)} km has a '
                  'confirmed step-free way up to the +15.'
              : 'You are more than ${(maxApproachM / 1000).toStringAsFixed(0)} km from the +15 '
                  'network. Take transit or drive downtown first.')
          : o == null
              ? 'Unknown starting point.'
              : '${o.name}: its +15 entry is not mapped.');
    }

    double? cost(NetEdge e, bool allowStreet, bool respectClosures) {
      if (respectClosures && closed.containsKey(e.id)) return null;
      if (e.confidence == 'unverified') return null;
      if (e.kind == 'virtual') return e.lengthM; // priced (and profile-checked) when created
      if (e.isStreet && !allowStreet) return null;
      if (accessible) {
        if (e.stairsRequired) return null;
        if (e.kind == 'street_exit') {
          final b = streetExitBuilding(e);
          if (b == null || b.noElevatorToStreet || elevatorsOut.contains(b.id)) return null;
        }
      }
      var c = switch (e.kind) {
        'street_transfer' => e.lengthM * RouteWeights.streetTransferFactor,
        'street_exit' => e.lengthM + RouteWeights.streetExitPenaltyM,
        _ => e.lengthM,
      };
      if (e.confidence == 'likely') c *= RouteWeights.likelyFactor;
      if (profile == RouteProfile.mostlyIndoors && !e.indoor) {
        c *= RouteWeights.openAirFactorMostlyIndoors;
      }
      return c;
    }

    // Origin and destination in the same +15 place.
    final shared = from.keys.where(targets.contains).toSet();
    if (shared.isNotEmpty && from.values.every((s) => s.virtual == null)) {
      return RouteResult.ok(finish([], false, [], {...from.keys}, targets, closed));
    }

    var hops = _dijkstra(from, targets, (e) => cost(e, false, true));
    var usesStreet = false;
    if (hops == null) {
      // No +15 route. Outdoor walks are allowed only between places that are
      // not connected at +15 (under the same closures and profile), so the
      // route never walks outside where it could stay in the +15.
      final comp = _components((e) => cost(e, false, true));
      double? pass2(NetEdge e) {
        if (e.kind == 'street_transfer') {
          final a = comp[_entryOf[e.from]], b = comp[_entryOf[e.to]];
          if (a == null || b == null || a == b) return null;
        }
        return cost(e, true, true);
      }

      hops = _dijkstra(from, targets, pass2);
      usesStreet = hops != null && hops.any((h) => h.edge.isStreet && h.edge.kind != 'virtual');
    }
    // The same search ignoring closures: what they cost, and a view-only
    // route through them for planning.
    final free = closed.isEmpty
        ? null
        : _dijkstra(from, targets, (e) => cost(e, false, false)) ??
            _dijkstra(from, targets, (e) => cost(e, true, false));
    final through = {
      for (final h in free ?? const <RouteHop>[])
        if (closed[h.edge.id] != null) closed[h.edge.id]!
    };
    final freeOutdoor = free?.any((h) => h.edge.isStreet && h.edge.kind != 'virtual') ?? false;
    final viaClosed = through.isEmpty
        ? null
        : finish(free!, freeOutdoor, const [], {...from.keys}, targets, const {},
            through: through.toList());
    if (hops == null) {
      final why = <String>[];
      if (closed.isNotEmpty) why.add('current closures');
      if (accessible) why.add('step-free access');
      final oName = origin.isLocation
          ? 'your location'
          : network.buildingById[origin.buildingId]?.name ?? 'the start';
      return RouteResult.unavailable('No route from $oName to ${dest.name}'
          '${why.isEmpty ? '' : ' with ${why.join(' and ')}'}.', viaClosed: viaClosed);
    }

    // What the closures cost. Prefer a +15-only comparison: if one exists
    // without closures but not with them, the closure forces the outdoor walk.
    final notes = <String>[];
    if (free != null) {
      final extra = hops.fold(0.0, (s, h) => s + h.lengthM) -
          free.fold(0.0, (s, h) => s + h.lengthM);
      for (final c in through) {
        notes.add(usesStreet && !freeOutdoor
            ? 'Closure: ${c.title}. There is no +15 route while it is closed, so this '
                'route includes an outdoor walk.'
            : 'Avoids closure: ${c.title}'
                '${extra > 5 ? ' (adds about ${extra.round()} m)' : ''}.');
      }
    }
    return RouteResult.ok(finish(hops, usesStreet, notes, {...from.keys}, targets, closed),
        viaClosed: viaClosed);
  }

  PlannedRoute _finish(
    List<RouteHop> hops,
    RouteOrigin origin,
    NetBuilding dest,
    RouteProfile profile,
    DateTime at,
    bool usesStreet,
    List<String> notes,
    Set<String> originNodes,
    Set<String> targets,
    Map<String, Closure> closed, {
    DateTime? opensAt,
    String closedLabel = '',
    List<Closure> through = const [],
  }) {
    final warnings = <String>[];
    for (final c in through) {
      warnings.add('Preview only: this goes through a bridge that is closed now (${c.title}).');
    }
    if (opensAt != null) {
      warnings.add('The +15 is closed now (${closedLabel.replaceFirst('Closed · ', '')}). '
          'This route is for planning.');
    }
    if (hops.any((h) => h.edge.confidence == 'likely')) {
      warnings.add('Part of this route uses a connection shown on the official City map '
          'but not mapped in detail in City walkway data.');
    }
    if (usesStreet) {
      warnings.add('No +15 route is available: this route includes outdoor walking at street '
          'level (straight-line estimate, not +15).');
    }
    if (hops.any((h) => h.edge.stairsRequired)) {
      warnings.add('Includes a stairs-only link (official City map). Use Accessible for a '
          'step-free route.');
    }
    if (profile == RouteProfile.accessible &&
        hops.any((h) => h.edge.kind == 'street_exit' || h.edge.kind == 'virtual')) {
      warnings.add('Elevator access between street and +15 is not confirmed for every building.');
    }
    final status = conditions.networkStatusAt(at);
    final walkS = hops.fold(0.0, (s, h) => s + h.lengthM) / RouteWeights.walkingSpeedMps;
    if (status.open && !conditions.networkStatusAt(at.add(Duration(seconds: walkS.round()))).open) {
      warnings.add('The +15 is ${status.label.toLowerCase()}: this walk takes about '
          '${(walkS / 60).ceil()} min and may not finish before closing.');
    }
    if (profile == RouteProfile.accessible) {
      for (final b in {network.buildingById[origin.buildingId], dest}) {
        if (b != null && b.noElevatorToStreet) {
          warnings.add('${b.name}: the official City map shows no elevator between the street '
              'and the +15 here.');
        }
      }
    }
    if (status.reducedHoursDay) {
      warnings.add('Weekend/holiday hours: the City notes some bridges may have shorter hours '
          'or be closed.');
    }
    final used = {for (final h in hops) h.edge.id};
    for (final c in conditions.recentlyEndedAt(at)
        .where((c) => conditions.edgesClosedBy(c).any(used.contains))) {
      warnings.add('${c.title}: the City estimated it would reopen around '
          '${c.end!.year}-${c.end!.month.toString().padLeft(2, '0')}; reopening not confirmed.');
    }
    final route = PlannedRoute(
      hops: hops,
      originBuildingId: origin.buildingId,
      destinationBuildingId: dest.id,
      profile: profile,
      at: at,
      usesStreet: usesStreet,
      warnings: warnings,
      notes: notes,
      originNodes: originNodes,
      destinationNodes: targets,
      opensAt: opensAt,
      throughClosures: through,
    );
    route.steps = buildDirections(network, route, origin);
    return route;
  }

  /// The building walkway polygon (not a bridge) containing a GPS fix.
  NetRegion? regionAt(RouteOrigin o) {
    final p = project(o.lat!, o.lng!);
    for (final r in network.regions) {
      if (r.excluded != null || r.isBridge || r.buildingIds.isEmpty) continue;
      if (r.polygon.contains(p)) return r;
    }
    return null;
  }

  /// Source nodes with their entry cost (and a virtual edge for GPS origins).
  /// A fix inside a building's +15 walkway starts there. Anywhere else —
  /// including under a bridge, which is usually street level — starts outdoors
  /// and goes up through a nearby building (with a confirmed street elevator
  /// for Accessible).
  Map<String, _Source>? _sources(RouteOrigin o,
      {required bool accessible, required Set<String> elevatorsOut}) {
    if (!o.isLocation) {
      final b = network.buildingById[o.buildingId];
      if (b == null || !b.isRoutable) return null;
      return {for (final n in b.nodeIds) n: const _Source(0, null)};
    }
    final p = project(o.lat!, o.lng!);
    final r = regionAt(o);
    if (r != null) {
      final out = <String, _Source>{};
      for (final n in network.nodes) {
        if (!n.regionIds.contains(r.id)) continue;
        final d = n.at.dist(p);
        out[n.id] = _Source(d, NetEdge(
          id: 'virtual:${n.id}',
          from: 'origin',
          to: n.id,
          kind: 'virtual',
          regionId: r.id,
          buildingIds: r.buildingIds,
          lengthM: d,
          indoor: true,
          confidence: 'estimate',
          sources: const ['gps'],
          note: 'From your location inside ${r.label}',
          geometry: [[o.lat!, o.lng!], [n.lat, n.lng]],
        ));
      }
      if (out.isNotEmpty) return out;
    }
    // Outdoors: walk to a street door and go up to the +15 level. Doors of
    // every building up to [maxApproachM] away are candidates; the search
    // then picks the door that makes the whole trip shortest (outdoor
    // metres cost more), which is the nearest door in your direction.
    final doors = approachDoors(o, accessible: accessible, elevatorsOut: elevatorsOut);
    if (doors.isEmpty) return null;
    final nearest = doors.first.distanceM;
    final out = <String, _Source>{};
    for (final d in doors) {
      if (d.distanceM > max(300.0, nearest + 250)) break;
      final entry = network.nodeById[_entryOf[d.nodeId]];
      if (entry == null) continue;
      final up = project(d.lat, d.lng).dist(entry.at) + 10; // + the level change
      final price = d.distanceM * RouteWeights.streetTransferFactor +
          RouteWeights.streetExitPenaltyM + up;
      final prev = out[entry.id];
      if (prev != null && prev.cost <= price) continue;
      out[entry.id] = _Source(price, NetEdge(
        id: 'virtual:street:${d.nodeId}',
        from: 'origin',
        to: entry.id,
        kind: 'virtual',
        buildingIds: [d.building.id],
        lengthM: d.distanceM + up,
        indoor: false,
        confidence: 'estimate',
        sources: const ['gps'],
        note: 'Outdoors to ${d.label}, then up to the +15 level',
        via: d.label,
        geometry: [[o.lat!, o.lng!], [d.lat, d.lng], [entry.lat, entry.lng]],
      ));
    }
    return out.isEmpty ? null : out;
  }

  /// Street doors near a GPS fix, nearest first, within [maxApproachM].
  /// Mapped OpenStreetMap doors are used as they are; for a building whose
  /// doors aren't mapped, the point of its outline nearest you stands in.
  List<ApproachDoor> approachDoors(RouteOrigin o,
      {bool accessible = false, Set<String> elevatorsOut = const {}}) {
    final p = project(o.lat!, o.lng!);
    final out = <ApproachDoor>[];
    for (final b in network.buildings) {
      if (!b.isRoutable || b.secondary || b.type == 'transit') continue;
      if (accessible && (b.noElevatorToStreet || elevatorsOut.contains(b.id))) continue;
      for (final id in b.doors) {
        final n = network.nodeById[id];
        if (n == null || _entryOf[id] == null) continue;
        if (accessible && n.wheelchair == 'no') continue;
        var at = n.at;
        var label = n.label ?? b.name;
        if (!n.isMappedDoor) {
          label = b.name;
          if (b.outline.length > 3) {
            at = Polygon([
              [for (final q in b.outline) project(q[0], q[1])]
            ]).closestBoundaryPoint(p);
          }
        }
        final d = at.dist(p);
        if (d > maxApproachM) continue;
        final ll = unproject(at);
        out.add(ApproachDoor(b, id, ll[0], ll[1], d, label, n.isMappedDoor));
      }
    }
    out.sort((a, b) => a.distanceM.compareTo(b.distanceM));
    return out;
  }

  /// Connected +15 components under [costOf] (street edges excluded by it).
  Map<String, int> _components(double? Function(NetEdge) costOf) {
    final comp = <String, int>{};
    var next = 0;
    for (final n in network.nodes) {
      if (n.level != '+15' || comp.containsKey(n.id)) continue;
      final stack = [n.id];
      comp[n.id] = next;
      while (stack.isNotEmpty) {
        final u = stack.removeLast();
        for (final e in network.edgesAt[u] ?? const <NetEdge>[]) {
          if (costOf(e) == null) continue;
          final v = e.other(u);
          if (!comp.containsKey(v)) {
            comp[v] = next;
            stack.add(v);
          }
        }
      }
      next++;
    }
    return comp;
  }

  List<RouteHop>? _dijkstra(
    Map<String, _Source> sources,
    Set<String> targets,
    double? Function(NetEdge) costOf,
  ) {
    final dist = <String, double>{};
    final prev = <String, (String, NetEdge, double)>{};
    final pq = PriorityQueue<(double, String)>((a, b) => a.$1.compareTo(b.$1));
    sources.forEach((n, s) {
      dist[n] = s.cost;
      pq.add((s.cost, n));
    });
    String? reached;
    while (pq.isNotEmpty) {
      final (d, u) = pq.removeFirst();
      if (d > (dist[u] ?? double.infinity)) continue;
      if (targets.contains(u)) {
        reached = u;
        break;
      }
      for (final e in network.edgesAt[u] ?? const <NetEdge>[]) {
        if (e.oneWay && e.from != u) continue;
        final c = costOf(e);
        if (c == null) continue;
        final v = e.other(u);
        final nd = d + c;
        if (nd < (dist[v] ?? double.infinity)) {
          dist[v] = nd;
          prev[v] = (u, e, c);
          pq.add((nd, v));
        }
      }
    }
    if (reached == null) return null;
    final hops = <RouteHop>[];
    var v = reached;
    while (prev.containsKey(v)) {
      final (u, e, c) = prev[v]!;
      hops.insert(0, _hop(e, u, v, c));
      v = u;
    }
    final start = sources[v]!;
    if (start.virtual != null) {
      hops.insert(0, RouteHop(start.virtual!, 'origin', v, start.virtual!.geometry,
          start.cost, 'estimate from GPS'));
    }
    return hops;
  }

  RouteHop _hop(NetEdge e, String from, String to, double cost) {
    final forward = e.from == from;
    final geom = forward ? e.geometry : e.geometry.reversed.toList();
    final notes = <String>['${e.lengthM.toStringAsFixed(0)} m'];
    if (e.kind == 'street_transfer') notes.add('× ${RouteWeights.streetTransferFactor} outdoor');
    if (e.kind == 'street_exit') notes.add('+ ${RouteWeights.streetExitPenaltyM.round()} level change');
    if (e.confidence == 'likely') notes.add('× ${RouteWeights.likelyFactor} likely');
    if (!e.indoor && e.kind != 'street_exit' && cost > e.lengthM * RouteWeights.streetTransferFactor) {
      notes.add('× ${RouteWeights.openAirFactorMostlyIndoors} open-air');
    }
    return RouteHop(e, from, to, geom, cost, '${notes.join(' ')} = ${cost.toStringAsFixed(0)}');
  }
}

class _Source {
  final double cost;
  final NetEdge? virtual;
  const _Source(this.cost, this.virtual);
}
