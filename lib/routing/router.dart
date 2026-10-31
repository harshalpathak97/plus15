import 'dart:math';

import 'package:collection/collection.dart';

import 'conditions.dart';
import 'directions.dart';
import 'geo.dart';
import 'network.dart';
import 'streets.dart';

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
/// Up to this far, the walk to a door is a straight line (across a plaza or
/// the sidewalk you are on), not a trip via the nearest mapped sidewalk.
const directWalkM = 50.0;
/// Doors tried per end (you, the destination) when planning a maps-app handoff.
const _handoffPool = 12;

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

  /// "Nearest +15 entrance": one outdoor walk that ends at a street door.
  bool get isEntranceRoute =>
      hops.length == 1 && hops.single.edge.id.startsWith('virtual:entrance:');

  /// The street door this route walks to, when it has an outdoor start.
  List<double>? get doorPoint {
    final h = hops.firstOrNull;
    if (h == null || h.edge.kind != 'virtual' || h.edge.indoor) return null;
    return isEntranceRoute ? h.geometry.last : h.geometry[h.geometry.length - 2];
  }

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

/// A door to reach with a maps app, and the +15 route from it to the destination.
class HandoffPlan {
  final ApproachDoor door;
  final PlannedRoute indoor;
  const HandoffPlan(this.door, this.indoor);

  /// Straight line to the door stands in for the street leg (the maps app
  /// plans the real one), plus the metres walked inside the +15.
  double get score => door.distanceM + indoor.lengthM;
}

/// Entrances worth taking a maps app to, best first, one per building.
class HandoffResult {
  final List<HandoffPlan> plans;
  final String? unavailableReason;
  const HandoffResult(this.plans, [this.unavailableReason]);
  bool get ok => plans.isNotEmpty;
}

/// Ranked street doors into the +15 from a GPS fix.
class EntranceResult {
  /// Nearest first by walking distance; each is one outdoor hop to a door.
  final List<PlannedRoute> routes;
  /// Doors nearer by air that have no mapped street path from here.
  final int skipped;
  /// Straight-line distances: the fix is off the mapped street grid.
  final bool approximate;
  final String? unavailableReason;
  final DateTime? nextOpen;
  /// Set when the fix is already inside a +15 walkway.
  final String? insideLabel;
  /// The start was chosen on the map, not the phone's location.
  final bool manualStart;
  const EntranceResult(this.routes,
      {this.skipped = 0,
      this.approximate = false,
      this.unavailableReason,
      this.nextOpen,
      this.insideLabel,
      this.manualStart = false});
  bool get ok => routes.isNotEmpty;

  EntranceResult withManualStart() => EntranceResult(routes,
      skipped: skipped,
      approximate: approximate,
      unavailableReason: unavailableReason,
      nextOpen: nextOpen,
      insideLabel: insideLabel,
      manualStart: true);
}

class Plus15Router {
  final Plus15Network network;
  final Conditions conditions;
  /// Sidewalk graph for the outdoor leg; without it, outdoor walks are
  /// straight lines.
  final StreetGraph? streets;

  /// Street node → the +15 node its street exit leads to.
  final Map<String, String> _entryOf;
  /// Street node → its street exit edge (closable).
  final Map<String, String> _exitEdgeOf;

  Plus15Router(this.network, this.conditions, {this.streets})
      : _entryOf = {
          for (final e in network.edges)
            if (e.kind == 'street_exit')
              if (network.nodeById[e.to]?.level == 'street') e.to: e.from else e.from: e.to
        },
        _exitEdgeOf = {
          for (final e in network.edges)
            if (e.kind == 'street_exit')
              if (network.nodeById[e.to]?.level == 'street') e.to: e.id else e.from: e.id
        };

