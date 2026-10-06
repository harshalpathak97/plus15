import 'package:flutter/material.dart';
import '../../core/theme/app_palette.dart';
import '../../data/models/shop.dart';

/// The one icon per shop category, used wherever a category is shown.
IconData categoryIcon(ShopCategory c) => switch (c) {
      ShopCategory.food => Icons.restaurant_rounded,
      ShopCategory.retail => Icons.shopping_bag_rounded,
      ShopCategory.services => Icons.business_center_rounded,
      ShopCategory.transit => Icons.train_rounded,
      ShopCategory.washroom => Icons.wc_rounded,
      ShopCategory.hotel => Icons.hotel_rounded,
      ShopCategory.health => Icons.local_pharmacy_rounded,
      ShopCategory.entertainment => Icons.theaters_rounded,
    };

/// A shop's brand logo as a rounded tile; falls back to a tinted category
/// glyph when no logo is bundled.
///
/// The bundled logos (assets/logos, 256 px) already sit on a white card, so
/// the tile shows them edge to edge.
class BrandLogo extends StatelessWidget {
  final Shop shop;
  final double size;
  final String? heroTag;

  const BrandLogo({super.key, required this.shop, this.size = 44, this.heroTag});

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(size * 0.26);
    final scheme = Theme.of(context).colorScheme;
    final fallback = _CategoryGlyph(category: shop.category, size: size, radius: radius);
    Widget tile = shop.logo == null
        ? fallback
        : DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: radius,
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: ClipRRect(
              borderRadius: radius,
              child: Image.asset(
                shop.logo!,
                width: size,
                height: size,
                fit: BoxFit.cover,
                cacheWidth: (size * MediaQuery.devicePixelRatioOf(context)).round(),
                errorBuilder: (_, __, ___) => fallback,
              ),
            ),
          );
    tile = Semantics(
      image: true,
      label: '${shop.name} logo',
      child: SizedBox.square(dimension: size, child: tile),
    );
    return heroTag == null ? tile : Hero(tag: heroTag!, child: tile);
  }
}

class _CategoryGlyph extends StatelessWidget {
  final ShopCategory category;
  final double size;
  final BorderRadius radius;

  const _CategoryGlyph({required this.category, required this.size, required this.radius});

  @override
  Widget build(BuildContext context) {
    final color = AppPalette.categoryColor(category.name);
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: dark ? 0.2 : 0.12),
        borderRadius: radius,
      ),
      child: Icon(categoryIcon(category), size: size * 0.5, color: color),
    );
  }
}
