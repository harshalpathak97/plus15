import 'dart:convert';
import 'dart:io';

import 'package:plus15_navigator/routing/conditions.dart';
import 'package:plus15_navigator/routing/network.dart';
import 'package:plus15_navigator/routing/router.dart';

/// The real generated network and closures, loaded from disk.
final Plus15Network network = Plus15Network.fromJson(
    jsonDecode(File('assets/data/network.json').readAsStringSync()) as Map<String, dynamic>);

final List<Closure> closures = ((jsonDecode(File('assets/data/closures.json').readAsStringSync())
        as Map<String, dynamic>)['closures'] as List)
    .map((c) => Closure.fromJson(c as Map<String, dynamic>))
    .toList();

final Conditions conditions = Conditions(network, closures);
final Plus15Router router = Plus15Router(network, conditions);

/// A weekday noon after every published closure has ended.
final DateTime clearDay = DateTime(2027, 6, 15, 12);

/// A weekday noon while the Place 800, 640 Fifth and Suncor–Hanover closures
/// are all in effect.
final DateTime closureDay = DateTime(2026, 10, 15, 12);

PlannedRoute mustRoute(String from, String to,
    {RouteProfile profile = RouteProfile.fastest, DateTime? at}) {
  final r = router.route(RouteOrigin.building(from), to, profile: profile, at: at ?? clearDay);
  if (!r.ok) throw StateError('$from → $to: ${r.unavailableReason}');
  return r.route!;
}
