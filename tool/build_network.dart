// Builds assets/data/network.json (the single routing source of truth) from
// City of Calgary open-data snapshots in tool/sources/ plus the hand-curated
// tool/curation.json. See docs/routing.md.
//
//   dart run tool/build_network.dart            # build from snapshots
//   dart run tool/build_network.dart --refresh  # re-download City and OSM data first
//   dart run tool/build_network.dart --refresh-osm  # re-download OSM street doors only
//   dart run tool/build_network.dart --dump     # print zones for curation
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:plus15_navigator/routing/geo.dart';

const walkwaysUrl =
    'https://data.calgary.ca/resource/3u3x-hrc7.geojson?\$limit=5000';
const bridgesUrl =
    'https://data.calgary.ca/resource/fu7z-c7ar.json?\$limit=5000';
const walkwaysSource = 'City of Calgary Open Data "Plus 15" (3u3x-hrc7)';
const bridgesSource = 'City of Calgary Open Data "Plus 15 Bridges" (fu7z-c7ar)';
const mapSource = 'City of Calgary +15 Skywalk Network map v30 (2025)';
const osmUrl = 'https://overpass-api.de/api/interpreter';
const osmQuery = '[out:json][timeout:120];'
    '(node["entrance"](51.0405,-114.0905,51.0565,-114.0500);'
    'way["building"](51.0405,-114.0905,51.0565,-114.0500);'
    'relation["building"](51.0405,-114.0905,51.0565,-114.0500););out body;>;out skel qt;';
const osmSource = 'OpenStreetMap building entrances (© OpenStreetMap contributors, ODbL)';

final _errors = <String>[];
final _warnings = <String>[];
void err(String m) => _errors.add(m);
void warn(String m) => _warnings.add(m);

class Region {
  final int index; // position in the source file
  late String id;
  String type; // Enclosed | Open to Sky | Bridge Enclosed | Bridge Open to Sky | Unrecorded
  final String cityType; // as published, before curation overrides
  String? typeNote;
  final Polygon poly;
  final List<List<List<double>>> lngLatRings;
  bool excluded = false;
  String? excludedReason;
  int zone = -1;
  String? buildingId;
  Map<String, dynamic>? bridgeRecord;
  final portals = <Portal>[];
  Region(this.index, this.type, this.poly, this.lngLatRings) : cityType = type;
  bool get isBridge => type.startsWith('Bridge');
  bool get openToSky => type.contains('Open to Sky');
}

class Portal {
  final Region a, b;
  final P at;
  final double widthM;
  late String nodeId;
  Portal(this.a, this.b, this.at, this.widthM);
  Region other(Region r) => r == a ? b : a;
}

// main() is defined in the build section below.

/// Street doors and building outlines downtown from OpenStreetMap (Overpass),
/// saved compactly: doors (with tags) and outline rings (ways and the outer
/// rings of multipolygon buildings).
Future<void> _downloadOsm(String path) async {
  stdout.writeln('POST $osmUrl');
  final client = HttpClient()..userAgent = 'plus15-navigator-build/1.0';
  final req = await client.postUrl(Uri.parse(osmUrl));
  req.headers
    ..contentType = ContentType('application', 'x-www-form-urlencoded')
    ..set('Accept', 'application/json');
  req.write('data=${Uri.encodeQueryComponent(osmQuery)}');
  final res = await req.close();
  if (res.statusCode != 200) throw 'HTTP ${res.statusCode} for $osmUrl';
  final els = ((jsonDecode(await res.transform(utf8.decoder).join()) as Map)['elements'] as List)
      .cast<Map>();
  client.close();
  final nodes = <int, Map>{};
  for (final e in els) {
    // Recursed outlines repeat nodes without tags: keep the tagged copy.
    if (e['type'] == 'node' && (nodes[e['id']] == null || e['tags'] != null)) nodes[e['id']] = e;
  }
  final wayNodes = {
    for (final e in els)
      if (e['type'] == 'way') e['id'] as int: (e['nodes'] as List).cast<int>()
  };
  List<double> ll(int id) => [
        double.parse((nodes[id]!['lat'] as num).toStringAsFixed(7)),
        double.parse((nodes[id]!['lon'] as num).toStringAsFixed(7)),
      ];
  final outlines = <Map<String, Object>>[];
  void outline(String id, List<int> ids) {
    if (ids.length < 4 || ids.first != ids.last || !ids.every(nodes.containsKey)) return;
    outlines.add({'id': id, 'nodes': ids, 'ring': [for (final n in ids) ll(n)]});
  }
  for (final e in els) {
    final tags = (e['tags'] as Map?) ?? const {};
    if (e['type'] == 'way' && tags['building'] != null) outline('w${e['id']}', wayNodes[e['id']]!);
    if (e['type'] == 'relation' && tags['building'] != null) {
      for (final m in (e['members'] as List).cast<Map>()) {
        if (m['type'] == 'way' && m['role'] == 'outer' && wayNodes[m['ref']] != null) {
          outline('r${e['id']}', wayNodes[m['ref']]!);
        }
      }
    }
  }
  await File(path).writeAsString(jsonEncode({
    'source': osmSource,
    'query': osmQuery,
    'retrieved': DateTime.now().toUtc().toIso8601String().substring(0, 10),
    'doors': [
      for (final n in nodes.values)
        if ((n['tags'] as Map?)?['entrance'] != null)
          {'id': n['id'], 'll': ll(n['id'] as int), 'tags': n['tags']}
    ],
    'outlines': outlines,
  }));
}

/// A public street door of an OSM building.
class OsmEntrance {
  final int id;
  final P at;
  final String type; // main | yes | secondary
  final String? wheelchair; // yes | limited | no
  final String? street; // addr:street
  OsmEntrance(this.id, this.at, this.type, this.wheelchair, this.street);
}

class OsmOutline {
  final String id; // w<way> or r<relation>
  final Polygon poly;
  final Set<int> nodeIds;
  OsmOutline(this.id, this.poly, this.nodeIds);
}

