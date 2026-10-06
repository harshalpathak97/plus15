import 'dart:async';
import 'dart:collection' show SplayTreeMap;
import 'dart:convert';
import 'dart:math';

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../../data/models/opening_hours.dart';
import '../../../data/models/shop.dart';
import '../../../routing/conditions.dart';
import '../../../routing/geo.dart';
import '../../../routing/network.dart';
import '../../../routing/router.dart';
import '../../../shared/providers/providers.dart';
import '../models/ai_message.dart';

/// Our proxy in front of NVIDIA's OpenAI-compatible chat endpoint
/// (server/ai-proxy). The NVIDIA key lives only there: anything compiled into
/// the app can be pulled out of the APK.
const _endpoint = String.fromEnvironment('AI_PROXY_URL');

const kimiModel = 'moonshotai/kimi-k3';

/// Tried in order when Kimi fails, and straight away for a quick answer.
const fallbackModels = ['openai/gpt-oss-20b', 'meta/llama-3.2-11b-vision-instruct'];

/// Kimi can wait in NVIDIA's queue for minutes before its first token; after
/// this long the quick model answers instead (the user can also skip ahead).
const _kimiFirstToken = Duration(seconds: 25);
const _fallbackFirstToken = Duration(seconds: 20);
const _messageTimeout = Duration(seconds: 150);

/// How long Kimi may stay silent before the sheet offers a quick answer.
const _queuedAfter = Duration(seconds: 6);

final kimiAiProvider = StateNotifierProvider<KimiAiNotifier, List<AiMessage>>(
  (ref) => KimiAiNotifier(ref),
);

class KimiAiNotifier extends StateNotifier<List<AiMessage>> {
  /// [messages] restores a conversation.
  KimiAiNotifier(this._ref, [List<AiMessage> messages = const []]) : super(messages);

  final Ref _ref;

  /// The request in flight; closing it cancels it.
  http.Client? _client;

  /// False when the build has no AI_PROXY_URL, or (release) one that isn't
  /// https: Android's cleartext setting doesn't cover Dart's HTTP client.
  bool get isConfigured =>
      _endpoint.isNotEmpty && (!kReleaseMode || _endpoint.startsWith('https://'));

  bool get isBusy => state.lastOrNull?.isStreaming ?? false;

  void clear() {
    _cancel();
    state = const [];
  }

  /// Stops waiting for a queued Kimi reply and asks the quick model instead.
  void answerQuickly() {
    final last = state.lastOrNull;
    if (last == null || !last.queued) return;
    _update(last.id, (m) => m.copyWith(queued: false, quick: true));
    _cancel();
  }

  Future<void> send(String text) async {
    final q = text.trim();
    if (q.isEmpty || isBusy || !isConfigured) return;
    final now = DateTime.now();
    final id = '${now.microsecondsSinceEpoch}';
    // Earlier turns, without failed replies.
    final past = state.where((m) => m.isUser || m.answeredBy != null).toList();
    state = [
      ...state,
      AiMessage(id: 'q$id', text: q, isUser: true, timestamp: now),
      AiMessage(id: id, text: '', isUser: false, timestamp: now, isStreaming: true),
    ];
    String? model, reply;
    try {
      final messages = [
        {'role': 'system', 'content': await _systemPrompt(q)},
        for (final m in past.skip(max(0, past.length - 9)))
          {'role': m.isUser ? 'user' : 'assistant', 'content': m.text},
        {'role': 'user', 'content': q},
      ];
      final deadline = now.add(_messageTimeout);
      for (final m in [kimiModel, ...fallbackModels]) {
        if (!_alive(id) || DateTime.now().isAfter(deadline)) break;
        reply = await _stream(id, m, messages, deadline);
        if (reply != null) {
          model = m;
          break;
        }
      }
    } finally {
      _update(
        id,
        (m) => model == null
            ? m.copyWith(
                text: "Sorry, I couldn't get an answer. Check your connection and try again.",
                reasoning: '',
                isStreaming: false,
                queued: false,
              )
            : AiMessage.parseActions(
                m.copyWith(text: reply, isStreaming: false, queued: false, answeredBy: model)),
      );
    }
  }

