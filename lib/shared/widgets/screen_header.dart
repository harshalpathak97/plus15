import 'package:flutter/material.dart';
import '../../core/theme/app_spacing.dart';

/// The title + subtitle block that heads each tab.
class ScreenHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget? trailing;

  const ScreenHeader(this.title, this.subtitle, {super.key, this.trailing});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: theme.textTheme.displayMedium),
              const SizedBox(height: AppSpacing.xs),
              Text(subtitle,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ],
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}
