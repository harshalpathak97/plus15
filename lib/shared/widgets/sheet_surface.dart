import 'package:flutter/material.dart';
import '../../core/theme/app_palette.dart';
import '../../core/theme/app_spacing.dart';

/// The visual chrome for a bottom sheet: a rounded top, a drag handle, a themed
/// surface, a hairline top border and a soft upward shadow.
///
/// Shared by the map's draggable sheet and the modal sheets so every sheet in
/// the app reads the same. Pass the [controller] from a
/// [DraggableScrollableSheet] builder (or a plain [ScrollController] for modal
/// sheets) so drag-to-expand works; [children] are laid out in a single
/// scroll view beneath the handle.
class SheetSurface extends StatelessWidget {
  final ScrollController? controller;
  final List<Widget> children;
  final EdgeInsetsGeometry padding;

  const SheetSurface({
    super.key,
    this.controller,
    required this.children,
    this.padding = const EdgeInsets.fromLTRB(
        AppSpacing.lg, AppSpacing.xs, AppSpacing.lg, AppSpacing.xxl),
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? AppPalette.cardDark : Colors.white;
    final border = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : AppPalette.borderLight;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: surface,
        borderRadius: AppRadii.rSheetTop,
        border: Border.all(color: border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.34 : 0.10),
            blurRadius: 28,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: AppRadii.rSheetTop,
        child: ListView(
          controller: controller,
          padding: EdgeInsets.zero,
          children: [
            const _DragHandle(),
            Padding(
              padding: padding,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: children,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DragHandle extends StatelessWidget {
  const _DragHandle();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Center(
      child: Container(
        margin: const EdgeInsets.only(top: AppSpacing.md, bottom: AppSpacing.sm),
        width: 42,
        height: 5,
        decoration: BoxDecoration(
          color: (isDark ? Colors.white : AppPalette.ink)
              .withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(3),
        ),
      ),
    );
  }
}
