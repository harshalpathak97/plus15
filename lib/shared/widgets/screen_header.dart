import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../core/theme/app_spacing.dart';

/// The large title + subtitle block that heads each of the secondary tabs.
///
/// Centralizes what was copy-pasted into Search, Route, Saved and Directory so
/// the screens share one rhythm and entrance animation.
class ScreenHeader extends StatelessWidget {
  final String title;
  final String subtitle;

  const ScreenHeader(this.title, this.subtitle, {super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: theme.textTheme.displayMedium)
            .animate()
            .fadeIn(duration: AppMotion.slow)
            .slideX(begin: -0.1, end: 0),
        const SizedBox(height: AppSpacing.xs),
        Text(
          subtitle,
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: theme.textTheme.bodySmall?.color),
        ).animate().fadeIn(duration: AppMotion.slow, delay: 100.ms),
      ],
    );
  }
}