  /// The app's facts for [q]: what the app does, where you are, the whole
  /// directory, +15 status and closures, the places the question is about
  /// with real walking times, and a verified route when it names places.
  Future<String> _systemPrompt(String q) async {
    final router = await _ref.read(routerProvider.future);
    final shops = await _ref.read(shopsProvider.future);
    final net = router.network;
    final now = calgaryNow();
    final loc = _ref.read(locationStreamProvider).valueOrNull;
    final here = loc == null ? null : RouteOrigin.location(loc.latitude, loc.longitude);
    final stepFree = _ref.read(accessibilityModeProvider) || _stepFreeWords.hasMatch(q);
    final profile = defaultProfile(stepFree);
    final named = matchBuildings(q, net.buildings);
    final plannerFrom = _ref.read(routeFromProvider);
    final plannerTo = _ref.read(routeToProvider);

    // Where routes start: a named start, else your location, else the
    // planner's start.
    final (RouteOrigin? origin, String originName) = named.length > 1
        ? (RouteOrigin.building(named[0].id), named[0].name)
        : here != null
            ? (here, 'your location')
            : plannerFrom != null
                ? (RouteOrigin.building(plannerFrom.id), plannerFrom.name)
                : (null, '');
    final to = named.length > 1 ? named[1] : named.firstOrNull;
    RouteResult? routeTo(String id) =>
        origin == null ? null : router.route(origin, id, profile: profile, at: now);

    // Places the question is about, nearest first, each with its walk.
    final near = named.firstOrNull ??
        (here == null ? null : router.approachDoors(here).firstOrNull?.building) ??
        plannerFrom;
    final places = matchShops(q, shops, net, near: near);
    final walks = <String, String>{};
    for (final s in places.take(8)) {
      final r = routeTo(s.buildingId);
      if (r?.route case final p?) {
        walks[s.id] = 'about ${(p.lengthM / RouteWeights.walkingSpeedMps / 60).ceil()} min '
            '(${p.lengthM.round()} m) from $originName${p.usesStreet ? ', partly outdoors' : ''}';
      }
    }

    String? whereYouAre;
    if (here != null) {
      final inside = router.regionAt(here);
      final door = router.approachDoors(here).firstOrNull;
      whereYouAre = inside != null
          ? 'Inside the +15 (${inside.label}).'
          : door == null
              ? 'More than ${(maxApproachM / 1000).round()} km from the +15.'
              : 'Outside the +15, about ${door.distanceM.round()} m from ${door.label}. '
                  'Routes from your location walk there first, then go up to the +15.';
    }

    final savedIds = _ref.read(savedPlacesProvider);
    return buildSystemPrompt(
      buildings: net.buildings,
      now: now,
      networkStatus: router.conditions.networkStatusAt(now).label,
      closures: [for (final c in router.conditions.activeAt(now)) c.title],
      directory: shops,
      shops: places,
      walks: walks,
      user: [
        'Location: ${whereYouAre ?? 'unknown (location off or not yet found)'}',
        if (plannerFrom != null || plannerTo != null)
          'Open in Navigate: ${plannerFrom?.name ?? 'start not set'} → ${plannerTo?.name ?? 'destination not set'}',
        'Prefers step-free routes: ${stepFree ? 'yes' : 'no'}',
        if (savedIds.isNotEmpty)
          'Saved places: ${[for (final s in shops) if (savedIds.contains(s.id)) s.name].join(', ')}',
      ],
      route: origin == null || to == null || origin.buildingId == to.id
          ? null
          : describeRoute(originName, to.name, routeTo(to.id)!),
    );
  }

