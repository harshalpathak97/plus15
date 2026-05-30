import 'package:flutter/material.dart';
import '../../core/theme/app_palette.dart';

/// A consistent section label: a short brand-gradient tick followed by a
/// small-caps title. Used to head grouped content on the secondary screens.
class SectionHeader extends StatelessWidget {
  final String title;
  final String? trailing;

  const SectionHeader(this.title, {super.key, this.trailing});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final muted = isDark ? AppPalette.inkMutedDark : AppPalette.inkMuted;

    return Row(
      children: [
        Container(
          width: 14,
          height: 3,
          decoration: BoxDecoration(
            gradient: AppPalette.brandGradient,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          title.toUpperCase(),
          style: theme.textTheme.labelSmall?.copyWith(
            color: muted,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.1,
          ),
        ),
        if (trailing != null) ...[
          const Spacer(),
          Text(
            trailing!,
            style: theme.textTheme.labelSmall?.copyWith(color: muted),
          ),
        ],
      ],
    );
  }
}
