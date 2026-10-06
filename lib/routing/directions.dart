import 'geo.dart';
import 'network.dart';
import 'router.dart';

/// One instruction. [hopIndices] are the route hops it covers, in order, so
/// route_validator can check that instructions correspond to the graph.
class RouteStep {
  /// start | approach | through | bridge | link | exit | outdoor | enter | arrive
  final String kind;
  final String text;
  final List<int> hopIndices;
  final double distanceM;
  final String? buildingId;
  final List<String> bridgeNumbers;
  final List<String> landmarks;
  final String? caution;

  const RouteStep({
    required this.kind,
    required this.text,
    this.hopIndices = const [],
    this.distanceM = 0,
    this.buildingId,
    this.bridgeNumbers = const [],
    this.landmarks = const [],
    this.caution,
  });
}

const _landmarkNames = {'food': 'Food court', 'shopping': 'Shopping', 'hotel': 'Hotel'};

/// Turn words only where they can be trusted: when one bridge leads almost
/// directly into the next (less than [directTransferM] of walking between
/// them), the bridges' own axes tell you which way to turn. Inside larger
/// spaces the City footprints do not show walls or corridors, so directions
/// name the next bridge instead of guessing a turn.
const directTransferM = 15.0;
/// Shorter bridge hops are connectors, not street crossings.
const minStreetCrossingM = 15.0;
/// Unnamed links shorter than this merge into the following bridge step.
const shortLinkM = 12.0;
const turnMinDeg = 45.0;
const straightMaxDeg = 20.0;

