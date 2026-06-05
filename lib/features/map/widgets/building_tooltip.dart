import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../data/models/building.dart';
import '../../../data/models/shop.dart';

class BuildingTooltip extends StatelessWidget {
  final Building building;
  final List<Shop> shops;
  final VoidCallback onNavigateHere;
  final VoidCallback onClose;

  /// When true, renders just the content column with no card chrome or entrance
  /// animation — for use inside a bottom sheet that already provides those.
  final bool embedded;

  const BuildingTooltip({
    super.key,
    required this.building,
    required this.shops,
    required this.onNavigateHere,
    required this.onClose,
    this.embedded = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final buildingShops =
        shops.where((s) => s.buildingId == building.id).toList();

    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: _children(context, theme, isDark, buildingShops),
    );

    if (embedded) return content;

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF18181B) : Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.06)
              : const Color(0xFFF1F5F9),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.08),
            blurRadius: 32,
            offset: const Offset(0, 8),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: content,
    )
        .animate()
        .fadeIn(duration: 250.ms)
        .slideY(begin: 0.08, end: 0, duration: 250.ms, curve: Curves.easeOutCubic);
  }

  List<Widget> _children(BuildContext context, ThemeData theme, bool isDark,
      List<Shop> buildingShops) {
    return [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      _typeColor(building.type),
                      _typeColor(building.type).withValues(alpha: 0.7),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(_typeIcon(building.type),
                    color: Colors.white, size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      building.name,
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    if (building.address.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(building.address,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: isDark
                                  ? Colors.white.withValues(alpha: 0.5)
                                  : const Color(0xFF94A3B8),
                            )),
                      ),
                  ],
                ),
              ),
              Material(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.06)
                    : const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(10),
                child: InkWell(
                  onTap: onClose,
                  borderRadius: BorderRadius.circular(10),
                  child: SizedBox(
                    width: 34,
                    height: 34,
                    child: Icon(Icons.close_rounded,
                        size: 16,
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.5)
                            : const Color(0xFF94A3B8)),
                  ),
                ),
              ),
            ],
          ),
          if (building.amenities.isNotEmpty) ...[
            const SizedBox(height: 14),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: building.amenities.map((a) {
                return Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: _amenityColor(a).withValues(alpha: isDark ? 0.15 : 0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: _amenityColor(a).withValues(alpha: 0.15),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(_amenityIcon(a),
                          size: 12, color: _amenityColor(a)),
                      const SizedBox(width: 4),
                      Text(
                        a[0].toUpperCase() + a.substring(1),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: _amenityColor(a),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ],
          if (buildingShops.isNotEmpty) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.04)
                    : const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${buildingShops.length} place${buildingShops.length > 1 ? 's' : ''} here',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.7)
                          : const Color(0xFF64748B),
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...buildingShops.take(3).map((s) => Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.primary
                                    .withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Icon(_categoryIcon(s.category.name),
                                  size: 12, color: theme.colorScheme.primary),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(s.name,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                      fontWeight: FontWeight.w500)),
                            ),
                          ],
                        ),
                      )),
                  if (buildingShops.length > 3)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        '+${buildingShops.length - 3} more',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: const Color(0xFF4F46E5),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onNavigateHere,
              icon: const Icon(Icons.directions_rounded, size: 18),
              label: const Text('Navigate Here',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF4F46E5),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                padding: const EdgeInsets.symmetric(vertical: 14),
                elevation: 0,
              ),
            ),
          ),
        ];
  }

  Color _typeColor(String type) {
    switch (type) {
      case 'hotel':
        return const Color(0xFFF59E0B);
      case 'retail':
        return const Color(0xFF8B5CF6);
      case 'landmark':
        return const Color(0xFFEF4444);
      case 'entertainment':
        return const Color(0xFFF97316);
      case 'government':
        return const Color(0xFF06B6D4);
      case 'convention':
        return const Color(0xFF10B981);
      case 'park':
        return const Color(0xFF22C55E);
      default:
        return const Color(0xFF4F46E5);
    }
  }

  IconData _typeIcon(String type) {
    switch (type) {
      case 'hotel':
        return Icons.hotel_rounded;
      case 'retail':
        return Icons.shopping_bag_rounded;
      case 'landmark':
        return Icons.star_rounded;
      case 'entertainment':
        return Icons.theaters_rounded;
      case 'government':
        return Icons.account_balance_rounded;
      case 'convention':
        return Icons.business_rounded;
      case 'park':
        return Icons.park_rounded;
      case 'parking':
        return Icons.local_parking_rounded;
      case 'residential':
        return Icons.apartment_rounded;
      default:
        return Icons.location_city_rounded;
    }
  }

  Color _amenityColor(String amenity) {
    switch (amenity) {
      case 'food':
        return const Color(0xFFEF4444);
      case 'retail':
        return const Color(0xFF8B5CF6);
      case 'transit':
        return const Color(0xFF10B981);
      case 'washroom':
        return const Color(0xFF06B6D4);
      case 'hotel':
        return const Color(0xFFF59E0B);
      case 'health':
        return const Color(0xFFEC4899);
      case 'entertainment':
        return const Color(0xFFF97316);
      default:
        return const Color(0xFF64748B);
    }
  }

  IconData _amenityIcon(String amenity) {
    switch (amenity) {
      case 'food':
        return Icons.restaurant_rounded;
      case 'retail':
        return Icons.shopping_bag_rounded;
      case 'transit':
        return Icons.train_rounded;
      case 'washroom':
        return Icons.wc_rounded;
      case 'hotel':
        return Icons.hotel_rounded;
      case 'health':
        return Icons.local_hospital_rounded;
      case 'entertainment':
        return Icons.theaters_rounded;
      default:
        return Icons.place_rounded;
    }
  }

  IconData _categoryIcon(String category) {
    switch (category) {
      case 'food':
        return Icons.restaurant_rounded;
      case 'retail':
        return Icons.shopping_bag_rounded;
      case 'services':
        return Icons.business_center_rounded;
      case 'transit':
        return Icons.train_rounded;
      case 'washroom':
        return Icons.wc_rounded;
      case 'hotel':
        return Icons.hotel_rounded;
      case 'health':
        return Icons.local_hospital_rounded;
      case 'entertainment':
        return Icons.theaters_rounded;
      default:
        return Icons.place_rounded;
    }
  }
}
