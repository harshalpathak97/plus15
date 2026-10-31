import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plus15_navigator/core/theme/app_theme.dart';
import 'package:plus15_navigator/features/route_planner/widgets/handoff_card.dart';
import 'package:plus15_navigator/routing/router.dart';

import 'routing/support.dart';

void main() {
  final handoff = router.planHandoff(
      const RouteOrigin.location(51.1250, -114.0700), 'the_bow',
      at: clearDay);

  for (final dark in [false, true]) {
    for (final scale in [1.0, 1.3, 2.0]) {
      testWidgets('handoff card fits 360x640 at ${scale}x text (${dark ? 'dark' : 'light'})',
          (tester) async {
        tester.view.physicalSize = const Size(360 * 3, 640 * 3);
        tester.view.devicePixelRatio = 3;
        addTearDown(tester.view.reset);
        var started = 0, picked = -1;
        await tester.pumpWidget(MaterialApp(
          theme: dark ? AppTheme.dark : AppTheme.light,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: Scaffold(
            body: ListView(padding: const EdgeInsets.all(16), children: [
              HandoffCard(
                handoff: handoff,
                selected: 0,
                destination: 'The Bow',
                walkingSpeedKmh: 4.5,
                onSelect: (i) => picked = i,
                onAtEntrance: () => started++,
                onPreview: () {},
              ),
            ]),
          ),
        ));
        await tester.pump(const Duration(seconds: 1)); // step entrance animations
        expect(tester.takeException(), isNull);
        expect(find.textContaining('Get to '), findsOneWidget);
        expect(find.text('Transit'), findsOneWidget);
        expect(find.textContaining('Then follow the +15 to The Bow'), findsOneWidget);
        final start = find.text('At the entrance');
        await tester.ensureVisible(start);
        await tester.pump();
        await tester.tap(start);
        expect(started, 1);
        if (handoff.plans.length > 1) {
          final other = find.text(handoff.plans[1].door.label).first;
          await tester.ensureVisible(other);
          await tester.pump();
          await tester.tap(other);
          expect(picked, 1);
        }
        expect(tester.takeException(), isNull);
      });
    }
  }
}
