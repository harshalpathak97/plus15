import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_palette.dart';
import '../../core/theme/app_spacing.dart';
import '../../shared/widgets/glass_card.dart';

/// Help & feedback. Teaches people how to read the +15 map (the single biggest
/// fix for the "unclear labels / missing landmarks" feedback) and offers
/// offline-friendly ways to report a closure or send feedback.
class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.brightness == Brightness.dark
        ? AppPalette.inkMutedDark
        : AppPalette.inkMuted;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
        ),
        title: const Text('Help & feedback'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.xxxl),
        children: [
          _sectionTitle(theme, muted, 'How to read the map'),
          const SizedBox(height: AppSpacing.md),
          GlassCard(
            child: Column(
              children: [
                _legendRow(theme, AppPalette.skywalk, Icons.remove_rounded,
                    'Open skywalk', 'A +15 bridge you can walk right now.'),
                const SizedBox(height: AppSpacing.md),
                _legendRow(theme, AppPalette.warning, Icons.stairs_rounded,
                    'Limited access', 'Stairs only — no step-free route.'),
                const SizedBox(height: AppSpacing.md),
                _legendRow(theme, AppPalette.danger, Icons.block_rounded,
                    'Closed', 'Out of service — routing goes around it.'),
                const SizedBox(height: AppSpacing.md),
                _legendRow(theme, AppPalette.brand, Icons.my_location_rounded,
                    'You are here',
                    'Your live position. The halo shows GPS accuracy.'),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          _sectionTitle(theme, muted, 'Navigating with confidence'),
          const SizedBox(height: AppSpacing.md),
          GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _tip(theme, Icons.sensors_rounded,
                    'GPS is approximate above-grade. Indoors and four storeys up, your dot may drift — follow the highlighted bridge and the building names rather than the exact dot.'),
                const SizedBox(height: AppSpacing.md),
                _tip(theme, Icons.alt_route_rounded,
                    'If a bridge ahead closes, we reroute automatically and tell you the added distance — you’ll never be sent to a locked door.'),
                const SizedBox(height: AppSpacing.md),
                _tip(theme, Icons.accessible_rounded,
                    'Turn on Accessible routing in Settings to avoid stairs and route elevator-to-elevator.'),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          _sectionTitle(theme, muted, 'Tell us'),
          const SizedBox(height: AppSpacing.md),
          GlassCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                _actionRow(context, Icons.report_outlined, 'Report a closure',
                    'Saw a bridge blocked? Let us know.', () {
                  _confirm(context,
                      'Thanks — we’ll review the closure and update the network.');
                }),
                Divider(height: 1, color: theme.dividerColor),
                _actionRow(context, Icons.feedback_outlined, 'Send feedback',
                    'Ideas, bugs, or a place we’re missing.', () {
                  _confirm(context,
                      'Thanks for the feedback — it helps us make the +15 easier for everyone.');
                }),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          Center(
            child: Text('Plus 15 · Calgary +15 Navigator',
                style: theme.textTheme.bodySmall),
          ),
        ],
      ),
    );
  }

  void _confirm(BuildContext context, String message) {
    HapticFeedback.lightImpact();
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Widget _sectionTitle(ThemeData theme, Color muted, String title) {
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
        Text(title.toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(
                color: muted, fontWeight: FontWeight.w700, letterSpacing: 1.1)),
      ],
    );
  }

  Widget _legendRow(ThemeData theme, Color color, IconData icon, String title,
      String subtitle) {
    return Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: AppRadii.rChip,
          ),
          child: Icon(icon, color: color, size: 18),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700)),
              Text(subtitle, style: theme.textTheme.bodySmall),
            ],
          ),
        ),
      ],
    );
  }

  Widget _tip(ThemeData theme, IconData icon, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: AppPalette.brand),
        const SizedBox(width: AppSpacing.md),
        Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
      ],
    );
  }

  Widget _actionRow(BuildContext context, IconData icon, String title,
      String subtitle, VoidCallback onTap) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          children: [
            Icon(icon, size: 22, color: AppPalette.brand),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700)),
                  Text(subtitle, style: theme.textTheme.bodySmall),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded,
                color: theme.textTheme.bodySmall?.color),
          ],
        ),
      ),
    ).animate().fadeIn(duration: AppMotion.fast);
  }
}
