import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_palette.dart';
import '../../core/theme/app_spacing.dart';
import '../../data/models/saved_route.dart';
import '../../shared/providers/providers.dart';
import '../../shared/widgets/glass_card.dart';
import '../../shared/widgets/screen_header.dart';

class SavedRoutesScreen extends ConsumerWidget {
  const SavedRoutesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final savedRoutes = ref.watch(savedRoutesProvider);
    final buildingsAsync = ref.watch(buildingsProvider);

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: ScreenHeader(
                'Saved Routes',
                '${savedRoutes.length} route${savedRoutes.length != 1 ? 's' : ''} saved',
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: savedRoutes.isEmpty
                  ? _buildEmptyState(context)
                  : buildingsAsync.when(
                      loading: () =>
                          const Center(child: CircularProgressIndicator()),
                      error: (e, _) => Center(child: Text('Error: $e')),
                      data: (buildings) {
                        final buildingMap = {
                          for (final b in buildings) b.id: b
                        };
                        return ListView.builder(
                          padding: const EdgeInsets.fromLTRB(
                              16, 0, 16, AppSpacing.bottomScrollClearance),
                          itemCount: savedRoutes.length,
                          itemBuilder: (context, index) {
                            final route = savedRoutes[index];
                            final fromName =
                                buildingMap[route.fromId]?.name ?? route.fromId;
                            final toName =
                                buildingMap[route.toId]?.name ?? route.toId;
                            return Dismissible(
                              key: Key(route.id),
                              direction: DismissDirection.endToStart,
                              background: Container(
                                alignment: Alignment.centerRight,
                                padding: const EdgeInsets.only(right: 22),
                                margin: const EdgeInsets.only(bottom: 12),
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      AppPalette.destination
                                          .withValues(alpha: 0.85),
                                      AppPalette.destination,
                                    ],
                                  ),
                                  borderRadius: BorderRadius.circular(18),
                                ),
                                child: const Icon(Icons.delete_rounded,
                                    color: Colors.white),
                              ),
                              onDismissed: (_) {
                                ref
                                    .read(savedRoutesProvider.notifier)
                                    .remove(route.id);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: const Text('Route deleted'),
                                    behavior: SnackBarBehavior.floating,
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(10)),
                                  ),
                                );
                              },
                              child: _buildRouteCard(context, ref, route,
                                      fromName, toName)
                                  .animate()
                                  .fadeIn(
                                      duration: 300.ms,
                                      delay: (50 * index).ms)
                                  .slideX(
                                      begin: 0.1,
                                      end: 0,
                                      duration: 300.ms,
                                      delay: (50 * index).ms),
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

  Widget _buildEmptyState(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(26),
            decoration: BoxDecoration(
              gradient: AppPalette.brandGradient,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: AppPalette.brand.withValues(alpha: 0.35),
                  blurRadius: 24,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: const Icon(Icons.bookmark_rounded,
                size: 48, color: Colors.white),
          ),
          const SizedBox(height: 20),
          Text('No saved routes yet', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            'Plan a route and tap "Save" to\nadd it here for quick access',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: () => GoRouter.of(context).go('/route'),
            icon: const Icon(Icons.route, size: 18),
            label: const Text('Plan a Route'),
            style: FilledButton.styleFrom(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 500.ms).scale(begin: const Offset(0.95, 0.95), end: const Offset(1, 1), duration: 500.ms);
  }

  Widget _buildRouteCard(BuildContext context, WidgetRef ref,
      SavedRoute route, String fromName, String toName) {
    final theme = Theme.of(context);
    final modeIcon = _modeIcon(route.routeType);
    final modeColor = _modeColor(route.routeType);
    final modeLabel = route.routeType[0].toUpperCase() +
        route.routeType.substring(1);

    return GlassCard(
      margin: const EdgeInsets.only(bottom: 12),
      accent: LinearGradient(
        colors: [modeColor, modeColor.withValues(alpha: 0.6)],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ),
      onTap: () => _goRoute(context, ref, route),
      onLongPress: () => _showRenameDialog(context, ref, route),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: modeColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(modeIcon, color: modeColor, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(route.name,
                          style: theme.textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    ),
                    if (route.isRoutine)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppPalette.warning.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color:
                                  AppPalette.warning.withValues(alpha: 0.25)),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.bolt_rounded,
                                size: 11, color: AppPalette.warning),
                            SizedBox(width: 2),
                            Text('Routine',
                                style: TextStyle(
                                    fontSize: 10,
                                    color: AppPalette.warning,
                                    fontWeight: FontWeight.w700)),
                          ],
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text('$fromName → $toName',
                    style: theme.textTheme.bodySmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text(modeLabel, style: theme.textTheme.labelSmall),
              ],
            ),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: () {
              HapticFeedback.mediumImpact();
              _goRoute(context, ref, route);
            },
            icon: const Icon(Icons.navigation_rounded, size: 15),
            label: const Text('Go', style: TextStyle(fontSize: 13)),
            style: FilledButton.styleFrom(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              minimumSize: Size.zero,
            ),
          ),
        ],
      ),
    );
  }

  Color _modeColor(String mode) {
    switch (mode) {
      case 'accessible':
        return AppPalette.origin;
      case 'explorer':
        return AppPalette.skywalk;
      default:
        return AppPalette.brand;
    }
  }

  void _goRoute(
      BuildContext context, WidgetRef ref, SavedRoute route) async {
    final navigator = GoRouter.of(context);
    final pathfinder = await ref.read(pathfinderProvider.future);
    final result = pathfinder.findRoute(route.fromId, route.toId,
        mode: route.routeType);
    if (result != null) {
      ref.read(activeRouteProvider.notifier).state = result.path;
      ref.read(activeRouteDistanceProvider.notifier).state =
          result.totalDistance;
      ref.read(navigationSessionProvider.notifier).start(
            destinationId: route.toId,
            mode: route.routeType,
            routePath: result.path,
            totalDistanceM: result.totalDistance,
          );
      navigator.go('/map');
    }
  }

  void _showRenameDialog(
      BuildContext context, WidgetRef ref, SavedRoute route) {
    final controller = TextEditingController(text: route.name);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Rename Route'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Route Name'),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              ref.read(savedRoutesProvider.notifier).update(
                    route.copyWith(name: controller.text),
                  );
              Navigator.pop(ctx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  IconData _modeIcon(String mode) {
    switch (mode) {
      case 'accessible':
        return Icons.accessible;
      case 'explorer':
        return Icons.explore;
      default:
        return Icons.speed;
    }
  }
}
