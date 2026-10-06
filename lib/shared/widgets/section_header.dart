import 'package:flutter/material.dart';

/// A section heading: sentence-case title with an optional trailing count.
class SectionHeader extends StatelessWidget {
  final String title;
  final String? trailing;

  const SectionHeader(this.title, {super.key, this.trailing});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: Text(title,
              maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleMedium),
        ),
        if (trailing != null)
          Text(trailing!,
              style: theme.textTheme.labelLarge
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
      ],
    );
  }
}
