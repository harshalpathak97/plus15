import 'dart:math';

import 'geo.dart';

/// The +15 routing network, loaded from assets/data/network.json (generated
/// by tool/build_network.dart). Pure Dart: shared by the app, tool and tests.

typedef LatLngList = List<List<double>>; // [[lat, lng], ...]

class NetNode {
  final String id;
  final double lat, lng;
  final String type; // bridge_end | junction | terminal | street | link
  final String level; // '+15' | 'street'
  final List<String> regionIds;
  final String? label;
  final String source;
  final String confidence;
  /// Street doors from OpenStreetMap: wheelchair access as tagged there.
  final String? wheelchair;
  final P at;

  NetNode({
    required this.id,
    required this.lat,
    required this.lng,
    required this.type,
    required this.level,
    required this.regionIds,
    required this.label,
    required this.source,
    required this.confidence,
    this.wheelchair,
  }) : at = project(lat, lng);

  /// A street door mapped in OpenStreetMap (not an estimate).
  bool get isMappedDoor => level == 'street' && source.startsWith('osm:');

  factory NetNode.fromJson(Map<String, dynamic> j) => NetNode(
        id: j['id'] as String,
        lat: (j['lat'] as num).toDouble(),
        lng: (j['lng'] as num).toDouble(),
        type: j['type'] as String,
        level: j['level'] as String,
        regionIds: (j['regionIds'] as List).cast<String>(),
        label: j['label'] as String?,
        source: j['source'] as String,
        confidence: j['confidence'] as String,
        wheelchair: j['wheelchair'] as String?,
      );
}

class NetEdge {
  final String id;
  final String from, to;
  /// bridge | lane_link | interior | manual_link | street_exit | street_transfer | virtual
  final String kind;
  final String? regionId;
  final String? bridgeNumber;
  final List<String> buildingIds;
  final double lengthM;
  final bool indoor;
  final bool stairsRequired;
  final bool oneWay;
  final String confidence; // verified | likely | unverified | estimate
  final List<String> sources;
  final String? note;
  final LatLngList geometry;
  /// GPS approach only: where you walk to from the street ("Bankers Hall
  /// entrance on 8 Avenue SW", or the building when its doors aren't mapped).
  final String? via;

  const NetEdge({
    required this.id,
    required this.from,
    required this.to,
    required this.kind,
    this.regionId,
    this.bridgeNumber,
    this.buildingIds = const [],
    required this.lengthM,
    required this.indoor,
    this.stairsRequired = false,
    this.oneWay = false,
    required this.confidence,
    this.sources = const [],
    this.note,
    required this.geometry,
    this.via,
  });

  bool get isStreet =>
      kind == 'street_exit' || kind == 'street_transfer' || kind == 'virtual';
  bool get isBridgeLike => kind == 'bridge' || kind == 'lane_link';

  String other(String nodeId) => nodeId == from ? to : from;

  factory NetEdge.fromJson(Map<String, dynamic> j) => NetEdge(
        id: j['id'] as String,
        from: j['from'] as String,
        to: j['to'] as String,
        kind: j['kind'] as String,
        regionId: j['regionId'] as String?,
        bridgeNumber: j['bridgeNumber'] as String?,
        buildingIds: (j['buildingIds'] as List? ?? const []).cast<String>(),
        lengthM: (j['lengthM'] as num).toDouble(),
        indoor: j['indoor'] as bool,
        stairsRequired: j['stairsRequired'] as bool? ?? false,
        oneWay: j['oneWay'] as bool? ?? false,
        confidence: j['confidence'] as String,
        sources: (j['sources'] as List? ?? const []).cast<String>(),
        note: j['note'] as String?,
        geometry: _latLngs(j['geometry'] as List),
      );
}

class NetBuilding {
  final String id;
  final String name;
  final List<String> aliases;
  final String address; // '' when not curated
  final String type;
  final double lat, lng; // the building's +15 location (City footprints)
  final List<String> regionIds;
  final List<String> nodeIds; // every +15 node that counts as being "in" it
  final String? streetNodeId;
  /// Street doors (street-level nodes): mapped OSM doors, else one estimate.
  final List<String> entranceNodeIds;
  /// OpenStreetMap building outline, when one holds the building.
  final LatLngList outline;
  final List<String> landmarks; // official-map icons: food, shopping, hotel
  final bool noElevatorToStreet; // true only where the official map says so
  final bool secondary;
  final String? note;

  const NetBuilding({
    required this.id,
    required this.name,
    this.aliases = const [],
    this.address = '',
    this.type = 'office',
    required this.lat,
    required this.lng,
    this.regionIds = const [],
    this.nodeIds = const [],
    this.streetNodeId,
    this.entranceNodeIds = const [],
    this.outline = const [],
    this.landmarks = const [],
    this.noElevatorToStreet = false,
    this.secondary = false,
    this.note,
  });

  bool get isRoutable => nodeIds.isNotEmpty;

