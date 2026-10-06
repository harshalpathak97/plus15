import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_spacing.dart';
import '../../shared/providers/providers.dart';

/// First-run onboarding. Three pages that sell the value of the +15 companion
/// and — critically — earn the location permission by explaining *why* before
/// the OS dialog ever appears. Skipping is always allowed; the app works in
/// browse-only mode without a fix.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _controller = PageController();
  int _page = 0;
  bool _requesting = false;

  static const _pages = [
    _OnboardPage(
      title: 'The +15, finally easy',
      body:
          '16 km of skywalk. 100+ buildings. One calm map of the largest elevated '
          'indoor walkway network on earth.',
    ),
    _OnboardPage(
      icon: Icons.navigation_rounded,
      title: 'Know exactly where to turn',
      body:
          'Step-by-step directions by named bridges and buildings, so you can '
          'find your way four storeys up even when GPS drifts.',
    ),
    _OnboardPage(
      icon: Icons.my_location_rounded,
      title: 'Place yourself in the network',
      body:
          'Turn on location to see where you are and get live guidance. '
          'Only while you use the app. Never in the background, never sold.',
      isPermission: true,
    ),
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    await ref.read(localStorageProvider).setOnboardingComplete(true);
    if (mounted) context.go('/map');
  }

  Future<void> _enableLocation() async {
    if (_requesting) return;
    setState(() => _requesting = true);
    HapticFeedback.lightImpact();
    try {
      await requestLocationAccess(ref);
    } catch (_) {
      // Permission flow is best-effort; never block onboarding on it.
    } finally {
      await _finish();
    }
  }

  void _next() {
    HapticFeedback.selectionClick();
    if (_page < _pages.length - 1) {
      _controller.nextPage(
          duration: AppMotion.normal, curve: AppMotion.curve);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLast = _page == _pages.length - 1;

    return Scaffold(
      body: Stack(
        children: [
          SafeArea(
            child: Column(
              children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: AnimatedOpacity(
                    opacity: isLast ? 0 : 1,
                    duration: AppMotion.fast,
                    child: TextButton(
                      onPressed: isLast ? null : _finish,
                      child: const Text('Skip'),
                    ),
                  ),
                ),
                Expanded(
                  child: PageView.builder(
                    controller: _controller,
                    itemCount: _pages.length,
                    onPageChanged: (i) => setState(() => _page = i),
                    itemBuilder: (_, i) => _pages[i],
                  ),
                ),
                _dots(),
                const SizedBox(height: AppSpacing.xl),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                      AppSpacing.xl, 0, AppSpacing.xl, AppSpacing.xl),
                  child: isLast
                      ? Column(
                          children: [
                            _primaryButton(
                              label: _requesting
                                  ? 'Enabling…'
                                  : 'Show me where I am',
                              onTap: _enableLocation,
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            TextButton(
                              onPressed: _requesting ? null : _finish,
                              child: const Text('Not now, I’ll browse'),
                            ),
                          ],
                        )
                      : _primaryButton(label: 'Next', onTap: _next),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }


  Widget _dots() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < _pages.length; i++)
          AnimatedContainer(
            duration: AppMotion.fast,
            margin: const EdgeInsets.symmetric(horizontal: 4),
            width: i == _page ? 26 : 8,
            height: 8,
            decoration: BoxDecoration(
              color: i == _page
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.outlineVariant,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
      ],
    );
  }

  Widget _primaryButton({required String label, required VoidCallback onTap}) => SizedBox(
        width: double.infinity,
        child: FilledButton(
          onPressed: onTap,
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)),
          child: Text(label),
        ),
      );
}

class _OnboardPage extends StatelessWidget {
  /// Null shows the +15 logo mark.
  final IconData? icon;
  final String title;
  final String body;
  final bool isPermission;

  const _OnboardPage({
    this.icon,
    required this.title,
    required this.body,
    this.isPermission = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              color: icon == null ? scheme.onSurface : scheme.primaryContainer,
              borderRadius: BorderRadius.circular(28),
            ),
            child: icon == null
                ? Center(
                    child: Image.asset(AppConstants.logoMark,
                        width: 60, color: scheme.surface, semanticLabel: AppConstants.appName))
                : Icon(icon, color: scheme.onPrimaryContainer, size: 44),
          )
              .animate()
              .scale(duration: AppMotion.slow, curve: Curves.easeOutBack),
          const SizedBox(height: AppSpacing.xxxl),
          Text(
            title,
            style: theme.textTheme.displayMedium,
          ).animate().fadeIn(duration: AppMotion.normal).slideY(begin: 0.15, end: 0),
          const SizedBox(height: AppSpacing.lg),
          Text(
            body,
            style: theme.textTheme.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
          )
              .animate()
              .fadeIn(duration: AppMotion.normal, delay: 80.ms)
              .slideY(begin: 0.15, end: 0),
          if (isPermission) ...[
            const SizedBox(height: AppSpacing.xl),
            Row(
              children: [
                Icon(Icons.lock_outline_rounded, color: scheme.onSurfaceVariant, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'You can change this anytime in your device settings.',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ).animate().fadeIn(duration: AppMotion.normal, delay: 160.ms),
          ],
        ],
      ),
    );
  }
}
