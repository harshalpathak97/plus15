import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plus15_navigator/features/directory/directory_screen.dart';
import 'package:plus15_navigator/features/map3d/map3d_screen.dart';

void main() {
  testWidgets('Directory loads real shop data and renders groups',
      (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(
      child: MaterialApp(home: DirectoryScreen()),
    ));
    // Let the shops/buildings FutureProviders resolve and animations run.
    for (var i = 0; i < 15; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.text('Directory'), findsOneWidget);
    expect(find.text('Open now'), findsOneWidget);
    // The header counts real entries loaded from shops.json.
    expect(find.textContaining('places on the +15'), findsOneWidget);
    // The list is grouped by building, alphabetically — first group visible.
    expect(find.text('240 FOURTH'), findsOneWidget);
  });

  testWidgets('3D view builds in free mode with its canvas and chrome',
      (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(
      child: MaterialApp(home: Map3DScreen()),
    ));
    await tester.pump();
    // Flush the data load and the 5 s gesture-hint timer.
    await tester.pump(const Duration(seconds: 6));

    expect(find.text('+15 in 3D'), findsOneWidget);
    expect(find.text('The whole network, 15 feet up'), findsOneWidget);
    expect(find.byType(CustomPaint), findsWidgets);
  });
}
