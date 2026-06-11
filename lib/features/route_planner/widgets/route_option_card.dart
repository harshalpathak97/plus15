import 'package:flutter/material.dart';
import '../../../core/theme/app_palette.dart';

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
    final isDark = theme.brightness == Brightness.dark;

    final secondaryOnSelected = Colors.white.withValues(alpha: 0.85);
    final mutedColor = theme.textTheme.bodySmall?.color;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        width: 158,
        padding: const EdgeInsets.all(14),
        transform: isSelected
            ? (Matrix4.identity()..scale(1.0))
            : (Matrix4.identity()..scale(0.97)),
        transformAlignment: Alignment.center,
        decoration: BoxDecoration(
          color: isSelected
              ? AppPalette.brand
              : (isDark ? AppPalette.cardDark : AppPalette.cardLight),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? Colors.transparent
                : (isDark ? AppPalette.borderDark : AppPalette.borderLight),
            width: 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: AppPalette.brand.withValues(alpha: 0.35),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  )
                ]
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.05),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  )
                ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? Colors.white.withValues(alpha: 0.18)
                        : AppPalette.brand.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon,
                      size: 18,
                      color: isSelected ? Colors.white : AppPalette.brand),
                ),
                const SizedBox(width: 8),
                Expanded(
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
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: isSelected ? secondaryOnSelected : mutedColor,
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Text(
                  '$bridges bridges',
                  style: TextStyle(
                    fontSize: 11,
                    color: isSelected
                        ? Colors.white.withValues(alpha: 0.7)
                        : mutedColor,
                  ),
                ),
                if (isAccessible) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? Colors.white.withValues(alpha: 0.18)
                          : AppPalette.origin.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Icon(Icons.accessible_rounded,
                        size: 12,
                        color: isSelected ? Colors.white : AppPalette.origin),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
