import 'package:flutter_test/flutter_test.dart';
import 'package:plus15_navigator/data/models/opening_hours.dart';

void main() {
  // 2024-01-01 is a Monday; 01-06 Saturday; 01-07 Sunday.
  DateTime mon(int h, int m) => DateTime(2024, 1, 1, h, m);
  DateTime sat(int h, int m) => DateTime(2024, 1, 6, h, m);
  DateTime sun(int h, int m) => DateTime(2024, 1, 7, h, m);

  group('OpeningHours', () {
    test('empty string is unknown', () {
      final s = OpeningHours.parse('').statusAt(mon(10, 0));
      expect(s.known, isFalse);
      expect(s.label, 'Hours not listed');
    });

    test('weekday range open and closed', () {
      final h = OpeningHours.parse('Mon-Fri 6:00-20:00, Sat-Sun 8:00-18:00');
      expect(h.statusAt(mon(10, 0)).open, isTrue);
      expect(h.statusAt(mon(21, 0)).open, isFalse);
      expect(h.statusAt(sat(9, 0)).open, isTrue);
      expect(h.statusAt(sat(7, 0)).open, isFalse);
    });

    test('Mon-Sat plus separate Sun segment', () {
      final h = OpeningHours.parse('Mon-Sat 11:00-23:00, Sun 11:00-22:00');
      expect(h.statusAt(sun(21, 0)).open, isTrue);
      expect(h.statusAt(sun(22, 30)).open, isFalse);
      expect(h.statusAt(sat(22, 30)).open, isTrue);
    });

    test('closing-soon label', () {
      final s = OpeningHours.parse('Mon-Fri 6:00-20:00').statusAt(mon(19, 40));
      expect(s.open, isTrue);
      expect(s.label, 'Open · closes in 20 min');
    });

    test('closed shows next opening', () {
      final s = OpeningHours.parse('Mon-Fri 6:00-20:00').statusAt(mon(5, 0));
      expect(s.open, isFalse);
      expect(s.label, 'Closed · opens 6:00 AM');
    });

    test('overnight close past midnight', () {
      final h = OpeningHours.parse('Mon-Sun 20:00-2:00');
      expect(h.statusAt(mon(23, 0)).open, isTrue);
      // Tuesday 1:00 AM is covered by Monday's overnight interval.
      expect(h.statusAt(DateTime(2024, 1, 2, 1, 0)).open, isTrue);
      expect(h.statusAt(DateTime(2024, 1, 2, 3, 0)).open, isFalse);
    });

    test('24/7 always open', () {
      final h = OpeningHours.parse('Open 24 hours');
      expect(h.statusAt(sun(3, 0)).open, isTrue);
    });
  });
}
