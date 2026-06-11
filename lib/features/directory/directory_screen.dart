import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_palette.dart';
import '../../core/theme/app_spacing.dart';
import '../../data/models/building.dart';
import '../../data/models/opening_hours.dart';
import '../../data/models/shop.dart';
import '../../shared/providers/providers.dart';
import '../../shared/widgets/app_pill.dart';
import '../../shared/widgets/glass_card.dart';
import '../../shared/widgets/screen_header.dart';
import '../../shared/widgets/shimmer_loading.dart';
import '../shop_detail/shop_detail_sheet.dart';

/// The full +15 business directory: every shop, restaurant and service in the
/// network, grouped by the building it lives in. Search and Explore answer
/// "where is X?" — this tab answers "what's here?".
class DirectoryScreen extends ConsumerStatefulWidget {
  const DirectoryScreen({super.key});

  @override
  ConsumerState<DirectoryScreen> createState() => _DirectoryScreenState();
}

class _DirectoryScreenState extends ConsumerState<DirectoryScreen> {
  final _searchController = TextEditingController();
  String _query = '';
  ShopCategory? _category;
  bool _openNowOnly = false;

  /// Amenity markers (washrooms, transit) aren't businesses — the directory
  /// only lists places you'd visit on purpose.
  static const _listedCategories = [
    ShopCategory.food,
    ShopCategory.retail,
    ShopCategory.services,
    ShopCategory.health,
    ShopCategory.entertainment,
    ShopCategory.hotel,
  ];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shopsAsync = ref.watch(shopsProvider);
    final buildings =
        ref.watch(buildingsProvider).valueOrNull ?? const <Building>[];
    final buildingMap = {for (final b in buildings) b.id: b};

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: shopsAsync.when(
          loading: () => const ShimmerList(count: 8),
          error: (_, __) => const Center(child: Text('Couldn\'t load places')),
          data: (shops) => _buildBody(context, shops, buildingMap),
        ),
      ),
    );
  }

  Widget _buildBody(
      BuildContext context, List<Shop> shops, Map<String, Building> bMap) {
    final listed = shops
        .where((s) => _listedCategories.contains(s.category))
        .toList(growable: false);
    final filtered = _applyFilters(listed, bMap);
    final groups = _groupByBuilding(filtered, bMap);
    final foodCount =
        listed.where((s) => s.category == ShopCategory.food).length;

    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg, AppSpacing.md, AppSpacing.lg, 0),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ScreenHeader(
                  'Directory',
                  '${listed.length} places on the +15 · $foodCount food & drink',
                ),
                const SizedBox(height: AppSpacing.md),
                _searchField(context),
                const SizedBox(height: AppSpacing.sm),
              ],
            ),
          ),
        ),
        SliverToBoxAdapter(child: _filterRow(context)),
        if (groups.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: _emptyState(context),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.sm,
                AppSpacing.lg, AppSpacing.xxxl + 60),
            sliver: SliverList.builder(
              itemCount: groups.length,
              itemBuilder: (context, i) {
                final group = groups[i];
                return _buildingGroup(context, group.building, group.shops)
                    .animate()
                    .fadeIn(
                        duration: 280.ms,
                        delay: (30 * (i < 8 ? i : 8)).ms,
                        curve: Curves.easeOut);
              },
            ),
          ),
      ],
    );
  }

  // --- Filtering ---------------------------------------------------------

  List<Shop> _applyFilters(List<Shop> shops, Map<String, Building> bMap) {
    final q = _query.trim().toLowerCase();
    return shops.where((s) {
      if (_category != null && s.category != _category) return false;
      if (_openNowOnly &&
          !OpeningHours.parse(s.hours).statusAt(DateTime.now()).open) {
        return false;
      }
      if (q.isEmpty) return true;
      final buildingName = bMap[s.buildingId]?.name.toLowerCase() ?? '';
      return s.name.toLowerCase().contains(q) ||
          s.description.toLowerCase().contains(q) ||
          buildingName.contains(q);
    }).toList(growable: false);
  }

  List<({Building? building, List<Shop> shops})> _groupByBuilding(
      List<Shop> shops, Map<String, Building> bMap) {
    final byBuilding = <String, List<Shop>>{};
    for (final s in shops) {
      byBuilding.putIfAbsent(s.buildingId, () => []).add(s);
    }
    final groups = byBuilding.entries
        .map((e) => (building: bMap[e.key], shops: e.value))
        .toList();
    for (final g in groups) {
      g.shops.sort((a, b) => a.name.compareTo(b.name));
    }
    groups.sort((a, b) {
      final an = a.building?.name ?? '';
      final bn = b.building?.name ?? '';
      return an.compareTo(bn);
    });
    return groups;
  }

  // --- Header controls ---------------------------------------------------

  Widget _searchField(BuildContext context) {
    final theme = Theme.of(context);
    return TextField(
      controller: _searchController,
      onChanged: (v) => setState(() => _query = v),
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: 'Search businesses, food, buildings…',
        prefixIcon: const Icon(Icons.search_rounded, size: 20),
        suffixIcon: _query.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.close_rounded, size: 18),
                onPressed: () {
                  _searchController.clear();
                  setState(() => _query = '');
                },
              ),
      ),
      style: theme.textTheme.bodyMedium,
    );
  }

  Widget _filterRow(BuildContext context) {
    return SizedBox(
      height: 36,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        children: [
          AppPill(
            label: 'All',
            selected: _category == null && !_openNowOnly,
            onTap: () => setState(() {
              _category = null;
              _openNowOnly = false;
            }),
          ),
          AppPill(
            label: 'Open now',
            icon: Icons.schedule_rounded,
            selected: _openNowOnly,
            onTap: () => setState(() => _openNowOnly = !_openNowOnly),
          ),
          for (final c in _listedCategories)
            AppPill(
              label: c.label,
              selected: _category == c,
              onTap: () => setState(() {
                _category = _category == c ? null : c;
              }),
            ),
        ],
      ),
    );
  }

  // --- Building group card -----------------------------------------------

  Widget _buildingGroup(
      BuildContext context, Building? building, List<Shop> shops) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final muted = isDark ? AppPalette.inkMutedDark : AppPalette.inkMuted;

    return GlassCard(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppPalette.brand.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: const Icon(Icons.location_city_rounded,
                      size: 18, color: AppPalette.brand),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        building?.name ?? 'On the network',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      if (building != null && building.address.isNotEmpty)
                        Text(
                          building.address,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: muted),
                        ),
                    ],
                  ),
                ),
                Text(
                  '${shops.length}',
                  style: theme.textTheme.labelSmall?.copyWith(
                      color: muted, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          for (final shop in shops) _shopRow(context, shop, building),
        ],
      ),
    );
  }

  Widget _shopRow(BuildContext context, Shop shop, Building? building) {
    final theme = Theme.of(context);
    final catColor = AppPalette.categoryColor(shop.category.name);
    final status = OpeningHours.parse(shop.hours).statusAt(DateTime.now());

    return InkWell(
      onTap: () {
        HapticFeedback.lightImpact();
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (_) =>
              ShopDetailSheet(shop: shop, buildingName: building?.name),
        );
      },
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 11, 14, 11),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: catColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(_categoryIcon(shop.category),
                  size: 18, color: catColor),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    shop.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  if (shop.description.isNotEmpty) ...[
                    const SizedBox(height: 1),
                    Text(
                      shop.description,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
            if (status.known) ...[
              const SizedBox(width: 8),
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: status.open
                      ? AppPalette.origin
                      : AppPalette.destination.withValues(alpha: 0.6),
                ),
              ),
            ],
            const SizedBox(width: 6),
            Icon(Icons.chevron_right_rounded,
                size: 18, color: theme.textTheme.bodySmall?.color),
          ],
        ),
      ),
    );
  }

  Widget _emptyState(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppPalette.brand.withValues(alpha: 0.10),
              ),
              child: const Icon(Icons.storefront_rounded,
                  color: AppPalette.brand, size: 32),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text('Nothing matches', style: theme.textTheme.titleMedium),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Try a different name or clear the filters.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  IconData _categoryIcon(ShopCategory c) {
    switch (c) {
      case ShopCategory.food:
        return Icons.restaurant_rounded;
      case ShopCategory.retail:
        return Icons.shopping_bag_rounded;
      case ShopCategory.services:
        return Icons.business_center_rounded;
      case ShopCategory.transit:
        return Icons.tram_rounded;
      case ShopCategory.washroom:
        return Icons.wc_rounded;
      case ShopCategory.hotel:
        return Icons.hotel_rounded;
      case ShopCategory.health:
        return Icons.favorite_rounded;
      case ShopCategory.entertainment:
        return Icons.theaters_rounded;
    }
  }
}
