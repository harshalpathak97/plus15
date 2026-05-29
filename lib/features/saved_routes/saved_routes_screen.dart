import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import '../../data/models/saved_route.dart';
import '../../shared/providers/providers.dart';

class SavedRoutesScreen extends ConsumerWidget {
  const SavedRoutesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final savedRoutes = ref.watch(savedRoutesProvider);
    final buildingsAsync = ref.watch(buildingsProvider);

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Saved Routes', style: theme.textTheme.displayMedium)
                      .animate()
                      .fadeIn(duration: 400.ms)
                      .slideX(begin: -0.1, end: 0),
                  const SizedBox(height: 4),
                  Text(
                    '${savedRoutes.length} route${savedRoutes.length != 1 ? 's' : ''} saved',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: theme.textTheme.bodySmall?.color),
                  ).animate().fadeIn(duration: 400.ms, delay: 100.ms),
                ],
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
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 108),
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
                                padding: const EdgeInsets.only(right: 20),
                                margin: const EdgeInsets.only(bottom: 10),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFEF4444),
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: const Icon(Icons.delete_outline,
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
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.bookmark_outline,
                size: 48, color: theme.colorScheme.primary.withValues(alpha: 0.5)),
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
    final modeLabel = route.routeType[0].toUpperCase() +
        route.routeType.substring(1);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: () => _goRoute(context, ref, route),
        onLongPress: () => _showRenameDialog(context, ref, route),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(modeIcon,
                    color: theme.colorScheme.primary, size: 20),
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
                                  ?.copyWith(fontWeight: FontWeight.w600),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                        ),
                        if (route.isRoutine)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF59E0B)
                                  .withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.bolt,
                                    size: 10, color: Color(0xFFF59E0B)),
                                SizedBox(width: 2),
                                Text('Routine',
                                    style: TextStyle(
                                        fontSize: 10,
                                        color: Color(0xFFF59E0B),
                                        fontWeight: FontWeight.w500)),
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
                    Text(modeLabel,
                        style: theme.textTheme.labelSmall),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: () => _goRoute(context, ref, route),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 8),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  minimumSize: Size.zero,
                ),
                child: const Text('Go', style: TextStyle(fontSize: 13)),
              ),
            ],
          ),
        ),
      ),
    );
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
