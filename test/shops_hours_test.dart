import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:plus15_navigator/data/models/opening_hours.dart';

void main() {
  final shops = (jsonDecode(File('assets/data/shops.json').readAsStringSync()) as List)
      .cast<Map<String, dynamic>>();

  test('every listed hours string parses', () {
    for (final s in shops) {
      final h = (s['hours'] as String? ?? '').trim();
      if (h.isEmpty) continue;
      expect(OpeningHours.parse(h).parsed, isTrue, reason: '${s['id']}: "$h"');
    }
  });

  test('hours cover most places', () {
    final with_ = shops.where((s) => ((s['hours'] as String?) ?? '').trim().isNotEmpty).length;
    // Was 25 of 144 before the Google Maps pass; the rest have no confirmed listing.
    expect(with_ / shops.length, greaterThan(0.9));
  });
}