/// OSM building outlines and street-level public doors. Shop, home, garage,
/// service and emergency doors, doors marked private, and doors above or
/// below ground (+15 bridge doors are tagged level=1) are left out.
(List<OsmOutline>, List<OsmEntrance>) _loadOsm(String path) {
  final f = File(path);
  if (!f.existsSync()) return (const [], const []);
  final j = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
  P at(List ll) => project((ll[0] as num).toDouble(), (ll[1] as num).toDouble());
  final outlines = [
    for (final o in (j['outlines'] as List).cast<Map>())
      OsmOutline(o['id'] as String, Polygon([[for (final p in o['ring'] as List) at(p as List)]]),
          (o['nodes'] as List).cast<int>().toSet())
  ];
  final entrances = <OsmEntrance>[];
  for (final d in (j['doors'] as List).cast<Map>()) {
    final t = (d['tags'] as Map).cast<String, dynamic>();
    final type = t['entrance'] as String?;
    if (!const {'main', 'yes', 'secondary'}.contains(type)) continue;
    if (const {'private', 'no'}.contains(t['access'])) continue;
    final level = double.tryParse('${t['level'] ?? '0'}'.split(';').first) ?? 0;
    if (level.abs() >= 0.5) continue;
    entrances.add(OsmEntrance(d['id'] as int, at(d['ll'] as List), type!,
        t['wheelchair'] as String?, t['addr:street'] as String?));
  }
  return (outlines, entrances);
}

Future<void> _download(String url, String path) async {
  stdout.writeln('GET $url');
  final client = HttpClient();
  final res = await (await client.getUrl(Uri.parse(url))).close();
  if (res.statusCode != 200) throw 'HTTP ${res.statusCode} for $url';
  await File(path).writeAsString(await res.transform(utf8.decoder).join());
  client.close();
}

List<Region> _loadRegions(String path) {
  final g = jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
  final out = <Region>[];
  final feats = (g['features'] as List).cast<Map<String, dynamic>>();
  for (var i = 0; i < feats.length; i++) {
    final f = feats[i];
    final geom = f['geometry'] as Map<String, dynamic>;
    final parts = geom['type'] == 'MultiPolygon'
        ? (geom['coordinates'] as List)
        : [geom['coordinates']];
    final type =
        (f['properties'] as Map)['structure_type'] as String? ?? 'Unrecorded';
    // One region per polygon part (only one source feature is multi-part).
    for (final part in parts) {
      final lngLat = (part as List)
          .map((ring) => (ring as List)
              .map((p) => [
                    ((p as List)[0] as num).toDouble(),
                    (p[1] as num).toDouble()
                  ])
              .toList())
          .toList();
      final rings =
          lngLat.map((r) => r.map((p) => project(p[1], p[0])).toList()).toList();
      out.add(Region(i, type, Polygon(rings), lngLat));
    }
  }
  // Stable ids: sort by centroid (north→south, west→east).
  final sorted = [...out]..sort((a, b) {
      final ca = a.poly.centroid, cb = b.poly.centroid;
      final dy = cb.y.compareTo(ca.y);
      return dy != 0 ? dy : ca.x.compareTo(cb.x);
    });
  for (var i = 0; i < sorted.length; i++) {
    sorted[i].id = 'R${(i + 1).toString().padLeft(3, '0')}';
  }
  return sorted;
}

bool _bboxNear(Polygon a, Polygon b, double pad) {
  final (ax0, ay0, ax1, ay1) = a.bbox;
  final (bx0, by0, bx1, by1) = b.bbox;
  return !(ax0 - pad > bx1 || bx0 - pad > ax1 || ay0 - pad > by1 || by0 - pad > ay1);
}

/// Portals: stretches where two City polygons share a boundary (within 0.5 m)
/// or overlap. One portal node at the middle of each stretch of >= 1 m.
void _findPortals(List<Region> regions) {
  const step = 0.25, tol = 0.5, minWidth = 1.0;
  for (var i = 0; i < regions.length; i++) {
    for (var j = i + 1; j < regions.length; j++) {
      final ri = regions[i], rj = regions[j];
      if (ri.excluded || rj.excluded) continue;
      if (!_bboxNear(ri.poly, rj.poly, 1)) continue;
      // Sample the boundary of the polygon with the shorter perimeter.
      final (p, q) =
          ri.poly.perimeter <= rj.poly.perimeter ? (ri, rj) : (rj, ri);
      for (final ring in p.poly.rings) {
        final samples = <(P, bool)>[];
        for (var k = 0; k + 1 < ring.length; k++) {
          final a = ring[k], b = ring[k + 1];
          final n = max(1, (a.dist(b) / step).ceil());
          for (var s = 0; s < n; s++) {
            final pt = a + (b - a) * (s / n);
            samples.add((pt, q.poly.covers(pt, tol: tol)));
          }
        }
        if (!samples.any((s) => s.$2)) continue;
        // Rotate so we start on a non-near sample (handles wrap-around runs).
        final start = samples.indexWhere((s) => !s.$2);
        final seq = start == -1
            ? samples
            : [...samples.sublist(start), ...samples.sublist(0, start)];
        var run = <P>[];
        void flush() {
          if (run.length >= 2) {
            final w = polylineLength(run);
            if (w >= minWidth) {
              // Middle of the run by arc length.
              var acc = 0.0;
              var mid = run[run.length ~/ 2];
              for (var k = 1; k < run.length; k++) {
                acc += run[k - 1].dist(run[k]);
                if (acc >= w / 2) {
                  mid = run[k];
                  break;
                }
              }
              final portal = Portal(ri, rj, mid, w);
              ri.portals.add(portal);
              rj.portals.add(portal);
            }
          }
          run = <P>[];
        }

        for (final (pt, near) in seq) {
          if (near) {
            run.add(pt);
          } else {
            flush();
          }
        }
        flush();
      }
    }
  }
}

final _wktPt = RegExp(r'(-?\d+\.\d+) (-?\d+\.\d+)');

void _matchBridgeRecords(
    List<Region> regions, List<Map<String, dynamic>> records) {
  for (final rec in records) {
    final number = rec['bridge_name'] as String?;
    final wkt = rec['polygon'] as String?;
    if (number == null) {
      warn('City bridge record without a bridge number skipped: '
          '"${rec['location']}" (${rec['structure_type']})');
      continue;
    }
    if (wkt == null) {
      err('City bridge record $number has no polygon');
      continue;
    }
    final pts = _wktPt
        .allMatches(wkt)
        .map((m) => project(double.parse(m[2]!), double.parse(m[1]!)))
        .toList();
    final recPoly = Polygon([pts]);
    final c = recPoly.centroid;
    Region? best;
    var bestScore = 0;
    for (final r in regions) {
      if (!r.cityType.startsWith('Bridge') && r.cityType != 'Unrecorded') continue;
      if (!_bboxNear(r.poly, recPoly, 2)) continue;
      var s = pts.where(r.poly.contains).length +
          r.poly.rings[0].where(recPoly.contains).length;
      if (r.poly.contains(c)) s += 100;
      if (s > bestScore) {
        bestScore = s;
        best = r;
      }
    }
    if (best == null) {
      err('City bridge $number "${rec['location']}" matches no walkway polygon');
    } else if (best.bridgeRecord != null) {
      err('Walkway ${best.id} matches two bridge records: '
          '${best.bridgeRecord!['bridge_name']} and $number');
    } else {
      best.bridgeRecord = rec;
    }
  }
}