  /// The nearest street doors into the +15 from a GPS fix, ranked by the
  /// walk along mapped sidewalks (straight line only as a labelled fallback).
  /// Each result is a route with one outdoor hop ending at the door, so it
  /// can be shown and navigated like any other. [doorNodeId] re-plans to a
  /// door already chosen (re-routing).
  EntranceResult nearestEntrances(
    RouteOrigin origin, {
    RouteProfile profile = RouteProfile.fastest,
    required DateTime at,
    int limit = 5,
    String? doorNodeId,
  }) {
    final status = conditions.networkStatusAt(at);
    if (!status.open && status.nextOpen == null) {
      return EntranceResult(const [],
          unavailableReason: 'The +15 network is closed (${status.label}).');
    }
    final opensAt = status.open ? null : status.nextOpen;
    at = opensAt ?? at;
    final region = regionAt(origin);
    if (region != null) {
      return EntranceResult(const [],
          insideLabel: network.placeLabel(region.id),
          unavailableReason: "You're already in the +15, in ${network.placeLabel(region.id)}.");
    }
    final accessible = profile == RouteProfile.accessible;
    final closed = conditions.closedEdgesAt(at);
    final elevatorsOut = conditions.elevatorOutagesAt(at);
    final closedBuildings = {
      for (final c in conditions.activeAt(at))
        if (c.kind == 'building_closed') ...c.buildings
    };
    // A door is usable when its +15 landing still leads beyond the building;
    // with every bridge of the building closed it is a dead end, not an entrance.
    final comp = _components((e) => closed.containsKey(e.id) ||
            e.confidence == 'unverified' ||
            e.isStreet ||
            (accessible && e.stairsRequired)
        ? null
        : e.lengthM);
    final compSize = <int, int>{};
    for (final c in comp.values) {
      compSize[c] = (compSize[c] ?? 0) + 1;
    }
    bool usable(ApproachDoor d) {
      if (closedBuildings.contains(d.building.id)) return false;
      if (closed.containsKey(_exitEdgeOf[d.nodeId])) return false;
      final c = comp[_entryOf[d.nodeId]];
      return c != null && (compSize[c] ?? 0) > d.building.nodeIds.length;
    }

    var doors = approachDoors(origin, accessible: accessible, elevatorsOut: elevatorsOut)
        .where((d) => usable(d) && (doorNodeId == null || d.nodeId == doorNodeId))
        .toList();
    if (doors.isEmpty) {
      return EntranceResult(const [],
          unavailableReason: accessible
              ? 'No building within ${(maxApproachM / 1000).toStringAsFixed(0)} km has a '
                  'confirmed step-free way up to the +15.'
              : 'You are more than ${(maxApproachM / 1000).toStringAsFixed(0)} km from the +15 '
                  'network. Take transit or drive downtown first.',
          nextOpen: opensAt);
    }
    // Straight line only prefilters; the walk decides the order.
    doors = doors.take(15).toList();
    final walks = _streetWalks(origin, doors, accessible: accessible);
    final routable = doors.where((d) => walks.containsKey(d.nodeId)).toList();
    final approximate = routable.isEmpty;
    final ranked = approximate ? doors : routable;
    if (!approximate) {
      ranked.sort((a, b) {
        final c = walks[a.nodeId]!.lengthM.compareTo(walks[b.nodeId]!.lengthM);
        return c != 0 ? c : a.distanceM.compareTo(b.distanceM);
      });
    }
    final routes = <PlannedRoute>[];
    final seenPoints = <String>{};
    for (final d in ranked) {
      if (routes.length >= limit) break;
      // Buildings sharing an outline share the same estimated point: list it once.
      if (!seenPoints.add('${d.lat.toStringAsFixed(5)},${d.lng.toStringAsFixed(5)}')) continue;
      final walk = walks[d.nodeId];
      final lengthM = walk?.lengthM ?? d.distanceM;
      final edge = NetEdge(
        id: 'virtual:entrance:${d.nodeId}',
        from: 'origin',
        to: d.nodeId,
        kind: 'virtual',
        buildingIds: [d.building.id],
        lengthM: lengthM,
        indoor: false,
        confidence: 'estimate',
        sources: ['gps', if (walk != null && !walk.direct) 'osm_streets'],
        note: 'Outdoors to ${d.label}',
        via: d.label,
        geometry: [
          [origin.lat!, origin.lng!],
          ...?walk?.geometry,
          [d.lat, d.lng],
        ],
      );
      final notes = <String>[
        if (walk == null)
          'Street path not mapped here: the distance is a straight-line estimate.',
        if (!d.mapped)
          '${d.building.name}: its street doors aren\'t mapped, so this points at the '
              'building. Use its nearest public door.',
        if (walk?.stairs ?? false) 'The walk to this door uses outdoor steps.',
      ];
      routes.add(_finish(
        [RouteHop(edge, 'origin', d.nodeId, edge.geometry, lengthM, 'street walk')],
        origin,
        d.building,
        profile,
        at,
        false,
        notes,
        {d.nodeId},
        {d.nodeId},
        closed,
        opensAt: opensAt,
        closedLabel: status.label,
      ));
    }
    // Doors nearer by air than the chosen one but with no street path.
    final skipped = approximate
        ? 0
        : doors
            .where((d) => d.distanceM < ranked.first.distanceM && !walks.containsKey(d.nodeId))
            .length;
    return EntranceResult(routes, skipped: skipped, approximate: approximate, nextOpen: opensAt);
  }