  /// Streams [model]'s reply into message [id]. Returns the raw reply, or
  /// null when nothing arrived (error, non-200, timeout or cancelled).
  Future<String?> _stream(
      String id, String model, List<Map<String, String>> messages, DateTime deadline) async {
    final client = _client = http.Client();
    final kimi = model == kimiModel;
    final left = deadline.difference(DateTime.now());
    final firstToken = kimi ? _kimiFirstToken : _fallbackFirstToken;
    final noToken = Timer(left < firstToken ? left : firstToken, client.close);
    final stop = Timer(left, client.close);
    final queued =
        kimi ? Timer(_queuedAfter, () => _update(id, (m) => m.copyWith(queued: true))) : null;
    final text = StringBuffer(), reasoning = StringBuffer();
    try {
      final res = await client.send(http.Request('POST', Uri.parse(_endpoint))
        ..headers.addAll({
          'Content-Type': 'application/json',
          'Accept': 'text/event-stream',
        })
        ..body = jsonEncode({
          'model': model,
          'messages': messages,
          'stream': true,
          'temperature': 0.4,
          'max_tokens': kimi ? 1600 : 700, // Kimi reasons before answering
        }));
      if (res.statusCode != 200) return null;
      await for (final line in res.stream.transform(utf8.decoder).transform(const LineSplitter())) {
        if (line.startsWith('data: [DONE]')) break;
        final (content, thought) = sseDelta(line) ?? ('', '');
        if (content.isEmpty && thought.isEmpty) continue;
        noToken.cancel();
        queued?.cancel();
        text.write(content);
        reasoning.write(thought);
        _update(
          id,
          (m) => m.copyWith(
            text: text.toString().replaceFirst(_trailingTag, ''),
            reasoning: reasoning.toString(),
            queued: false,
          ),
        );
      }
    } catch (_) {
      // Network error, timeout or cancel: keep whatever arrived.
    } finally {
      noToken.cancel();
      stop.cancel();
      queued?.cancel();
      client.close();
      if (kimi) _update(id, (m) => m.copyWith(queued: false));
    }
    return text.isEmpty || _client != client ? null : text.toString();
  }

  void _cancel() {
    _client?.close();
    _client = null;
  }

  bool _alive(String id) => mounted && state.any((m) => m.id == id);

  void _update(String id, AiMessage Function(AiMessage m) change) {
    if (mounted) state = [for (final m in state) m.id == id ? change(m) : m];
  }
}

/// A half-streamed action tag at the end of a reply, hidden until parsed.
final _trailingTag = RegExp(r'\s*\[[A-Z:]*(?:\|[^\]]*)?\]?\s*$');

final _stepFreeWords =
    RegExp(r'step[- ]?free|wheelchair|accessible|stroller|elevator|no stairs', caseSensitive: false);

/// Question words → text that marks a shop as relevant (searched in its
/// name, description and category).
const _shopTopics = {
  'coffee': 'coffee', 'espresso': 'coffee', 'latte': 'coffee', 'cafe': 'coffee',
  'food': 'food', 'lunch': 'food', 'eat': 'food', 'breakfast': 'food', 'dinner': 'food',
  'restaurant': 'food', 'hungry': 'food', 'snack': 'food',
  'pharmacy': 'pharmacy', 'pharmacies': 'pharmacy', 'drugstore': 'pharmacy',
  'bank': 'bank', 'atm': 'bank',
  'washroom': 'washroom', 'restroom': 'washroom', 'bathroom': 'washroom', 'toilet': 'washroom',
  'hotel': 'hotel',
  'clinic': 'health', 'doctor': 'health', 'dentist': 'health', 'health': 'health',
};

final _wordChar = RegExp('[a-z0-9]');

/// Where lower-case [term] occurs in lower-case [text] as whole words.
Iterable<int> _wordHits(String text, String term) sync* {
  bool word(int i) => i >= 0 && i < text.length && _wordChar.hasMatch(text[i]);
  for (var i = text.indexOf(term); i >= 0; i = text.indexOf(term, i + 1)) {
    if (!word(i - 1) && !word(i + term.length)) yield i;
  }
}

/// Buildings named in [text] (names and aliases, any case, whole words), in
/// the order written. Longer names win, so "Bankers Hall West Parkade" is not
/// also "Bankers Hall"; a name shared by two buildings goes to the first.
List<NetBuilding> matchBuildings(String text, List<NetBuilding> buildings) {
  final s = text.toLowerCase();
  final terms = [
    for (final b in buildings)
      for (final t in {b.name, ...b.aliases})
        if (t.length >= 4) (t.toLowerCase(), b),
  ];
  mergeSort(terms, compare: (a, b) => b.$1.length - a.$1.length); // stable
  final taken = <(int, int)>[];
  final found = SplayTreeMap<int, NetBuilding>();
  for (final (t, b) in terms) {
    for (final i in _wordHits(s, t)) {
      final end = i + t.length;
      if (taken.any((r) => i < r.$2 && r.$1 < end)) continue;
      taken.add((i, end));
      found[i] = b;
    }
  }
  return found.values.toSet().toList();
}

