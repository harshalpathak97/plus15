import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_palette.dart';
import '../../core/theme/app_spacing.dart';
import '../../data/models/saved_route.dart';
import '../../routing/conditions.dart';
import '../../routing/network.dart';
import '../../routing/router.dart';
import '../../shared/providers/providers.dart';
import '../../shared/widgets/location_prompt.dart';
import '../../shared/widgets/screen_header.dart';
import '../ai/widgets/ai_concierge_sheet.dart';
import '../ai/services/ai_service.dart' show aiConfigured;
import '../transit/street_directions.dart';
import 'widgets/route_option_card.dart';
import 'widgets/step_list.dart';

class RouteScreen extends ConsumerStatefulWidget {
  const RouteScreen({super.key});

  @override
  ConsumerState<RouteScreen> createState() => _RouteScreenState();
}

/// One distinct route and the profiles that produced it.
class _Option {
  final PlannedRoute route;
  final List<RouteProfile> profiles;
  _Option(this.route, this.profiles);
  String get title => route.throughClosures.isNotEmpty
      ? 'If the closed bridge reopens'
      : profiles.length == RouteProfile.values.length
          ? 'Recommended'
          : profiles.map((p) => p.label).join(' · ');
}

class _RouteScreenState extends ConsumerState<RouteScreen> {
  List<_Option>? _results;
  List<String> _unavailable = const [];
  int _selectedIndex = 0;
  bool _busy = false;
  bool _locating = false;

