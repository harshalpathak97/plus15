import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_palette.dart';
import '../../core/theme/app_spacing.dart';
import '../../data/models/building.dart';
import '../../data/models/bridge.dart';
import '../../data/models/opening_hours.dart';
import '../../data/models/shop.dart';
import '../../shared/providers/providers.dart';
import '../../shared/widgets/app_pill.dart';
import '../../shared/widgets/glass_card.dart';
import '../../shared/widgets/screen_header.dart';
import '../shop_detail/shop_detail_sheet.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _searchController = TextEditingController();
  final Set<String> _savedShopIds = <String>{};

  bool _filterOpenNow = false;
  bool _filterFood = false;
  bool _filterTransit = false;
  bool _filterAccessible = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shopsAsync = ref.watch(shopsProvider);
    final buildingsAsync = ref.watch(buildingsProvider);
    final bridgesAsync = ref.watch(bridgesProvider);
    final query = ref.watch(searchQueryProvider);
    final selectedCat = ref.watch(selectedCategoryProvider);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const ScreenHeader(
                      'Search', 'Explore shops and services with live filters'),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _searchController,
                    onChanged: (v) =>
                        ref.read(searchQueryProvider.notifier).state = v,
                    decoration: InputDecoration(
                      hintText: 'Search places, food, or services...',
                      prefixIcon: const Icon(Icons.search_rounded, size: 20),
                      suffixIcon: query.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.close_rounded, size: 18),
                              onPressed: () {
                                _searchController.clear();
                                ref.read(searchQueryProvider.notifier).state =
                                    '';
                              },
                            )
                          : null,
                    ),
                  ).animate().fadeIn(duration: 400.ms, delay: 150.ms),
                  const SizedBox(height: 12),
                  _buildFastFilterRow(context),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 36,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        _buildCategoryChip(context, null, 'All', selectedCat),
                        ...ShopCategory.values.map(
                          (c) => _buildCategoryChip(
                            context,
                            c.name,
                            c.label,
                            selectedCat,
                          ),
                        ),
                      ],
                    ),
                  ).animate().fadeIn(duration: 400.ms, delay: 220.ms),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: _buildResults(
                context,
                shopsAsync,
                buildingsAsync,
                bridgesAsync,
                query,
                selectedCat,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFastFilterRow(BuildContext context) {
    return SizedBox(
      height: 36,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          AppPill(
            label: 'Open now',
            icon: Icons.schedule_rounded,
            selected: _filterOpenNow,
            onTap: () => setState(() => _filterOpenNow = !_filterOpenNow),
          ),
          AppPill(
            label: 'Food',
            icon: Icons.restaurant_rounded,
            selected: _filterFood,
            onTap: () => setState(() => _filterFood = !_filterFood),
          ),
          AppPill(
            label: 'Transit',
            icon: Icons.train_rounded,
            selected: _filterTransit,
            onTap: () => setState(() => _filterTransit = !_filterTransit),
          ),
          AppPill(
            label: 'Accessible',
            icon: Icons.accessible_rounded,
            selected: _filterAccessible,
            onTap: () =>
                setState(() => _filterAccessible = !_filterAccessible),
          ),
        ],
      ),
    );
  }

  Widget _buildResults(
    BuildContext context,
    AsyncValue<List<Shop>> shopsAsync,
    AsyncValue<List<Building>> buildingsAsync,
    AsyncValue<List<Bridge>> bridgesAsync,
    String query,
    String? selectedCat,
  ) {
    if (shopsAsync.isLoading ||
        buildingsAsync.isLoading ||
        bridgesAsync.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (shopsAsync.hasError) {
      return Center(child: Text('Error: ${shopsAsync.error}'));
    }
    if (buildingsAsync.hasError) {
      return Center(child: Text('Error: ${buildingsAsync.error}'));
    }
    if (bridgesAsync.hasError) {
      return Center(child: Text('Error: ${bridgesAsync.error}'));
    }

    final shops = shopsAsync.value ?? const <Shop>[];
    final buildings = buildingsAsync.value ?? const <Building>[];
    final bridges = bridgesAsync.value ?? const <Bridge>[];

    final buildingMap = {for (final b in buildings) b.id: b};
    final accessibleBuildingIds = _computeAccessibleBuildings(bridges);

    final filtered = shops.where((shop) {
      final q = query.toLowerCase();
      final building = buildingMap[shop.buildingId];

      final matchesQuery = query.isEmpty ||
          shop.name.toLowerCase().contains(q) ||
          shop.description.toLowerCase().contains(q) ||
          (building?.name.toLowerCase().contains(q) ?? false);

      final matchesCategory =
          selectedCat == null || shop.category.name == selectedCat;

      final matchesOpenNow = !_filterOpenNow || _isOpenNow(shop.hours);
      final matchesFood = !_filterFood || shop.category == ShopCategory.food;
      final matchesTransit = !_filterTransit ||
          shop.category == ShopCategory.transit ||
          (building?.amenities.contains('transit') ?? false);
      final matchesAccessible =
          !_filterAccessible || accessibleBuildingIds.contains(shop.buildingId);

      return matchesQuery &&
          matchesCategory &&
          matchesOpenNow &&
          matchesFood &&
          matchesTransit &&
          matchesAccessible;
    }).toList();

    filtered.sort((a, b) {
      final byBuilding = (buildingMap[a.buildingId]?.name ?? a.buildingId)
          .compareTo(buildingMap[b.buildingId]?.name ?? b.buildingId);
      if (byBuilding != 0) return byBuilding;
      return a.name.compareTo(b.name);
    });

    if (filtered.isEmpty) {
      final theme = Theme.of(context);
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: AppPalette.brand,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: AppPalette.brand.withValues(alpha: 0.3),
                    blurRadius: 22,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: const Icon(Icons.travel_explore_rounded,
                  size: 44, color: Colors.white),
            ),
            const SizedBox(height: 18),
            Text('No matches yet', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Try changing filters or searching another building',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ).animate().fadeIn(duration: 260.ms).scale(
          begin: const Offset(0.96, 0.96), end: const Offset(1, 1));
    }

    final grouped = <String, List<Shop>>{};
    for (final shop in filtered) {
      grouped.putIfAbsent(shop.buildingId, () => <Shop>[]).add(shop);
    }
    final groupKeys = grouped.keys.toList()
      ..sort((a, b) => (buildingMap[a]?.name ?? a)
          .compareTo(buildingMap[b]?.name ?? b));

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(
          16, 0, 16, AppSpacing.bottomScrollClearance),
      itemCount: groupKeys.length,
      itemBuilder: (context, index) {
        final buildingId = groupKeys[index];
        final building = buildingMap[buildingId];
        final shopsInBuilding = grouped[buildingId]!;

        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _buildBuildingGroupCard(
            context,
            building,
            shopsInBuilding,
            accessibleBuildingIds.contains(buildingId),
          )
              .animate()
              .fadeIn(duration: 280.ms, delay: (index * 45).ms)
              .slideY(begin: 0.08, end: 0, delay: (index * 45).ms),
        );
      },
    );
  }

  Set<String> _computeAccessibleBuildings(List<Bridge> bridges) {
    final set = <String>{};
    for (final bridge in bridges) {
      if (bridge.status != 'open') continue;
      if (!bridge.isAccessible) continue;
      set.add(bridge.fromBuildingId);
      set.add(bridge.toBuildingId);
    }
    return set;
  }

  Widget _buildBuildingGroupCard(BuildContext context, Building? building,
      List<Shop> shops, bool isAccessible) {
    final theme = Theme.of(context);

    return GlassCard(
      padding: EdgeInsets.zero,
      accent: AppPalette.brand,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppPalette.brand,
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: const Icon(Icons.location_city_rounded,
                      size: 18, color: Colors.white),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        building?.name ?? shops.first.buildingId,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        '${shops.length} place${shops.length == 1 ? '' : 's'}',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                if (isAccessible)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppPalette.transit.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.accessible_rounded,
                            size: 11, color: AppPalette.transit),
                        SizedBox(width: 3),
                        Text(
                          'Accessible',
                          style: TextStyle(
                            color: AppPalette.transit,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          ...shops.map((shop) => _buildShopRow(context, shop, building)),
        ],
      ),
    );
  }

  Widget _buildShopRow(BuildContext context, Shop shop, Building? building) {
    final theme = Theme.of(context);
    final saved = _savedShopIds.contains(shop.id);
    final catColor = AppPalette.categoryColor(shop.category.name);
    final openNow = _isOpenNow(shop.hours);

    return InkWell(
      onTap: () => _showShopDetail(context, shop, building?.name),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
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
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        shop.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall,
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 3),
                            decoration: BoxDecoration(
                              color: catColor.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              shop.category.label,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: catColor,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Icon(
                            openNow
                                ? Icons.schedule_rounded
                                : Icons.schedule_outlined,
                            size: 12,
                            color: openNow
                                ? AppPalette.transit
                                : theme.textTheme.bodySmall?.color,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            openNow ? 'Open now' : 'Closed now',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: openNow
                                  ? AppPalette.transit
                                  : theme.textTheme.bodySmall?.color,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _actionButton(
                  icon: Icons.visibility_rounded,
                  label: 'Preview on map',
                  onTap: () {
                    if (building != null) {
                      ref.read(selectedBuildingProvider.notifier).state =
                          building;
                      context.go('/map');
                    }
                  },
                ),
                _actionButton(
                  icon: Icons.navigation_rounded,
                  label: 'Navigate',
                  onTap: () {
                    if (building != null) {
                      ref.read(routeToProvider.notifier).state = building;
                      context.go('/route');
                    }
                  },
                  accent: true,
                ),
                _actionButton(
                  icon: saved
                      ? Icons.bookmark_rounded
                      : Icons.bookmark_outline_rounded,
                  label: saved ? 'Saved' : 'Save',
                  onTap: () {
                    setState(() {
                      if (saved) {
                        _savedShopIds.remove(shop.id);
                      } else {
                        _savedShopIds.add(shop.id);
                      }
                    });
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _actionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool accent = false,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final neutralBg = isDark
        ? Colors.white.withValues(alpha: 0.06)
        : AppPalette.brand.withValues(alpha: 0.07);
    final fg = accent ? Colors.white : AppPalette.brand;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: accent ? AppPalette.brand : neutralBg,
        borderRadius: BorderRadius.circular(12),
        boxShadow: accent
            ? [
                BoxShadow(
                  color: AppPalette.brand.withValues(alpha: 0.3),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                )
              ]
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 14, color: fg),
                const SizedBox(width: 5),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: fg,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  bool _isOpenNow(String hours) {
    return OpeningHours.parse(hours).statusAt(DateTime.now()).open;
  }

  Widget _buildCategoryChip(
      BuildContext context, String? value, String label, String? selected) {
    final isSelected = value == selected;
    return AppPill(
      label: label,
      selected: isSelected,
      onTap: () => ref.read(selectedCategoryProvider.notifier).state = value,
    );
  }

  void _showShopDetail(BuildContext context, Shop shop, String? buildingName) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => ShopDetailSheet(shop: shop, buildingName: buildingName),
    );
  }

  IconData _categoryIcon(ShopCategory cat) {
    switch (cat) {
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
