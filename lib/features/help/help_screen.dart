import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_palette.dart';
import '../../core/theme/app_spacing.dart';
import '../../shared/providers/providers.dart';
import '../../shared/widgets/contact.dart';
import '../../shared/widgets/glass_card.dart';

/// Help & feedback. Teaches people how to read the +15 map (the single biggest
/// fix for the "unclear labels / missing landmarks" feedback) and offers
/// offline-friendly ways to report a closure or send feedback.
class HelpScreen extends ConsumerWidget {
  const HelpScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
        ),
        title: const Text('Settings & help'),
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.sm, AppSpacing.lg,
            AppSpacing.xxxl + MediaQuery.paddingOf(context).bottom),
        children: [
          _sectionTitle(theme, 'Appearance'),
          GlassCard(
            padding: EdgeInsets.zero,
            child: SwitchListTile(
              secondary: const Icon(Icons.dark_mode_outlined),
              title: const Text('Dark mode'),
              subtitle: const Text('The app uses light mode unless you turn this on.'),
              value: ref.watch(themeModeProvider) == ThemeMode.dark,
              onChanged: (v) {
                HapticFeedback.selectionClick();
                ref.read(themeModeProvider.notifier).setDark(v);
              },
            ),
          ),
          _sectionTitle(theme, 'Routes'),
          GlassCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                SwitchListTile(
                  secondary: const Icon(Icons.accessible_rounded),
                  title: const Text('Prefer step-free routes'),
                  subtitle: const Text('Plan with the Accessible option first.'),
                  value: ref.watch(accessibilityModeProvider),
                  onChanged: (v) => ref.read(accessibilityModeProvider.notifier).setEnabled(v),
                ),
                const Divider(indent: 56),
                Padding(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.directions_walk_rounded, color: muted),
                          const SizedBox(width: AppSpacing.lg),
                          Text('Walking pace', style: theme.textTheme.titleMedium),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.md),
                      SizedBox(
                        width: double.infinity,
                        child: SegmentedButton<double>(
                          showSelectedIcon: false,
                          segments: const [
                            ButtonSegment(value: 3.5, label: Text('Relaxed')),
                            ButtonSegment(value: 4.5, label: Text('Normal')),
                            ButtonSegment(value: 5.5, label: Text('Brisk')),
                          ],
                          selected: {_nearestPace(ref.watch(walkingSpeedProvider))},
                          onSelectionChanged: (v) =>
                              ref.read(walkingSpeedProvider.notifier).setSpeed(v.first),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          _sectionTitle(theme, 'How to read the map'),
          GlassCard(
            child: Column(
              children: [
                _legendRow(theme, AppPalette.skywalk, Icons.remove_rounded,
                    '+15 walkways', 'City of Calgary walkway footprints and bridges.'),
                const SizedBox(height: AppSpacing.md),
                _legendRow(theme, AppPalette.inkMuted, Icons.apartment_rounded, 'Buildings',
                    'Grey blocks, named where they fit. Tap one for its shops and directions.'),
                const SizedBox(height: AppSpacing.md),
                _legendRow(theme, AppPalette.brand, Icons.route_rounded,
                    'Your route', 'Drawn exactly along the walkways it uses.'),
                const SizedBox(height: AppSpacing.md),
                _legendRow(theme, AppPalette.warning, Icons.more_horiz_rounded,
                    'Dashed line', 'Outdoors at street level, or a link not mapped in detail.'),
                const SizedBox(height: AppSpacing.md),
                _legendRow(theme, AppPalette.warning, Icons.stairs_rounded,
                    'Stairs only', 'The City map shows no step-free way across.'),
                const SizedBox(height: AppSpacing.md),
                _legendRow(theme, AppPalette.danger, Icons.block_rounded,
                    'Closed', 'A published City closure. Routes go around it.'),
                const SizedBox(height: AppSpacing.lg),
                Text('Building dots (zoomed out)', style: theme.textTheme.titleSmall),
                const SizedBox(height: AppSpacing.sm),
                Wrap(
                  spacing: AppSpacing.lg,
                  runSpacing: AppSpacing.sm,
                  children: [
                    for (final (type, label) in const [
                      ('retail', 'Shopping'),
                      ('hotel', 'Hotel'),
                      ('landmark', 'Landmark'),
                      ('entertainment', 'Food & entertainment'),
                      ('transit', 'Transit'),
                    ])
                      _dotLabel(theme, AppPalette.typeColor(type), label),
                    _dotLabel(theme, theme.colorScheme.outline, 'Other'),
                  ],
                ),
              ],
            ),
          ),
          _sectionTitle(theme, 'Good to know'),
          GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _tip(theme, Icons.sensors_rounded,
                    'GPS drifts indoors. Follow the bridge and building names in each step rather than the exact dot.'),
                const SizedBox(height: AppSpacing.md),
                _tip(theme, Icons.schedule_rounded,
                    'When the +15 is closed you can still browse routes to plan ahead. Live navigation starts once it opens.'),
                const SizedBox(height: AppSpacing.md),
                _tip(theme, Icons.alt_route_rounded,
                    'Routes avoid the closures published on calgary.ca/plus15. Short-notice closures may not be listed.'),
                const SizedBox(height: AppSpacing.md),
                _tip(theme, Icons.accessible_rounded,
                    'Step-free routes avoid links the City marks as stairs-only. Elevator locations aren’t public, so street-to-+15 access isn’t guaranteed.'),
              ],
            ),
          ),
          _sectionTitle(theme, 'Tell us'),
          GlassCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                _actionRow(context, Icons.report_outlined, 'Report a closure',
                    'Saw a bridge blocked? Let us know.', () {
                  openMail(
                    context,
                    subject: 'Plus 15 - Bridge closure report',
                    body: 'Hi,\n\nI noticed a closure on the +15 network:\n\n'
                        'Location: \nDate/time: \nDetails: \n',
                  );
                }),
                const Divider(indent: 56),
                _actionRow(context, Icons.feedback_outlined, 'Send feedback',
                    'Ideas, bugs, or a place we\'re missing.', () {
                  openMail(
                    context,
                    subject: 'Plus 15 - App feedback',
                    body: 'Hi,\n\nHere\'s my feedback:\n\n',
                  );
                }),
              ],
            ),
          ),
          if (kDebugMode) ...[
            _sectionTitle(theme, 'Developer'),
            GlassCard(
              padding: EdgeInsets.zero,
              child: SwitchListTile(
                secondary: const Icon(Icons.hub_outlined),
                title: const Text('Routing debug overlay'),
                subtitle:
                    const Text('Show graph nodes, edges, City bridge numbers and a cost breakdown.'),
                value: ref.watch(debugGraphProvider),
                onChanged: (v) => ref.read(debugGraphProvider.notifier).setEnabled(v),
              ),
            ),
          ],
          _sectionTitle(theme, 'About'),
          GlassCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                _actionRow(context, Icons.privacy_tip_outlined, 'Privacy policy',
                    'What the app sends, and to whom.',
                    () => openLink(context, AppConstants.privacyUrl)),
                const Divider(indent: 56),
                _actionRow(context, Icons.description_outlined, 'Open-source licences',
                    'Software used to build the app.',
                    () => showLicensePage(
                          context: context,
                          applicationName: AppConstants.appName,
                          applicationVersion: appBuildName,
                        )),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xxl),
          Center(
            child: Image.asset(AppConstants.logoMark,
                width: 32, color: theme.colorScheme.onSurface, excludeFromSemantics: true),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            '${AppConstants.appName}${appBuildName == null ? '' : ' $appBuildName'} · '
            'Calgary’s +15 navigator\n\n'
            'An independent app. Not affiliated with or endorsed by The City of Calgary.\n\n'
            'Contains information licensed under the Open Government Licence – City of Calgary. '
            'Map data © OpenStreetMap contributors (ODbL). Imagery and base maps powered by Esri.\n\n'
            'Brand names and logos belong to their owners and are shown only to identify '
            'locations; no endorsement is implied.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  static double _nearestPace(double v) =>
      [3.5, 4.5, 5.5].reduce((a, b) => (a - v).abs() <= (b - v).abs() ? a : b);

  Widget _sectionTitle(ThemeData theme, String title) => Padding(
        padding: const EdgeInsets.fromLTRB(4, AppSpacing.xl, 4, AppSpacing.sm),
        child: Text(title,
            style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
      );

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
              Text(title, style: theme.textTheme.titleSmall),
              Text(subtitle, style: theme.textTheme.bodySmall),
            ],
          ),
        ),
      ],
    );
  }

  Widget _dotLabel(ThemeData theme, Color color, String label) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: AppSpacing.xs),
          Text(label, style: theme.textTheme.bodySmall),
        ],
      );

  Widget _tip(ThemeData theme, IconData icon, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: theme.colorScheme.primary),
        const SizedBox(width: AppSpacing.md),
        Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
      ],
    );
  }

  Widget _actionRow(BuildContext context, IconData icon, String title,
      String subtitle, VoidCallback onTap) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: onTap,
    );
  }
}
