import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
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
                  Text('Search',
                          style: theme.textTheme.displayMedium)
                      .animate()
                      .fadeIn(duration: 400.ms)
                      .slideX(begin: -0.1, end: 0),
                  const SizedBox(height: 4),
                  Text('Find shops, food, and services',
                          style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.textTheme.bodySmall?.color))
                      .animate()
                      .fadeIn(duration: 400.ms, delay: 100.ms),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _searchController,
                    onChanged: (v) =>
                        ref.read(searchQueryProvider.notifier).state = v,
                    decoration: InputDecoration(
                      hintText: 'Search places...',
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
                  SizedBox(
                    height: 36,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        _buildCategoryChip(context, null, 'All', selectedCat),
                        ...ShopCategory.values.map(
                          (c) => _buildCategoryChip(
                              context, c.name, c.label, selectedCat),
                        ),
                      ],
                    ),
                  ).animate().fadeIn(duration: 400.ms, delay: 200.ms),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: shopsAsync.when(
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('Error: $e')),
                data: (shops) {
                  var filtered = shops.where((s) {
                    final matchesQuery = query.isEmpty ||
                        s.name.toLowerCase().contains(query.toLowerCase()) ||
                        s.description
                            .toLowerCase()
                            .contains(query.toLowerCase());
                    final matchesCat =
                        selectedCat == null || s.category.name == selectedCat;
                    return matchesQuery && matchesCat;
                  }).toList();

                  if (filtered.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.search_off,
                              size: 56,
                              color: theme.textTheme.bodySmall?.color),
                          const SizedBox(height: 12),
                          Text('No results found',
                              style: theme.textTheme.titleMedium),
                          const SizedBox(height: 4),
                          Text('Try a different search or category',
                              style: theme.textTheme.bodySmall),
                        ],
                      ),
                    ).animate().fadeIn(duration: 300.ms);
                  }

                  return buildingsAsync.when(
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (e, _) => Center(child: Text('Error: $e')),
                    data: (buildings) {
                      final buildingMap = {
                        for (final b in buildings) b.id: b
                      };
                      return ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: filtered.length,
                        itemBuilder: (context, index) {
                          final shop = filtered[index];
                          final building = buildingMap[shop.buildingId];
                          return _buildShopCard(context, shop, building?.name)
                              .animate()
                              .fadeIn(
                                  duration: 300.ms,
                                  delay: (50 * index).ms)
                              .slideY(
                                  begin: 0.1,
                                  end: 0,
                                  duration: 300.ms,
                                  delay: (50 * index).ms);
                        },
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryChip(
      BuildContext context, String? value, String label, String? selected) {
    final isSelected = value == selected;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(label, style: TextStyle(fontSize: 12, fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400)),
        selected: isSelected,
        onSelected: (_) =>
            ref.read(selectedCategoryProvider.notifier).state = value,
        visualDensity: VisualDensity.compact,
      ),
    );
  }

  Widget _buildShopCard(BuildContext context, Shop shop, String? buildingName) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: () => _showShopDetail(context, shop, buildingName),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _categoryColor(shop.category).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(_categoryIcon(shop.category),
                    color: _categoryColor(shop.category), size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(shop.name,
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    if (buildingName != null)
                      Text(buildingName, style: theme.textTheme.bodySmall),
                    const SizedBox(height: 2),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color:
                            _categoryColor(shop.category).withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        shop.category.label,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                          color: _categoryColor(shop.category),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () {
                  final buildings = ref.read(buildingsProvider).value;
                  final building =
                      buildings?.where((b) => b.id == shop.buildingId).firstOrNull;
                  if (building != null) {
                    ref.read(routeToProvider.notifier).state = building;
                    context.go('/route');
                  }
                },
                icon: Icon(Icons.directions,
                    color: theme.colorScheme.primary, size: 20),
                tooltip: 'Navigate',
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showShopDetail(
      BuildContext context, Shop shop, String? buildingName) {
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
