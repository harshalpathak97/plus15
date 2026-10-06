import 'package:flutter_test/flutter_test.dart';
import 'package:plus15_navigator/routing/router.dart';

import 'support.dart';

List<String> _texts(PlannedRoute r) => [for (final s in r.steps) s.text];

void main() {
  test('one bridge: start, cross with the City crossing street, arrive', () {
    expect(_texts(mustRoute('bankers_hall', 'gulf_canada_square')), [
      'Start in Bankers Hall at the +15 level and head for the bridge to Gulf Canada Square.',
      'Cross the +15 bridge over 9 Ave SW into Gulf Canada Square.',
      'Arrive at Gulf Canada Square (+15 level).',
    ]);
  });

  test('reverse direction is generated independently, not by reversing text', () {
    expect(_texts(mustRoute('gulf_canada_square', 'bankers_hall')), [
      'Start in Gulf Canada Square at the +15 level and head for the bridge to Bankers Hall.',
      'Cross the +15 bridge over 9 Ave SW into Bankers Hall.',
      'Arrive at Bankers Hall (+15 level).',
    ]);
  });

  test('through-building steps name the next bridge, not an angle', () {
    final steps = mustRoute('the_bow', 'bankers_hall').steps;
    final through = steps.where((s) => s.kind == 'through').map((s) => s.text).toList();
    expect(through.first, 'Walk through Suncor Energy Centre to the +15 bridge toward Bow Valley Square.');
    for (final s in steps) {
      expect(s.text, isNot(matches(RegExp(r'\d+ ?°'))));
      expect(s.text, isNot(contains('northeast')));
    }
  });

  test('building landmarks are attached as facts, never as "pass the food court"', () {
    final s = mustRoute('the_bow', 'bankers_hall').steps.last;
    expect(s.landmarks, ['Food court', 'Shopping']);
    for (final step in mustRoute('the_bow', 'bankers_hall').steps) {
      expect(step.text.toLowerCase(), isNot(contains('food court')));
    }
  });

  test('turn words only between bridges that meet directly', () {
    // Across whole network: every turn instruction is on a bridge step that
    // follows another bridge with < 15 m between them.
    for (final pair in [
      ['the_bow', 'bankers_hall'],
      ['eau_claire_tower', 'bankers_hall'],
      ['amec_place', 'western_canadian_place'],
      ['harry_hays', 'gulf_canada_square'],
    ]) {
      final r = mustRoute(pair[0], pair[1]);
      for (var i = 0; i < r.steps.length; i++) {
        final s = r.steps[i];
        if (!RegExp(r'^(Turn|Continue straight)').hasMatch(s.text)) continue;
        expect(s.kind, 'bridge', reason: s.text);
        final between = r.steps
            .sublist(0, i)
            .reversed
            .takeWhile((p) => p.kind == 'through')
            .fold(0.0, (a, p) => a + p.distanceM);
        expect(between, lessThan(15), reason: s.text);
      }
    }
  });

  test('stairs-only links say so in the step', () {
    final s = mustRoute('shell_centre', 'the_westin').steps[1];
    expect(s.text, contains('stairs only'));
    expect(s.caution, 'Stairs only');
  });

  test('outdoor transfer is explicit about leaving the +15', () {
    final r = mustRoute('bankers_hall', 'calgary_tower');
    final kinds = [for (final s in r.steps) s.kind];
    expect(kinds, containsAllInOrder(['exit', 'outdoor', 'enter', 'arrive']));
    final outdoor = r.steps.firstWhere((s) => s.kind == 'outdoor');
    expect(outdoor.text, contains('straight-line estimate, not +15'));
  });

  test('map-only connection is flagged as not mapped in detail', () {
    final r = mustRoute('bvc_south', 'carter_place');
    final link = r.steps.firstWhere((s) => s.kind == 'link');
    expect(link.text, contains('not mapped in detail'));
    expect(r.warnings.join(), contains('official City map'));
  });

  test('a shared concourse is explained instead of inventing a walk', () {
    expect(mustRoute('calgary_tower', 'palliser_square').steps.single.text,
        'Palliser One shares its +15 concourse with Calgary Tower: you are already there.');
    expect(mustRoute('calgary_place', 'canada_place').steps.single.text,
        contains('adjoins Calgary Place directly at the +15 level'));
  });

  test('step distances add up to the route length', () {
    final r = mustRoute('eau_claire_tower', 'bankers_hall');
    expect(r.steps.fold(0.0, (a, s) => a + s.distanceM), closeTo(r.lengthM, 0.01));
  });
}
