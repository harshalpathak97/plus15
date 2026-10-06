import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_theme.dart';

/// One route choice, full width so nothing truncates.
class RouteOptionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final double distance;
  final int bridges;
  final double time;
  final bool isAccessible;
  final bool isSelected;
  final bool previewOnly;
  final String? badge;
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
    this.previewOnly = false,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final muted = scheme.onSurfaceVariant;
    return Semantics(
      button: true,
      selected: isSelected,
      excludeSemantics: true, // read once, as this label
      onTap: onTap,
      label: [
        title,
        if (badge != null) badge!,
        '${time.ceil()} minutes, ${distance.round()} metres, $bridges bridges',
        if (isAccessible) 'step-free',
        if (previewOnly) 'preview only',
      ].join(', '),
      child: Material(
        color: isSelected ? scheme.primaryContainer.withValues(alpha: 0.5) : scheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadii.rCard,
          side: BorderSide(
            color: isSelected ? scheme.primary : scheme.outlineVariant,
            width: isSelected ? 1.6 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Row(
              children: [
                Icon(icon, color: previewOnly ? muted : scheme.primary),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: theme.textTheme.titleSmall),
                      const SizedBox(height: 2),
                      Text(
                        [
                          '${distance.round()} m',
                          '$bridges bridge${bridges == 1 ? '' : 's'}',
                          if (isAccessible) 'step-free',
                        ].join(' · '),
                        style: theme.textTheme.bodySmall?.copyWith(fontFeatures: AppTheme.tabular),
                      ),
                      if (badge != null) ...[
                        const SizedBox(height: 6),
                        Text(badge!,
                            style: theme.textTheme.labelMedium?.copyWith(
                                color: previewOnly ? AppPalette.danger : scheme.primary)),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Text.rich(
                  TextSpan(children: [
                    TextSpan(text: '${time.ceil()}', style: theme.textTheme.headlineSmall),
                    TextSpan(text: ' min', style: theme.textTheme.bodySmall),
                  ]),
                  style: const TextStyle(fontFeatures: AppTheme.tabular),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
