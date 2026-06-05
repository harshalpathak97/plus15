import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme/app_palette.dart';
import '../../core/theme/app_spacing.dart';

/// A selectable pill: brand-gradient fill when selected, a bordered surface
/// otherwise, with a subtle scale. Shared by Search filters/category chips and
/// any other chip-style toggles so they stay visually identical.
class AppPill extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  const AppPill({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? AppPalette.cardDark : Colors.white;
    final border = isDark ? AppPalette.borderDark : AppPalette.borderLight;
    final textColor = selected
        ? Colors.white
        : (isDark ? AppPalette.inkMutedDark : AppPalette.inkMuted);

    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.sm),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: AnimatedScale(
          scale: selected ? 1.0 : 0.97,
          duration: const Duration(milliseconds: 200),
          curve: AppMotion.curve,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: selected ? AppPalette.brandGradient : null,
              color: selected ? null : surface,
              borderRadius: AppRadii.rChip,
              border: Border.all(color: selected ? Colors.transparent : border),
              boxShadow: selected
                  ? [
                      BoxShadow(
                        color: AppPalette.brand.withValues(alpha: 0.3),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      )
                    ]
                  : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 14, color: textColor),
                  const SizedBox(width: 5),
                ],
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                    color: textColor,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
