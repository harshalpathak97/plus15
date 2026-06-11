/// Parses the free-text `hours` strings carried by shops (e.g.
/// "Mon-Fri 6:00-20:00, Sat-Sun 8:00-18:00") into structured weekly intervals
/// and answers "is it open now?" with a human label.
///
/// This is pure Dart with no Flutter dependency so it stays unit-testable and
/// shared between Search and the business detail sheet. It is deliberately
/// forgiving: anything it can't parse degrades to [OpenStatus.unknown] rather
/// than guessing.
library;

class OpenStatus {
  /// Whether the hours string was understood at all.
  final bool known;
  final bool open;

  /// e.g. "Open · closes 8:00 PM", "Closed · opens 6:00 AM",
  /// "Open · closes in 25 min", or "Hours not listed".
  final String label;

  const OpenStatus(this.known, this.open, this.label);

  static const unknown = OpenStatus(false, false, 'Hours not listed');
}

class _Interval {
  /// Weekday this interval starts on (Mon=1 … Sun=7, matching [DateTime]).
  final int day;

  /// Minutes from midnight. [end] may exceed 1440 to express closing after
  /// midnight (e.g. open until 2 AM).
  final int start;
  final int end;

  const _Interval(this.day, this.start, this.end);
}

class OpeningHours {
  final List<_Interval> _intervals;
  final bool parsed;

  const OpeningHours._(this._intervals, this.parsed);

  static const _dayIndex = {
    'mon': 1,
    'tue': 2,
    'wed': 3,
    'thu': 4,
    'fri': 5,
    'sat': 6,
    'sun': 7,
  };
  static const _dayLabel = {
    1: 'Mon',
    2: 'Tue',
    3: 'Wed',
    4: 'Thu',
    5: 'Fri',
    6: 'Sat',
    7: 'Sun',
  };

  factory OpeningHours.parse(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return const OpeningHours._([], false);

    final lower = s.toLowerCase();
    if (lower.contains('24/7') ||
        (lower.contains('24') && lower.contains('hour'))) {
      return OpeningHours._(
        [for (var d = 1; d <= 7; d++) _Interval(d, 0, 1440)],
        true,
      );
    }

    final intervals = <_Interval>[];
    for (final segRaw in s.split(',')) {
      final seg = segRaw.trim();
      final sp = seg.indexOf(' ');
      if (sp < 0) continue;
      final days = _parseDays(seg.substring(0, sp));
      final range = _parseTimeRange(seg.substring(sp + 1));
      if (days.isEmpty || range == null) continue;
      for (final d in days) {
        intervals.add(_Interval(d, range.$1, range.$2));
      }
    }
    return OpeningHours._(intervals, intervals.isNotEmpty);
  }

  static List<int> _parseDays(String part) {
    final p = part.trim().toLowerCase();
    if (p == 'daily' || p == 'everyday' || p == 'every day') {
      return [1, 2, 3, 4, 5, 6, 7];
    }
    if (p.contains('-')) {
      final ends = p.split('-');
      if (ends.length != 2) return const [];
      final a = _dayIndex[_key(ends[0])];
      final b = _dayIndex[_key(ends[1])];
      if (a == null || b == null) return const [];
      final out = <int>[];
      var d = a;
      // Walk forward inclusively, wrapping through the week if needed.
      while (true) {
        out.add(d);
        if (d == b) break;
        d = d % 7 + 1;
        if (out.length > 7) break;
      }
      return out;
    }
    final single = _dayIndex[_key(p)];
    return single == null ? const [] : [single];
  }

  static String _key(String s) {
    final t = s.trim().toLowerCase();
    return t.length >= 3 ? t.substring(0, 3) : t;
  }

  /// Returns (startMinutes, endMinutes) with end pushed past midnight when the
  /// closing time is earlier than the opening time.
  static (int, int)? _parseTimeRange(String part) {
    final m = RegExp(r'(\d{1,2}):(\d{2})\s*-\s*(\d{1,2}):(\d{2})')
        .firstMatch(part.trim());
    if (m == null) return null;
    final start = int.parse(m.group(1)!) * 60 + int.parse(m.group(2)!);
    var end = int.parse(m.group(3)!) * 60 + int.parse(m.group(4)!);
    if (end <= start) end += 1440;
    return (start, end);
  }

  OpenStatus statusAt(DateTime now) {
    if (!parsed) return OpenStatus.unknown;
    final wd = now.weekday;
    final mins = now.hour * 60 + now.minute;

    for (final iv in _intervals) {
      // Open today within this interval.
      if (iv.day == wd && mins >= iv.start && mins < iv.end) {
        return OpenStatus(true, true, _closingLabel(iv.end, mins));
      }
      // Open via an interval that began yesterday and runs past midnight.
      if (iv.end > 1440) {
        final nextDay = iv.day % 7 + 1;
        if (nextDay == wd && mins < iv.end - 1440) {
          return OpenStatus(true, true, _closingLabel(iv.end - 1440, mins));
        }
      }
    }

    final next = _nextOpening(wd, mins);
    if (next == null) return OpenStatus.unknown;
    final (addDay, iv) = next;
    final when = addDay == 0
        ? _fmt(iv.start)
        : '${_dayLabel[iv.day]} ${_fmt(iv.start)}';
    return OpenStatus(true, false, 'Closed · opens $when');
  }

  String _closingLabel(int endMins, int nowMins) {
    final remaining = endMins - nowMins;
    if (remaining <= 60) return 'Open · closes in $remaining min';
    return 'Open · closes ${_fmt(endMins % 1440)}';
  }

  (int, _Interval)? _nextOpening(int wd, int mins) {
    for (var addDay = 0; addDay < 8; addDay++) {
      final day = (wd - 1 + addDay) % 7 + 1;
      final today = _intervals.where((i) => i.day == day).toList()
        ..sort((a, b) => a.start - b.start);
      for (final iv in today) {
        if (addDay == 0 && iv.start <= mins) continue;
        return (addDay, iv);
      }
    }
    return null;
  }

  static String _fmt(int minutes) {
    final h24 = (minutes ~/ 60) % 24;
    final m = minutes % 60;
    final period = h24 >= 12 ? 'PM' : 'AM';
    final h12 = h24 % 12 == 0 ? 12 : h24 % 12;
    return '$h12:${m.toString().padLeft(2, '0')} $period';
  }
}
