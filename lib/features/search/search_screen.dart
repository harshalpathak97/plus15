import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_palette.dart';
import '../../core/theme/app_spacing.dart';
import '../../data/models/opening_hours.dart';
import '../../data/models/shop.dart';
import '../../routing/conditions.dart';
import '../../routing/network.dart';
import '../../shared/providers/providers.dart';
import '../../shared/widgets/app_pill.dart';
import '../../shared/widgets/brand_logo.dart';
import '../../shared/widgets/section_header.dart';
import '../ai/widgets/ai_concierge_sheet.dart';
import '../ai/services/kimi_ai_service.dart' show aiConfigured;
import '../shop_detail/shop_detail_sheet.dart';

/// Search places and buildings on the +15.
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  late final _controller = TextEditingController(text: ref.read(searchQueryProvider));
  bool _openNow = false;
  bool _accessible = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _setQuery(String v) => ref.read(searchQueryProvider.notifier).state = v;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // The query can be set from elsewhere (map pills) while this tab sleeps.
    ref.listen(searchQueryProvider, (_, q) {
      if (_controller.text != q) _controller.text = q;
    });
    final query = ref.watch(searchQueryProvider).trim().toLowerCase();
    final category = ref.watch(selectedCategoryProvider);
    final shops = ref.watch(shopsProvider).valueOrNull;
    final net = ref.watch(networkProvider).valueOrNull;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.xs, AppSpacing.sm, AppSpacing.lg, 0),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Back to map',
                    icon: const Icon(Icons.arrow_back_rounded),
                    onPressed: () => context.go('/map'),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      autofocus: query.isEmpty,
                      onChanged: (v) => setState(() => _setQuery(v)),
                      textInputAction: TextInputAction.search,
                      decoration: InputDecoration(
                        hintText: 'Shops, food, services, buildings',
                        prefixIcon: const Icon(Icons.search_rounded),
                        suffixIcon: query.isEmpty
                            ? null
                            : IconButton(
                                tooltip: 'Clear',
                                icon: const Icon(Icons.close_rounded),
                                onPressed: () => setState(() {
                                  _controller.clear();
                                  _setQuery('');
                                }),
                              ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Grows with the text size instead of clipping it.
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 6, AppSpacing.lg, 6),
              child: Row(
                children: [
                  AppPill(
                    label: 'Open now',
                    icon: Icons.schedule_rounded,
                    selected: _openNow,
                    onTap: () => setState(() => _openNow = !_openNow),
                  ),
                  AppPill(
                    label: 'Step-free',
                    icon: Icons.accessible_rounded,
                    selected: _accessible,
                    onTap: () => setState(() => _accessible = !_accessible),
                  ),
                  for (final c in const [
                    ShopCategory.food,
                    ShopCategory.retail,
                    ShopCategory.services,
                    ShopCategory.health,
                    ShopCategory.entertainment,
                    ShopCategory.hotel,
                    ShopCategory.washroom,
                  ])
                    AppPill(
                      label: c.label,
                      selected: category == c.name,
                      onTap: () => ref.read(selectedCategoryProvider.notifier).state =
                          category == c.name ? null : c.name,
                    ),
                ],
              ),
            ),
            Expanded(
              child: shops == null || net == null
                  ? const Center(child: CircularProgressIndicator())
                  : _results(context, theme, shops, net, query, category),
            ),
          ],
        ),
      ),
    );
  }

  Widget _results(BuildContext context, ThemeData theme, List<Shop> shops, Plus15Network net,
      String query, String? category) {
    final bMap = net.buildingById;
    final stepFree = _accessible ? _stepFreeBuildings(net) : const <String>{};
    final now = calgaryNow();

    final places = shops.where((s) {
      final b = bMap[s.buildingId];
      if (category != null && s.category.name != category) return false;
      if (_openNow && !OpeningHours.parse(s.hours).statusAt(now).open) return false;
      if (_accessible && !stepFree.contains(s.buildingId)) return false;
      return query.isEmpty ||
          s.name.toLowerCase().contains(query) ||
          s.description.toLowerCase().contains(query) ||
          (b?.name.toLowerCase().contains(query) ?? false);
    }).toList()
      ..sort((a, b) => a.name.compareTo(b.name));

    final buildings = query.isEmpty || category != null || _openNow
        ? const <NetBuilding>[]
        : net.buildings
            .where((b) =>
                b.isRoutable &&
                (!_accessible || stepFree.contains(b.id)) &&
                (b.name.toLowerCase().contains(query) ||
                    b.aliases.any((a) => a.toLowerCase().contains(query))))
            .toList();

    if (places.isEmpty && buildings.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        children: [
          Icon(Icons.search_off_rounded, size: 40, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(height: AppSpacing.md),
          Text('No matches', textAlign: TextAlign.center, style: theme.textTheme.titleMedium),
          const SizedBox(height: AppSpacing.xs),
          Text(
            _openNow
                ? 'Open now only includes places with listed hours. Try clearing filters.'
                : aiConfigured
                    ? 'Try another name, or Ask +15.'
                    : 'Try another name or category.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          if (aiConfigured) ...[
            const SizedBox(height: AppSpacing.lg),
            Center(
              child: OutlinedButton.icon(
                onPressed: () => showAiConcierge(context,
                    initialPrompt: query.isEmpty ? null : 'Where can I find $query on the +15?'),
                icon: const Icon(Icons.auto_awesome_rounded),
                label: const Text('Ask +15'),
              ),
            ),
          ],
        ],
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(0, AppSpacing.sm, 0, AppSpacing.bottomScrollClearance),
      children: [
        if (buildings.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.xs),
            child: SectionHeader('Buildings'),
          ),
          for (final b in buildings.take(6)) _buildingRow(context, theme, b),
        ],
        if (places.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.xs),
            child: SectionHeader('Places', trailing: '${places.length}'),
          ),
          for (final s in places) _placeRow(context, theme, s, bMap[s.buildingId], now),
        ],
      ],
    );
  }

  Widget _buildingRow(BuildContext context, ThemeData theme, NetBuilding b) {
    return ListTile(
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: theme.colorScheme.primaryContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(Icons.apartment_rounded, color: theme.colorScheme.onPrimaryContainer),
      ),
      title: Text(b.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(b.address.isEmpty ? 'Building on the +15' : b.address,
          maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: IconButton(
        tooltip: 'Directions',
        icon: const Icon(Icons.directions_rounded),
        onPressed: () {
          ref.read(routeToProvider.notifier).state = b;
          context.go('/route');
        },
      ),
      onTap: () {
        HapticFeedback.selectionClick();
        ref.read(selectedBuildingProvider.notifier).state = b;
        context.go('/map');
      },
    );
  }

  Widget _placeRow(BuildContext context, ThemeData theme, Shop s, NetBuilding? b, DateTime now) {
    final status = OpeningHours.parse(s.hours).statusAt(now);
    final saved = ref.watch(savedPlacesProvider).contains(s.id);
    final muted = theme.colorScheme.onSurfaceVariant;
    return ListTile(
      leading: BrandLogo(shop: s, size: 44, heroTag: 'logo-${s.id}'),
      title: Text(s.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text.rich(
        TextSpan(children: [
          if (status.known)
            TextSpan(
              text: status.open ? 'Open · ' : 'Closed · ',
              style: TextStyle(
                  color: status.open
                      ? AppPalette.openText(Theme.of(context).brightness)
                      : AppPalette.danger,
                  fontWeight: FontWeight.w600),
            ),
          TextSpan(text: b?.name ?? s.category.label, style: TextStyle(color: muted)),
        ]),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: IconButton(
        tooltip: saved ? 'Remove from saved' : 'Save',
        icon: Icon(saved ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
            color: saved ? theme.colorScheme.primary : null),
        onPressed: () {
          HapticFeedback.selectionClick();
          ref.read(savedPlacesProvider.notifier).toggle(s.id);
        },
      ),
      onTap: () => showShopDetail(context, s),
    );
  }

  /// Buildings with a step-free +15 bridge and no official-map
  /// "no elevator to street" flag.
  static Set<String> _stepFreeBuildings(Plus15Network net) => {
        for (final b in net.buildings)
          if (!b.noElevatorToStreet &&
              b.nodeIds.any((n) => (net.edgesAt[n] ?? const <NetEdge>[])
                  .any((e) => e.isBridgeLike && !e.stairsRequired)))
            b.id
      };
}