/// Zones: maximal sets of non-bridge regions connected by portals.
List<List<Region>> _zones(List<Region> regions) {
  final zones = <List<Region>>[];
  for (final r in regions) {
    if (r.isBridge || r.excluded || r.zone != -1) continue;
    final z = <Region>[];
    final stack = [r];
    r.zone = zones.length;
    while (stack.isNotEmpty) {
      final u = stack.removeLast();
      z.add(u);
      for (final p in u.portals) {
        final v = p.other(u);
        if (!v.isBridge && !v.excluded && v.zone == -1) {
          v.zone = zones.length;
          stack.add(v);
        }
      }
    }
    zones.add(z);
  }
  return zones;
}

String _ll(P p) {
  final ll = unproject(p);
  return '${ll[0].toStringAsFixed(6)},${ll[1].toStringAsFixed(6)}';
}

String _bridgeLabel(Region b) {
  final rec = b.bridgeRecord;
  if (rec == null) return '${b.id}[unnamed ${b.type}]';
  return '${b.id}[${rec['bridge_name']}: ${rec['location']} / ${rec['cross_loc']}]';
}

void _dump(List<Region> regions, List<List<Region>> zones) {
  for (var zi = 0; zi < zones.length; zi++) {
    final z = zones[zi];
    final bridges = <Region>{
      for (final r in z)
        for (final p in r.portals)
          if (p.other(r).isBridge) p.other(r)
    };
    stdout.writeln('Z$zi');
    for (final r in z) {
      stdout.writeln('  ${r.id} ${r.type} ${r.poly.area.round()}m2 '
          '@${_ll(r.poly.centroid)}');
    }
    for (final b in bridges) {
      final zonesOfB = {
        for (final p in b.portals)
          if (!p.other(b).isBridge) 'Z${p.other(b).zone}' else p.other(b).id
      };
      stdout.writeln('  -> ${_bridgeLabel(b)} links ${zonesOfB.join(",")}');
    }
  }
  stdout.writeln('\nBRIDGES');
  for (final b in regions.where((r) => r.isBridge)) {
    final ends = b.portals
        .map((p) => p.other(b).isBridge ? p.other(b).id : 'Z${p.other(b).zone}')
        .join(',');
    stdout.writeln('${_bridgeLabel(b)} ${b.poly.area.round()}m2 '
        '@${_ll(b.poly.centroid)} ends: $ends');
  }
  stdout.writeln('\nERRORS');
  _errors.forEach(stdout.writeln);
  stdout.writeln('WARNINGS');
  _warnings.forEach(stdout.writeln);
}

// ---------------------------------------------------------------------------
// Full build
// ---------------------------------------------------------------------------

class Node {
  final String id;
  final P at;
  final String type; // bridge_end | junction | terminal | street | link
  final regions = <Region>{};
  String? label;
  String source;
  String confidence;
  String? wheelchair; // OSM door: yes | limited | no
  Node(this.id, this.at, this.type, {required this.source, required this.confidence});
}

class Edge {
  final String id;
  final Node a, b;
  final String kind; // bridge | lane_link | interior | manual_link | street_exit | street_transfer
  final Region? region;
  final List<P> geometry;
  String confidence;
  final List<String> sources;
  bool stairsRequired = false;
  String? note;
  Edge(this.id, this.a, this.b, this.kind, this.region, this.geometry,
      this.confidence, this.sources);
  double get lengthM => polylineLength(geometry);
}

class Building {
  final Map<String, dynamic> raw;
  final regions = <Region>{};
  final accessNodes = <Node>{};
  Node? street;
  final streets = <Node>[];
  OsmOutline? outline; // largest OSM outline holding the building
  Building(this.raw);
  String get id => raw['id'] as String;
  String get name => raw['name'] as String;
  List<String> get cityNames => (raw['cityNames'] as List? ?? []).cast<String>();
}

P _pt(List p) => project((p[0] as num).toDouble(), (p[1] as num).toDouble());

Region? _regionAt(List<Region> regions, List point, {bool includeExcluded = false}) {
  final p = _pt(point);
  Region? best;
  var bestD = 3.0; // metres of tolerance
  for (final r in regions) {
    if (r.excluded && !includeExcluded) continue;
    // Curation points are either inside the polygon or its centroid (which
    // lies outside some non-convex footprints).
    if (r.poly.contains(p) || r.poly.centroid.dist(p) < 2) return r;
    final d = r.poly.boundaryDist(p);
    if (d < bestD) {
      bestD = d;
      best = r;
    }
  }
  return best;
}

/// City record 'location' → building names, e.g. "TD Square - Bankers Hall".
List<String> _recordNames(Map<String, dynamic> rec) {
  final loc = (rec['location'] as String? ?? '').trim();
  final parts = loc.contains(' - ')
      ? loc.split(' - ')
      : loc.contains(', ')
          ? loc.split(', ')
          : [loc];
  return parts
      .map((s) => s
          .replaceAll(RegExp(r':.*$'), '') // ": West bridge"
          .replaceAll(RegExp(r'\s*\(\d+ St SW\)$'), '') // "The Core (4 St SW)"
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim())
      .where((s) => s.isNotEmpty)
      .toList();
}

/// "8 Avenue/2-3 Streets SW" → "8 Ave SW"; lanes → "the lane".
String? _crossing(Map<String, dynamic> rec) {
  final c = rec['cross_loc'] as String?;
  if (c == null) return null;
  if (c.startsWith('Lane')) return 'the lane';
  final m = RegExp(r'^(\w+) (Avenue|Street)/[^ ]+ \w+ ?(SW|SE|S|NE)?').firstMatch(c);
  if (m == null) return null;
  final quad = m[3] == null || m[3] == 'S' ? '' : ' ${m[3]}';
  final name = '${m[1]} ${m[2] == 'Avenue' ? 'Ave' : 'St'}$quad';
  // 2 St SE is signed Macleod Trail SE (official map v30).
  return name == '2 St SE' ? 'Macleod Trail SE' : name;
}

