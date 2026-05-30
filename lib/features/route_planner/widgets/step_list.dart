import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../core/theme/app_palette.dart';
import '../../../data/models/building.dart';
import '../../../data/models/bridge.dart';

class StepList extends StatelessWidget {
  final List<String> path;
  final List<Building> buildings;
  final List<Bridge> bridges;

  const StepList({
    super.key,
    required this.path,
    required this.buildings,
    required this.bridges,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final buildingMap = {for (final b in buildings) b.id: b};

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Step-by-step', style: theme.textTheme.titleMedium),
        const SizedBox(height: 14),
        ...List.generate(path.length, (i) {
          final building = buildingMap[path[i]];
          final isFirst = i == 0;
          final isLast = i == path.length - 1;
          final isEndpoint = isFirst || isLast;

          final nodeColor = isFirst
              ? AppPalette.origin
              : isLast
                  ? AppPalette.destination
                  : AppPalette.brand;

          Bridge? bridgeToNext;
          if (!isLast) {
            bridgeToNext = _findBridge(path[i], path[i + 1]);
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 34,
                child: Column(
                  children: [
                    Container(
                      width: isEndpoint ? 18 : 14,
                      height: isEndpoint ? 18 : 14,
                      decoration: BoxDecoration(
                        color: isEndpoint
                            ? nodeColor
                            : nodeColor.withValues(alpha: 0.18),
                        shape: BoxShape.circle,
                        border: Border.all(color: nodeColor, width: 2.5),
                        boxShadow: isEndpoint
                            ? [
                                BoxShadow(
                                  color: nodeColor.withValues(alpha: 0.35),
                                  blurRadius: 8,
                                  spreadRadius: 1,
                                )
                              ]
                            : null,
                      ),
                      child: isEndpoint
                          ? Icon(
                              isFirst
                                  ? Icons.trip_origin
                                  : Icons.flag_rounded,
                              size: 9,
                              color: Colors.white,
                            )
                          : null,
                    ),
                    if (!isLast)
                      Container(
                        width: 3,
                        height: 42,
                        margin: const EdgeInsets.symmetric(vertical: 2),
                        decoration: BoxDecoration(
                          color: AppPalette.skywalk.withValues(alpha: 0.35),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        building?.name ?? path[i],
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight:
                              isEndpoint ? FontWeight.w700 : FontWeight.w500,
                        ),
                      ),
                      if (isFirst)
                        _tag('Start here', AppPalette.origin),
                      if (isLast) _tag('Destination', AppPalette.destination),
                      if (bridgeToNext != null) ...[
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            _chip(
                              context,
                              Icons.straighten_rounded,
                              '${bridgeToNext.distanceM.toInt()} m',
                              AppPalette.skywalk,
                            ),
                            if (!bridgeToNext.isAccessible)
                              _chip(context, Icons.stairs_rounded,
                                  'Stairs only', AppPalette.warning),
                            if (bridgeToNext.hasElevator &&
                                bridgeToNext.isAccessible)
                              _chip(context, Icons.elevator_rounded,
                                  'Elevator', AppPalette.origin),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          )
              .animate()
              .fadeIn(duration: 260.ms, delay: (i * 40).ms)
              .slideX(begin: 0.06, end: 0, delay: (i * 40).ms);
        }),
      ],
    );
  }

  Widget _tag(String label, Color color) {
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _chip(
      BuildContext context, IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Bridge? _findBridge(String fromId, String toId) {
    for (final b in bridges) {
      if ((b.fromBuildingId == fromId && b.toBuildingId == toId) ||
          (b.fromBuildingId == toId && b.toBuildingId == fromId)) {
        return b;
      }
    }
    return null;
  }
}
