// Prints a route with its steps and per-hop cost breakdown.
//
//   dart run tool/route.dart <from> <to> [fastest|accessible|mostlyIndoors] [2026-10-15T12:00]
//   dart run tool/route.dart 51.0453,-114.0690 the_bow
import 'dart:convert';
import 'dart:io';

import 'package:plus15_navigator/routing/conditions.dart';
import 'package:plus15_navigator/routing/network.dart';
import 'package:plus15_navigator/routing/route_validator.dart';
import 'package:plus15_navigator/routing/router.dart';

void main(List<String> args) {
  if (args.length < 2) {
    stderr.writeln('usage: dart run tool/route.dart <from> <to> [profile] [time]');
    exit(64);
  }
  final net = Plus15Network.fromJson(
      jsonDecode(File('assets/data/network.json').readAsStringSync()) as Map<String, dynamic>);
  final closures = ((jsonDecode(File('assets/data/closures.json').readAsStringSync())
          as Map<String, dynamic>)['closures'] as List)
      .map((c) => Closure.fromJson(c as Map<String, dynamic>))
      .toList();
  final cond = Conditions(net, closures);
  final router = Plus15Router(net, cond);
  final profile = RouteProfile.values.firstWhere(
      (p) => p.name.toLowerCase() == (args.length > 2 ? args[2] : 'fastest').toLowerCase());
  final at = args.length > 3 ? DateTime.parse(args[3]) : DateTime.now();
  final ll = RegExp(r'^(-?[\d.]+),(-?[\d.]+)$').firstMatch(args[0]);
  final origin = ll != null
      ? RouteOrigin.location(double.parse(ll[1]!), double.parse(ll[2]!))
      : RouteOrigin.building(args[0]);
  final res = router.route(origin, args[1], profile: profile, at: at);
  if (!res.ok) {
    stdout.writeln('UNAVAILABLE: ${res.unavailableReason}'
        '${res.nextOpen != null ? ' (next open ${res.nextOpen})' : ''}');
    return;
  }
  final r = res.route!;
  stdout.writeln('${r.lengthM.round()} m, ${r.bridgeCount} bridges, '
      'street=${r.usesStreet}, transitions=${r.transitions.join(' ')}');
  for (final w in [...r.notes, ...r.warnings]) {
    stdout.writeln('  ! $w');
  }
  for (final s in r.steps) {
    stdout.writeln('- [${s.kind}] ${s.text} (${s.distanceM.round()} m)'
        '${s.landmarks.isEmpty ? '' : ' {${s.landmarks.join(', ')}}'}');
  }
  if (args.contains('--hops')) {
    for (final h in r.hops) {
      stdout.writeln('    ${h.edge.id} ${h.edge.kind} ${h.fromNode}→${h.toNode} '
          '${h.edge.bridgeNumber ?? ''} ${h.costNote} [${h.edge.confidence}]');
    }
  }
  final problems = validateRoute(net, cond, r);
  stdout.writeln(problems.isEmpty ? 'valid' : 'INVALID: ${problems.join('; ')}');
}