Future<void> main(List<String> args) async {
  final root = Directory.current.path;
  final src = '$root/tool/sources';
  if (args.contains('--refresh')) {
    await _download(walkwaysUrl, '$src/plus15_walkways.geojson');
    await _download(bridgesUrl, '$src/plus15_bridges.json');
  }
  if (args.contains('--refresh') || args.contains('--refresh-osm')) {
    await _downloadOsm('$src/osm_entrances.json');
  }
  final (osmOutlines, osmEntrances) = _loadOsm('$src/osm_entrances.json');
  final cur =
      jsonDecode(File('$root/tool/curation.json').readAsStringSync()) as Map<String, dynamic>;
  final regions = _loadRegions('$src/plus15_walkways.geojson');
  final records = (jsonDecode(File('$src/plus15_bridges.json').readAsStringSync()) as List)
      .cast<Map<String, dynamic>>();

  // Degenerate and duplicate polygons.
  for (var i = 0; i < regions.length; i++) {
    final r = regions[i];
    if (r.poly.area < 1) {
      r.excluded = true;
      r.excludedReason = 'Degenerate City polygon (area < 1 m²).';
      continue;
    }
    for (var j = 0; j < i; j++) {
      final o = regions[j];
      if (!o.excluded &&
          (o.poly.area - r.poly.area).abs() < 0.5 &&
          o.poly.centroid.dist(r.poly.centroid) < 0.5) {
        r.excluded = true;
        r.excludedReason = 'Duplicate City polygon of ${o.id}.';
        warn('${r.id} is a duplicate of ${o.id} in the City dataset; ignored.');
      }
    }
  }
  for (final o in (cur['regionOverrides'] as List).cast<Map<String, dynamic>>()) {
    final r = _regionAt(regions, o['at'] as List);
    if (r == null) {
      err('regionOverride at ${o['at']} hits no polygon');
      continue;
    }
    r.type = o['type'] as String;
    r.typeNote = o['note'] as String;
  }
  for (final x in (cur['excluded'] as List).cast<Map<String, dynamic>>()) {
    final r = _regionAt(regions, x['at'] as List);
    if (r == null) {
      err('excluded point ${x['at']} hits no polygon');
      continue;
    }
    r.excluded = true;
    r.excludedReason = x['reason'] as String;
  }

  _findPortals(regions);
  _matchBridgeRecords(regions, records);
  final zones = _zones(regions);
  if (args.contains('--dump')) {
    _dump(regions, zones);
    return;
  }

  // Buildings and their region claims.
  final buildings = (cur['buildings'] as List)
      .cast<Map<String, dynamic>>()
      .map(Building.new)
      .toList();
  final byId = {for (final b in buildings) b.id: b};
  if (byId.length != buildings.length) err('Duplicate building ids in curation');
  final claims = <Region, List<Building>>{};
  for (final b in buildings) {
    for (final pt in (b.raw['regions'] as List? ?? const [])) {
      final r = _regionAt(regions, pt as List);
      if (r == null) {
        err('Building ${b.id}: region point $pt hits no active City polygon');
        continue;
      }
      b.regions.add(r);
      (claims[r] ??= []).add(b);
    }
  }

  // Nodes: one per portal between active regions, plus dead-end terminals.
  final nodes = <Node>[];
  Node newNode(P at, String type, String source, String confidence) {
    final n = Node('N${(nodes.length + 1).toString().padLeft(3, '0')}', at, type,
        source: source, confidence: confidence);
    nodes.add(n);
    return n;
  }

  final regionNodes = <Region, List<Node>>{};
  final seenPortals = <Portal>{};
  for (final r in regions) {
    for (final p in r.portals) {
      if (!seenPortals.add(p)) continue;
      final type = p.a.isBridge != p.b.isBridge ? 'bridge_end' : 'junction';
      final n = newNode(p.at, type, 'walkways', 'verified');
      n.regions.addAll([p.a, p.b]);
      p.nodeId = n.id;
      (regionNodes[p.a] ??= []).add(n);
      (regionNodes[p.b] ??= []).add(n);
    }
  }
  for (final r in regions) {
    if (r.excluded || !r.isBridge) continue;
    final ns = regionNodes[r] ?? [];
    if (ns.length != 1) continue;
    // Dead-end bridge: the far end lands somewhere with no City polygon.
    final from = ns.first.at;
    var far = r.poly.rings[0].first;
    for (final v in r.poly.rings[0]) {
      if (v.dist(from) > far.dist(from)) far = v;
    }
    final t = newNode(r.poly.nudgeInside(far), 'terminal', 'walkways', 'verified');
    t.regions.add(r);
    (regionNodes[r] ??= []).add(t);
  }

  // Building access points that are not whole regions.
  Node? nearestNode(List point, double maxM) {
    final p = _pt(point);
    Node? best;
    var bd = maxM;
    for (final n in nodes) {
      if (n.type == 'street') continue;
      final d = n.at.dist(p);
      if (d < bd) {
        bd = d;
        best = n;
      }
    }
    return best;
  }

  for (final b in buildings) {
    for (final a in (b.raw['access'] as List? ?? const []).cast<Map<String, dynamic>>()) {
      final n = nearestNode(a['near'] as List, (a['maxM'] as num? ?? 10).toDouble());
      if (n == null) {
        err('Building ${b.id}: no graph node within reach of access point ${a['near']}');
      } else {
        b.accessNodes.add(n);
      }
    }
  }

  // Manual links (official map shows a connection the City polygons lack).
  final edges = <Edge>[];
  Edge newEdge(Node a, Node b, String kind, Region? region, List<P> geom,
      String confidence, List<String> sources) {
    final e = Edge('E${(edges.length + 1).toString().padLeft(3, '0')}', a, b, kind,
        region, geom, confidence, sources);
    edges.add(e);
    return e;
  }

  final manualEdges = <Edge>[];
  for (final m in (cur['manualLinks'] as List).cast<Map<String, dynamic>>()) {
    final from = nearestNode((m['from'] as Map)['near'] as List, 10);
    final toRegion = _regionAt(regions, m['toRegion'] as List);
    if (from == null || toRegion == null) {
      err('Manual link ${m['id']} endpoints do not resolve');
      continue;
    }
    final onBoundary = toRegion.poly.closestBoundaryPoint(from.at);
    final to = newNode(toRegion.poly.nudgeInside(onBoundary), 'link', 'map', 'likely');
    to.regions.add(toRegion);
    (regionNodes[toRegion] ??= []).add(to);
    final e = newEdge(from, to, 'manual_link', null, [from.at, to.at], 'likely', ['map']);
    e.note = m['note'] as String;
    manualEdges.add(e);
  }

  // Interior and bridge edges: every node pair on a region, routed inside it.
  for (final r in regions) {
    if (r.excluded) continue;
    final ns = regionNodes[r] ?? const [];
    final rec = r.bridgeRecord;
    final kind = !r.isBridge
        ? 'interior'
        : (rec?['conn_type'] == 'Lane Link' ? 'lane_link' : 'bridge');
    for (var i = 0; i < ns.length; i++) {
      for (var j = i + 1; j < ns.length; j++) {
        final a = ns[i], b = ns[j];
        final ia = r.poly.nudgeInside(a.at), ib = r.poly.nudgeInside(b.at);
        final path = r.poly.geodesic(ia, ib);
        if (path == null) {
          err('No path inside ${r.id} between ${a.id} and ${b.id}');
          continue;
        }
        final geom = <P>[a.at, ...path, b.at];
        // Drop zero-length steps created by nudging.
        final clean = <P>[geom.first];
        for (final p in geom.skip(1)) {
          if (p.dist(clean.last) > 0.05) clean.add(p);
        }
        if (clean.length == 1) clean.add(b.at);
        newEdge(a, b, kind, r, clean, 'verified',
            [r.isBridge && rec != null ? 'bridges' : 'walkways', 'walkways']);
      }
    }
  }

  // Stairs-only links from the official map.
  final byNumber = {
    for (final r in regions)
      if (r.bridgeRecord != null) r.bridgeRecord!['bridge_name'] as String: r
  };
  for (final s in (cur['stairsOnlyBridges'] as List).cast<Map<String, dynamic>>()) {
    final r = byNumber[s['bridge']];
    if (r == null || r.excluded) {
      err('stairsOnly bridge ${s['bridge']} not in the active network');
      continue;
    }
    for (final e in edges.where((e) => e.region == r)) {
      e.stairsRequired = true;
      e.note = s['note'] as String;
      if (!e.sources.contains('map')) e.sources.add('map');
    }
  }

  // Which buildings can be reached at each node.
  final nodeBuildings = <Node, Set<Building>>{};
  for (final b in buildings) {
    for (final r in b.regions) {
      for (final n in regionNodes[r] ?? const <Node>[]) {
        (nodeBuildings[n] ??= {}).add(b);
      }
    }
    for (final n in b.accessNodes) {
      (nodeBuildings[n] ??= {}).add(b);
    }
  }

  // Bridge chains: connected bridge regions (e.g. 1561 – unnamed – 1560).
  final chainOf = <Region, int>{};
  final chains = <Set<Region>>[];
  for (final r in regions) {
    if (r.excluded || !r.isBridge || chainOf.containsKey(r)) continue;
    final c = <Region>{};
    final st = [r];
    chainOf[r] = chains.length;
    while (st.isNotEmpty) {
      final u = st.removeLast();
      c.add(u);
      for (final p in u.portals) {
        final v = p.other(u);
        if (v.isBridge && !v.excluded && !chainOf.containsKey(v)) {
          chainOf[v] = chains.length;
          st.add(v);
        }
      }
    }
    chains.add(c);
  }
  Set<Building> buildingsAtChain(Set<Region> chain) {
    final out = <Building>{};
    for (final r in chain) {
      for (final n in regionNodes[r] ?? const <Node>[]) {
        out.addAll(nodeBuildings[n] ?? const {});
      }
    }
    return out;
  }

  // Zone-aware: every building in a walkway zone the chain lands in (zones
  // are contiguous +15 space, so no further bridge is needed to reach them).
  Set<Building> zoneBuildingsAtChain(Set<Region> chain) {
    final out = buildingsAtChain(chain);
    for (final r in chain) {
      for (final n in regionNodes[r] ?? const <Node>[]) {
        for (final nr in n.regions) {
          if (nr.isBridge || nr.excluded || nr.zone < 0) continue;
          for (final zr in zones[nr.zone]) {
            out.addAll(claims[zr] ?? const []);
          }
        }
      }
    }
    return out;
  }

  // Validate City bridge names against the curated buildings.
  final nameIndex = <String, List<Building>>{};
  for (final b in buildings) {
    for (final n in b.cityNames) {
      (nameIndex[n.toLowerCase()] ??= []).add(b);
    }
  }
  final unmatchedNames = <String>[];
  for (final r in regions) {
    final rec = r.bridgeRecord;
    if (rec == null || r.excluded) continue;
    // Strict: a named building must be at an end of this bridge's own
    // polygon. A record on a region reclassified as interior (P1501) is
    // checked against that region plus the bridges touching it.
    // One hop through an adjacent *unnamed* City connector polygon is
    // allowed (e.g. Suncor's connector to bridge 1532).
    final near = r.isBridge
        ? buildingsAtChain({
            r,
            for (final p in r.portals)
              if (p.other(r).isBridge && !p.other(r).excluded && p.other(r).bridgeRecord == null)
                p.other(r)
          })
        : buildingsAtChain({
            r,
            for (final p in r.portals)
              if (p.other(r).isBridge && !p.other(r).excluded) p.other(r)
          });
    for (final name in _recordNames(rec)) {
      final bs = nameIndex[name.toLowerCase()];
      if (bs == null) {
        unmatchedNames.add('${rec['bridge_name']}: "$name"');
        continue;
      }
      if (!bs.any(near.contains)) {
        err('Bridge ${rec['bridge_name']} ("${rec['location']}") names "$name" '
            '(${bs.map((b) => b.id).join("/")}) but that building is not at either end '
            '(found: ${near.map((b) => b.id).join(", ")})');
      }
    }
  }

  // Official-map cross-check at building level.
  String pairKey(String a, String b) => a.compareTo(b) < 0 ? '$a|$b' : '$b|$a';
  final mapPairs = {
    for (final l in (cur['officialMapLinks'] as List))
      pairKey((l as List)[0] as String, l[1] as String)
  };
  for (final k in mapPairs) {
    for (final id in k.split('|')) {
      if (!byId.containsKey(id)) err('officialMapLinks references unknown building $id');
    }
  }
  final graphPairs = <String, Set<Region>>{}; // pair → bridge chain regions
  for (final c in chains) {
    final bs = zoneBuildingsAtChain(c).toList();
    for (var i = 0; i < bs.length; i++) {
      for (var j = i + 1; j < bs.length; j++) {
        (graphPairs[pairKey(bs[i].id, bs[j].id)] ??= {}).addAll(c);
      }
    }
  }
  for (final z in zones) {
    final bs = {for (final r in z) ...?claims[r]}.toList();
    for (var i = 0; i < bs.length; i++) {
      for (var j = i + 1; j < bs.length; j++) {
        graphPairs.putIfAbsent(pairKey(bs[i].id, bs[j].id), () => {});
      }
    }
  }
  for (final e in manualEdges) {
    for (final a in nodeBuildings[e.a] ?? const <Building>{}) {
      for (final b in nodeBuildings[e.b] ?? const <Building>{}) {
        graphPairs.putIfAbsent(pairKey(a.id, b.id), () => {});
      }
    }
  }
  // A City bridge record naming both buildings also verifies the pair (the
  // schematic map cannot draw every pairing at three-way lane links).
  final recordPairs = <String>{};
  for (final r in regions) {
    final rec = r.bridgeRecord;
    if (rec == null) continue;
    final bs = {
      for (final n in _recordNames(rec)) ...?nameIndex[n.toLowerCase()]
    }.toList();
    for (var i = 0; i < bs.length; i++) {
      for (var j = i + 1; j < bs.length; j++) {
        recordPairs.add(pairKey(bs[i].id, bs[j].id));
      }
    }
  }
  // Bridge chains whose building pairs are on the official map (or named
  // together by a City record) are verified; City-geometry-only is 'likely'.
  final chainVerified = <int>{};
  final notOnMap = <String>[];
  // A chain inside a single building (e.g. Lot 40's internal bridge 1564)
  // makes no cross-building claim to check.
  for (var i = 0; i < chains.length; i++) {
    if (zoneBuildingsAtChain(chains[i]).length < 2) chainVerified.add(i);
  }
  graphPairs.forEach((k, chainRegions) {
    if (mapPairs.contains(k) || recordPairs.contains(k)) {
      for (final r in chainRegions) {
        chainVerified.add(chainOf[r]!);
      }
    }
  });
  graphPairs.forEach((k, chainRegions) {
    if (!mapPairs.contains(k) && !recordPairs.contains(k)) {
      final verifiedElsewhere =
          chainRegions.isNotEmpty && chainRegions.every((r) => chainVerified.contains(chainOf[r]));
      if (!verifiedElsewhere) notOnMap.add(k);
    }
  });
  for (final e in edges) {
    final r = e.region;
    if (r != null && r.isBridge && !chainVerified.contains(chainOf[r])) {
      e.confidence = 'likely';
    }
  }
  final missingFromGraph = mapPairs.where((k) => !graphPairs.containsKey(k)).toList()..sort();

  // Building positions: area-weighted centroid of claimed regions, else access nodes.
  final location = <Building, P>{};
  for (final b in buildings) {
    if (b.regions.isNotEmpty) {
      var ax = 0.0, ay = 0.0, aw = 0.0;
      for (final r in b.regions) {
        final c = r.poly.centroid, w = r.poly.area;
        ax += c.x * w;
        ay += c.y * w;
        aw += w;
      }
      location[b] = P(ax / aw, ay / aw);
    } else if (b.accessNodes.isNotEmpty) {
      final ns = b.accessNodes.toList();
      location[b] = P(ns.map((n) => n.at.x).reduce((a, c) => a + c) / ns.length,
          ns.map((n) => n.at.y).reduce((a, c) => a + c) / ns.length);
    }
  }

  // Street exits: the building's public street doors from OpenStreetMap
  // (doors on the OSM outline that contains the building), each joined to
  // the nearest +15 node of the building. The stairs, escalator or elevator
  // between door and +15 level is not mapped. Buildings without a mapped
  // door get one estimated street point at their +15 location.
  final entrancesUsed = <OsmEntrance, Building>{};
  var osmBuildings = 0;
  for (final b in buildings) {
    final loc = location[b];
    if (loc == null || b.raw['type'] == 'transit') continue;
    final dest = {
      for (final r in b.regions) ...?regionNodes[r],
      ...b.accessNodes
    };
    if (dest.isEmpty) continue;
    Node nearestTo(P p) => dest.reduce((x, y) => x.at.dist(p) <= y.at.dist(p) ? x : y);
    final probes = [loc, for (final r in b.regions) r.poly.centroid];
    final mine = [
      for (final o in osmOutlines)
        if (probes.any(o.poly.contains)) o
    ];
    // A door is the building's when it is a vertex of its outline, or mapped
    // within 3 m of it and not on another building's outline.
    bool ours(OsmEntrance e) =>
        mine.any((o) => o.nodeIds.contains(e.id)) ||
        (mine.any((o) => o.poly.boundaryDist(e.at) <= 3) &&
            !osmOutlines.any((o) => !mine.contains(o) && o.nodeIds.contains(e.id)));
    final rank = {'main': 0, 'yes': 1, 'secondary': 2};
    final doors = osmEntrances
        .where((e) => !entrancesUsed.containsKey(e) && ours(e))
        .toList()
      ..sort((x, y) => rank[x.type]!.compareTo(rank[y.type]!));
    final kept = <OsmEntrance>[];
    for (final d in doors) {
      // Doors a few metres apart are one entrance for routing.
      if (kept.length < 4 && kept.every((k) => k.at.dist(d.at) > 15)) kept.add(d);
    }
    if (mine.isNotEmpty) {
      b.outline = mine.reduce((x, y) => x.poly.area >= y.poly.area ? x : y);
    }
    if (kept.isNotEmpty) osmBuildings++;
    for (final d in kept) {
      entrancesUsed[d] = b;
      final s = newNode(d.at, 'street', 'osm:node/${d.id}', 'likely')
        ..label = d.street == null ? '${b.name} entrance' : '${b.name} entrance on ${d.street}'
        ..wheelchair = d.wheelchair;
      b.streets.add(s);
      final n = nearestTo(d.at);
      newEdge(n, s, 'street_exit', null, [n.at, s.at], 'estimate', [osmSource])
          .note = 'Street door from OpenStreetMap; the stairs, escalator or elevator up to '
              'the +15 is not mapped. Length includes a nominal 10 m for the level change.';
    }
    if (kept.isEmpty) {
      // No mapped door: an estimated street point on the building's outline
      // (its side facing the nearest building on the other +15 network, so
      // outdoor transfers leave from the right side), else its +15 location.
      final other = buildings.where((o) =>
          o != b &&
          location[o] != null &&
          o.regions.isNotEmpty &&
          b.regions.isNotEmpty &&
          o.regions.first.zone != b.regions.first.zone);
      final toward = other.isEmpty
          ? loc
          : location[other.reduce(
              (x, y) => location[x]!.dist(loc) <= location[y]!.dist(loc) ? x : y)]!;
      final at = b.outline?.poly.closestBoundaryPoint(toward) ?? loc;
      final s = newNode(at, 'street', 'estimate', 'estimate')..label = b.name;
      b.streets.add(s);
      final n = nearestTo(loc);
      newEdge(n, s, 'street_exit', null, [n.at, s.at], 'estimate', ['estimate'])
          .note = 'Exit location and vertical access not mapped; length includes a nominal 10 m '
              'for the level change.';
    }
    b.street = b.streets.first;
  }
  final streetBuildings = buildings.where((b) => b.street != null).toList();
  final zoneOf = {
    for (final b in buildings)
      b: b.regions.isEmpty ? null : b.regions.first.zone
  };
  // Outdoor transfers between the two +15 networks, door to door: the
  // closest pair of street doors of buildings within about one long block.
  for (var i = 0; i < streetBuildings.length; i++) {
    for (var j = i + 1; j < streetBuildings.length; j++) {
      final a = streetBuildings[i], c = streetBuildings[j];
      if (zoneOf[a] != null && zoneOf[a] == zoneOf[c]) continue;
      Node? x, y;
      var d = double.infinity;
      for (final sa in a.streets) {
        for (final sc in c.streets) {
          final dd = sa.at.dist(sc.at);
          if (dd < d) (x, y, d) = (sa, sc, dd);
        }
      }
      if (d > 250) continue;
      newEdge(x!, y!, 'street_transfer', null, [x.at, y.at], 'estimate', ['estimate']);
    }
  }
  stdout.writeln('Street doors: ${entrancesUsed.length} OpenStreetMap entrances for '
      '$osmBuildings buildings; ${streetBuildings.length - osmBuildings} estimated.');

  // Isolation: active regions not reachable from any building.
  final adj = <Node, List<Node>>{};
  for (final e in edges) {
    (adj[e.a] ??= []).add(e.b);
    (adj[e.b] ??= []).add(e.a);
  }
  final reached = <Node>{};
  final st = <Node>[for (final s in nodeBuildings.keys) s];
  reached.addAll(st);
  while (st.isNotEmpty) {
    final u = st.removeLast();
    for (final v in adj[u] ?? const <Node>[]) {
      if (reached.add(v)) st.add(v);
    }
  }
  final isolatedRegions = <Region>{};
  for (final r in regions) {
    if (r.excluded) continue;
    final ns = regionNodes[r] ?? const [];
    if (!ns.any(reached.contains) && !claims.containsKey(r)) {
      r.excluded = true;
      r.excludedReason = 'Isolated: not connected to any building on the official map.';
      isolatedRegions.add(r);
    }
  }
  final dropNodes = {
    for (final n in nodes)
      if (n.type != 'street' && n.regions.every((r) => r.excluded)) n
  };
  nodes.removeWhere(dropNodes.contains);
  edges.removeWhere((e) => dropNodes.contains(e.a) || dropNodes.contains(e.b));

  // Unclaimed but connected regions (walkable, building unknown).
  final unclaimed = [
    for (final r in regions)
      if (!r.excluded && !r.isBridge && !claims.containsKey(r)) r
  ];
  for (final r in unclaimed) {
    warn('${r.id} (${r.type}) is connected but no building claims it');
  }
  for (final n in nodes) {
    final bs = nodeBuildings[n];
    if (n.type != 'street' && bs != null && bs.isNotEmpty) {
      n.label ??= bs.map((b) => b.name).join(' / ');
    }
  }

  _write(
    root: root,
    cur: cur,
    regions: regions,
    nodes: nodes,
    edges: edges,
    buildings: buildings,
    location: location,
    regionNodes: regionNodes,
    claims: claims,
    unmatchedNames: unmatchedNames,
    missingFromGraph: missingFromGraph,
    notOnMap: notOnMap..sort(),
    isolated: isolatedRegions,
  );
  stdout.writeln('nodes ${nodes.length}, edges ${edges.length}, '
      'buildings ${buildings.length}, errors ${_errors.length}, warnings ${_warnings.length}');
  for (final e in _errors) {
    stderr.writeln('ERROR: $e');
  }
  if (_errors.isNotEmpty) exit(1);
}