/// The building an action tag names: whole names first, then any name,
/// alias or id containing it. Null for "current" / "my location" or no match.
NetBuilding? resolveBuilding(String name, List<NetBuilding> buildings) {
  final n = name.replaceAll(RegExp('["<>]'), '').trim().toLowerCase();
  if (n.length < 3 || n == 'current' || n.contains('location')) return null;
  return matchBuildings(n, buildings).firstOrNull ??
      buildings.firstWhereOrNull(
          (b) => [b.id, b.name, ...b.aliases].any((t) => t.toLowerCase().contains(n)));
}

/// Shops a question is about, by topic ("coffee", "lunch", "bank"…) or by
/// name: nearest [near] first, at most 3 per building and 12 in all.
List<Shop> matchShops(String text, List<Shop> shops, Plus15Network net, {NetBuilding? near}) {
  final s = text.toLowerCase();
  final topics = {
    for (final w in s.split(RegExp('[^a-z]+')))
      if (_shopTopics[w] ?? _shopTopics[w.replaceFirst(RegExp(r's$'), '')] case final t?) t,
  };
  final hits = [
    for (final shop in shops)
      if (topics.any('${shop.name} ${shop.description} ${shop.category.name}'.toLowerCase().contains) ||
          (shop.name.length >= 3 && _wordHits(s, shop.name.toLowerCase()).isNotEmpty))
        shop,
  ];
  if (near != null) {
    final at = project(near.lat, near.lng);
    double dist(Shop x) {
      final b = net.buildingById[x.buildingId];
      return b == null ? double.infinity : project(b.lat, b.lng).dist(at);
    }

    hits.sort((a, b) => dist(a).compareTo(dist(b)));
  }
  final perBuilding = <String, int>{};
  return [
    for (final x in hits)
      if ((perBuilding[x.buildingId] = (perBuilding[x.buildingId] ?? 0) + 1) <= 3) x,
  ].take(12).toList();
}

/// The VERIFIED ROUTE facts for [r], planned [from] → [to]. When the +15 is
/// closed now, the router's warnings say the route is for planning.
String describeRoute(String from, String to, RouteResult r) {
  final p = r.route;
  if (p == null) return 'No route from $from to $to: ${r.unavailableReason}';
  final minutes = (p.lengthM / RouteWeights.walkingSpeedMps / 60).ceil();
  return [
    '$from to $to (${p.profile.label}): ${p.lengthM.round()} m, about $minutes min walk, '
        '${p.bridgeCount} +15 bridges, ${p.stepFree ? 'step-free' : 'has stairs'}'
        '${p.usesStreet ? ', includes outdoor walking' : ''}.',
    for (final (i, step) in p.steps.indexed) '${i + 1}. ${step.text}',
    for (final w in [...p.warnings, ...p.notes]) 'Note: $w',
  ].join('\n');
}

/// What the app does, so answers can point people to the right feature.
const _aboutApp = [
  'Explore: the map of the +15 network with search, map styles, a 3D view, and Ask AI (you).',
  'Directory: every shop, restaurant and service on the +15, grouped by building, with logos.',
  'Navigate: indoor routes between buildings or from "My location". From outside the +15 a '
      'route first walks outdoors (dotted line) to the nearest street door, then up to the +15. '
      'It offers Fastest, Accessible (step-free) and Mostly indoors options.',
  'When the +15 is closed (weekdays 9 p.m.–6 a.m., weekends and holidays 7 p.m.–9 a.m.), '
      'routes can still be browsed and previewed for planning; live navigation starts at opening.',
  'Closed bridges are avoided; a route through one is shown as a preview only.',
  'Saved: saved routes and saved places. Settings: dark mode, step-free preference, walking pace.',
];

