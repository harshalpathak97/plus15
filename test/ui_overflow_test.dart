import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plus15_navigator/core/theme/app_theme.dart';
import 'package:plus15_navigator/data/datasources/local_storage.dart';
import 'package:plus15_navigator/data/models/saved_route.dart';
import 'package:plus15_navigator/features/alerts/alerts_screen.dart';
import 'package:plus15_navigator/features/directory/directory_screen.dart';
import 'package:plus15_navigator/features/help/help_screen.dart';
import 'package:plus15_navigator/features/route_planner/route_screen.dart';
import 'package:plus15_navigator/features/saved_routes/saved_routes_screen.dart';
import 'package:plus15_navigator/features/search/search_screen.dart';
import 'package:plus15_navigator/shared/providers/providers.dart';

/// Preferences without Hive.
class _Storage extends LocalStorage {
  @override
  List<SavedRoute> getSavedRoutes() => [
        SavedRoute(
          id: 'r1',
          name: 'Bankers Hall to the Calgary City Centre office tower, the long way',
          fromId: 'bankers_hall',
          toId: 'the_bow',
          routeType: 'fastest',
          createdAt: DateTime(2026, 9, 1),
          isRoutine: true,
        ),
      ];
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
  Set<String> getSavedPlaces() => {'s24'};
}

Future<void> _settle(WidgetTester tester, bool Function() done) async {
  for (var i = 0; i < 80 && !done(); i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
    await tester.pump(const Duration(milliseconds: 100));
  }
  await tester.pump(const Duration(seconds: 1)); // entrance animations
}

/// Small phone, large text: the layouts must wrap or ellipsize, never overflow.
void main() {
  final screens = <String, Widget>{
    'directory': const DirectoryScreen(),
    'search': const SearchScreen(),
    'route': const RouteScreen(),
    'saved': const SavedRoutesScreen(),
    'settings': const HelpScreen(),
    'alerts': const AlertsScreen(),
  };
  // Each test loads assets in its own fake-async zone; don't share futures.
  setUp(() => rootBundle.clear());
  for (final dark in [false, true]) {
    for (final MapEntry(key: name, value: screen) in screens.entries) {
      testWidgets('$name fits 360x640 at 1.3x text (${dark ? 'dark' : 'light'})', (tester) async {
        tester.view.physicalSize = const Size(360 * 3, 640 * 3);
        tester.view.devicePixelRatio = 3;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(ProviderScope(
          overrides: [localStorageProvider.overrideWithValue(_Storage())],
          child: MaterialApp(
            theme: AppTheme.light,
            darkTheme: AppTheme.dark,
            themeMode: dark ? ThemeMode.dark : ThemeMode.light,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(1.3)),
              child: child!,
            ),
            home: screen,
          ),
        ));
        // Data loads from real assets: wait until nothing is loading.
        await _settle(tester, () => find.byType(CircularProgressIndicator).evaluate().isEmpty);
        if (name == 'route') {
          // Plan a real route so options, notices and steps render.
          final c = ProviderScope.containerOf(tester.element(find.byWidget(screen)));
          final b = await c.read(buildingsProvider.future);
          c.read(routeFromProvider.notifier).state = b.firstWhere((x) => x.id == 'bankers_hall');
          c.read(routeToProvider.notifier).state = b.firstWhere((x) => x.id == 'the_bow');
          await _settle(tester, () => find.text('Recommended').evaluate().isNotEmpty);
          expect(find.text('Recommended'), findsOneWidget);
          await tester.scrollUntilVisible(find.text('Steps'), 300,
              scrollable: find.byType(Scrollable).first);
          await tester.scrollUntilVisible(find.textContaining('Arrive'), 300,
              scrollable: find.byType(Scrollable).first);
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 2));
      });
    }
  }
}
