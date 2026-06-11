import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_palette.dart';
import '../../core/theme/app_spacing.dart';
import '../../shared/providers/providers.dart';
import '../../shared/widgets/glass_card.dart';
import '../../shared/widgets/screen_header.dart';
import '../../shared/widgets/section_header.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final themeMode = ref.watch(themeModeProvider);
    final accessibilityMode = ref.watch(accessibilityModeProvider);
    final walkingSpeed = ref.watch(walkingSpeedProvider);

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
              16, 16, 16, AppSpacing.bottomScrollClearance),
          children: [
            const ScreenHeader('Settings', 'Customize your experience'),
            const SizedBox(height: 24),
            const SectionHeader('Appearance'),
            const SizedBox(height: 10),
            _buildThemeSelector(context, ref, themeMode)
                .animate()
                .fadeIn(duration: 400.ms, delay: 150.ms),
            const SizedBox(height: 24),
            const SectionHeader('Navigation Preferences'),
            const SizedBox(height: 10),
            _buildAccessibilityToggle(context, ref, accessibilityMode)
                .animate()
                .fadeIn(duration: 400.ms, delay: 200.ms),
            const SizedBox(height: 10),
            _buildWalkingSpeedSlider(context, ref, walkingSpeed)
                .animate()
                .fadeIn(duration: 400.ms, delay: 250.ms),
            const SizedBox(height: 24),
            const SectionHeader('Support'),
            const SizedBox(height: 10),
            _buildLinkCard(context)
                .animate()
                .fadeIn(duration: 400.ms, delay: 280.ms),
            const SizedBox(height: 24),
            const SectionHeader('About'),
            const SizedBox(height: 10),
            _buildAboutCard(context)
                .animate()
                .fadeIn(duration: 400.ms, delay: 300.ms),
            const SizedBox(height: 32),
            Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Made with ',
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.textTheme.bodySmall?.color
                              ?.withValues(alpha: 0.6))),
                  const Icon(Icons.favorite,
                      size: 14, color: AppPalette.destination),
                  Text(' by Harshal',
                      style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: theme.textTheme.bodySmall?.color
                              ?.withValues(alpha: 0.8))),
                ],
              ),
            ).animate().fadeIn(duration: 400.ms, delay: 400.ms),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildThemeSelector(
      BuildContext context, WidgetRef ref, ThemeMode current) {
    final options = <(ThemeMode, IconData, String)>[
      (ThemeMode.system, Icons.brightness_auto_rounded, 'System'),
      (ThemeMode.light, Icons.light_mode_rounded, 'Light'),
      (ThemeMode.dark, Icons.dark_mode_rounded, 'Dark'),
    ];
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GlassCard(
      padding: const EdgeInsets.all(6),
      child: Row(
        children: [
          for (final (mode, icon, label) in options)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  HapticFeedback.lightImpact();
                  ref.read(themeModeProvider.notifier).setMode(mode);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 240),
                  curve: Curves.easeOutCubic,
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    gradient: mode == current ? AppPalette.brandGradient : null,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: mode == current
                        ? [
                            BoxShadow(
                              color: AppPalette.brand.withValues(alpha: 0.3),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            )
                          ]
                        : null,
                  ),
                  child: Column(
                    children: [
                      Icon(icon,
                          size: 20,
                          color: mode == current
                              ? Colors.white
                              : (isDark
                                  ? AppPalette.inkMutedDark
                                  : AppPalette.inkMuted)),
                      const SizedBox(height: 6),
                      Text(label,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: mode == current
                                ? Colors.white
                                : (isDark
                                    ? AppPalette.inkMutedDark
                                    : AppPalette.inkMuted),
                          )),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildAccessibilityToggle(
      BuildContext context, WidgetRef ref, bool current) {
    return GlassCard(
      padding: EdgeInsets.zero,
      child: SwitchListTile(
        title: const Text('Accessibility Mode'),
        subtitle: const Text('Always prefer accessible routes',
            style: TextStyle(fontSize: 12)),
        secondary: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppPalette.transit.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.accessible_rounded,
              color: AppPalette.transit, size: 20),
        ),
        value: current,
        onChanged: (v) {
          HapticFeedback.lightImpact();
          ref.read(accessibilityModeProvider.notifier).setEnabled(v);
        },
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
    );
  }

  Widget _buildWalkingSpeedSlider(
      BuildContext context, WidgetRef ref, double speed) {
    final theme = Theme.of(context);
    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppPalette.brand.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.directions_walk_rounded,
                    color: AppPalette.brand, size: 20),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Walking Speed',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                    Text('Affects time estimates',
                        style: TextStyle(fontSize: 12)),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: AppPalette.brand.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('${speed.toStringAsFixed(1)} km/h',
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                        color: theme.colorScheme.primary)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Slider(
            value: speed,
            min: 2.0,
            max: 7.0,
            divisions: 10,
            label: '${speed.toStringAsFixed(1)} km/h',
            onChanged: (v) {
              ref.read(walkingSpeedProvider.notifier).setSpeed(v);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildLinkCard(BuildContext context) {
    final theme = Theme.of(context);
    Widget row(IconData icon, Color color, String title, String subtitle,
        String route) {
      return InkWell(
        onTap: () {
          HapticFeedback.lightImpact();
          context.push(route);
        },
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 12),
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
      );
    }

    return GlassCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          row(Icons.notifications_none_rounded, AppPalette.warning,
              'Network status', 'Closures and limited segments', '/alerts'),
          Divider(height: 1, color: theme.dividerColor),
          row(Icons.help_outline_rounded, AppPalette.brand, 'Help & feedback',
              'How to read the map, report a closure', '/help'),
        ],
      ),
    );
  }

  Widget _buildAboutCard(BuildContext context) {
    final theme = Theme.of(context);
    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  gradient: AppPalette.brandGradient,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: AppPalette.brand.withValues(alpha: 0.32),
                      blurRadius: 14,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: const Text('+15',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.5)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Plus15 Navigator',
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700)),
                    Text('Version 1.0.0', style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'Navigate Calgary\'s Plus 15 skywalk network with ease. '
            '16km of elevated, climate-controlled walkways connecting '
            '100+ buildings in downtown Calgary.',
            style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
          ),
          const SizedBox(height: 16),
          const Divider(height: 1),
          const SizedBox(height: 12),
          _buildInfoTile(context, Icons.schedule_rounded, 'Operating Hours',
              'Mon-Fri 6AM-9PM · Sat-Sun 9AM-7PM'),
          const SizedBox(height: 8),
          _buildInfoTile(context, Icons.source_rounded, 'Data Source',
              'City of Calgary Official Map'),
          const SizedBox(height: 8),
          _buildInfoTile(
              context, Icons.code_rounded, 'Built With', 'Flutter & Dart'),
        ],
      ),
    );
  }

  Widget _buildInfoTile(
      BuildContext context, IconData icon, String label, String value) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: 16, color: theme.textTheme.bodySmall?.color),
        const SizedBox(width: 8),
        Text(label, style: theme.textTheme.bodySmall),
        const SizedBox(width: 8),
        Expanded(
          child: Text(value,
              textAlign: TextAlign.end,
              style: theme.textTheme.bodySmall
                  ?.copyWith(fontWeight: FontWeight.w500)),
        ),
      ],
    );
  }
}
