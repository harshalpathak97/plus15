import 'package:flutter/material.dart';
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
        const SizedBox(height: 12),
        ...List.generate(path.length, (i) {
          final building = buildingMap[path[i]];
          final isFirst = i == 0;
          final isLast = i == path.length - 1;

          Bridge? bridgeToNext;
          if (!isLast) {
            bridgeToNext = _findBridge(path[i], path[i + 1]);
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 32,
                child: Column(
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: isFirst || isLast
                            ? theme.colorScheme.primary
                            : theme.colorScheme.primary.withValues(alpha: 0.3),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: theme.colorScheme.primary,
                          width: 2,
                        ),
                      ),
                    ),
                    if (!isLast)
                      Container(
                        width: 2,
                        height: 40,
                        color: theme.colorScheme.primary.withValues(alpha: 0.2),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        building?.name ?? path[i],
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: isFirst || isLast
                              ? FontWeight.w600
                              : FontWeight.w400,
                        ),
                      ),
                      if (bridgeToNext != null) ...[
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Text(
                              '${bridgeToNext.distanceM.toInt()}m',
                              style: theme.textTheme.bodySmall,
                            ),
                            if (!bridgeToNext.isAccessible) ...[
                              const SizedBox(width: 6),
                              Icon(Icons.stairs,
                                  size: 12,
                                  color: const Color(0xFFF59E0B)),
                              const SizedBox(width: 2),
                              Text('Stairs only',
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: const Color(0xFFF59E0B))),
                            ],
                            if (bridgeToNext.hasElevator &&
                                bridgeToNext.isAccessible) ...[
                              const SizedBox(width: 6),
                              Icon(Icons.elevator,
                                  size: 12,
                                  color: const Color(0xFF22C55E)),
                            ],
                          ],
                        ),
                      ],
                      if (isFirst)
                        Text('Start here',
                            style: TextStyle(
                                fontSize: 11,
                                color: const Color(0xFF22C55E),
                                fontWeight: FontWeight.w500)),
                      if (isLast)
                        Text('Destination',
                            style: TextStyle(
                                fontSize: 11,
                                color: const Color(0xFFEF4444),
                                fontWeight: FontWeight.w500)),
                    ],
                  ),
                ),
              ),
            ],
          );
        }),
      ],
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
