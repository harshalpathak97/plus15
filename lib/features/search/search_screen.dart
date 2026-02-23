import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../data/models/building.dart';
import '../../data/models/bridge.dart';
import '../../data/models/shop.dart';
import '../../shared/providers/providers.dart';
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
    final theme = Theme.of(context);
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
                  Text('Search', style: theme.textTheme.displayMedium)
                      .animate()
                      .fadeIn(duration: 400.ms)
                      .slideX(begin: -0.1, end: 0),
                  const SizedBox(height: 4),
                  Text(
                    'Explore shops and services with live smart filters',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: theme.textTheme.bodySmall?.color),
                  ).animate().fadeIn(duration: 400.ms, delay: 100.ms),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _searchController,
                    onChanged: (v) =>
                        ref.read(searchQueryProvider.notifier).state = v,
                    decoration: InputDecoration(
                      hintText: 'Search places, food, or services...',
                      prefixIcon: const Icon(Icons.search, size: 20),
                      suffixIcon: query.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 18),
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
          _quickFilterChip(
            label: 'Open now',
            selected: _filterOpenNow,
            onTap: () => setState(() => _filterOpenNow = !_filterOpenNow),
          ),
          _quickFilterChip(
            label: 'Food',
            selected: _filterFood,
            onTap: () => setState(() => _filterFood = !_filterFood),
          ),
          _quickFilterChip(
            label: 'Transit',
            selected: _filterTransit,
            onTap: () => setState(() => _filterTransit = !_filterTransit),
          ),
          _quickFilterChip(
            label: 'Accessible',
            selected: _filterAccessible,
            onTap: () =>
                setState(() => _filterAccessible = !_filterAccessible),
          ),
        ],
      ),
    );
  }

  Widget _quickFilterChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
        selected: selected,
        onSelected: (_) => onTap(),
        visualDensity: VisualDensity.compact,
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
            Icon(Icons.travel_explore,
                size: 60, color: theme.textTheme.bodySmall?.color),
            const SizedBox(height: 12),
            Text('No matches yet', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Try changing filters or searching another building',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ).animate().fadeIn(duration: 260.ms);
    }

    final grouped = <String, List<Shop>>{};
    for (final shop in filtered) {
      grouped.putIfAbsent(shop.buildingId, () => <Shop>[]).add(shop);
    }
    final groupKeys = grouped.keys.toList()
      ..sort((a, b) => (buildingMap[a]?.name ?? a)
          .compareTo(buildingMap[b]?.name ?? b));

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
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
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF151922) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : const Color(0xFFE2E8F0),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.22 : 0.06),
            blurRadius: 20,
            offset: const Offset(0, 6),
          )
        ],
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF3B82F6), Color(0xFF06B6D4)],
                    ),
                    borderRadius: BorderRadius.circular(10),
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
                      color: const Color(0xFF22C55E).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'Accessible',
                      style: TextStyle(
                        color: Color(0xFF16A34A),
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
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
                    color: _categoryColor(shop.category).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(_categoryIcon(shop.category),
                      size: 18, color: _categoryColor(shop.category)),
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
                                horizontal: 6, vertical: 3),
                            decoration: BoxDecoration(
                              color: _categoryColor(shop.category)
                                  .withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              shop.category.label,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: _categoryColor(shop.category),
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Icon(
                            _isOpenNow(shop.hours)
                                ? Icons.schedule
                                : Icons.schedule_outlined,
                            size: 12,
                            color: _isOpenNow(shop.hours)
                                ? const Color(0xFF22C55E)
                                : theme.textTheme.bodySmall?.color,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            _isOpenNow(shop.hours) ? 'Open now' : 'Closed now',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: _isOpenNow(shop.hours)
                                  ? const Color(0xFF16A34A)
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
    return Material(
      color: accent
          ? const Color(0xFF2563EB)
          : const Color(0xFF334155).withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon,
                  size: 14,
                  color: accent ? Colors.white : const Color(0xFF2563EB)),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: accent ? Colors.white : const Color(0xFF2563EB),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  bool _isOpenNow(String hours) {
    final now = DateTime.now();
    final weekday = now.weekday; // Mon=1
    final nowMinutes = (now.hour * 60) + now.minute;

    final segments = hours.split(',');
    for (final segment in segments) {
      final s = segment.trim();
      final appliesWeekday =
          (s.contains('Mon-Fri') && weekday >= 1 && weekday <= 5) ||
              (s.contains('Sat-Sun') && weekday >= 6 && weekday <= 7) ||
              (!s.contains('Mon-Fri') && !s.contains('Sat-Sun'));
      if (!appliesWeekday) continue;

      final match = RegExp(r'(\d{1,2}):(\d{2})-(\d{1,2}):(\d{2})')
          .firstMatch(s);
      if (match == null) continue;

      final start = (int.parse(match.group(1)!) * 60) +
          int.parse(match.group(2)!);
      final end =
          (int.parse(match.group(3)!) * 60) + int.parse(match.group(4)!);
      if (nowMinutes >= start && nowMinutes <= end) {
        return true;
      }
    }

    return false;
  }

  Widget _buildCategoryChip(
      BuildContext context, String? value, String label, String? selected) {
    final isSelected = value == selected;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(
          label,
          style: TextStyle(
              fontSize: 12,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400),
        ),
        selected: isSelected,
        onSelected: (_) =>
            ref.read(selectedCategoryProvider.notifier).state = value,
        visualDensity: VisualDensity.compact,
      ),
    );
  }

  void _showShopDetail(BuildContext context, Shop shop, String? buildingName) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => ShopDetailSheet(shop: shop, buildingName: buildingName),
    );
  }

  Color _categoryColor(ShopCategory cat) {
    switch (cat) {
      case ShopCategory.food:
        return const Color(0xFFEF4444);
      case ShopCategory.retail:
        return const Color(0xFF8B5CF6);
      case ShopCategory.services:
        return const Color(0xFF3B82F6);
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
