import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_palette.dart';
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
      icon: Icons.account_tree_rounded,
      title: 'The +15, finally easy',
      body:
          '16 km of skywalk. 100+ buildings. One calm map of the largest elevated '
          'indoor walkway network on earth.',
    ),
    _OnboardPage(
      icon: Icons.navigation_rounded,
      title: 'Know exactly where to turn',
      body:
          'Step-by-step guidance by named bridges and buildings — confident '
          'wayfinding even four storeys up, and even when GPS is imperfect.',
    ),
    _OnboardPage(
      icon: Icons.my_location_rounded,
      title: 'Place yourself in the network',
      body:
          'Turn on location so we can show where you are and guide you live. '
          'While-in-use only — never in the background, never sold.',
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
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (serviceEnabled) {
        var permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.denied) {
          await Geolocator.requestPermission();
        }
      }
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
      backgroundColor: AppPalette.surfaceDark,
      body: Stack(
        children: [
          // Ambient brand glow behind everything.
          Positioned(
            top: -120,
            right: -80,
            child: _glow(AppPalette.brand, 320),
          ),
          Positioned(
            bottom: -140,
            left: -100,
            child: _glow(AppPalette.skywalk, 360),
          ),
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
                      child: const Text('Skip',
                          style: TextStyle(color: Colors.white70)),
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
                              child: const Text("Not now — I'll browse",
                                  style: TextStyle(color: Colors.white70)),
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

  Widget _glow(Color color, double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withValues(alpha: 0.10),
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
              color: i == _page ? AppPalette.brand : Colors.white24,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
      ],
    );
  }

  Widget _primaryButton({required String label, required VoidCallback onTap}) {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppPalette.brand,
          borderRadius: AppRadii.rControl,
          boxShadow: [
            BoxShadow(
              color: AppPalette.brand.withValues(alpha: 0.4),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: AppRadii.rControl,
            onTap: onTap,
            child: Center(
              child: Text(label,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700)),
            ),
          ),
        ),
      ),
    );
  }
}

class _OnboardPage extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  final bool isPermission;

  const _OnboardPage({
    required this.icon,
    required this.title,
    required this.body,
    this.isPermission = false,
  });

  @override
  Widget build(BuildContext context) {
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
              color: AppPalette.brand,
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(
                  color: AppPalette.brand.withValues(alpha: 0.4),
                  blurRadius: 28,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Icon(icon, color: Colors.white, size: 44),
          )
              .animate()
              .scale(duration: AppMotion.slow, curve: Curves.easeOutBack),
          const SizedBox(height: AppSpacing.xxxl),
          Text(
            title,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 30,
                fontWeight: FontWeight.w800,
                height: 1.1,
                letterSpacing: -0.5),
          ).animate().fadeIn(duration: AppMotion.normal).slideY(begin: 0.15, end: 0),
          const SizedBox(height: AppSpacing.lg),
          Text(
            body,
            style: const TextStyle(
                color: Colors.white70, fontSize: 16, height: 1.5),
          )
              .animate()
              .fadeIn(duration: AppMotion.normal, delay: 80.ms)
              .slideY(begin: 0.15, end: 0),
          if (isPermission) ...[
            const SizedBox(height: AppSpacing.xl),
            Row(
              children: [
                const Icon(Icons.lock_outline_rounded,
                    color: Colors.white38, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'You can change this anytime in your device settings.',
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.5),
                        fontSize: 13),
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
