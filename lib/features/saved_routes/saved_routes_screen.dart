import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_palette.dart';
import '../../core/theme/app_spacing.dart';
import '../../data/models/saved_route.dart';
import '../../data/models/shop.dart';
import '../../routing/conditions.dart';
import '../../routing/network.dart';
import '../../routing/router.dart';
import '../../shared/providers/providers.dart';
import '../../shared/widgets/brand_logo.dart';
import '../../shared/widgets/screen_header.dart';
import '../shop_detail/shop_detail_sheet.dart';

/// Saved routes and saved places.
class SavedRoutesScreen extends ConsumerStatefulWidget {
  const SavedRoutesScreen({super.key});

  @override
  ConsumerState<SavedRoutesScreen> createState() => _SavedRoutesScreenState();
}

class _SavedRoutesScreenState extends ConsumerState<SavedRoutesScreen> {
  bool _places = false;

  @override
  Widget build(BuildContext context) {
    final routes = ref.watch(savedRoutesProvider);
    final placeIds = ref.watch(savedPlacesProvider);
    final shops = ref.watch(shopsProvider).valueOrNull ?? const <Shop>[];
    final places = shops.where((s) => placeIds.contains(s.id)).toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    final bMap =
        ref.watch(networkProvider).valueOrNull?.buildingById ?? const <String, NetBuilding>{};

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.bottomScrollClearance),
          children: [
            const ScreenHeader('Saved', 'Your routes and places'),
            const SizedBox(height: AppSpacing.lg),
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<bool>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(value: false, label: Text('Routes (${routes.length})')),
                  ButtonSegment(value: true, label: Text('Places (${places.length})')),
                ],
                selected: {_places},
                onSelectionChanged: (v) => setState(() => _places = v.first),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            if (!_places && routes.isEmpty)
              _empty(context, Icons.bookmark_border_rounded, 'No saved routes yet',
                  'Plan a route and tap Save to keep it here.', 'Plan a route', '/route'),
            if (_places && places.isEmpty)
              _empty(
                  context,
                  Icons.storefront_outlined,
                  'No saved places yet',
                  'Tap the bookmark on any shop or service to save it.',
                  'Browse the directory',
                  '/directory'),
            if (!_places)
              for (final r in routes) _routeTile(context, r, bMap),
            if (_places)
              for (final s in places)
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
                  leading: BrandLogo(shop: s, size: 44),
                  title: Text(s.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(bMap[s.buildingId]?.name ?? s.category.label,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  trailing: IconButton(
                    tooltip: 'Remove from saved',
                    icon:
                        Icon(Icons.bookmark_rounded, color: Theme.of(context).colorScheme.primary),
                    onPressed: () => ref.read(savedPlacesProvider.notifier).toggle(s.id),
                  ),
                  onTap: () => showShopDetail(context, s),
                ),
          ],
        ),
      ),
    );
  }

  Widget _empty(
      BuildContext context, IconData icon, String title, String body, String cta, String path) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xxxl),
      child: Column(
        children: [
          Icon(icon, size: 40, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(height: AppSpacing.md),
          Text(title, style: theme.textTheme.titleMedium),
          const SizedBox(height: AppSpacing.xs),
          Text(body,
              textAlign: TextAlign.center,
              style:
                  theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          const SizedBox(height: AppSpacing.lg),
          OutlinedButton(onPressed: () => context.go(path), child: Text(cta)),
        ],
      ),
    );
  }

  Widget _routeTile(BuildContext context, SavedRoute r, Map<String, NetBuilding> bMap) {
    final theme = Theme.of(context);
    final from = bMap[r.fromId];
    final to = bMap[r.toId];
    final profile = profileFromName(r.routeType);
    return Dismissible(
      key: Key(r.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: AppSpacing.xl),
        decoration: BoxDecoration(
          color: AppPalette.danger,
          borderRadius: AppRadii.rControl,
        ),
        child: const Icon(Icons.delete_outline_rounded, color: Colors.white),
      ),
      onDismissed: (_) => _delete(context, r),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(r.isRoutine ? Icons.bolt_rounded : Icons.route_rounded,
              color: theme.colorScheme.onPrimaryContainer),
        ),
        title: Text(r.name, maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          '${profile.label}${r.isRoutine ? ' · on the map' : ''}'
          '${from == null || to == null ? ' · a building is no longer on the network' : ''}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton.filledTonal(
              tooltip: 'Start',
              icon: const Icon(Icons.navigation_rounded),
              onPressed: from == null || to == null ? null : () => _start(context, r),
            ),
            // Rename and delete, also reachable by long-press and swipe.
            PopupMenuButton<String>(
              tooltip: 'More',
              onSelected: (v) => v == 'rename' ? _rename(context, r) : _delete(context, r),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'rename', child: Text('Rename')),
                PopupMenuItem(value: 'delete', child: Text('Delete')),
              ],
            ),
          ],
        ),
        onTap: from == null || to == null
            ? null
            : () {
                ref.read(routeFromProvider.notifier).state = from;
                ref.read(routeToProvider.notifier).state = to;
                context.go('/route');
              },
        onLongPress: () => _rename(context, r),
      ),
    );
  }

  void _delete(BuildContext context, SavedRoute r) {
    ref.read(savedRoutesProvider.notifier).remove(r.id);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        persist: false, // auto-dismiss despite the action
        content: const Text('Route deleted'),
        action: SnackBarAction(
            label: 'Undo', onPressed: () => ref.read(savedRoutesProvider.notifier).add(r)),
      ));
  }

  /// Starts live navigation, or previews the route when the +15 is closed.
  Future<void> _start(BuildContext context, SavedRoute r) async {
    HapticFeedback.mediumImpact();
    final go = GoRouter.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final router = await ref.read(routerProvider.future);
    if (!mounted) return;
    final result = router.route(RouteOrigin.building(r.fromId), r.toId,
        profile: profileFromName(r.routeType), at: calgaryNow());
    // A route only blocked by a closure is still worth previewing.
    final route = result.route ?? result.viaClosed;
    if (route == null) {
      messenger
          .showSnackBar(SnackBar(content: Text(result.unavailableReason ?? 'Route unavailable.')));
      return;
    }
    ref.read(activeRouteProvider.notifier).state = route;
    if (route.previewOnly) {
      ref.read(navigationSessionProvider.notifier).stop();
      messenger.showSnackBar(SnackBar(
          content: Text(route.opensAt != null
              ? 'The +15 is closed now. Showing the route so you can plan ahead.'
              : 'This route goes through a closed bridge. Preview only.')));
    } else {
      ref.read(navigationSessionProvider.notifier).start(route: route);
    }
    go.go('/map');
  }

  void _rename(BuildContext context, SavedRoute r) {
    final controller = TextEditingController(text: r.name);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename route'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Name'),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                ref
                    .read(savedRoutesProvider.notifier)
                    .update(r.copyWith(name: controller.text.trim()));
              }
              Navigator.pop(ctx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}
