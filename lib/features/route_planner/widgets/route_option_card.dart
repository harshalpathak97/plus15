import 'package:flutter/material.dart';

class RouteOptionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final double distance;
  final int bridges;
  final double time;
  final bool isAccessible;
  final bool isSelected;
  final VoidCallback onTap;

  const RouteOptionCard({
    super.key,
    required this.title,
    required this.icon,
    required this.distance,
    required this.bridges,
    required this.time,
    required this.isAccessible,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 150,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected
              ? theme.colorScheme.primary
              : theme.cardTheme.color,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected
                ? theme.colorScheme.primary
                : theme.brightness == Brightness.dark
                    ? const Color(0xFF1E293B)
                    : const Color(0xFFE2E8F0),
            width: isSelected ? 2 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: theme.colorScheme.primary.withValues(alpha: 0.25),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  )
                ]
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon,
                    size: 18,
                    color: isSelected
                        ? Colors.white
                        : theme.colorScheme.primary),
                const SizedBox(width: 6),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isSelected ? Colors.white : null,
                  ),
                ),
              ],
            ),
            const Spacer(),
            Text(
              '${distance.toInt()}m · ~${time.ceil()} min',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: isSelected
                    ? Colors.white.withValues(alpha: 0.9)
                    : theme.textTheme.bodySmall?.color,
              ),
            ),
            const SizedBox(height: 2),
            Row(
              children: [
                Text(
                  '$bridges bridges',
                  style: TextStyle(
                    fontSize: 11,
                    color: isSelected
                        ? Colors.white.withValues(alpha: 0.7)
                        : theme.textTheme.bodySmall?.color,
                  ),
                ),
                if (isAccessible) ...[
                  const SizedBox(width: 4),
                  Icon(Icons.accessible,
                      size: 12,
                      color: isSelected
                          ? Colors.white.withValues(alpha: 0.8)
                          : const Color(0xFF22C55E)),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
