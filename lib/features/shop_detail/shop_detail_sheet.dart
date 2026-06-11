import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/theme/app_palette.dart';
import '../../core/theme/app_spacing.dart';
import '../../data/models/building.dart';
import '../../data/models/opening_hours.dart';
import '../../data/models/shop.dart';
import '../../shared/providers/providers.dart';

class ShopDetailSheet extends ConsumerWidget {
  final Shop shop;
  final String? buildingName;

  const ShopDetailSheet({
    super.key,
    required this.shop,
    this.buildingName,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return DraggableScrollableSheet(
      initialChildSize: 0.5,
      maxChildSize: 0.78,
      minChildSize: 0.3,
      expand: false,
      builder: (context, controller) {
        return Container(
          decoration: BoxDecoration(
            color: theme.scaffoldBackgroundColor,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: ListView(
            controller: controller,
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 28),
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: theme.dividerColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: _categoryColor(),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: _categoryColor().withValues(alpha: 0.35),
                          blurRadius: 16,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Icon(_categoryIcon(),
                        color: Colors.white, size: 24),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(shop.name,
                            style: theme.textTheme.headlineMedium),
                        const SizedBox(height: 2),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: _categoryColor().withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            shop.category.label,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: _categoryColor(),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ).animate().fadeIn(duration: 300.ms),
              if (shop.hours.trim().isNotEmpty) ...[
                const SizedBox(height: 16),
                _statusChip(context)
                    .animate()
                    .fadeIn(duration: 300.ms, delay: 60.ms),
              ],
              const SizedBox(height: 20),
              _ctaRow(context, ref)
                  .animate()
                  .fadeIn(duration: 300.ms, delay: 80.ms)
                  .slideY(begin: 0.15, end: 0),
              const SizedBox(height: 20),
              if (shop.description.isNotEmpty) ...[
                Text(shop.description,
                        style:
                            theme.textTheme.bodyLarge?.copyWith(height: 1.5))
                    .animate()
                    .fadeIn(duration: 300.ms, delay: 120.ms),
                const SizedBox(height: 20),
              ],
              _buildInfoRow(
                context,
                Icons.location_on_outlined,
                'Location',
                buildingName ?? 'Plus 15 Network',
              ).animate().fadeIn(duration: 300.ms, delay: 150.ms),
              if (shop.hours.isNotEmpty) ...[
                const SizedBox(height: 12),
                _buildInfoRow(
                  context,
                  Icons.access_time,
                  'Hours',
                  shop.hours,
                ).animate().fadeIn(duration: 300.ms, delay: 200.ms),
              ],
              if (shop.phone.isNotEmpty) ...[
                const SizedBox(height: 12),
                _buildInfoRow(
                  context,
                  Icons.phone_outlined,
                  'Phone',
                  shop.phone,
                ).animate().fadeIn(duration: 300.ms, delay: 250.ms),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _statusChip(BuildContext context) {
    final status = OpeningHours.parse(shop.hours).statusAt(DateTime.now());
    final color = !status.known
        ? AppPalette.inkMuted
        : status.open
            ? AppPalette.origin
            : AppPalette.destination;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.28)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(shape: BoxShape.circle, color: color),
            ),
            const SizedBox(width: 8),
            Text(
              status.label,
              style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w700, color: color),
            ),
          ],
        ),
      ),
    );
  }

  Widget _ctaRow(BuildContext context, WidgetRef ref) {
    final hasPhone = shop.phone.trim().isNotEmpty;
    final hasWeb = shop.website.trim().isNotEmpty;

    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          height: 52,
          child: FilledButton.icon(
            onPressed: () => _navigateHere(context, ref),
            icon: const Icon(Icons.navigation_rounded, size: 20),
            label: const Text('Navigate here'),
          ),
        ),
        if (hasPhone || hasWeb) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              if (hasPhone)
                Expanded(
                  child: _secondaryCta(
                    context,
                    icon: Icons.call_rounded,
                    label: 'Call',
                    onTap: () => _launch(
                        context, Uri(scheme: 'tel', path: _telDigits())),
                  ),
                ),
              if (hasPhone && hasWeb) const SizedBox(width: 10),
              if (hasWeb)
                Expanded(
                  child: _secondaryCta(
                    context,
                    icon: Icons.public_rounded,
                    label: 'Website',
                    onTap: () =>
                        _launch(context, Uri.parse(shop.website.trim())),
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _secondaryCta(BuildContext context,
      {required IconData icon,
      required String label,
      required VoidCallback onTap}) {
    return SizedBox(
      height: 48,
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 18),
        label: Text(label),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppPalette.brand,
          side: BorderSide(color: AppPalette.brand.withValues(alpha: 0.4)),
          shape: RoundedRectangleBorder(borderRadius: AppRadii.rControl),
        ),
      ),
    );
  }

  String _telDigits() =>
      shop.phone.replaceAll(RegExp(r'[^0-9+]'), '');

  void _navigateHere(BuildContext context, WidgetRef ref) {
    HapticFeedback.mediumImpact();
    final buildings =
        ref.read(buildingsProvider).valueOrNull ?? const <Building>[];
    Building? target;
    for (final b in buildings) {
      if (b.id == shop.buildingId) {
        target = b;
        break;
      }
    }
    if (target != null) {
      ref.read(routeToProvider.notifier).state = target;
      ref.read(selectedBuildingProvider.notifier).state = null;
    }
    Navigator.of(context).pop();
    context.go('/route');
  }

  Future<void> _launch(BuildContext context, Uri uri) async {
    HapticFeedback.lightImpact();
    try {
      final ok =
          await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && context.mounted) {
        _toast(context, 'Couldn’t open that link.');
      }
    } catch (_) {
      if (context.mounted) _toast(context, 'Couldn’t open that link.');
    }
  }

  void _toast(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Widget _buildInfoRow(
      BuildContext context, IconData icon, String label, String value) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: theme.colorScheme.primary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 18, color: theme.colorScheme.primary),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: theme.textTheme.labelSmall),
              const SizedBox(height: 2),
              Text(value, style: theme.textTheme.bodyMedium),
            ],
          ),
        ),
      ],
    );
  }

  Color _categoryColor() => AppPalette.categoryColor(shop.category.name);

  IconData _categoryIcon() {
    switch (shop.category) {
      case ShopCategory.food:
        return Icons.restaurant;
      case ShopCategory.retail:
        return Icons.shopping_bag;
      case ShopCategory.services:
        return Icons.business_center;
      case ShopCategory.transit:
        return Icons.train;
      case ShopCategory.washroom:
        return Icons.wc;
      case ShopCategory.hotel:
        return Icons.hotel;
      case ShopCategory.health:
        return Icons.local_hospital;
      case ShopCategory.entertainment:
        return Icons.theaters;
    }
  }
}