List<RouteStep> buildDirections(Plus15Network net, PlannedRoute route, RouteOrigin origin) {
  final hops = route.hops;
  final dest = net.buildingById[route.destinationBuildingId]!;
  final steps = <RouteStep>[];

  String nameAt(String nodeId) =>
      net.primaryBuildingAt(nodeId)?.name ?? net.nodeById[nodeId]?.label ?? 'the next building';

  List<String> landmarksOf(NetBuilding? b) =>
      [for (final l in b?.landmarks ?? const <String>[]) _landmarkNames[l] ?? l];

  // Zero-length: already there.
  if (hops.isEmpty) {
    final o = net.buildingById[route.originBuildingId];
    if (origin.isLocation) {
      return [
        RouteStep(kind: 'arrive', text: 'You are in ${dest.name} (+15 walkway).', buildingId: dest.id)
      ];
    }
    final sharesRegion = o != null && o.regionIds.any(dest.regionIds.contains);
    final text = o == null || o.id == dest.id
        ? 'You are already in ${dest.name} (+15 level).'
        : sharesRegion
            ? '${dest.name} shares its +15 concourse with ${o.name}: you are already there.'
            : '${dest.name} adjoins ${o.name} directly at the +15 level (no bridge): walk straight in.';
    return [RouteStep(kind: 'arrive', text: text, buildingId: dest.id)];
  }

  // Group hops into segments.
  final segs = <List<int>>[];
  String segKey(RouteHop h) {
    final e = h.edge;
    if (e.kind == 'virtual') return 'virtual';
    if (e.kind == 'street_exit' || e.kind == 'street_transfer' || e.kind == 'manual_link') {
      return '${e.kind}:${e.id}';
    }
    if (e.isBridgeLike) return 'bridge';
    return 'interior:${net.placeLabel(e.regionId)}';
  }

  for (var i = 0; i < hops.length; i++) {
    final k = segKey(hops[i]);
    // Consecutive street transfers collapse into one outdoor walk.
    final prevK = segs.isEmpty ? null : segKey(hops[segs.last.last]);
    final sameOutdoor =
        k.startsWith('street_transfer') && (prevK?.startsWith('street_transfer') ?? false);
    // A chain of bridges is split wherever it reaches a building, so every
    // building passed is named.
    final atBuilding = k == 'bridge' &&
        segs.isNotEmpty &&
        (net.buildingsAtNode[hops[segs.last.last].toNode]?.isNotEmpty ?? false);
    if (segs.isNotEmpty && (prevK == k && !k.startsWith('street') || sameOutdoor) &&
        !k.startsWith('manual') &&
        !atBuilding) {
      segs.last.add(i);
    } else {
      segs.add([i]);
    }
  }

  double len(List<int> idx) => idx.fold(0.0, (s, i) => s + hops[i].lengthM);

  // Start.
  final first = hops.first;
  if (first.edge.kind == 'virtual') {
    final b = net.buildingById[first.edge.buildingIds.firstOrNull ?? ''];
    steps.add(RouteStep(
      kind: 'approach',
      text: first.edge.indoor
          ? _fromHere(net.placeLabel(first.edge.regionId),
              segs.length > 1 && hops[segs[1].first].edge.isBridgeLike
                  ? nameAt(hops[segs[1].last].toNode)
                  : null)
          : _approach(first.edge, b?.name ?? nameAt(first.toNode)),
      hopIndices: [0],
      distanceM: first.lengthM,
      buildingId: b?.id,
      caution: first.edge.indoor ? null : 'Outdoors at street level, not part of the +15',
    ));
  } else {
    final o = net.buildingById[route.originBuildingId];
    final oName = o?.name ?? nameAt(first.fromNode);
    final firstSeg = segs.first;
    final firstBridge = first.edge.isBridgeLike;
    steps.add(RouteStep(
      kind: 'start',
      text: firstBridge
          ? 'Start in $oName at the +15 level and head for the bridge to '
              '${nameAt(hops[firstSeg.last].toNode)}.'
          : 'Start in $oName at the +15 level.',
      buildingId: o?.id,
      landmarks: landmarksOf(o),
    ));
  }

  for (var s = 0; s < segs.length; s++) {
    final idx = segs[s];
    final h0 = hops[idx.first], hN = hops[idx.last];
    final e = h0.edge;
    if (e.kind == 'virtual') continue; // covered by the approach step
    final turn = e.isBridgeLike ? _turnBetweenBridges(hops, segs, s) : null;
    String withTurn(String text) =>
        turn == null ? text : '$turn and ${text[0].toLowerCase()}${text.substring(1)}';
    final nextIdx = s + 1 < segs.length ? segs[s + 1] : null;

    switch (e.kind) {
      case 'bridge' || 'lane_link':
        final numbers = {
          for (final i in idx)
            if (hops[i].edge.bridgeNumber != null) hops[i].edge.bridgeNumber!
        }.toList();
        // A City crossing applies only to a hop long enough to span a street:
        // short connectors in the same polygon chain (e.g. bridge 1561, 9 m)
        // are just links.
        final crossings = {
          for (final i in idx)
            if (hops[i].lengthM >= minStreetCrossingM &&
                net.bridgeByNumber[hops[i].edge.bridgeNumber]?.crossing != null)
              net.bridgeByNumber[hops[i].edge.bridgeNumber]!.crossing!
        }.toList();
        final into = nameAt(hN.toNode);
        final staying = into == nameAt(h0.fromNode);
        final openAir = idx.any((i) => !hops[i].edge.indoor);
        final stairs = idx.any((i) => hops[i].edge.stairsRequired);
        final lane = e.kind == 'lane_link' || crossings.contains('the lane');
        final over = crossings.where((c) => c != 'the lane').toList();
        final target = staying ? 'within $into' : 'into $into';
        var text = lane && over.isEmpty
            ? 'Cross the +15 lane link $target'
            : over.isEmpty
                ? 'Take the +15 link $target'
                : 'Cross the +15 bridge over ${over.join(' and ')}'
                    '${staying ? ', staying in $into' : ' into $into'}';
        // Buildings the walkway passes without entering (their entrances are
        // on this City polygon), e.g. the walkway behind Fifth & Fifth.
        final passing = <String>{
          for (final i in idx)
            for (final n in net.nodes)
              if (n.regionIds.contains(hops[i].edge.regionId))
                for (final b in net.buildingsAtNode[n.id] ?? const <NetBuilding>[])
                  if (!b.secondary) b.name
        }
          ..remove(into)
          ..remove(nameAt(h0.fromNode));
        if (passing.isNotEmpty && len(idx) > 60) text += ', passing ${passing.join(' and ')}';
        if (openAir) text += ' (open-air, exposed to weather)';
        text += '.';
        if (stairs) text += ' This link has stairs only — no step-free route here.';
        steps.add(RouteStep(
          kind: 'bridge',
          text: withTurn(text),
          hopIndices: idx,
          distanceM: len(idx),
          buildingId: net.primaryBuildingAt(hN.toNode)?.id,
          bridgeNumbers: numbers,
          landmarks: landmarksOf(net.primaryBuildingAt(hN.toNode)),
          caution: stairs ? 'Stairs only' : (h0.edge.confidence == 'likely' ? 'Not verified in detail' : null),
        ));
      case 'interior':
        final place = net.placeLabel(e.regionId);
        final b = net.primaryBuildingAt(h0.toNode) ?? net.primaryBuildingAt(h0.fromNode);
        String toward;
        if (nextIdx == null) {
          toward = dest.name == place ? '' : ' into ${dest.name}';
        } else {
          final nk = hops[nextIdx.first].edge.kind;
          final far = hops[nextIdx.last].toNode;
          final farName = nameAt(far);
          toward = switch (nk) {
            'bridge' || 'lane_link' when farName == place || farName == b?.name =>
              ' to the next +15 bridge',
            'bridge' || 'lane_link' => ' to the +15 bridge toward $farName',
            'street_exit' => ' to a street exit',
            'manual_link' => ' toward ${nameAt(far)}',
            'interior' => ' into ${net.placeLabel(hops[nextIdx.first].edge.regionId)}',
            _ => '',
          };
        }
        final openAir = idx.any((i) => !hops[i].edge.indoor);
        steps.add(RouteStep(
          kind: 'through',
          text: withTurn('Walk through $place$toward'
              '${openAir ? ' (part of this walkway is open to the sky)' : ''}.'),
          hopIndices: idx,
          distanceM: len(idx),
          buildingId: b?.id,
          landmarks: landmarksOf(b),
        ));
      case 'manual_link':
        final into = nameAt(hN.toNode);
        final fromName = nameAt(h0.fromNode);
        steps.add(RouteStep(
          kind: 'link',
          text: 'The +15 connection from $fromName into $into is shown on the official City '
              'map but not mapped in detail. Follow the +15 signs toward $into.',
          hopIndices: idx,
          distanceM: len(idx),
          buildingId: net.primaryBuildingAt(hN.toNode)?.id,
          caution: 'Not verified in detail',
        ));
      case 'street_exit':
        final leaving = net.nodeById[h0.toNode]?.type == 'street';
        // The building whose street exit this is (not whoever else shares
        // the +15 node it connects to).
        final b = net.streetOwner[leaving ? h0.toNode : h0.fromNode] ??
            net.primaryBuildingAt(leaving ? h0.fromNode : h0.toNode);
        final name = b?.name ?? nameAt(leaving ? h0.fromNode : h0.toNode);
        final door = net.nodeById[leaving ? h0.toNode : h0.fromNode];
        final mapped = door?.isMappedDoor ?? false;
        steps.add(RouteStep(
          kind: leaving ? 'exit' : 'enter',
          text: leaving
              ? (mapped
                  ? 'Go down to street level and leave $name by ${_the(door!.label!)}.'
                  : 'Go down to street level and leave $name by the nearest public door '
                      '(door locations here aren\'t mapped).')
              : (mapped
                  ? 'Enter $name by ${_the(door!.label!)} and go up to the +15 level.'
                  : 'Enter $name by its nearest public door and go up to the +15 level.'),
          hopIndices: idx,
          distanceM: len(idx),
          buildingId: b?.id,
          caution: b?.noElevatorToStreet == true
              ? 'No elevator to street here (official City map)'
              : mapped
                  ? 'Stairs, escalator or elevator inside not mapped'
                  : 'Street access not mapped',
        ));
      case 'street_transfer':
        final toNode = net.nodeById[hN.toNode];
        final toLabel = toNode == null
            ? 'the next building'
            : toNode.isMappedDoor
                ? _the(toNode.label!)
                : toNode.label ?? 'the next building';
        steps.add(RouteStep(
          kind: 'outdoor',
          text: 'Walk about ${_roundM(len(idx))} outdoors at street level to $toLabel '
              '(straight-line estimate, not +15).',
          hopIndices: idx,
          distanceM: len(idx),
          caution: 'Outdoors — not part of the +15',
        ));
    }
  }

  // A very short unnamed link (e.g. the 9 m connector into the Bankers Hall
  // West Parkade) folds into the bridge step that follows it.
  for (var i = steps.length - 2; i >= 0; i--) {
    final a = steps[i], b = steps[i + 1];
    if (a.kind == 'bridge' && b.kind == 'bridge' && a.distanceM < shortLinkM &&
        a.text.startsWith('Take the +15 link') && a.caution == null) {
      steps[i + 1] = RouteStep(
        kind: 'bridge',
        text: b.text,
        hopIndices: [...a.hopIndices, ...b.hopIndices],
        distanceM: a.distanceM + b.distanceM,
        buildingId: b.buildingId,
        bridgeNumbers: {...a.bridgeNumbers, ...b.bridgeNumbers}.toList(),
        landmarks: b.landmarks,
        caution: b.caution,
      );
      steps.removeAt(i);
    }
  }

  // The start step names the building the first (possibly merged) bridge
  // step leads into.
  if (steps.length > 1 && steps[0].kind == 'start' && steps[1].kind == 'bridge') {
    final next = net.buildingById[steps[1].buildingId]?.name;
    final o = net.buildingById[route.originBuildingId];
    if (next != null && o != null) {
      steps[0] = RouteStep(
        kind: 'start',
        text: 'Start in ${o.name} at the +15 level and head for the bridge to $next.',
        buildingId: o.id,
        landmarks: steps[0].landmarks,
      );
    }
  }

  final shared = dest.secondary || (net.regionById[dest.regionIds.firstOrNull]?.buildingIds.length ?? 0) > 1;
  final label = net.placeLabel(dest.regionIds.firstOrNull);
  steps.add(RouteStep(
    kind: 'arrive',
    text: shared && label.isNotEmpty && label != dest.name
        ? 'Arrive at ${dest.name} (+15 level, in ${label.startsWith('The ') ? label : 'the $label'} concourse).'
        : 'Arrive at ${dest.name} (+15 level).',
    buildingId: dest.id,
    landmarks: landmarksOf(dest),
  ));
  return steps;
}