  /// Street-level door nodes (falls back to the single street node).
  List<String> get doors =>
      entranceNodeIds.isNotEmpty ? entranceNodeIds : [if (streetNodeId != null) streetNodeId!];

  /// Where the name goes on the map: the middle of the widest stretch across
  /// the outline at its mid-latitude (so it lands inside L-shaped blocks too),
  /// and how wide that stretch is. The +15 location, 0 m wide, without one.
  ({double lat, double lng, double widthM}) get label {
    if (outline.length < 4) return (lat: lat, lng: lng, widthM: 0);
    final lats = outline.map((p) => p[0]);
    final y = (lats.reduce(min) + lats.reduce(max)) / 2;
    final xs = [
      for (var i = 1; i < outline.length; i++)
        if ((outline[i - 1][0] > y) != (outline[i][0] > y))
          outline[i - 1][1] +
              (y - outline[i - 1][0]) *
                  (outline[i][1] - outline[i - 1][1]) /
                  (outline[i][0] - outline[i - 1][0]),
    ]..sort();
    var best = (lat: lat, lng: lng, widthM: 0.0);
    for (var i = 0; i + 1 < xs.length; i += 2) {
      final w = haversineM(y, xs[i], y, xs[i + 1]);
      if (w > best.widthM) best = (lat: y, lng: (xs[i] + xs[i + 1]) / 2, widthM: w);
    }
    return best;
  }

  /// Official-map icons plus 'transit' for CTrain links, for UI filters.
  List<String> get amenities => [...landmarks, if (type == 'transit') 'transit'];

  factory NetBuilding.fromJson(Map<String, dynamic> j) => NetBuilding(
        id: j['id'] as String,
        name: j['name'] as String,
        aliases: (j['aliases'] as List? ?? const []).cast<String>(),
        address: j['address'] as String? ?? '',
        type: j['type'] as String? ?? 'office',
        lat: (j['lat'] as num).toDouble(),
        lng: (j['lng'] as num).toDouble(),
        regionIds: (j['regionIds'] as List? ?? const []).cast<String>(),
        nodeIds: (j['nodeIds'] as List? ?? const []).cast<String>(),
        streetNodeId: j['streetNodeId'] as String?,
        entranceNodeIds: (j['entranceNodeIds'] as List? ??
                [if (j['streetNodeId'] != null) j['streetNodeId']])
            .cast<String>(),
        outline: _latLngs(j['outline'] as List? ?? const []),
        landmarks: (j['landmarks'] as List? ?? const []).cast<String>(),
        noElevatorToStreet: j['noElevatorToStreet'] as bool? ?? false,
        secondary: j['secondary'] as bool? ?? false,
        note: j['note'] as String?,
      );
}

class NetBridge {
  final String number;
  final String name;
  final String? crossing; // e.g. "8 Ave SW", "the lane"
  final String? connType;
  final String? structure;
  final String? constructed;
  final String regionId;
  final String? excluded;

  const NetBridge({
    required this.number,
    required this.name,
    this.crossing,
    this.connType,
    this.structure,
    this.constructed,
    required this.regionId,
    this.excluded,
  });

  bool get openToSky => structure?.contains('Open to Sky') ?? false;

  factory NetBridge.fromJson(Map<String, dynamic> j) => NetBridge(
        number: j['number'] as String,
        name: j['name'] as String,
        crossing: j['crossing'] as String?,
        connType: j['connType'] as String?,
        structure: j['structure'] as String?,
        constructed: j['constructed'] as String?,
        regionId: j['regionId'] as String,
        excluded: j['excluded'] as String?,
      );
}

class NetRegion {
  final String id;
  final String type; // Enclosed | Open to Sky | Bridge Enclosed | Bridge Open to Sky | Unrecorded
  final String? bridgeNumber;
  final List<String> buildingIds;
  final String label;
  final double widthM;
  final String? excluded;
  final List<LatLngList> rings; // [[lat, lng], ...] per ring; rings[0] outer

  const NetRegion({
    required this.id,
    required this.type,
    this.bridgeNumber,
    this.buildingIds = const [],
    this.label = '',
    this.widthM = 0,
    this.excluded,
    required this.rings,
  });

  bool get isBridge => type.startsWith('Bridge');
  bool get openToSky => type.contains('Open to Sky');

  Polygon get polygon =>
      Polygon([for (final r in rings) [for (final p in r) project(p[0], p[1])]]);

  factory NetRegion.fromJson(Map<String, dynamic> j) => NetRegion(
        id: j['id'] as String,
        type: j['type'] as String,
        bridgeNumber: j['bridgeNumber'] as String?,
        buildingIds: (j['buildingIds'] as List? ?? const []).cast<String>(),
        label: j['label'] as String? ?? '',
        widthM: (j['widthM'] as num? ?? 0).toDouble(),
        excluded: j['excluded'] as String?,
        rings: [for (final r in j['rings'] as List) _latLngs(r as List)],
      );
}

class NetworkHours {
  final List<int> weekday; // [openMinute, closeMinute]
  final List<int> weekendHoliday;
  final List<String> closedDates; // 'MM-DD'
  final String note;

