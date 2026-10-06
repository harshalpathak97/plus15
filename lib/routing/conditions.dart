import 'network.dart';

/// A closure from assets/data/closures.json (transcribed from calgary.ca/plus15).
class Closure {
  final String id;
  /// bridge_closed | building_closed | section_closed | detour |
  /// elevator_unavailable | time_restricted
  final String kind;
  final List<String> bridges;
  final List<String> buildings; // every bridge connected to the building
  final List<String> edges;
  final List<String> nodes;
  final DateTime? start; // local date; null = already in effect
  final DateTime? end; // exclusive; null = until further notice
  final bool endIsEstimate;
  /// time_restricted only: the target is open daily within this window.
  final List<int>? openDaily; // [openMinute, closeMinute]
  final String title;
  final String reason;
  final String cityText;
  final String sourceUrl;
  final String retrieved;

  const Closure({
    required this.id,
    required this.kind,
    this.bridges = const [],
    this.buildings = const [],
    this.edges = const [],
    this.nodes = const [],
    this.start,
    this.end,
    this.endIsEstimate = false,
    this.openDaily,
    required this.title,
    this.reason = '',
    this.cityText = '',
    this.sourceUrl = '',
    this.retrieved = '',
  });

  bool activeOn(DateTime t) =>
      (start == null || !t.isBefore(start!)) && (end == null || t.isBefore(end!));

  /// Within [days] after an estimated end: the City may not have reopened yet.
  bool recentlyEnded(DateTime t, {int days = 60}) =>
      end != null &&
      endIsEstimate &&
      !t.isBefore(end!) &&
      t.isBefore(end!.add(Duration(days: days)));

  static DateTime? _date(String? s) => s == null ? null : DateTime.parse(s);

  factory Closure.fromJson(Map<String, dynamic> j) {
    final t = j['targets'] as Map<String, dynamic>? ?? const {};
    List<String> l(String k) => (t[k] as List? ?? const []).cast<String>();
    final daily = (j['openDaily'] as List?)?.cast<String>();
    return Closure(
      id: j['id'] as String,
      kind: j['kind'] as String,
      bridges: l('bridges'),
      buildings: l('buildings'),
      edges: l('edges'),
      nodes: l('nodes'),
      start: _date(j['start'] as String?),
      end: _date(j['end'] as String?),
      endIsEstimate: j['endIsEstimate'] as bool? ?? false,
      openDaily: daily?.map(NetworkHours.minuteOf).toList(),
      title: j['title'] as String,
      reason: j['reason'] as String? ?? '',
      cityText: j['cityText'] as String? ?? '',
      sourceUrl: j['sourceUrl'] as String? ?? '',
      retrieved: j['retrieved'] as String? ?? '',
    );
  }
}

/// Alberta general holidays (Employment Standards Code), used for the City's
/// "weekends & statutory holidays" hours. Heritage Day and Boxing Day are
/// optional in Alberta and not included.
bool isAlbertaHoliday(DateTime d) {
  final y = d.year, m = d.month, day = d.day;
  DateTime nthMonday(int month, int n) {
    var x = DateTime(y, month, 1);
    while (x.weekday != DateTime.monday) {
      x = x.add(const Duration(days: 1));
    }
    return x.add(Duration(days: 7 * (n - 1)));
  }

  bool same(DateTime a) => a.month == m && a.day == day;
  if ((m == 1 && day == 1) ||
      (m == 7 && day == 1) ||
      (m == 11 && day == 11) ||
      (m == 12 && day == 25)) {
    return true;
  }
  if (same(nthMonday(2, 3))) return true; // Family Day
  if (same(nthMonday(9, 1))) return true; // Labour Day
  if (same(nthMonday(10, 2))) return true; // Thanksgiving
  // Victoria Day: the Monday before May 25.
  var v = DateTime(y, 5, 24);
  while (v.weekday != DateTime.monday) {
    v = v.subtract(const Duration(days: 1));
  }
  if (same(v)) return true;
  return same(goodFriday(y));
}

/// Good Friday via the anonymous Gregorian Easter algorithm.
DateTime goodFriday(int y) {
  final a = y % 19, b = y ~/ 100, c = y % 100;
  final d = b ~/ 4, e = b % 4, f = (b + 8) ~/ 25, g = (b - f + 1) ~/ 3;
  final h = (19 * a + b - d - g + 15) % 30;
  final i = c ~/ 4, k = c % 4;
  final l = (32 + 2 * e + 2 * i - h - k) % 7;
  final m = (a + 11 * h + 22 * l) ~/ 451;
  final month = (h + l - 7 * m + 114) ~/ 31;
  final day = ((h + l - 7 * m + 114) % 31) + 1;
  return DateTime(y, month, day).subtract(const Duration(days: 2));
}

class NetworkStatus {
  final bool open;
  final String label; // e.g. "Open until 9 p.m."
  final DateTime? nextOpen;
  final bool reducedHoursDay; // weekend or holiday: some bridges may close
  const NetworkStatus(this.open, this.label, this.nextOpen, this.reducedHoursDay);
}