/// The GPS approach: outdoors to a street door, then up to the +15.
String _approach(NetEdge e, String building) {
  final via = e.via ?? building;
  final where = via == building
      ? '$building (use its nearest public door; door locations here aren\'t mapped)'
      : _the(via);
  return 'From your location, walk about ${_roundM(e.lengthM)} outdoors to $where, '
      'then go up to the +15 level.';
}

/// "the Bankers Hall entrance", but "The Bow entrance".
String _the(String label) => label.startsWith('The ') ? label : 'the $label';

String _fromHere(String label, String? nextBridgeTo) {
  final where = label.isEmpty ? 'the +15' : label;
  return nextBridgeTo == null
      ? 'From your location in $where, follow the route on the map.'
      : 'From your location in $where, head for the +15 bridge to $nextBridgeTo.';
}

String _roundM(double m) => m < 100 ? '${(m / 5).round() * 5} m' : '${(m / 10).round() * 10} m';

/// "Turn left"/"Turn right"/"Continue straight" when bridge segment [s]
/// follows another bridge almost directly, else null.
String? _turnBetweenBridges(List<RouteHop> hops, List<List<int>> segs, int s) {
  // Find the previous bridge segment, allowing only a short interior gap.
  var gap = 0.0;
  var k = s - 1;
  while (k >= 0 && !hops[segs[k].first].edge.isBridgeLike) {
    if (hops[segs[k].first].edge.kind != 'interior') return null;
    gap += segs[k].fold(0.0, (a, i) => a + hops[i].lengthM);
    k--;
  }
  if (k < 0 || gap >= directTransferM) return null;
  final hin = _axis(hops[segs[k].last].geometry);
  final hout = _axis(hops[segs[s].first].geometry);
  if (hin == null || hout == null) return null;
  final t = turnDeg(hin, hout);
  if (t.abs() <= straightMaxDeg) return 'Continue straight';
  if (t.abs() < turnMinDeg) return null;
  return t > 0 ? 'Turn right' : 'Turn left';
}

/// Overall direction of a bridge hop (bridges are straight structures).
double? _axis(LatLngList g) {
  if (g.length < 2) return null;
  final a = project(g.first[0], g.first[1]), b = project(g.last[0], g.last[1]);
  if (a.dist(b) < 5) return null;
  return headingDeg(a, b);
}
