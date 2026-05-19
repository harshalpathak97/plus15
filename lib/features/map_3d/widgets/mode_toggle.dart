import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/design/glass.dart';
import '../../../core/design/palette.dart';
import '../../../shared/providers/providers.dart';

class ModeToggle extends StatelessWidget {
  final MapViewMode mode;
  final ValueChanged<MapViewMode> onChanged;

  const ModeToggle({
    super.key,
    required this.mode,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return GlassContainer(
      borderRadius: BorderRadius.circular(100),
      padding: const EdgeInsets.all(4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _segment(
            context: context,
            label: '2D',
            icon: Icons.map_rounded,
            active: mode == MapViewMode.flat,
            onTap: () {
              HapticFeedback.selectionClick();
              onChanged(MapViewMode.flat);
            },
          ),
          _segment(
            context: context,
            label: '3D',
            icon: Icons.view_in_ar_rounded,
            active: mode == MapViewMode.isometric,
            onTap: () {
              HapticFeedback.selectionClick();
              onChanged(MapViewMode.isometric);
            },
          ),
        ],
      ),
    );
  }

  Widget _segment({
    required BuildContext context,
    required String label,
    required IconData icon,
    required bool active,
    required VoidCallback onTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(100),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            gradient: active ? P15Palette.brandGradient : null,
            borderRadius: BorderRadius.circular(100),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 15,
                color: active
                    ? Colors.white
                    : (isDark
                        ? P15Palette.onSurfaceDarkMuted
                        : P15Palette.onSurfaceMuted),
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.2,
                  color: active
                      ? Colors.white
                      : (isDark
                          ? P15Palette.onSurfaceDarkMuted
                          : P15Palette.onSurfaceMuted),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
