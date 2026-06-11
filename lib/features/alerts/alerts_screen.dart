import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_palette.dart';
import '../../core/theme/app_spacing.dart';
import '../../data/models/bridge.dart';
import '../../data/models/building.dart';
import '../../shared/providers/providers.dart';
import '../../shared/widgets/glass_card.dart';

/// Live +15 network conditions. Closed and limited-access skywalk segments are
/// derived directly from the bridge graph (status / accessibility), so this
/// screen always reflects what routing will actually avoid.
///
/// This is "conditional chrome" in the IA: it's reachable from the Explore
/// header's alert bell, and it owns a genuinely delightful empty state for the
/// (common) case where the whole network is open.
class AlertsScreen extends ConsumerWidget {
  const AlertsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final bridges = ref.watch(bridgesProvider).valueOrNull ?? const <Bridge>[];
    final buildings =
        ref.watch(buildingsProvider).valueOrNull ?? const <Building>[];
    final buildingMap = {for (final b in buildings) b.id: b};

    final closed =
        bridges.where((b) => b.status != 'open').toList(growable: false);
    final limited = bridges
        .where((b) => b.status == 'open' && !b.isAccessible)
        .toList(growable: false);

    final hasAlerts = closed.isNotEmpty || limited.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
        ),
        title: const Text('Network status'),
      ),
      body: hasAlerts
          ? ListView(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.xxxl),
              children: [
                _summaryBanner(theme, closed.length, limited.length),
                if (closed.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.xl),
                  _heading(theme, 'Closed segments', closed.length),
                  const SizedBox(height: AppSpacing.md),
                  ...closed.map((b) => _alertCard(
                        context,
                        ref,
                        bridge: b,
                        buildingMap: buildingMap,
                        closed: true,
                      )),
                ],
                if (limited.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.xl),
                  _heading(theme, 'Limited access', limited.length),
                  const SizedBox(height: AppSpacing.md),
                  ...limited.map((b) => _alertCard(
                        context,
                        ref,
                        bridge: b,
                        buildingMap: buildingMap,
                        closed: false,
                      )),
                ],
              ],
            )
          : _allClear(context, theme),
    );
  }

  Widget _summaryBanner(ThemeData theme, int closed, int limited) {
    final parts = <String>[
      if (closed > 0) '$closed closed',
      if (limited > 0) '$limited limited',
    ];
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppPalette.warning.withValues(alpha: 0.10),
        borderRadius: AppRadii.rCard,
        border: Border.all(color: AppPalette.warning.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline_rounded,
              color: AppPalette.warning, size: 20),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              'Routing is already avoiding these — ${parts.join(' · ')}.',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: AppMotion.normal);
  }

  Widget _heading(ThemeData theme, String title, int count) {
    final muted = theme.brightness == Brightness.dark
        ? AppPalette.inkMutedDark
        : AppPalette.inkMuted;
    return Row(
      children: [
        Text(title.toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(
                color: muted, fontWeight: FontWeight.w700, letterSpacing: 1.1)),
        const SizedBox(width: 6),
        Text('$count',
            style: theme.textTheme.labelSmall?.copyWith(color: muted)),
      ],
    );
  }

  Widget _alertCard(
    BuildContext context,
    WidgetRef ref, {
    required Bridge bridge,
    required Map<String, Building> buildingMap,
    required bool closed,
  }) {
    final theme = Theme.of(context);
    final from = buildingMap[bridge.fromBuildingId];
    final to = buildingMap[bridge.toBuildingId];
    final fromName = from?.name ?? bridge.fromBuildingId;
    final toName = to?.name ?? bridge.toBuildingId;
    final accent = closed ? AppPalette.danger : AppPalette.warning;

    return GlassCard(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      accent: accent,
      onTap: from == null
          ? null
          : () {
              HapticFeedback.lightImpact();
              ref.read(selectedBuildingProvider.notifier).state = from;
              context.go('/map');
            },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(closed ? Icons.block_rounded : Icons.stairs_rounded,
                  color: accent, size: 18),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text('$fromName ↔ $toName',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            closed
                ? 'Closed — this bridge is currently out of service.'
                : 'Stairs only — no step-free access on this segment.',
            style: theme.textTheme.bodySmall,
          ),
          if (from != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Icon(Icons.map_rounded,
                    size: 14, color: theme.textTheme.bodySmall?.color),
                const SizedBox(width: 4),
                Text('Show on map',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(fontWeight: FontWeight.w600)),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _allClear(BuildContext context, ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppPalette.origin.withValues(alpha: 0.12),
              ),
              child: const Icon(Icons.check_circle_rounded,
                  color: AppPalette.origin, size: 44),
            ).animate().scale(
                duration: AppMotion.slow, curve: Curves.easeOutBack),
            const SizedBox(height: AppSpacing.xl),
            Text('All clear',
                style: theme.textTheme.headlineMedium, textAlign: TextAlign.center),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'The entire +15 network is open right now. We’ll flag any closures or limited segments here the moment they appear.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.textTheme.bodySmall?.color),
            ),
          ],
        ).animate().fadeIn(duration: AppMotion.normal),
      ),
    );
  }
}