/// The system prompt: who the assistant is, the app's facts and the rules
/// that keep it to them.
String buildSystemPrompt({
  required List<NetBuilding> buildings,
  required DateTime now,
  required String networkStatus,
  List<String> closures = const [],
  List<Shop> directory = const [],
  List<Shop> shops = const [],
  Map<String, String> walks = const {},
  List<String> user = const [],
  String? route,
}) {
  final names = {for (final b in buildings) b.id: b.name};
  String hours(Shop s) {
    if (s.hours.isEmpty) return 'hours not listed';
    final open = OpeningHours.parse(s.hours).statusAt(now);
    return open.known ? '${s.hours} (${open.label})' : s.hours;
  }

  final byBuilding = <String, List<Shop>>{};
  for (final s in directory) {
    (byBuilding[s.buildingId] ??= []).add(s);
  }
  final day = const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][now.weekday - 1];
  return [
    "You are Ask +15, the assistant inside the Plus 15 app for Calgary's +15 skywalk network: "
        'enclosed walkways about 15 feet above the downtown streets. You know everything in the '
        'app below. Answer from it, recommend specific places, and offer to take people there.',
    '',
    'NOW: $day ${now.hour}:${now.minute.toString().padLeft(2, '0')} Calgary time. '
        '+15 network: $networkStatus',
    'CLOSURES IN EFFECT: ${closures.isEmpty ? 'none' : closures.join('; ')}',
    '',
    'THE APP:',
    for (final a in _aboutApp) '- $a',
    if (user.isNotEmpty) ...['', 'THE USER:', for (final u in user) '- $u'],
    '',
    'BUILDINGS (id: name / aliases [official-map amenities]):',
    for (final b in buildings)
      '${b.id}: ${[b.name, ...b.aliases].join(' / ')}'
          '${b.amenities.isEmpty ? '' : ' [${b.amenities.join(', ')}]'}',
    if (byBuilding.isNotEmpty) ...[
      '',
      'DIRECTORY (every place in the app, by building):',
      for (final e in byBuilding.entries)
        '${names[e.key] ?? e.key}: ${[
          for (final s in e.value)
            '${s.name} (${s.category.label}${s.hours.isEmpty ? '' : ', ${s.hours}'})'
        ].join('; ')}',
    ],
    if (shops.isNotEmpty) ...[
      '',
      'PLACES MATCHING THE QUESTION, nearest first (name — building — category — hours — walk):',
      for (final s in shops)
        '- ${s.name} — ${names[s.buildingId] ?? s.buildingId} — ${s.category.label} — ${hours(s)}'
            '${walks[s.id] == null ? '' : ' — ${walks[s.id]}'}',
    ],
    '',
    'VERIFIED ROUTE:',
    route ?? 'None for this question.',
    '',
    'RULES:',
    '- Search the DIRECTORY and BUILDINGS yourself: match brands, cuisines, services and '
        'building names even when the user words them loosely. Prefer the nearest options, '
        'using the walk times given.',
    '- Use only these facts. Never invent places, +15 connections, bridges, floors, elevators '
        'or hours, and never claim a route is fully indoors.',
    '- Describe a route only from the VERIFIED ROUTE, following its steps and notes. Otherwise '
        'give the building and walk time and offer directions.',
    '- Hours not listed are unknown: say so rather than guess.',
    '- At most 120 words. Plain text; "- " bullets are fine. No markdown headings, bold or emoji.',
    '- For every place you recommend (at most 3), end with one tag per place: '
        '[ACTION:NAVIGATE|from=<current or a building name>|to=<building name>|place=<shop name>] '
        '(from=current when the user\'s location is known). For a route between buildings, '
        'leave out |place=.',
    '- If you point to one building without directions, end with: [ACTION:FOCUS|name=<building name>]',
  ].join('\n');
}

/// The (content, reasoning) text in one line of an OpenAI-style SSE stream,
/// or null for keep-alives, `[DONE]` and anything unparseable.
(String, String)? sseDelta(String line) {
  if (!line.startsWith('data:')) return null;
  try {
    if (jsonDecode(line.substring(5)) case {'choices': [{'delta': final Map d}, ...]}) {
      return ((d['content'] as String?) ?? '', (d['reasoning_content'] as String?) ?? '');
    }
  } on FormatException {
    // [DONE] or a partial line.
  }
  return null;
}
