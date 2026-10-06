import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/providers.dart';

/// From a user tap: asks for location and, when it's blocked, offers the
/// system screen that unblocks it. True when location can be used.
Future<bool> ensureLocation(BuildContext context, WidgetRef ref) async {
  final messenger = ScaffoldMessenger.of(context);
  final block = await requestLocationAccess(ref);
  if (block == LocationBlock.none) return true;
  messenger.showSnackBar(SnackBar(
    persist: false, // auto-dismiss despite the action
    content: Text(block == LocationBlock.serviceOff
        ? 'Location is turned off on this phone.'
        : "Plus 15 can't use your location."),
    action: SnackBarAction(label: 'Turn on', onPressed: () => openLocationSettingsFor(block)),
  ));
  return false;
}
