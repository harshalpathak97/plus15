import 'package:flutter/material.dart';
import '../../core/theme/app_palette.dart';

/// A cohesive surface used across the app's lists and sections.
///
/// It's an opaque card (not a live blur — that's reserved for floating
/// overlays so scrolling stays smooth) with a soft brand-tinted glow, a hairline
/// border, and an optional vertical gradient accent bar on the leading edge.
class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double radius;

  /// Optional accent gradient drawn as a thin bar down the left edge.
  final Gradient? accent;

  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.margin = EdgeInsets.zero,
    this.onTap,
    this.onLongPress,
    this.radius = 18,
    this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? AppPalette.cardDark : AppPalette.cardLight;
    final border = isDark
        ? Colors.white.withValues(alpha: 0.07)
        : AppPalette.borderLight;

    final card = DecoratedBox(
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.22 : 0.06),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            onLongPress: onLongPress,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (accent != null)
                  Container(width: 4, decoration: BoxDecoration(gradient: accent)),
                Expanded(
                  child: Padding(padding: padding, child: child),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    return Padding(padding: margin, child: card);
  }
}
