import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_palette.dart';
import '../../core/theme/app_spacing.dart';
import '../../routing/network.dart';
import '../../data/models/opening_hours.dart';
import '../../data/models/shop.dart';
import '../../shared/providers/providers.dart';
import '../../shared/widgets/app_pill.dart';
import '../../shared/widgets/brand_logo.dart';
import '../../shared/widgets/glass_card.dart';
import '../../shared/widgets/screen_header.dart';
import '../../shared/widgets/shimmer_loading.dart';
import '../shop_detail/shop_detail_sheet.dart';
import '../../routing/conditions.dart';

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
        ref.watch(buildingsProvider).valueOrNull ?? const <NetBuilding>[];
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
      BuildContext context, List<Shop> shops, Map<String, NetBuilding> bMap) {
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
                AppSpacing.lg, AppSpacing.bottomScrollClearance),
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

  List<Shop> _applyFilters(List<Shop> shops, Map<String, NetBuilding> bMap) {
    final q = _query.trim().toLowerCase();
    return shops.where((s) {
      if (_category != null && s.category != _category) return false;
      if (_openNowOnly &&
          !OpeningHours.parse(s.hours).statusAt(calgaryNow()).open) {
        return false;
      }
      if (q.isEmpty) return true;
      final buildingName = bMap[s.buildingId]?.name.toLowerCase() ?? '';
      return s.name.toLowerCase().contains(q) ||
          s.description.toLowerCase().contains(q) ||
          buildingName.contains(q);
    }).toList(growable: false);
  }

  List<({NetBuilding? building, List<Shop> shops})> _groupByBuilding(
      List<Shop> shops, Map<String, NetBuilding> bMap) {
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
        hintText: 'Search places or buildings',
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
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: 6),
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
      BuildContext context, NetBuilding? building, List<Shop> shops) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final muted = scheme.onSurfaceVariant;

    return GlassCard(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            child: Row(
              children: [
                Icon(Icons.apartment_rounded, size: 22, color: scheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        building?.name ?? 'On the network',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium,
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
                const SizedBox(width: 8),
                Text(
                  shops.length == 1 ? '1 place' : '${shops.length} places',
                  style: theme.textTheme.labelMedium?.copyWith(color: muted),
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

  Widget _shopRow(BuildContext context, Shop shop, NetBuilding? building) {
    final theme = Theme.of(context);
    final status = OpeningHours.parse(shop.hours).statusAt(calgaryNow());

    return InkWell(
      onTap: () => showShopDetail(context, shop),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 64),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 10, 10),
          child: Row(
            children: [
              BrandLogo(shop: shop, size: 44),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      shop.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      status.known ? status.label : shop.category.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: !status.known
                            ? null
                            : status.open
                                ? AppPalette.origin
                                : AppPalette.danger,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded,
                  color: theme.colorScheme.onSurfaceVariant),
            ],
          ),
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
            Icon(Icons.storefront_outlined,
                size: 40, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: AppSpacing.lg),
            Text('Nothing matches', style: theme.textTheme.titleMedium),
            const SizedBox(height: AppSpacing.xs),
            Text(
              _openNowOnly
                  ? 'Only places with listed hours show under Open now. Try clearing the filter.'
                  : 'Try a different name or clear the filters.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