  const NetworkHours({
    required this.weekday,
    required this.weekendHoliday,
    required this.closedDates,
    required this.note,
  });

  static int minuteOf(String hhmm) {
    final p = hhmm.split(':');
    return int.parse(p[0]) * 60 + int.parse(p[1]);
  }

  factory NetworkHours.fromJson(Map<String, dynamic> j) => NetworkHours(
        weekday: (j['weekday'] as List).cast<String>().map(minuteOf).toList(),
        weekendHoliday:
            (j['weekendHoliday'] as List).cast<String>().map(minuteOf).toList(),
        closedDates: (j['closedDates'] as List).cast<String>(),
        note: j['note'] as String? ?? '',
      );
}

class Plus15Network {
  final List<NetNode> nodes;
  final List<NetEdge> edges;
  final List<NetBuilding> buildings;
  final List<NetBridge> bridges;
  final List<NetRegion> regions;
  final NetworkHours hours;
  final Map<String, dynamic> sources;
  final Map<String, dynamic> issues;

  final Map<String, NetNode> nodeById;
  final Map<String, NetEdge> edgeById;
  final Map<String, NetBuilding> buildingById;
  final Map<String, NetBridge> bridgeByNumber;
  final Map<String, NetRegion> regionById;
  final Map<String, List<NetEdge>> edgesAt;
  /// Buildings each +15 node belongs to (a node on a shared polygon belongs
  /// to every building claiming it).
  final Map<String, List<NetBuilding>> buildingsAtNode;
  /// Street node → the building whose street exit it is.
  final Map<String, NetBuilding> streetOwner;

  Plus15Network({
    required this.nodes,
    required this.edges,
    required this.buildings,
    required this.bridges,
    required this.regions,
    required this.hours,
    this.sources = const {},
    this.issues = const {},
  })  : nodeById = {for (final n in nodes) n.id: n},
        edgeById = {for (final e in edges) e.id: e},
        buildingById = {for (final b in buildings) b.id: b},
        bridgeByNumber = {for (final b in bridges) b.number: b},
        regionById = {for (final r in regions) r.id: r},
        edgesAt = _index(edges),
        buildingsAtNode = _buildingsAtNode(buildings),
        streetOwner = {
          for (final b in buildings)
            for (final id in b.doors) id: b
        };

  static Map<String, List<NetEdge>> _index(List<NetEdge> edges) {
    final m = <String, List<NetEdge>>{};
    for (final e in edges) {
      (m[e.from] ??= []).add(e);
      if (!e.oneWay) (m[e.to] ??= []).add(e);
    }
    return m;
  }

  static Map<String, List<NetBuilding>> _buildingsAtNode(List<NetBuilding> bs) {
    final m = <String, List<NetBuilding>>{};
    for (final b in bs) {
      for (final n in b.nodeIds) {
        (m[n] ??= []).add(b);
      }
    }
    return m;
  }

  factory Plus15Network.fromJson(Map<String, dynamic> j) => Plus15Network(
        nodes: [for (final n in j['nodes'] as List) NetNode.fromJson(n as Map<String, dynamic>)],
        edges: [for (final e in j['edges'] as List) NetEdge.fromJson(e as Map<String, dynamic>)],
        buildings: [
          for (final b in j['buildings'] as List) NetBuilding.fromJson(b as Map<String, dynamic>)
        ],
        bridges: [for (final b in j['bridges'] as List) NetBridge.fromJson(b as Map<String, dynamic>)],
        regions: [for (final r in j['regions'] as List) NetRegion.fromJson(r as Map<String, dynamic>)],
        hours: NetworkHours.fromJson(j['hours'] as Map<String, dynamic>),
        sources: j['sources'] as Map<String, dynamic>? ?? const {},
        issues: j['issues'] as Map<String, dynamic>? ?? const {},
      );

  /// Display label for a +15 place: the non-secondary buildings claiming the
  /// region (e.g. "Bankers Hall", "Calgary Tower / Palliser One").
  String placeLabel(String? regionId) {
    final r = regionById[regionId];
    if (r == null) return '';
    return r.label;
  }

  /// The primary (first non-secondary) building at a node, for directions.
  NetBuilding? primaryBuildingAt(String nodeId) {
    final bs = buildingsAtNode[nodeId];
    if (bs == null || bs.isEmpty) return null;
    return bs.firstWhere((b) => !b.secondary, orElse: () => bs.first);
  }

  /// Bridge numbers touching any +15 node of [buildingId] — "bridges
  /// connected to X" in City closure notices.
  Set<String> bridgesOfBuilding(String buildingId) {
    final b = buildingById[buildingId];
    if (b == null) return {};
    return {
      for (final n in b.nodeIds)
        for (final e in edgesAt[n] ?? const <NetEdge>[])
          if (e.bridgeNumber != null) e.bridgeNumber!
    };
  }
}

LatLngList _latLngs(List raw) => [
      for (final p in raw)
        [((p as List)[0] as num).toDouble(), (p[1] as num).toDouble()]
    ];
