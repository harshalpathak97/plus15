import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/theme/app_palette.dart';
import '../../core/theme/app_spacing.dart';
import '../../routing/network.dart';
import '../../routing/router.dart';
import '../../shared/widgets/button_row.dart';

enum StreetMode {
  transit('transit', 'r', 'Transit', Icons.directions_transit_rounded),
  walking('walking', 'w', 'Walk', Icons.directions_walk_rounded),
  driving('driving', 'd', 'Drive', Icons.directions_car_rounded);

  final String google, apple, label;
  final IconData icon;
  const StreetMode(this.google, this.apple, this.label, this.icon);
}

/// Street-level directions to a building (CTrain, bus, walk or drive) in the
/// phone's maps app. The +15 part of the trip starts once you're inside.
Future<void> openStreetDirections(BuildContext context, NetBuilding b, StreetMode mode) =>
    openDirectionsTo(context, b.lat, b.lng, b.name, mode);

/// Street directions to a point (e.g. the exact +15 door) in the maps app.
Future<void> openDirectionsTo(
    BuildContext context, double lat, double lng, String label, StreetMode mode) async {
  final ios = !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
  final q = Uri.encodeComponent('$label, Calgary');
  final uri = ios
      ? Uri.parse('https://maps.apple.com/?daddr=$lat,$lng&dirflg=${mode.apple}&q=$q')
      : Uri.parse('https://www.google.com/maps/dir/?api=1'
          '&destination=$lat,$lng&travelmode=${mode.google}');
  final messenger = ScaffoldMessenger.maybeOf(context);
  try {
    if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return;
  } catch (_) {}
  messenger?.showSnackBar(const SnackBar(content: Text('Couldn’t open your maps app.')));
}

/// A compact row of Transit / Walk / Drive buttons for getting to [b].
class StreetDirectionsRow extends StatelessWidget {
  final NetBuilding building;
  const StreetDirectionsRow({super.key, required this.building});

  @override
  Widget build(BuildContext context) {
    return ButtonRow(
      children: [
        for (final m in StreetMode.values)
          OutlinedButton.icon(
            onPressed: () => openStreetDirections(context, building, m),
            icon: Icon(m.icon, size: 18),
            label: Text(m.label, maxLines: 1, overflow: TextOverflow.ellipsis),
            style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8)),
          ),
      ],
    );
  }
}

/// When a route starts outdoors (from your location): how far to the +15
/// door, and turn-by-turn street directions to it in the maps app.
class WalkToEntranceCard extends StatelessWidget {
  final PlannedRoute route;
  const WalkToEntranceCard({super.key, required this.route});

  @override
  Widget build(BuildContext context) {
    final h = route.hops.firstOrNull;
    if (h == null || h.edge.kind != 'virtual' || h.edge.indoor || h.geometry.length < 3) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    final door = h.geometry[1];
    final label = h.edge.via ?? 'the +15';
    final far = h.lengthM > 800;
    final metres = h.lengthM < 1000
        ? '${(h.lengthM / 10).round() * 10} m'
        : '${(h.lengthM / 1000).toStringAsFixed(1)} km';
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppPalette.warning.withValues(alpha: 0.10),
        borderRadius: AppRadii.rCard,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.door_front_door_rounded, color: AppPalette.warning),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text('First, get to the +15', style: theme.textTheme.titleSmall),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text('$metres outdoors to ${label.startsWith('The ') ? label : 'the $label'}. '
              'The dotted line on the map is a straight-line guide; your maps app has the '
              'street-by-street way.',
              style: theme.textTheme.bodyMedium),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () =>
                      openDirectionsTo(context, door[0], door[1], label, StreetMode.walking),
                  icon: const Icon(Icons.directions_walk_rounded),
                  label: const Text('Walk there'),
                ),
              ),
              if (far) ...[
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () =>
                        openDirectionsTo(context, door[0], door[1], label, StreetMode.transit),
                    icon: const Icon(Icons.directions_transit_rounded),
                    label: const Text('Transit'),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
