import 'package:flutter/material.dart';

/// Equal-width buttons side by side, stacked full-width instead when large
/// system text would clip their labels.
class ButtonRow extends StatelessWidget {
  final List<Widget> children;
  const ButtonRow({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.textScalerOf(context).scale(10) > 13) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (i, c) in children.indexed) ...[
            if (i > 0) const SizedBox(height: 8),
            c,
          ],
        ],
      );
    }
    return Row(
      children: [
        for (final (i, c) in children.indexed) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(child: c),
        ],
      ],
    );
  }
}
