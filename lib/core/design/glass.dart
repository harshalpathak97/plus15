import 'dart:ui';

import 'package:flutter/material.dart';

import 'palette.dart';

/// Reusable glassmorphism surfaces.
///
/// Wraps children in a backdrop blur + a translucent tint matching the
/// active brightness. Pass [tint] = 0 for pure blur, [tint] = 1 for an
/// opaque surface. Default ~0.7 reads well in both themes.
class GlassContainer extends StatelessWidget {
  final Widget child;
  final BorderRadius borderRadius;
  final EdgeInsetsGeometry padding;
  final double blur;
  final double tint;
  final Color? color;
  final Border? border;
  final List<BoxShadow>? shadows;

  const GlassContainer({
    super.key,
    required this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(20)),
    this.padding = EdgeInsets.zero,
    this.blur = 22,
    this.tint = 0.72,
    this.color,
    this.border,
    this.shadows,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = color ??
        (isDark ? P15Palette.surfaceDark1 : P15Palette.surface1);
    final defaultBorder = Border.all(
      color: isDark
          ? Colors.white.withValues(alpha: 0.08)
          : Colors.black.withValues(alpha: 0.05),
    );

    return ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: baseColor.withValues(alpha: tint),
            borderRadius: borderRadius,
            border: border ?? defaultBorder,
            boxShadow: shadows ??
                [
                  BoxShadow(
                    color: Colors.black
                        .withValues(alpha: isDark ? 0.32 : 0.06),
                    blurRadius: 24,
                    offset: const Offset(0, 6),
                  ),
                ],
          ),
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

/// Pill-shaped glass surface used for floating nav, toggles, and chips.
class GlassPill extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double blur;
  final double tint;
  final Color? color;
  final VoidCallback? onTap;

  const GlassPill({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    this.blur = 22,
    this.tint = 0.78,
    this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final container = GlassContainer(
      borderRadius: const BorderRadius.all(Radius.circular(100)),
      padding: padding,
      blur: blur,
      tint: tint,
      color: color,
      child: child,
    );
    if (onTap == null) return container;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: const BorderRadius.all(Radius.circular(100)),
        onTap: onTap,
        child: container,
      ),
    );
  }
}
