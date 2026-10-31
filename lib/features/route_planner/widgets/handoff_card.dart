import 'package:flutter/material.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../routing/router.dart';
import '../../../shared/widgets/button_row.dart';
import '../../transit/street_directions.dart';
import 'step_list.dart';

/// Within this far of the entrance, the in-app +15 route takes over by itself.
const handoffRadiusM = 150.0;

String _far(double m) => m < 1000
    ? '${(m / 10).round() * 10} m'
    : '${(m / 1000).toStringAsFixed(m < 10000 ? 1 : 0)} km';

String _the(String label) => label.startsWith('The ') ? label : 'the $label';

/// Too far to walk to the +15: the maps app takes you to the best entrance,
/// then Plus 15 takes over inside.
class HandoffCard extends StatelessWidget {
  final HandoffResult handoff;
  final int selected;
  final String destination;
  final double walkingSpeedKmh;
  final ValueChanged<int> onSelect;
  final VoidCallback onAtEntrance, onPreview;

  const HandoffCard({
    super.key,
    required this.handoff,
    required this.selected,
    required this.destination,
    required this.walkingSpeedKmh,
    required this.onSelect,
    required this.onAtEntrance,
    required this.onPreview,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final plan = handoff.plans[selected];
    final door = plan.door;
    final indoor = plan.indoor;
    final minutes = AppConstants.estimateWalkTimeMinutes(indoor.lengthM, speedKmh: walkingSpeedKmh);
    final bridges = indoor.bridgeCount;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
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
                    child: Text('1 · Get to ${_the(door.label)}',
                        style: theme.textTheme.titleSmall),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                  '${_far(door.distanceM)} from you, the first +15 entrance on your way to '
                  '$destination. Your maps app plans the street leg; Plus 15 takes over at the door.',
                  style: theme.textTheme.bodyMedium),
              const SizedBox(height: AppSpacing.md),
              ButtonRow(
                children: [
                  for (final m in StreetMode.values)
                    _modeButton(context, m, door, primary: m == StreetMode.transit),
                ],
              ),
              if (handoff.plans.length > 1) ...[
                const SizedBox(height: AppSpacing.md),
                Text('Other entrances', style: theme.textTheme.labelLarge),
                for (final (i, p) in handoff.plans.indexed)
                  if (i != selected)
                    // Ink needs a Material under the tinted box.
                    Material(
                      type: MaterialType.transparency,
                      child: ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(p.door.label, maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text('${_far(p.door.distanceM)} away · '
                            '${_far(p.indoor.lengthM)} inside the +15'),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => onSelect(i),
                      ),
                    ),
              ],
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Text('2 · Then follow the +15 to $destination', style: theme.textTheme.titleSmall),
        const SizedBox(height: AppSpacing.xs),
        Text(
            indoor.lengthM == 0
                ? 'You’ll already be there.'
                : '${_far(indoor.lengthM)} · about ${minutes.round().clamp(1, 999)} min'
                    '${bridges > 0 ? ' · $bridges ${bridges == 1 ? 'bridge' : 'bridges'}' : ''}',
            style: theme.textTheme.bodyMedium),
        const SizedBox(height: AppSpacing.md),
        ButtonRow(
          children: [
            if (!indoor.previewOnly)
              FilledButton.icon(
                onPressed: onAtEntrance,
                icon: const Icon(Icons.navigation_rounded, size: 18),
                label: const Text('At the entrance',
                    maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
            OutlinedButton.icon(
              onPressed: onPreview,
              icon: const Icon(Icons.map_outlined, size: 18),
              label: const Text('Preview on map', maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
        if (!indoor.previewOnly) ...[
          const SizedBox(height: AppSpacing.xs),
          Text('Starts by itself when you’re within ${handoffRadiusM.round()} m.',
              style: theme.textTheme.bodySmall),
        ],
        const SizedBox(height: AppSpacing.lg),
        StepList(route: indoor),
      ],
    );
  }

  Widget _modeButton(BuildContext context, StreetMode m, ApproachDoor door,
      {required bool primary}) {
    void open() => openDirectionsTo(context, door.lat, door.lng, door.label, m);
    final icon = Icon(m.icon, size: 18);
    final label = Text(m.label, maxLines: 1, overflow: TextOverflow.ellipsis);
    const pad = EdgeInsets.symmetric(horizontal: 8);
    return primary
        ? FilledButton.icon(
            onPressed: open,
            icon: icon,
            label: label,
            style: FilledButton.styleFrom(padding: pad))
        : OutlinedButton.icon(
            onPressed: open,
            icon: icon,
            label: label,
            style: OutlinedButton.styleFrom(padding: pad));
  }
}