  /// Sidewalk walks from a fix to each door (by street node id). Empty when
  /// there is no street graph or the fix is off it (inside a block or park).
  Map<String, StreetWalk> _streetWalks(RouteOrigin o, List<ApproachDoor> doors,
      {required bool accessible}) {
    final g = streets;
    if (g == null || doors.isEmpty) return const {};
    final from = g.snap(project(o.lat!, o.lng!));
    if (from == null) return const {};
    final targets = <String, StreetSnap>{};
    final out = <String, StreetWalk>{};
    for (final d in doors) {
      // A door a few steps away: walk straight to it. Snapping both ends to
      // sidewalks would route around the block for a 5 m gap.
      if (d.distanceM <= directWalkM) {
        out[d.nodeId] = StreetWalk(d.distanceM, const [], false, direct: true);
        continue;
      }
      final s = g.snap(project(d.lat, d.lng));
      if (s != null) targets[d.nodeId] = s;
    }
    out.addAll(g.walks(from, targets, avoidStairs: accessible, maxM: maxApproachM * 1.5));
    return out;
  }

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
    final near = doors.takeWhile((d) => d.distanceM <= max(300.0, nearest + 250)).toList();
    // Along mapped sidewalks where the street graph covers the fix; a door
    // with no street path keeps the straight line (drawn as an estimate).
    final walks = _streetWalks(o, near, accessible: accessible);
    final out = <String, _Source>{};
    for (final d in near) {
      final entry = network.nodeById[_entryOf[d.nodeId]];
      if (entry == null) continue;
      final walk = walks[d.nodeId];
      final walkM = walk?.lengthM ?? d.distanceM;
      final up = project(d.lat, d.lng).dist(entry.at) + 10; // + the level change
      final price = walkM * RouteWeights.streetTransferFactor +
          RouteWeights.streetExitPenaltyM + up;
      final prev = out[entry.id];
      if (prev != null && prev.cost <= price) continue;
      out[entry.id] = _Source(price, NetEdge(
        id: 'virtual:street:${d.nodeId}',
        from: 'origin',
        to: entry.id,
        kind: 'virtual',
        buildingIds: [d.building.id],
        lengthM: walkM + up,
        indoor: false,
        confidence: 'estimate',
        sources: ['gps', if (walk != null && !walk.direct) 'osm_streets'],
        note: 'Outdoors to ${d.label}, then up to the +15 level',
        via: d.label,
        geometry: [
          [o.lat!, o.lng!],
          ...?walk?.geometry,
          [d.lat, d.lng],
          [entry.lat, entry.lng],
        ],
      ));
    }
    return out.isEmpty ? null : out;
  }

  /// For a fix too far from the +15 to walk to it: the entrances worth taking
  /// a maps app to, each with the +15 route onward to [destinationId]. The
  /// candidates are the doors nearest you and nearest the destination; the
  /// best is the one with the shortest straight line plus indoor route.
  HandoffResult planHandoff(
    RouteOrigin origin,
    String destinationId, {
    RouteProfile profile = RouteProfile.fastest,
    required DateTime at,
    int limit = 3,
  }) {
    final dest = network.buildingById[destinationId];
    if (dest == null || !origin.isLocation) {
      return const HandoffResult([], 'Unknown destination.');
    }
    final accessible = profile == RouteProfile.accessible;
    final out = conditions.elevatorOutagesAt(at);
    List<ApproachDoor> doorsFrom(RouteOrigin o) => approachDoors(o,
        accessible: accessible, elevatorsOut: out, maxM: double.infinity);
    final fromYou = doorsFrom(origin);
    final byNode = {for (final d in fromYou) d.nodeId: d};
    final nearDest = doorsFrom(RouteOrigin.location(dest.lat, dest.lng));
    final pool = {
      for (final d in fromYou.take(_handoffPool)) d.nodeId,
      for (final d in nearDest.take(_handoffPool)) d.nodeId,
    };
    final best = <String, HandoffPlan>{};
    String? reason;
    for (final id in pool) {
      final d = byNode[id];
      if (d == null) continue;
      final r = route(RouteOrigin.building(d.building.id), destinationId,
          profile: profile, at: at);
      if (!r.ok) {
        reason ??= r.unavailableReason;
        continue;
      }
      final plan = HandoffPlan(d, r.route!);
      final prev = best[d.building.id];
      if (prev == null || plan.score < prev.score) best[d.building.id] = plan;
    }
    if (best.isEmpty) {
      return HandoffResult(const [], reason ?? 'No +15 entrance leads to ${dest.name}.');
    }
    final plans = best.values.sorted((a, b) => a.score.compareTo(b.score));
    return HandoffResult(plans.take(limit).toList());
  }

  /// Street doors near a GPS fix, nearest first, within [maxM] (default
  /// [maxApproachM]). Mapped OpenStreetMap doors are used as they are; for a
  /// building whose doors aren't mapped, the point of its outline nearest you
  /// stands in.
  List<ApproachDoor> approachDoors(RouteOrigin o,
      {bool accessible = false,
      Set<String> elevatorsOut = const {},
      double maxM = maxApproachM}) {
    final p = project(o.lat!, o.lng!);
    final out = <ApproachDoor>[];
    for (final b in network.buildings) {
      if (!b.isRoutable) continue;
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
        if (d > maxM) continue;
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