  /// Set when the user chose "Use my location" as the start.
  LatLng? _fromLocation;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Start from where you are when we already know it (no prompt).
      if (ref.read(routeFromMyLocationProvider) ||
          ref.read(routeFromProvider) == null &&
              ref.read(locationStreamProvider).valueOrNull != null) {
        _useMyLocationAsStart();
      } else {
        _recalculate();
      }
    });
  }

  /// Start from a building (or nothing): no longer from the phone's location.
  void _clearLocationStart() {
    _fromLocation = null;
    ref.read(routeFromMyLocationProvider.notifier).state = false;
  }

  bool get _ready =>
      (ref.read(routeFromProvider) != null || _fromLocation != null) &&
      ref.read(routeToProvider) != null;

  /// Routes update as soon as both ends are set (from here, the map, search
  /// or Ask AI).
  void _recalculate() {
    if (!mounted) return;
    if (_ready) {
      _calculateRoutes(ref.read(routeFromProvider), ref.read(routeToProvider)!);
    } else if (_results != null) {
      setState(() => _results = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final buildingsAsync = ref.watch(buildingsProvider);
    final from = ref.watch(routeFromProvider);
    final to = ref.watch(routeToProvider);
    final walkingSpeed = ref.watch(walkingSpeedProvider);
    ref.listen(routeFromProvider, (_, __) => _recalculate());
    ref.listen(routeToProvider, (_, __) => _recalculate());
    ref.listen(accessibilityModeProvider, (_, __) => _recalculate());
    ref.listen(routeFromMyLocationProvider, (_, mine) {
      if (mine && _fromLocation == null) _useMyLocationAsStart();
    });

    final selected = _results == null || _results!.isEmpty ? null : _results![_selectedIndex];

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: buildingsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(
            child: TextButton(
              onPressed: () => ref.invalidate(networkProvider),
              child: const Text('Couldn’t load the +15 network. Try again'),
            ),
          ),
          data: (buildings) => ListView(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.bottomScrollClearance),
            children: [
              const ScreenHeader('Navigate', 'Indoor routes through Calgary’s +15'),
              const SizedBox(height: AppSpacing.xl),
              _endpoints(context, buildings, from, to),
              if (_busy) ...[
                const SizedBox(height: AppSpacing.xl),
                const LinearProgressIndicator(minHeight: 2),
              ],
              if (from == null && _fromLocation == null || to == null) ...[
                const SizedBox(height: AppSpacing.xxl),
                _hint(theme),
              ],
              if (selected != null) ...[
                const SizedBox(height: AppSpacing.xl),
                for (var i = 0; i < _results!.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: RouteOptionCard(
                      title: _results![i].title,
                      icon: _results![i].route.throughClosures.isNotEmpty
                          ? Icons.block_rounded
                          : _profileIcon(_results![i].profiles.first),
                      distance: _results![i].route.lengthM,
                      bridges: _results![i].route.bridgeCount,
                      time: AppConstants.estimateWalkTimeMinutes(_results![i].route.lengthM,
                          speedKmh: walkingSpeed),
                      isAccessible: _results![i].route.stepFree && !_results![i].route.usesStreet,
                      isSelected: _selectedIndex == i,
                      previewOnly: _results![i].route.throughClosures.isNotEmpty,
                      badge: _results![i].route.throughClosures.isNotEmpty
                          ? 'Preview only · bridge closed now'
                          : _results![i].route.usesStreet
                              ? 'Includes an outdoor walk'
                              : null,
                      onTap: () => setState(() => _selectedIndex = i),
                    ),
                  ).animate().fadeIn(duration: 220.ms, delay: (60 * i).ms),
                for (final u in _unavailable)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.xs),
                    child: Text(u, style: theme.textTheme.bodySmall),
                  ),
                if (selected.route.previewOnly) ...[
                  const SizedBox(height: AppSpacing.md),
                  PreviewBanner(route: selected.route),
                ],
                const SizedBox(height: AppSpacing.lg),
                _actions(selected.route),
                if (!selected.route.previewOnly || selected.route.opensAt != null) ...[
                  const SizedBox(height: AppSpacing.lg),
                  WalkToEntranceCard(route: selected.route),
                ],
                const SizedBox(height: AppSpacing.xl),
                RouteNotices(route: selected.route),
                const SizedBox(height: AppSpacing.lg),
                StepList(route: selected.route, showDebug: ref.watch(debugGraphProvider)),
                if (ref.watch(debugGraphProvider)) RouteExplanation(route: selected.route),
                if (aiConfigured) ...[
                  const SizedBox(height: AppSpacing.lg),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () => showAiConcierge(context,
                          initialPrompt: 'Tell me about the +15 route from '
                              '${from?.name ?? 'my location'} to ${to!.name}. '
                              'Anything to grab on the way?'),
                      icon: const Icon(Icons.auto_awesome_rounded, size: 18),
                      label: const Text('Ask +15 about this route'),
                    ),
                  ),
                ],
                if (to != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  Text('Not in the +15 yet?', style: theme.textTheme.titleSmall),
                  const SizedBox(height: AppSpacing.xs),
                  Text('Get to ${from?.name ?? to.name} by transit, on foot or by car.',
                      style: theme.textTheme.bodySmall),
                  const SizedBox(height: AppSpacing.sm),
                  StreetDirectionsRow(building: from ?? to),
                ],
              ],
              if (_results != null && _results!.isEmpty) _noRoute(theme),
            ],
          ),
        ),
      ),
    );
  }

  Widget _hint(ThemeData theme) => Column(
        children: [
          Icon(Icons.alt_route_rounded, size: 40, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(height: AppSpacing.md),
          Text('Choose where you’re starting and where you’re going.',
              textAlign: TextAlign.center,
              style:
                  theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ],
      );

  Widget _noRoute(ThemeData theme) {
    final to = ref.read(routeToProvider);
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xxl),
      child: Column(
        children: [
          Icon(Icons.wrong_location_outlined, size: 40, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(height: AppSpacing.md),
          Text('No route found', style: theme.textTheme.titleMedium),
          const SizedBox(height: AppSpacing.xs),
          for (final u in _unavailable)
            Text(u,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          if (to != null && _fromLocation != null) ...[
            const SizedBox(height: AppSpacing.lg),
            Text('Get to ${to.name}', style: theme.textTheme.titleSmall),
            const SizedBox(height: AppSpacing.sm),
            StreetDirectionsRow(building: to),
          ],
        ],
      ),
    ).animate().fadeIn(duration: 250.ms);
  }

  Widget _actions(PlannedRoute route) {
    final start = route.previewOnly
        ? FilledButton.icon(
            onPressed: _previewOnMap,
            icon: const Icon(Icons.map_outlined),
            label: const Text('Preview on map'),
          )
        : FilledButton.icon(
            onPressed: _startNavigation,
            icon: const Icon(Icons.navigation_rounded),
            label: const Text('Start'),
          );
    return Row(
      children: [
        Expanded(flex: 3, child: start),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          flex: 2,
          child: OutlinedButton.icon(
            onPressed: route.throughClosures.isEmpty ? _saveRoute : null,
            icon: const Icon(Icons.bookmark_add_outlined),
            label: const Text('Save'),
          ),
        ),
      ],
    );
  }

  /// From / To in one card, with swap — the familiar maps-app pattern.
  Widget _endpoints(
      BuildContext context, List<NetBuilding> buildings, NetBuilding? from, NetBuilding? to) {
    final scheme = Theme.of(context).colorScheme;
    final shop = ref.watch(routeToShopProvider);
    return Material(
      color: scheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadii.rCard,
        side: BorderSide(color: scheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        children: [
          Expanded(
            child: Column(
              children: [
                _endpointRow(
                  context,
                  icon: Icons.trip_origin_rounded,
                  color: AppPalette.origin,
                  label: _fromLocation != null ? 'My location' : from?.name,
                  placeholder: 'Choose start',
                  onTap: () => _showBuildingPicker(context, buildings, true),
                  trailing: IconButton(
                    tooltip: 'Start from my location',
                    icon: _locating
                        ? const SizedBox.square(
                            dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : Icon(Icons.my_location_rounded,
                            color:
                                _fromLocation != null ? scheme.primary : scheme.onSurfaceVariant),
                    onPressed: _useMyLocationAsStart,
                  ),
                ),
                Divider(height: 1, indent: 52, color: scheme.outlineVariant),
                _endpointRow(
                  context,
                  icon: Icons.location_on_rounded,
                  color: AppPalette.destination,
                  label: shop?.name ?? to?.name,
                  sublabel: shop == null ? null : 'in ${to?.name}',
                  placeholder: 'Choose destination',
                  onTap: () => _showBuildingPicker(context, buildings, false),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Swap start and destination',
            icon: const Icon(Icons.swap_vert_rounded),
            // "My location" can't be a destination.
            onPressed: _fromLocation != null
                ? null
                : () {
                    HapticFeedback.selectionClick();
                    final f = ref.read(routeFromProvider);
                    final t = ref.read(routeToProvider);
                    setState(_clearLocationStart);
                    ref.read(routeFromProvider.notifier).state = t;
                    ref.read(routeToProvider.notifier).state = f;
                  },
          ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }

  Widget _endpointRow(
    BuildContext context, {
    required IconData icon,
    required Color color,
    required String? label,
    String? sublabel,
    required String placeholder,
    required VoidCallback onTap,
    Widget? trailing,
  }) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 60),
        child: Padding(
          padding:
              EdgeInsets.only(left: AppSpacing.lg, right: trailing == null ? AppSpacing.lg : 0),
          child: Row(
            children: [
              Icon(icon, size: 20, color: color),
              const SizedBox(width: AppSpacing.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label ?? placeholder,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: label == null ? theme.colorScheme.onSurfaceVariant : null,
                        fontWeight: label == null ? null : FontWeight.w600,
                      ),
                    ),
                    if (sublabel != null)
                      Text(sublabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                  ],
                ),
              ),
              if (trailing != null) trailing,
            ],
          ),
        ),
      ),
    );
  }

  void _showBuildingPicker(BuildContext context, List<NetBuilding> buildings, bool isFrom) {
    final searchController = TextEditingController();
    final sorted = [...buildings.where((b) => b.isRoutable)]
      ..sort((a, b) => a.name.compareTo(b.name));
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          final query = searchController.text.toLowerCase();
          // Former names (e.g. "Shell Centre" → 400 4th) match too.
          int rank(NetBuilding b) {
            final n = b.name.toLowerCase();
            if (n == query || n == 'the $query') return 0;
            if (n.startsWith(query)) return 1;
            if (n.split(' ').any((w) => w.startsWith(query))) return 2;
            return 3;
          }

          final filtered = sorted
              .where((b) =>
                  b.name.toLowerCase().contains(query) ||
                  b.aliases.any((a) => a.toLowerCase().contains(query)))
              .toList();
          if (query.isNotEmpty) mergeSort(filtered, compare: (a, b) => rank(a) - rank(b));
          return DraggableScrollableSheet(
            initialChildSize: 0.75,
            maxChildSize: 0.92,
            minChildSize: 0.4,
            expand: false,
            builder: (context, controller) => Column(
              children: [
                Padding(
                  padding:
                      const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.sm),
                  child: TextField(
                    controller: searchController,
                    onChanged: (_) => setModalState(() {}),
                    autofocus: true,
                    decoration: InputDecoration(
                      hintText: isFrom ? 'Start from…' : 'Where to?',
                      prefixIcon: const Icon(Icons.search_rounded),
                    ),
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    controller: controller,
                    itemCount: filtered.length,
                    itemBuilder: (_, i) {
                      final b = filtered[i];
                      final tColor = AppPalette.typeColor(b.type);
                      return ListTile(
                        leading: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: tColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(_typeIcon(b.type), size: 20, color: tColor),
                        ),
                        title: Text(b.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: b.address.isNotEmpty || b.aliases.isNotEmpty
                            ? Text(
                                [
                                  if (b.address.isNotEmpty) b.address,
                                  if (b.aliases.isNotEmpty) 'Formerly ${b.aliases.join(', ')}',
                                ].join(' · '),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis)
                            : null,
                        onTap: () {
                          Navigator.pop(context);
                          if (isFrom) {
                            setState(_clearLocationStart);
                            ref.read(routeFromProvider.notifier).state = b;
                          } else {
                            ref.read(routeToProvider.notifier).state = b;
                          }
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _calculateRoutes(NetBuilding? from, NetBuilding to) async {
    setState(() => _busy = true);
    final router = await ref.read(routerProvider.future);
    final origin = _fromLocation != null
        ? RouteOrigin.location(_fromLocation!.latitude, _fromLocation!.longitude)
        : RouteOrigin.building(from!.id);
    final now = calgaryNow();
    final preferred = defaultProfile(ref.read(accessibilityModeProvider));
    final profiles = [preferred, ...RouteProfile.values.where((p) => p != preferred)];
    final options = <_Option>[];
    final unavailable = <String>[];
    PlannedRoute? viaClosed;
    for (final p in profiles) {
      final r = router.route(origin, to.id, profile: p, at: now);
      if (p == preferred) viaClosed = r.viaClosed;
      if (!r.ok) {
        unavailable.add('${p.label}: ${r.unavailableReason}');
        continue;
      }
      final same = options.where((o) => _sameRoute(o.route, r.route!));
      if (same.isNotEmpty) {
        same.first.profiles.add(p);
      } else {
        options.add(_Option(r.route!, [p]));
      }
    }
    // A view-only route through bridges closed today, for planning.
    if (viaClosed != null && !options.any((o) => _sameRoute(o.route, viaClosed!))) {
      options.add(_Option(viaClosed, [preferred]));
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _results = options;
      _unavailable = options.isEmpty ? unavailable.take(1).toList() : unavailable;
      _selectedIndex = 0;
    });
  }

  static bool _sameRoute(PlannedRoute a, PlannedRoute b) =>
      a.edgeIds.length == b.edgeIds.length &&
      [for (var i = 0; i < a.edgeIds.length; i++) a.edgeIds[i] == b.edgeIds[i]].every((x) => x);

  static IconData _profileIcon(RouteProfile p) => switch (p) {
        RouteProfile.fastest => Icons.verified_rounded,
        RouteProfile.accessible => Icons.accessible_rounded,
        RouteProfile.mostlyIndoors => Icons.roofing_rounded,
      };

  /// Shows a route on the map without starting navigation.
  void _previewOnMap() {
    if (_results == null || _results!.isEmpty) return;
    HapticFeedback.selectionClick();
    ref.read(navigationSessionProvider.notifier).stop();
    ref.read(activeRouteProvider.notifier).state = _results![_selectedIndex].route;
    context.go('/map');
  }

  void _startNavigation() {
    if (_results == null || _results!.isEmpty) return;
    HapticFeedback.mediumImpact();
    final selected = _results![_selectedIndex].route;
    ref.read(activeRouteProvider.notifier).state = selected;
    ref.read(navigationSessionProvider.notifier).start(route: selected);
    context.go('/map');
  }

  /// Start from the phone's location. Outside the +15 the route first walks
  /// you outdoors to the best nearby door.
  Future<void> _useMyLocationAsStart() async {
    if (_locating) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _locating = true);
    LatLng? loc;
    try {
      if (await ensureLocation(context, ref) && mounted) {
        ref.read(routeFromMyLocationProvider.notifier).state = true;
        loc = await ref.read(locationStreamProvider.future).timeout(const Duration(seconds: 12));
      }
    } catch (_) {
      messenger.showSnackBar(const SnackBar(
          content: Text("Couldn't find your location. Choose a starting building.")));
    } finally {
      if (mounted) setState(() => _locating = false);
    }
    if (!mounted) return;
    if (loc == null) {
      ref.read(routeFromMyLocationProvider.notifier).state = false;
      return;
    }
    setState(() => _fromLocation = loc);
    ref.read(routeFromProvider.notifier).state = null;
    _recalculate();
  }

  static IconData _typeIcon(String type) => switch (type) {
        'hotel' => Icons.hotel_rounded,
        'retail' => Icons.shopping_bag_rounded,
        'landmark' => Icons.star_rounded,
        'entertainment' => Icons.theaters_rounded,
        'government' => Icons.account_balance_rounded,
        'convention' => Icons.business_rounded,
        'transit' => Icons.train_rounded,
        'parking' => Icons.local_parking_rounded,
        'residential' => Icons.home_rounded,
        _ => Icons.apartment_rounded,
      };

  void _saveRoute() {
    if (_results == null || _results!.isEmpty) return;
    final from = ref.read(routeFromProvider);
    final to = ref.read(routeToProvider);
    if (from == null || to == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Choose a starting building to save this route.')));
      return;
    }
    final nameController = TextEditingController(text: '${from.name} → ${to.name}');
    var isRoutine = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Save route'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              const SizedBox(height: AppSpacing.md),
              SwitchListTile(
                title: const Text('Show on the map'),
                subtitle: const Text('Start it in one tap from Explore'),
                value: isRoutine,
                onChanged: (v) => setDialogState(() => isRoutine = v),
                contentPadding: EdgeInsets.zero,
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                final now = calgaryNow();
                ref.read(savedRoutesProvider.notifier).add(SavedRoute(
                      id: '${from.id}_${to.id}_${now.millisecondsSinceEpoch}',
                      name: nameController.text.trim().isEmpty
                          ? '${from.name} → ${to.name}'
                          : nameController.text.trim(),
                      fromId: from.id,
                      toId: to.id,
                      routeType: _results![_selectedIndex].profiles.first.name,
                      createdAt: now,
                      isRoutine: isRoutine,
                    ));
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context)
                    .showSnackBar(const SnackBar(content: Text('Route saved')));
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}
