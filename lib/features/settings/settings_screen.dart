import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../shared/providers/providers.dart';
import '../../data/datasources/local_storage.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final themeMode = ref.watch(themeModeProvider);
    final storage = ref.read(localStorageProvider);
    final accessibilityMode = storage.getAccessibilityMode();

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('Settings', style: theme.textTheme.displayMedium)
                .animate()
                .fadeIn(duration: 400.ms)
                .slideX(begin: -0.1, end: 0),
            const SizedBox(height: 4),
            Text('Customize your experience',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: theme.textTheme.bodySmall?.color))
                .animate()
                .fadeIn(duration: 400.ms, delay: 100.ms),
            const SizedBox(height: 24),
            _buildSectionTitle(context, 'Appearance'),
            const SizedBox(height: 8),
            _buildThemeSelector(context, ref, themeMode)
                .animate()
                .fadeIn(duration: 400.ms, delay: 150.ms),
            const SizedBox(height: 24),
            _buildSectionTitle(context, 'Navigation Preferences'),
            const SizedBox(height: 8),
            _buildAccessibilityToggle(
                    context, ref, storage, accessibilityMode)
                .animate()
                .fadeIn(duration: 400.ms, delay: 200.ms),
            const SizedBox(height: 8),
            _buildWalkingSpeedSlider(context, ref, storage)
                .animate()
                .fadeIn(duration: 400.ms, delay: 250.ms),
            const SizedBox(height: 24),
            _buildSectionTitle(context, 'About'),
            const SizedBox(height: 8),
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
                  const Icon(Icons.favorite, size: 14, color: Color(0xFFEF4444)),
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

  Widget _buildSectionTitle(BuildContext context, String title) {
    return Text(title,
        style: Theme.of(context)
            .textTheme
            .titleMedium
            ?.copyWith(fontWeight: FontWeight.w600));
  }

  Widget _buildThemeSelector(
      BuildContext context, WidgetRef ref, ThemeMode current) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Column(
          children: [
            _buildThemeOption(context, ref, ThemeMode.system, current,
                Icons.brightness_auto, 'System'),
            _buildThemeOption(context, ref, ThemeMode.light, current,
                Icons.light_mode, 'Light'),
            _buildThemeOption(context, ref, ThemeMode.dark, current,
                Icons.dark_mode, 'Dark'),
          ],
        ),
      ),
    );
  }

  Widget _buildThemeOption(BuildContext context, WidgetRef ref, ThemeMode mode,
      ThemeMode current, IconData icon, String label) {
    final theme = Theme.of(context);
    final isSelected = mode == current;
    return ListTile(
      onTap: () => ref.read(themeModeProvider.notifier).setMode(mode),
      leading: Icon(icon,
          color: isSelected ? theme.colorScheme.primary : null, size: 20),
      title: Text(label,
          style: TextStyle(
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
            color: isSelected ? theme.colorScheme.primary : null,
          )),
      trailing: isSelected
          ? Icon(Icons.check_circle,
              color: theme.colorScheme.primary, size: 20)
          : null,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      dense: true,
    );
  }

  Widget _buildAccessibilityToggle(BuildContext context, WidgetRef ref,
      LocalStorage storage, bool current) {
    return Card(
      child: SwitchListTile(
        title: const Text('Accessibility Mode'),
        subtitle: const Text('Always prefer accessible routes',
            style: TextStyle(fontSize: 12)),
        secondary: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: const Color(0xFF22C55E).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.accessible,
              color: Color(0xFF22C55E), size: 20),
        ),
        value: current,
        onChanged: (v) => storage.setAccessibilityMode(v),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }

  Widget _buildWalkingSpeedSlider(
      BuildContext context, WidgetRef ref, LocalStorage storage) {
    final speed = storage.getWalkingSpeed();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF3B82F6).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.directions_walk,
                      color: Color(0xFF3B82F6), size: 20),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Walking Speed',
                          style: TextStyle(fontWeight: FontWeight.w500)),
                      Text('Affects time estimates',
                          style: TextStyle(fontSize: 12)),
                    ],
                  ),
                ),
                Text('${speed.toStringAsFixed(1)} km/h',
                    style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.primary)),
              ],
            ),
            const SizedBox(height: 8),
            StatefulBuilder(
              builder: (context, setSliderState) {
                var val = speed;
                return Slider(
                  value: val,
                  min: 2.0,
                  max: 7.0,
                  divisions: 10,
                  label: '${val.toStringAsFixed(1)} km/h',
                  onChanged: (v) {
                    setSliderState(() => val = v);
                    storage.setWalkingSpeed(v);
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAboutCard(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF2563EB), Color(0xFF7C3AED)],
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.location_city,
                      color: Colors.white, size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Plus15 Navigator',
                          style: theme.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700)),
                      Text('Version 1.0.0',
                          style: theme.textTheme.bodySmall),
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
            _buildInfoTile(context, Icons.schedule, 'Operating Hours',
                'Mon-Fri 6AM-9PM · Sat-Sun 9AM-7PM'),
            const SizedBox(height: 8),
            _buildInfoTile(context, Icons.source, 'Data Source',
                'City of Calgary Official Map'),
            const SizedBox(height: 8),
            _buildInfoTile(context, Icons.code, 'Built With',
                'Flutter & Dart'),
          ],
        ),
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
