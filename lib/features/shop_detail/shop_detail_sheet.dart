import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../data/models/shop.dart';

class ShopDetailSheet extends StatelessWidget {
  final Shop shop;
  final String? buildingName;

  const ShopDetailSheet({
    super.key,
    required this.shop,
    this.buildingName,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DraggableScrollableSheet(
      initialChildSize: 0.45,
      maxChildSize: 0.7,
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
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
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
                      color: _categoryColor().withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(_categoryIcon(),
                        color: _categoryColor(), size: 24),
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
              const SizedBox(height: 20),
              if (shop.description.isNotEmpty) ...[
                Text(shop.description,
                    style: theme.textTheme.bodyLarge
                        ?.copyWith(height: 1.5))
                    .animate()
                    .fadeIn(duration: 300.ms, delay: 100.ms),
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

  Color _categoryColor() {
    switch (shop.category) {
      case ShopCategory.food:
        return const Color(0xFFEF4444);
      case ShopCategory.retail:
        return const Color(0xFF8B5CF6);
      case ShopCategory.services:
        return const Color(0xFF4F46E5);
      case ShopCategory.transit:
        return const Color(0xFF22C55E);
      case ShopCategory.washroom:
        return const Color(0xFF06B6D4);
      case ShopCategory.hotel:
        return const Color(0xFFF59E0B);
      case ShopCategory.health:
        return const Color(0xFFEC4899);
      case ShopCategory.entertainment:
        return const Color(0xFFF97316);
    }
  }

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
