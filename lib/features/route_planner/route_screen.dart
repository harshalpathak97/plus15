import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import '../../core/constants/app_constants.dart';
import '../../data/models/building.dart';
import '../../data/models/saved_route.dart';
import '../../data/graph/pathfinder.dart';
import '../../shared/providers/providers.dart';
import 'widgets/route_option_card.dart';
import 'widgets/step_list.dart';

class RouteScreen extends ConsumerStatefulWidget {
  const RouteScreen({super.key});

  @override
  ConsumerState<RouteScreen> createState() => _RouteScreenState();
}

class _RouteScreenState extends ConsumerState<RouteScreen> {
  List<RouteResult>? _results;
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final buildingsAsync = ref.watch(buildingsProvider);
    final from = ref.watch(routeFromProvider);
    final to = ref.watch(routeToProvider);
    final walkingSpeed = ref.watch(walkingSpeedProvider);

    return Scaffold(
      body: SafeArea(
        child: buildingsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Error: $e')),
          data: (buildings) => ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text('Route Planner', style: theme.textTheme.displayMedium)
                  .animate()
                  .fadeIn(duration: 400.ms)
                  .slideX(begin: -0.1, end: 0),
              const SizedBox(height: 4),
              Text('Find the best path through Plus 15',
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: theme.textTheme.bodySmall?.color))
                  .animate()
                  .fadeIn(duration: 400.ms, delay: 100.ms),
              const SizedBox(height: 20),
              _buildLocationSelector(context, buildings, true, from,
                      allowUseMyLocation: true)
                  .animate()
                  .fadeIn(duration: 400.ms, delay: 150.ms),
              const SizedBox(height: 10),
              Center(
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.swap_vert,
                      size: 20, color: theme.colorScheme.primary),
                ),
              ),
              const SizedBox(height: 10),
              _buildLocationSelector(context, buildings, false, to)
                  .animate()
                  .fadeIn(duration: 400.ms, delay: 200.ms),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: from != null && to != null
                      ? () => _calculateRoutes(from, to)
                      : null,
                  icon: const Icon(Icons.route, size: 18),
                  label: const Text('Find Routes'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ).animate().fadeIn(duration: 400.ms, delay: 250.ms),
              if (_results != null && _results!.isNotEmpty) ...[
                const SizedBox(height: 24),
                Text('Route Options', style: theme.textTheme.titleLarge)
                    .animate()
                    .fadeIn(duration: 300.ms),
                const SizedBox(height: 12),
                SizedBox(
                  height: 124,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: _results!.length,
                    itemBuilder: (context, index) {
                      final r = _results![index];
                      return Padding(
                        padding: const EdgeInsets.only(right: 10),
                        child: RouteOptionCard(
                          title: _modeTitle(r.modeName),
                          icon: _modeIcon(r.modeName),
                          distance: r.totalDistanceM,
                          bridges: r.bridgeCount,
                          time: AppConstants.estimateWalkTimeMinutes(
                            r.totalDistanceM,
                            speedKmh: walkingSpeed,
                          ),
                          floorChanges: r.floorChanges,
                          scenicScore: r.scenicScore,
                          isAccessible: r.fullyAccessible,
                          isSelected: _selectedIndex == index,
                          onTap: () => setState(() => _selectedIndex = index),
                        ),
                      )
                          .animate()
                          .fadeIn(duration: 300.ms, delay: (100 * index).ms)
                          .slideX(
                              begin: 0.2,
                              end: 0,
                              duration: 300.ms,
                              delay: (100 * index).ms);
                    },
                  ),
                ),
                const SizedBox(height: 20),
                StepList(
                  path: _results![_selectedIndex].path,
                  buildings: buildings,
                  bridges: ref.watch(bridgesProvider).value ?? [],
                ).animate().fadeIn(duration: 300.ms, delay: 200.ms),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _startNavigation,
                        icon: const Icon(Icons.navigation, size: 18),
                        label: const Text('Start'),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _saveRoute,
                        icon: const Icon(Icons.bookmark_add_outlined, size: 18),
                        label: const Text('Save'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ],
                ).animate().fadeIn(duration: 300.ms, delay: 300.ms),
              ],
              if (_results != null && _results!.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 40),
                  child: Center(
                    child: Column(
                      children: [
                        Icon(Icons.route,
                            size: 56, color: theme.textTheme.bodySmall?.color),
                        const SizedBox(height: 12),
                        Text('No route found',
                            style: theme.textTheme.titleMedium),
                        const SizedBox(height: 4),
                        Text('These buildings may not be connected',
                            style: theme.textTheme.bodySmall),
                      ],
                    ),
                  ),
                ).animate().fadeIn(duration: 300.ms),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLocationSelector(
    BuildContext context,
    List<Building> buildings,
    bool isFrom,
    Building? selected, {
    bool allowUseMyLocation = false,
  }) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: () => _showBuildingPicker(context, buildings, isFrom),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: theme.inputDecorationTheme.fillColor,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color:
                    (isFrom ? const Color(0xFF22C55E) : const Color(0xFFEF4444))
                        .withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                isFrom ? Icons.trip_origin : Icons.location_on,
                size: 16,
                color:
                    isFrom ? const Color(0xFF22C55E) : const Color(0xFFEF4444),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                selected?.name ??
                    (isFrom ? 'Choose starting point' : 'Choose destination'),
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: selected != null
                      ? null
                      : theme.textTheme.bodySmall?.color,
                ),
              ),
            ),
            if (allowUseMyLocation)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: InkWell(
                  onTap: () => _useMyLocationAsStart(buildings),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'Use my location',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
            Icon(Icons.chevron_right,
                size: 20, color: theme.textTheme.bodySmall?.color),
          ],
        ),
      ),
    );
  }

  void _showBuildingPicker(
      BuildContext context, List<Building> buildings, bool isFrom) {
    final searchController = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            final query = searchController.text.toLowerCase();
            final filtered = buildings
                .where((b) => b.name.toLowerCase().contains(query))
                .toList();
            return DraggableScrollableSheet(
              initialChildSize: 0.7,
              maxChildSize: 0.9,
              minChildSize: 0.4,
              expand: false,
              builder: (context, controller) {
                return Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context).scaffoldBackgroundColor,
                    borderRadius:
                        const BorderRadius.vertical(top: Radius.circular(20)),
                  ),
                  child: Column(
                    children: [
                      const SizedBox(height: 12),
                      Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Theme.of(context).dividerColor,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: TextField(
                          controller: searchController,
                          onChanged: (_) => setModalState(() {}),
                          decoration: const InputDecoration(
                            hintText: 'Search buildings...',
                            prefixIcon: Icon(Icons.search, size: 20),
                          ),
                          autofocus: true,
                        ),
                      ),
                      Expanded(
                        child: ListView.builder(
                          controller: controller,
                          itemCount: filtered.length,
                          itemBuilder: (_, i) {
                            final b = filtered[i];
                            return ListTile(
                              leading:
                                  const Icon(Icons.location_city, size: 20),
                              title: Text(b.name),
                              subtitle: b.address.isNotEmpty
                                  ? Text(b.address,
                                      style: const TextStyle(fontSize: 12))
                                  : null,
                              onTap: () {
                                if (isFrom) {
                                  ref.read(routeFromProvider.notifier).state =
                                      b;
                                } else {
                                  ref.read(routeToProvider.notifier).state = b;
                                }
                                Navigator.pop(context);
                                setState(() => _results = null);
                              },
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Future<void> _calculateRoutes(Building from, Building to) async {
    final pathfinder = await ref.read(pathfinderProvider.future);
    final results = pathfinder.findParetoRoutes(from.id, to.id);
    setState(() {
      _results = results;
      _selectedIndex = 0;
    });
  }

  String _modeTitle(String mode) {
    switch (mode) {
      case 'fastest':
        return 'Fastest';
      case 'accessible':
        return 'Accessible';
      case 'scenic':
        return 'Scenic';
      case 'explorer':
        return 'Explorer';
      default:
        return mode;
    }
  }

  IconData _modeIcon(String mode) {
    switch (mode) {
      case 'accessible':
        return Icons.accessible_rounded;
      case 'scenic':
        return Icons.visibility_rounded;
      case 'explorer':
        return Icons.explore_rounded;
      case 'fastest':
      default:
        return Icons.bolt_rounded;
    }
  }

  void _startNavigation() {
    if (_results == null || _results!.isEmpty) return;
    HapticFeedback.mediumImpact();
    final selected = _results![_selectedIndex];
    final to = ref.read(routeToProvider);
    ref.read(activeRouteProvider.notifier).state = selected.path;
    ref.read(activeRouteDistanceProvider.notifier).state =
        selected.totalDistanceM;
    if (to != null) {
      ref.read(navigationSessionProvider.notifier).start(
            destinationId: to.id,
            mode: selected.modeName,
            routePath: selected.path,
            totalDistanceM: selected.totalDistanceM,
          );
    }
    context.go('/map');
  }

  Future<void> _useMyLocationAsStart(List<Building> buildings) async {
    final loc = await ref.read(locationStreamProvider.future);
    if (loc == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Location unavailable. Choose a starting building.'),
        ),
      );
      return;
    }

    Building? nearest;
    var bestDistance = double.infinity;
    for (final building in buildings) {
      final d = _distanceM(loc, LatLng(building.lat, building.lng));
      if (d < bestDistance) {
        bestDistance = d;
        nearest = building;
      }
    }

    if (nearest != null) {
      ref.read(routeFromProvider.notifier).state = nearest;
      setState(() => _results = null);
    }
  }

  double _distanceM(LatLng from, LatLng to) {
    const meter = Distance();
    return meter(from, to);
  }

  void _saveRoute() {
    if (_results == null || _results!.isEmpty) return;
    final from = ref.read(routeFromProvider);
    final to = ref.read(routeToProvider);
    if (from == null || to == null) return;

    final selectedMode = _results![_selectedIndex].modeName;
    final nameController =
        TextEditingController(text: '${from.name} → ${to.name}');
    bool isRoutine = false;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setDialogState) {
          return AlertDialog(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Text('Save Route'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(labelText: 'Route Name'),
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  title: const Text('Routine Route'),
                  subtitle: const Text('Quick launch from map',
                      style: TextStyle(fontSize: 12)),
                  value: isRoutine,
                  onChanged: (v) => setDialogState(() => isRoutine = v),
                  contentPadding: EdgeInsets.zero,
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  final now = DateTime.now();
                  final saved = SavedRoute(
                    id: '${from.id}_${to.id}_${now.millisecondsSinceEpoch}',
                    name: nameController.text,
                    fromId: from.id,
                    toId: to.id,
                    routeType: selectedMode,
                    createdAt: now,
                    isRoutine: isRoutine,
                  );
                  ref.read(savedRoutesProvider.notifier).add(saved);
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text('Route saved!'),
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  );
                },
                child: const Text('Save'),
              ),
            ],
          );
        });
      },
    );
  }
}
