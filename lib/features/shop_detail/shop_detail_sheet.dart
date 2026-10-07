import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/theme/app_palette.dart';
import '../../core/theme/app_spacing.dart';
import '../../data/models/opening_hours.dart';
import '../../data/models/shop.dart';
import '../../routing/conditions.dart';
import '../../routing/network.dart';
import '../../shared/providers/providers.dart';
import '../../shared/widgets/brand_logo.dart';
import '../transit/street_directions.dart';
import '../../shared/widgets/button_row.dart';

/// Opens the business detail sheet over everything (root navigator).
Future<void> showShopDetail(BuildContext context, Shop shop) {
  HapticFeedback.lightImpact();
  return showModalBottomSheet(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    builder: (_) => ShopDetailSheet(shop: shop),
  );
}

class ShopDetailSheet extends ConsumerWidget {
  final Shop shop;

  const ShopDetailSheet({super.key, required this.shop});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final buildings = ref.watch(buildingsProvider).valueOrNull ?? const <NetBuilding>[];
    final building = buildings.where((b) => b.id == shop.buildingId).firstOrNull;
    final saved = ref.watch(savedPlacesProvider).contains(shop.id);
    final status = OpeningHours.parse(shop.hours).statusAt(calgaryNow());
    final hasPhone = shop.phone.trim().isNotEmpty;
    final hasWeb = shop.website.trim().isNotEmpty;

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      maxChildSize: 0.9,
      minChildSize: 0.35,
      expand: false,
      builder: (context, controller) => ListView(
        controller: controller,
        padding: EdgeInsets.fromLTRB(
            AppSpacing.xl, 0, AppSpacing.xl, AppSpacing.xxl + MediaQuery.paddingOf(context).bottom),
        children: [
          Row(
            children: [
              BrandLogo(shop: shop, size: 64, heroTag: 'logo-${shop.id}'),
              const SizedBox(width: AppSpacing.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(shop.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.headlineSmall),
                    const SizedBox(height: 2),
                    Text(
                      [shop.category.label, if (building != null) building.name].join(' · '),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (status.known) ...[
            const SizedBox(height: AppSpacing.lg),
            _StatusLine(status: status),
          ],
          const SizedBox(height: AppSpacing.xl),
          FilledButton.icon(
            onPressed: building == null ? null : () => _navigateHere(context, ref, building),
            icon: const Icon(Icons.directions_walk_rounded),
            label: const Text('Directions through the +15'),
          ),
          const SizedBox(height: AppSpacing.sm),
          ButtonRow(
            children: [
              OutlinedButton.icon(
                onPressed: () {
                  HapticFeedback.selectionClick();
                  ref.read(savedPlacesProvider.notifier).toggle(shop.id);
                },
                icon: Icon(saved ? Icons.bookmark_rounded : Icons.bookmark_border_rounded),
                label: Text(saved ? 'Saved' : 'Save'),
              ),
              if (hasPhone)
                OutlinedButton.icon(
                  onPressed: () => _launch(
                      context, Uri(scheme: 'tel', path: shop.phone.replaceAll(RegExp(r'[^0-9+]'), ''))),
                  icon: const Icon(Icons.call_rounded),
                  label: const Text('Call'),
                ),
              if (hasWeb)
                OutlinedButton.icon(
                  onPressed: () => _launch(context, Uri.parse(shop.website.trim())),
                  icon: const Icon(Icons.public_rounded),
                  label: const Text('Website'),
                ),
            ],
          ),
          if (shop.description.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xl),
            Text(shop.description, style: theme.textTheme.bodyLarge),
          ],
          const SizedBox(height: AppSpacing.xl),
          const Divider(),
          _InfoRow(
            icon: Icons.location_on_outlined,
            label: 'Where',
            value: building == null
                ? 'On the +15 network'
                : [building.name, if (building.address.isNotEmpty) building.address].join('\n'),
          ),
          _InfoRow(
            icon: Icons.schedule_rounded,
            label: 'Hours',
            value: shop.hours.trim().isEmpty ? 'Not listed. Check with the business.' : shop.hours,
          ),
          if (hasPhone) _InfoRow(icon: Icons.call_outlined, label: 'Phone', value: shop.phone),
          if (building != null) ...[
            const SizedBox(height: AppSpacing.md),
            Text('Getting to the building', style: theme.textTheme.titleSmall),
            const SizedBox(height: AppSpacing.sm),
            StreetDirectionsRow(building: building),
          ],
        ],
      ),
    );
  }

  void _navigateHere(BuildContext context, WidgetRef ref, NetBuilding target) {
    HapticFeedback.mediumImpact();
    ref.read(routeToProvider.notifier).state = target;
    ref.read(routeToShopProvider.notifier).state = shop;
    ref.read(selectedBuildingProvider.notifier).state = null;
    final router = GoRouter.of(context);
    Navigator.of(context).pop();
    router.go('/route');
  }

  Future<void> _launch(BuildContext context, Uri uri) async {
    HapticFeedback.lightImpact();
    final messenger = ScaffoldMessenger.of(context);
    var ok = false;
    try {
      ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
    if (!ok) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Couldn’t open that link.')));
    }
  }
}

class _StatusLine extends StatelessWidget {
  final OpenStatus status;
  const _StatusLine({required this.status});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = !status.known
        ? theme.colorScheme.onSurfaceVariant
        : status.open
            ? AppPalette.openText(theme.brightness)
            : AppPalette.danger;
    return Row(
      children: [
        Icon(Icons.circle, size: 10, color: color),
        const SizedBox(width: AppSpacing.sm),
        Flexible(
          child: Text(
            status.known ? status.label : 'Hours not listed',
            style: theme.textTheme.labelLarge?.copyWith(color: color),
          ),
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _InfoRow({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: theme.textTheme.labelMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                const SizedBox(height: 2),
                Text(value, style: theme.textTheme.bodyMedium),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
