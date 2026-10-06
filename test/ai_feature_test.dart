import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plus15_navigator/data/models/shop.dart';
import 'package:plus15_navigator/features/ai/models/ai_message.dart';
import 'package:plus15_navigator/features/ai/services/kimi_ai_service.dart';
import 'package:plus15_navigator/features/ai/widgets/ai_concierge_sheet.dart';
import 'package:plus15_navigator/routing/router.dart';

import 'routing/support.dart';

void main() {
  final t = DateTime(2026, 10, 1, 12);

  group('parseActions', () {
    test('Parses navigation action tags correctly', () {
      const rawText = '''
Here is the best way to get to Bankers Hall:
Walk through the Level 2 walkway across 4th Street SW.
[ACTION:NAVIGATE|from=The CORE Shopping Centre|to=Bankers Hall]
''';
      final parsed =
          AiMessage.parseActions(AiMessage(id: '1', text: rawText, isUser: false, timestamp: t));

      expect(parsed.actionType, AiActionType.navigate);
      expect(parsed.actionFrom, 'The CORE Shopping Centre');
      expect(parsed.actionTo, 'Bankers Hall');
      expect(parsed.text.contains('[ACTION:NAVIGATE'), isFalse);
      expect(parsed.text.contains('Walk through the Level 2 walkway'), isTrue);
    });

    test('Parses focus action tags correctly', () {
      const rawText = '''
Scotia Centre is located on 7th Avenue SW.
[ACTION:FOCUS|name=Scotia Centre]
''';
      final parsed =
          AiMessage.parseActions(AiMessage(id: '2', text: rawText, isUser: false, timestamp: t));

      expect(parsed.actionType, AiActionType.focus);
      expect(parsed.actionTarget, 'Scotia Centre');
      expect(parsed.text.contains('[ACTION:FOCUS'), isFalse);
    });

    test('Collects up to three places to navigate to', () {
      const rawText = '''Three coffee spots near you:
- Analog Coffee, Bankers Hall, about 3 min
[ACTION:NAVIGATE|from=current|to=Bankers Hall|place=Analog Coffee]
[ACTION:NAVIGATE|from=current|to=The CORE Shopping Centre|place=Starbucks]
[ACTION:NAVIGATE|from=current|to=Bankers Hall|place=Analog Coffee]
[ACTION:NAVIGATE|from=current|to=Stephen Avenue Place|place=Deville Coffee]
[ACTION:NAVIGATE|from=current|to=Brookfield Place|place=Deville Coffee]''';
      final parsed =
          AiMessage.parseActions(AiMessage(id: '4', text: rawText, isUser: false, timestamp: t));
      expect([for (final n in parsed.offers) n.place],
          ['Analog Coffee', 'Starbucks', 'Deville Coffee']);
      expect(parsed.offers.first.from, 'current');
      expect(parsed.text, isNot(contains('[ACTION')));
    });

    test('Leaves regular messages unchanged', () {
      const rawText = 'Calgary +15 is open from 6am to 6pm on weekdays.';
      final parsed =
          AiMessage.parseActions(AiMessage(id: '3', text: rawText, isUser: false, timestamp: t));

      expect(parsed.actionType, AiActionType.none);
      expect(parsed.actionFrom, isNull);
      expect(parsed.actionTo, isNull);
      expect(parsed.text, rawText);
    });
  });

  group('matchBuildings', () {
    List<String> ids(String text) => [for (final b in matchBuildings(text, network.buildings)) b.id];

    test('finds names and aliases in the order written', () {
      expect(ids('Bankers Hall to The Bow'), ['bankers_hall', 'the_bow']);
      expect(ids('from devon tower to the SCOTIA CENTRE?'), ['400_third_ave', 'stephen_ave_place']);
    });

    test('prefers the longest name and matches each span once', () {
      expect(ids('Bankers Hall West Parkade'), ['bankers_hall_west']);
      expect(ids('Step-free route to City Hall'), ['city_hall']); // alias shared by two buildings
    });

    test('ignores names inside other words', () {
      expect(ids('the bowl at bowness, the corner store, sheratons'), isEmpty);
    });

    test('resolveBuilding reads action tag names', () {
      expect(resolveBuilding('"Bankers Hall" (+15 level)', network.buildings)?.id, 'bankers_hall');
      expect(resolveBuilding('Westin', network.buildings)?.id, 'the_westin');
      expect(resolveBuilding('current', network.buildings), isNull);
      expect(resolveBuilding('My location', network.buildings), isNull);
    });
  });

  test('matchShops finds a topic nearest the named building', () {
    Shop shop(String id, String name, String building, String description) => Shop(
        id: id,
        name: name,
        buildingId: building,
        category: ShopCategory.food,
        description: description);
    final shops = [
      shop('a', 'Far Coffee', 'the_bow', 'Coffee & espresso bar.'),
      shop('b', 'RBC', 'bankers_hall', 'Bank branch.'),
      shop('c', 'Analog Coffee', 'bankers_hall', 'Coffee & espresso bar.'),
      shop('d', 'Holy Grill', 'bankers_hall', 'Food court vendor.'),
    ];
    final bankersHall = network.buildingById['bankers_hall']!;
    final names = [
      for (final s in matchShops('Coffee near Bankers Hall', shops, network, near: bankersHall))
        s.name
    ];
    expect(names, ['Analog Coffee', 'Far Coffee']); // "Bankers" is not "bank"
    expect([for (final s in matchShops('where is holy grill', shops, network)) s.id], ['d']);
  });

  group('buildSystemPrompt', () {
    test('includes the verified route, its steps and warnings', () {
      final night = DateTime(2027, 6, 15, 23); // +15 closed: planned for opening
      final r = router.route(const RouteOrigin.building('bankers_hall'), 'the_bow', at: night);
      final prompt = buildSystemPrompt(
        buildings: network.buildings,
        now: night,
        networkStatus: conditions.networkStatusAt(night).label,
        route: describeRoute('Bankers Hall', 'The Bow', r),
      );

      expect(r.route!.opensAt, isNotNull);
      for (final s in r.route!.steps) {
        expect(prompt, contains(s.text));
      }
      for (final w in r.route!.warnings) {
        expect(prompt, contains(w));
      }
      expect(prompt, contains('closed now'));
      expect(prompt, contains('${r.route!.bridgeCount} +15 bridges'));
      expect(prompt, contains('[ACTION:NAVIGATE|from='));
      expect(prompt, isNot(contains('100%')));
    });

    test('carries the whole directory, the app and the user', () {
      final prompt = buildSystemPrompt(
        buildings: network.buildings,
        now: clearDay,
        networkStatus: 'Open until 9 p.m.',
        directory: const [
          Shop(id: 'x', name: 'Analog Coffee', buildingId: 'bankers_hall', category: ShopCategory.food),
          Shop(id: 'y', name: 'RBC', buildingId: 'the_core', category: ShopCategory.services),
        ],
        user: const ['Location: Outside the +15, about 120 m from the Bankers Hall entrance.'],
      );
      expect(prompt, contains('DIRECTORY'));
      expect(prompt, contains('Bankers Hall: Analog Coffee (Food & Dining)'));
      expect(prompt, contains('RBC (Services)'));
      expect(prompt, contains('THE APP:'));
      expect(prompt, contains('about 120 m from the Bankers Hall entrance'));
      expect(prompt, contains('|place='));
    });

    test('says when there is no route and lists matching shops', () {
      final prompt = buildSystemPrompt(
        buildings: network.buildings,
        now: clearDay,
        networkStatus: 'Open until 9 p.m.',
        shops: const [
          Shop(id: 'x', name: 'Analog Coffee', buildingId: 'bankers_hall', category: ShopCategory.food)
        ],
      );

      expect(prompt, contains('None for this question.'));
      expect(prompt, contains('- Analog Coffee — Bankers Hall — Food & Dining — hours not listed'));
      expect(prompt, isNot(contains('100%')));
    });
  });

  test('sseDelta reads content and reasoning chunks', () {
    expect(sseDelta('data: {"choices":[{"index":0,"delta":{"role":"assistant","content":"Hi"}}]}'),
        ('Hi', ''));
    expect(sseDelta('data: {"choices":[{"delta":{"reasoning_content":"hmm","content":null}}]}'),
        ('', 'hmm'));
    expect(sseDelta('data: {"choices":[],"usage":{"total_tokens":9}}'), isNull);
    expect(sseDelta('data: [DONE]'), isNull);
    expect(sseDelta(': keep-alive'), isNull);
  });

  group('sheet', () {
    Future<void> open(WidgetTester tester, Brightness brightness, List<AiMessage> messages) async {
      tester.view.physicalSize = const Size(960, 3600); // 320 x 1200: narrow, all on screen
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        overrides: [kimiAiProvider.overrideWith((ref) => KimiAiNotifier(ref, messages))],
        child: MaterialApp(
          theme: ThemeData(
            brightness: brightness,
            bottomSheetTheme: const BottomSheetThemeData(showDragHandle: true),
          ),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(onPressed: () => showAiConcierge(context), child: const Text('open')),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    for (final brightness in Brightness.values) {
      testWidgets('renders a conversation without overflow (${brightness.name})', (tester) async {
        await open(tester, brightness, [
          AiMessage(id: '1', text: 'Bankers Hall to The Bow', isUser: true, timestamp: t),
          AiMessage(
            id: '2',
            text: 'Take the +15 bridge north. ${'Averylongunbrokenword' * 8}',
            reasoning: 'The verified route has two bridges.',
            isUser: false,
            timestamp: t,
            answeredBy: fallbackModels.first,
            actionType: AiActionType.navigate,
            actionFrom: 'current',
            actionTo: 'Bankers Hall West Parkade',
          ),
          AiMessage(
            id: '3',
            text: 'It is on Stephen Avenue.',
            isUser: false,
            timestamp: t,
            answeredBy: kimiModel,
            actionType: AiActionType.focus,
            actionTarget: 'Scotia Centre',
          ),
          AiMessage(id: '4', text: 'Coffee?', isUser: true, timestamp: t),
          AiMessage(id: '5', text: '', isUser: false, timestamp: t, isStreaming: true, queued: true),
        ]);

        expect(find.text('Ask +15'), findsOneWidget);
        expect(find.text('Directions to Bankers Hall West Parkade'), findsOneWidget);
        expect(find.text('Show route'), findsOneWidget);
        expect(find.text('Show on map'), findsOneWidget);
        expect(find.text('Reasoning'), findsOneWidget);
        expect(find.text('Answered by fallback model'), findsOneWidget);
        expect(find.textContaining("Kimi is busy on NVIDIA's servers."), findsOneWidget);
        expect(find.text('Get a quick answer'), findsOneWidget);
      });
    }

    testWidgets('explains when Ask AI has no key', (tester) async {
      await open(tester, Brightness.light, const []);

      expect(find.text("Ask AI isn't set up in this build"), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
    });
  });
}
