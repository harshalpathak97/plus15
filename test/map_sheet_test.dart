import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plus15_navigator/core/theme/app_theme.dart';
import 'package:plus15_navigator/data/datasources/local_storage.dart';
import 'package:plus15_navigator/data/models/saved_route.dart';
import 'package:plus15_navigator/features/map/widgets/map_bottom_sheet.dart';
import 'package:plus15_navigator/routing/conditions.dart';
import 'package:plus15_navigator/routing/router.dart';
import 'package:plus15_navigator/shared/providers/providers.dart';

class _Storage extends LocalStorage {
  @override
  List<SavedRoute> getSavedRoutes() => const [];
  @override
  double getWalkingSpeed() => 4.5;
  @override
  bool getAccessibilityMode() => false;
  @override
  bool getDebugGraph() => false;
  @override
  String? getBasemap() => null;
  @override
  String getThemeMode() => 'light';
  @override
  Set<String> getSavedPlaces() => const {};
}

Future<void> _settle(WidgetTester tester, bool Function() done) async {
  for (var i = 0; i < 80 && !done(); i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
    await tester.pump(const Duration(milliseconds: 100));
  }
  await tester.pump(const Duration(seconds: 1));
}

/// The map sheet's "Find nearest +15 entrance" action and result card.
void main() {
  setUp(() => rootBundle.clear());

  testWidgets('idle sheet offers the action; the result lists ranked doors and Start',
      (tester) async {
    tester.view.physicalSize = const Size(360 * 3, 640 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    var finds = 0;
    final sheet = MapBottomSheet(
      onStopNavigation: () {},
      onStartQuickRoute: (_, __, ___) {},
      onFindEntrance: () => finds++,
    );
    await tester.pumpWidget(ProviderScope(
      overrides: [localStorageProvider.overrideWithValue(_Storage())],
      child: MaterialApp(
        theme: AppTheme.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(1.3)),
          child: child!,
        ),
        home: Scaffold(body: Stack(children: [sheet])),
      ),
    ));
    await _settle(tester, () => find.text('Find nearest +15 entrance').evaluate().isNotEmpty);
    // Pull the sheet up so the idle content is on screen at large text.
    await tester.dragFrom(const Offset(180, 600), const Offset(0, -300));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Find nearest +15 entrance'));
    expect(finds, 1);

    // A real search from 9 Ave SW, shown as the active route.
    final c = ProviderScope.containerOf(tester.element(find.byWidget(sheet)));
    final router = await tester.runAsync(() => c.read(routerProvider.future));
    final result = router!.nearestEntrances(const RouteOrigin.location(51.0440, -114.0620),
        at: DateTime(2027, 6, 15, 12));
    expect(result.routes.length, 5);
    c.read(entranceOptionsProvider.notifier).state = result;
    c.read(activeRouteProvider.notifier).state = result.routes.first;
    await _settle(tester, () => find.text('Start').evaluate().isNotEmpty);
    await tester.dragFrom(const Offset(180, 600), const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(find.text('Nearest entrances by walking distance'), findsOneWidget);
    expect(find.text('Start'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('Walk to this entrance'), findsOneWidget);
    expect(find.textContaining(' m'), findsWidgets);
    // Picking another door swaps the route; Retry asks the map to search again.
    final second = result.routes[1];
    final chip = find.textContaining('${second.lengthM.round()} m');
    await tester.tap(chip.first);
    await tester.pump();
    expect(identical(c.read(activeRouteProvider), second), isTrue);
    await tester.tap(find.text('Retry'));
    expect(finds, 2);
    expect(c.read(conditionsProvider).valueOrNull, isA<Conditions>());
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
  });
}
