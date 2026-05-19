import 'package:flutter/material.dart';

import '../../../core/design/palette.dart';

class RouteOptionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final double distance;
  final int bridges;
  final double time;
  final int floorChanges;
  final double scenicScore;
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
    this.floorChanges = 0,
    this.scenicScore = 0,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scenic = scenicScore >= 0.6;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 162,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: isSelected ? P15Palette.brandGradient : null,
          color: isSelected ? null : theme.cardTheme.color,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? Colors.transparent
                : theme.brightness == Brightness.dark
                    ? const Color(0xFF1E293B)
                    : const Color(0xFFE2E8F0),
            width: 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: P15Palette.electricBlue.withValues(alpha: 0.32),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
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
                Flexible(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: isSelected ? Colors.white : null,
                    ),
                  ),
                ),
              ],
            ),
            const Spacer(),
            Text(
              '${distance.toInt()}m · ~${time.ceil()} min',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: isSelected
                    ? Colors.white.withValues(alpha: 0.95)
                    : theme.textTheme.bodyMedium?.color,
              ),
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 4,
              runSpacing: 2,
              children: [
                _chip(
                  context,
                  '$bridges br',
                  Icons.linear_scale_rounded,
                  isSelected,
                ),
                if (floorChanges > 0)
                  _chip(
                    context,
                    'lv$floorChanges',
                    Icons.elevator_rounded,
                    isSelected,
                  ),
                if (isAccessible)
                  _chip(
                    context,
                    'a11y',
                    Icons.accessible_rounded,
                    isSelected,
                    color: const Color(0xFF22C55E),
                  ),
                if (scenic)
                  _chip(
                    context,
                    'scenic',
                    Icons.visibility_rounded,
                    isSelected,
                    color: P15Palette.violetAccent,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(
    BuildContext context,
    String label,
    IconData icon,
    bool selected, {
    Color? color,
  }) {
    final fg = selected
        ? Colors.white.withValues(alpha: 0.92)
        : (color ?? Theme.of(context).textTheme.bodySmall?.color);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 11, color: fg),
        const SizedBox(width: 2),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: fg,
          ),
        ),
      ],
    );
  }
}