String? _crossingOverride(Map<String, dynamic> cur, String? number) {
  for (final o in (cur['crossingOverrides'] as List? ?? const []).cast<Map<String, dynamic>>()) {
    if (o['bridge'] == number) return o['crossing'] as String;
  }
  return null;
}

List<double> _ll6(P p) {
  final ll = unproject(p);
  return [double.parse(ll[0].toStringAsFixed(6)), double.parse(ll[1].toStringAsFixed(6))];
}

void _write({
  required String root,
  required Map<String, dynamic> cur,
  required List<Region> regions,
  required List<Node> nodes,
  required List<Edge> edges,
  required List<Building> buildings,
  required Map<Building, P> location,
  required Map<Region, List<Node>> regionNodes,
  required Map<Region, List<Building>> claims,
  required List<String> unmatchedNames,
  required List<String> missingFromGraph,
  required List<String> notOnMap,
  required Set<Region> isolated,
}) {
  String? zoneLabel(Region r) => claims[r]?.map((b) => b.id).join(',');
  final destNodes = <Building, Set<Node>>{};
  for (final b in buildings) {
    destNodes[b] = {
      for (final r in b.regions) ...?regionNodes[r],
      ...b.accessNodes
    }..removeWhere((n) => !nodes.contains(n));
  }
  final out = {
    'version': 1,
    'generatedBy': 'tool/build_network.dart',
    'sources': cur['sources'],
    'hours': cur['hours'],
    'buildings': [
      for (final b in buildings)
        if (location[b] != null)
        {
          'id': b.id,
          'name': b.name,
          'aliases': b.raw['aliases'] ?? const [],
          'address': b.raw['address'] ?? '',
          'type': b.raw['type'] ?? 'office',
          'lat': _ll6(location[b]!)[0],
          'lng': _ll6(location[b]!)[1],
          'regionIds': [for (final r in b.regions) r.id],
          'nodeIds': [for (final n in destNodes[b]!) n.id]..sort(),
          if (b.street != null) 'streetNodeId': b.street!.id,
          if (b.streets.isNotEmpty) 'entranceNodeIds': [for (final n in b.streets) n.id],
          if (b.outline != null)
            'outline': [for (final p in b.outline!.poly.rings.first) _ll6(p)],
          'landmarks': b.raw['map'] ?? const [],
          if (b.raw['noElevatorToStreet'] == true) 'noElevatorToStreet': true,
          if (b.raw['secondary'] == true) 'secondary': true,
          if (b.raw['note'] != null) 'note': b.raw['note'],
          'source': b.cityNames.isNotEmpty ? 'bridges' : 'map',
        }
    ],
    'bridges': [
      for (final r in regions)
        if (r.bridgeRecord != null)
          {
            'number': r.bridgeRecord!['bridge_name'],
            'name': r.bridgeRecord!['location'],
            'crossing': _crossingOverride(cur, r.bridgeRecord!['bridge_name'] as String?) ??
                _crossing(r.bridgeRecord!),
            'crossingRaw': r.bridgeRecord!['cross_loc'],
            'connType': r.bridgeRecord!['conn_type'],
            'structure': r.bridgeRecord!['structure_type'],
            'constructed': (r.bridgeRecord!['const_dec'] as String?)?.substring(0, 4),
            'regionId': r.id,
            if (r.excluded) 'excluded': r.excludedReason,
          }
    ],
    'regions': [
      for (final r in regions)
        {
          'id': r.id,
          'type': r.type,
          if (r.typeNote != null) 'typeNote': r.typeNote,
          if (r.bridgeRecord != null) 'bridgeNumber': r.bridgeRecord!['bridge_name'],
          'buildingIds': [for (final b in claims[r] ?? const <Building>[]) b.id],
          'label': [
            for (final b in claims[r] ?? const <Building>[])
              if (b.raw['secondary'] != true) b.name
          ].join(' / '),
          'areaM2': r.poly.area.round(),
          // Mean corridor width (2·area/perimeter), used to decide whether a
          // turn instruction is meaningful.
          'widthM': double.parse((2 * r.poly.area / r.poly.perimeter).toStringAsFixed(1)),
          if (r.excluded) 'excluded': r.excludedReason,
          'rings': [
            for (final ring in r.poly.rings) [for (final p in ring) _ll6(p)]
          ],
        }
    ],
    'nodes': [
      for (final n in nodes)
        {
          'id': n.id,
          'lat': _ll6(n.at)[0],
          'lng': _ll6(n.at)[1],
          'type': n.type,
          'level': n.type == 'street' ? 'street' : '+15',
          'regionIds': [for (final r in n.regions) r.id],
          if (n.label != null) 'label': n.label,
          'source': n.source,
          'confidence': n.confidence,
          if (n.wheelchair != null) 'wheelchair': n.wheelchair,
        }
    ],
    'edges': [
      for (final e in edges)
        {
          'id': e.id,
          'from': e.a.id,
          'to': e.b.id,
          'kind': e.kind,
          if (e.region != null) 'regionId': e.region!.id,
          if (e.region?.bridgeRecord != null)
            'bridgeNumber': e.region!.bridgeRecord!['bridge_name'],
          if (e.region != null) 'buildingIds': [for (final b in claims[e.region] ?? const <Building>[]) b.id],
          // Street exits add a nominal 10 m for the level change, which the
          // City data does not describe.
          'lengthM': double.parse(
              (e.lengthM + (e.kind == 'street_exit' ? 10 : 0)).toStringAsFixed(1)),
          'indoor': e.region != null
              ? !e.region!.openToSky
              : e.kind == 'manual_link',
          if (e.stairsRequired) 'stairsRequired': true,
          'oneWay': false,
          'confidence': e.confidence,
          'sources': e.sources.toSet().toList(),
          if (e.note != null) 'note': e.note,
          'geometry': [for (final p in e.geometry) _ll6(p)],
        }
    ],
    'issues': {
      'errors': _errors,
      'warnings': _warnings,
      'cityNamesWithoutBuilding': unmatchedNames,
      'officialMapLinksMissingFromCityData': missingFromGraph,
      'cityLinksNotOnOfficialMap': notOnMap,
      'unresolvedBuildings': [
        for (final b in buildings)
          if (location[b] == null)
            {'id': b.id, 'name': b.name, 'reason': b.raw['unresolved'] ?? 'no mapped +15 entry'}
      ],
    },
  };
  File('$root/assets/data/network.json')
      .writeAsStringSync(const JsonEncoder().convert(out));

  // Human-readable report.
  final b = StringBuffer()
    ..writeln('# +15 network build report')
    ..writeln()
    ..writeln('Generated by `dart run tool/build_network.dart` from the City snapshots in '
        '`tool/sources/` and `tool/curation.json`. Do not edit by hand.')
    ..writeln()
    ..writeln('## Counts')
    ..writeln()
    ..writeln('| | |')
    ..writeln('|---|---|')
    ..writeln('| City walkway polygons | ${regions.length} |')
    ..writeln('| Active regions | ${regions.where((r) => !r.excluded).length} |')
    ..writeln('| City bridge records joined | ${regions.where((r) => r.bridgeRecord != null).length} |')
    ..writeln('| Buildings | ${buildings.length} (${buildings.where((x) => destNodes[x]!.isEmpty).length} without a mapped +15 entry) |')
    ..writeln('| Nodes | ${nodes.length} |')
    ..writeln('| Edges | ${edges.length} (${edges.where((e) => e.confidence == 'verified').length} verified, '
        '${edges.where((e) => e.confidence == 'likely').length} likely, '
        '${edges.where((e) => e.confidence == 'estimate').length} street estimates) |')
    ..writeln()
    ..writeln('## Errors')
    ..writeln()
    ..writeln(_errors.isEmpty ? 'None.' : _errors.map((e) => '- $e').join('\n'))
    ..writeln()
    ..writeln('## Unresolved')
    ..writeln()
    ..writeln('### Buildings on the official map with no mapped +15 entry')
    ..writeln();
  for (final x in buildings.where((x) => destNodes[x]!.isEmpty)) {
    b.writeln('- **${x.name}** (`${x.id}`): ${x.raw['unresolved'] ?? 'no region or access node'}');
  }
  b
    ..writeln()
    ..writeln('### Official-map links with no City walkway connection')
    ..writeln()
    ..writeln(missingFromGraph.isEmpty ? 'None.' : missingFromGraph.map((k) => '- `$k`').join('\n'))
    ..writeln()
    ..writeln('### City connections not shown on the official map (routed as *likely*)')
    ..writeln()
    ..writeln(notOnMap.isEmpty ? 'None.' : notOnMap.map((k) => '- `$k`').join('\n'))
    ..writeln()
    ..writeln('### Manual links (official map only, routed as *likely*)')
    ..writeln();
  for (final m in (cur['manualLinks'] as List).cast<Map<String, dynamic>>()) {
    b.writeln('- `${m['id']}`: ${m['note']}');
  }
  b
    ..writeln()
    ..writeln('### City bridge names with no curated building')
    ..writeln()
    ..writeln(unmatchedNames.isEmpty ? 'None.' : unmatchedNames.map((k) => '- $k').join('\n'))
    ..writeln()
    ..writeln('## Excluded City polygons')
    ..writeln()
    ..writeln('| Region | Type | Bridge | Reason |')
    ..writeln('|---|---|---|---|');
  for (final r in regions.where((r) => r.excluded)) {
    b.writeln('| ${r.id} | ${r.type} | ${r.bridgeRecord?['bridge_name'] ?? ''} | ${r.excludedReason} |');
  }
  b
    ..writeln()
    ..writeln('## Warnings')
    ..writeln()
    ..writeln(_warnings.isEmpty ? 'None.' : _warnings.map((w) => '- $w').join('\n'));
  for (final r in regions) {
    if (!r.excluded && zoneLabel(r) == null && !r.isBridge) {
      // Already listed as a warning.
    }
  }
  File('$root/docs/network-report.md').writeAsStringSync(b.toString());
}
