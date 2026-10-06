import 'package:flutter/material.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../data/models/shop.dart';
import '../../../routing/conditions.dart';
import '../../../routing/network.dart';
import '../../../shared/widgets/brand_logo.dart';
import '../../shop_detail/shop_detail_sheet.dart';
import '../../transit/street_directions.dart';

/// A selected building in the map sheet: name, what's inside (with logos),
/// directions through the +15 and street directions to get there.
class BuildingTooltip extends StatelessWidget {
  final NetBuilding building;
  final List<Shop> shops;
  final VoidCallback onNavigateHere;
  final VoidCallback onClose;

  /// Whether the +15 is open now ("Open until 9 p.m."); null while loading.
  final NetworkStatus? networkStatus;

  const BuildingTooltip({
    super.key,
    required this.building,
    required this.shops,
    this.networkStatus,
    required this.onNavigateHere,
    required this.onClose,
  });

  static const _amenityLabels = {
    'food': (Icons.restaurant_rounded, 'Food court'),
    'shopping': (Icons.shopping_bag_rounded, 'Shopping'),
    'hotel': (Icons.hotel_rounded, 'Hotel'),
    'transit': (Icons.train_rounded, 'CTrain'),
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final here = shops.where((s) => s.buildingId == building.id).toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    final typeColor = AppPalette.typeColor(building.type);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: typeColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.apartment_rounded, color: typeColor),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(building.name,
                      maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleLarge),
                  if (building.address.isNotEmpty)
                    Text(building.address,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
                  if (networkStatus case final st?)
                    Text('+15 ${st.label.replaceFirst(st.label[0], st.label[0].toLowerCase())}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelLarge?.copyWith(
                            color: st.open
                                ? AppPalette.openText(theme.brightness)
                                : AppPalette.danger)),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Close',
              onPressed: onClose,
              icon: const Icon(Icons.close_rounded),
            ),
          ],
        ),
        if (building.amenities.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.lg,
            runSpacing: AppSpacing.xs,
            children: [
              for (final a in building.amenities)
                if (_amenityLabels[a] case (final icon, final label))
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon, size: 16, color: AppPalette.amenityColor(a == 'shopping' ? 'retail' : a)),
                      const SizedBox(width: 6),
                      Text(label, style: theme.textTheme.labelLarge),
                    ],
                  ),
            ],
          ),
        ],
        if (building.noElevatorToStreet) ...[
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              const Icon(Icons.warning_amber_rounded, size: 16, color: AppPalette.warning),
              const SizedBox(width: 6),
              Expanded(
                child: Text('No elevator between street and +15 (City map)',
                    style: theme.textTheme.bodySmall),
              ),
            ],
          ),
        ],
        const SizedBox(height: AppSpacing.lg),
        FilledButton.icon(
          onPressed: onNavigateHere,
          icon: const Icon(Icons.directions_walk_rounded),
          label: const Text('Directions through the +15'),
        ),
        const SizedBox(height: AppSpacing.sm),
        StreetDirectionsRow(building: building),
        if (here.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xl),
          Text(here.length == 1 ? '1 place inside' : '${here.length} places inside',
              style: theme.textTheme.titleMedium),
          const SizedBox(height: AppSpacing.xs),
          for (final s in here)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: BrandLogo(shop: s, size: 40),
              title: Text(s.name, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(s.category.label, maxLines: 1),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => showShopDetail(context, s),
            ),
        ],
      ],
    );
  }
}