/// What is unavailable at a given time. All times are Calgary local time.
class Conditions {
  final Plus15Network network;
  final List<Closure> closures;

  Conditions(this.network, this.closures);

  List<int> _window(DateTime d) {
    final h = network.hours;
    final weekend = d.weekday == DateTime.saturday || d.weekday == DateTime.sunday;
    return weekend || isAlbertaHoliday(d) ? h.weekendHoliday : h.weekday;
  }

  bool _closedDate(DateTime d) {
    final key = '${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    return network.hours.closedDates.contains(key);
  }

  NetworkStatus networkStatusAt(DateTime t) {
    final day = DateTime(t.year, t.month, t.day);
    final reduced = t.weekday >= DateTime.saturday || isAlbertaHoliday(day);
    final minute = t.hour * 60 + t.minute;
    if (!_closedDate(day)) {
      final w = _window(day);
      if (minute >= w[0] && minute < w[1]) {
        return NetworkStatus(true, 'Open until ${_fmt(w[1])}', null, reduced);
      }
    }
    // Find the next opening (search up to a week ahead).
    for (var i = 0; i < 8; i++) {
      final d = day.add(Duration(days: i));
      if (_closedDate(d)) continue;
      final w = _window(d);
      final open = d.add(Duration(minutes: w[0]));
      if (open.isAfter(t)) {
        final when = i == 0
            ? 'today'
            : i == 1
                ? 'tomorrow'
                : _weekday(open.weekday);
        return NetworkStatus(false, 'Closed · opens ${_fmt(w[0])} $when', open, reduced);
      }
    }
    return NetworkStatus(false, 'Closed', null, reduced);
  }

  List<Closure> activeAt(DateTime t) => [
        for (final c in closures)
          if (c.activeOn(t) && (c.openDaily == null || !_inDaily(c.openDaily!, t))) c
      ];

  bool _inDaily(List<int> w, DateTime t) {
    final m = t.hour * 60 + t.minute;
    return m >= w[0] && m < w[1];
  }

  /// Edge id → the closure that removes it from routing at [t].
  Map<String, Closure> closedEdgesAt(DateTime t) {
    final out = <String, Closure>{};
    for (final c in activeAt(t)) {
      if (c.kind == 'elevator_unavailable') continue; // handled per profile
      for (final id in edgesClosedBy(c)) {
        out.putIfAbsent(id, () => c);
      }
    }
    return out;
  }

  /// The edges [c] removes while it is in effect.
  Set<String> edgesClosedBy(Closure c) {
    final bridges = {
      ...c.bridges,
      for (final b in c.buildings) ...network.bridgesOfBuilding(b)
    };
    final nodes = c.nodes.toSet();
    if (c.kind == 'building_closed') {
      for (final b in c.buildings) {
        nodes.addAll(network.buildingById[b]?.nodeIds ?? const []);
      }
    }
    return {
      for (final e in network.edges)
        if ((e.bridgeNumber != null && bridges.contains(e.bridgeNumber)) ||
            c.edges.contains(e.id) ||
            nodes.contains(e.from) ||
            nodes.contains(e.to))
          e.id
    };
  }

  /// Buildings whose elevator to the street is reported out of service.
  Set<String> elevatorOutagesAt(DateTime t) => {
        for (final c in activeAt(t))
          if (c.kind == 'elevator_unavailable') ...c.buildings
      };

  List<Closure> recentlyEndedAt(DateTime t) =>
      [for (final c in closures) if (c.recentlyEnded(t)) c];

  static String _fmt(int minute) {
    final h = minute ~/ 60, m = minute % 60;
    final h12 = h % 12 == 0 ? 12 : h % 12;
    final ap = h < 12 ? 'a.m.' : 'p.m.';
    return m == 0 ? '$h12 $ap' : '$h12:${m.toString().padLeft(2, '0')} $ap';
  }

  static String _weekday(int w) =>
      const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][w - 1];
}

/// Calgary wall-clock time (America/Edmonton: MST, MDT from 2 a.m. on the
/// second Sunday of March to 2 a.m. on the first Sunday of November), so +15
/// hours and shop hours are right whatever time zone the phone is set to.
DateTime calgaryNow([DateTime? instant]) {
  final u = (instant ?? DateTime.now()).toUtc();
  DateTime nthSunday(int month, int n) {
    var d = DateTime.utc(u.year, month, 1);
    while (d.weekday != DateTime.sunday) {
      d = d.add(const Duration(days: 1));
    }
    return d.add(Duration(days: 7 * (n - 1)));
  }

  final dstStart = nthSunday(3, 2).add(const Duration(hours: 9)); // 2:00 MST
  final dstEnd = nthSunday(11, 1).add(const Duration(hours: 8)); // 2:00 MDT
  final dst = !u.isBefore(dstStart) && u.isBefore(dstEnd);
  final l = u.add(Duration(hours: dst ? -6 : -7));
  return DateTime(l.year, l.month, l.day, l.hour, l.minute, l.second);
}
