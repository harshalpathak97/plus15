import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_palette.dart';
import '../../core/theme/app_spacing.dart';
import '../../routing/conditions.dart';
import '../../routing/network.dart';
import '../../shared/providers/providers.dart';
import '../../shared/widgets/glass_card.dart';

/// Network status: hours, City closures (which routing removes from the
/// graph), stairs-only links and known data gaps. Everything shown here comes
/// from network.json / closures.json, the same data routing uses.
class AlertsScreen extends ConsumerWidget {
  const AlertsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final net = ref.watch(networkProvider).valueOrNull;
    final cond = ref.watch(conditionsProvider).valueOrNull;
    final feed = ref.watch(closuresProvider).valueOrNull;
    if (net == null || cond == null || feed == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final now = calgaryNow();
    final status = cond.networkStatusAt(now);
    final active = cond.activeAt(now);
    final upcoming = [
      for (final c in feed.closures)
        if (c.start != null && c.start!.isAfter(now)) c
    ];
    final ended = cond.recentlyEndedAt(now);
    final stairs = {
      for (final e in net.edges)
        if (e.stairsRequired && e.bridgeNumber != null) e.bridgeNumber!
    }.map((n) => net.bridgeByNumber[n]!).toList();
    final unresolved = (net.issues['unresolvedBuildings'] as List? ?? const [])
        .cast<Map<String, dynamic>>();

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
        ),
        title: const Text('Network status'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.xxxl),
        children: [
          _hoursCard(theme, status, net),
          const SizedBox(height: AppSpacing.xl),
          _heading(theme, 'Closed now', active.length),
          const SizedBox(height: AppSpacing.md),
          if (active.isEmpty)
            Text('No published closures right now.', style: theme.textTheme.bodyMedium),
          for (final c in active) _closureCard(context, ref, net, cond, c, AppPalette.danger),
          if (ended.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xl),
            _heading(theme, 'Probably reopened (not confirmed)', ended.length),
            const SizedBox(height: AppSpacing.md),
            for (final c in ended) _closureCard(context, ref, net, cond, c, AppPalette.warning),
          ],
          if (upcoming.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xl),
            _heading(theme, 'Upcoming', upcoming.length),
            const SizedBox(height: AppSpacing.md),
            for (final c in upcoming) _closureCard(context, ref, net, cond, c, AppPalette.warning),
          ],
          const SizedBox(height: AppSpacing.sm),
          Text(
            'From ${feed.sourceUrl}, checked ${_date(DateTime.tryParse(feed.retrieved))}. '
            'Short-notice closures may not be listed.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: AppSpacing.xl),
          _heading(theme, 'Stairs only', stairs.length),
          const SizedBox(height: AppSpacing.md),
          for (final b in stairs)
            GlassCard(
              margin: const EdgeInsets.only(bottom: AppSpacing.sm),
              accent: AppPalette.warning,
              child: Row(
                children: [
                  const Icon(Icons.stairs_rounded, color: AppPalette.warning, size: 18),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text('${b.name}${b.crossing != null ? ' (over ${b.crossing})' : ''}',
                        style: theme.textTheme.bodyMedium),
                  ),
                ],
              ),
            ),
          const SizedBox(height: AppSpacing.xl),
          _heading(theme, 'About the data', unresolved.length + 2),
          const SizedBox(height: AppSpacing.md),
          _note(theme,
              'The +15 is two networks. The downtown core (Bankers Hall, The CORE, Bow Valley '
              'Square, Eau Claire…) and the east side (TELUS Convention Centre, Calgary Tower, '
              'City Hall, Bow Valley College) don’t connect at +15, so routes between them '
              'include a short, marked outdoor walk.'),
          _note(theme,
              'The link between Castell Building and Bow Valley College South Campus is on the '
              'official City map but not in City walkway data. Routes that use it say so.'),
          for (final u in unresolved)
            _note(theme, '${u['name']}: ${u['reason']}'),
        ],
      ).animate().fadeIn(duration: AppMotion.normal),
    );
  }

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];
  static String _date(DateTime? d) =>
      d == null ? 'recently' : '${_months[d.month - 1]} ${d.day}, ${d.year}';
  static String _clock(int minute) {
    final h = minute ~/ 60, m = minute % 60;
    final h12 = h % 12 == 0 ? 12 : h % 12;
    return '$h12${m == 0 ? '' : ':${m.toString().padLeft(2, '0')}'} ${h < 12 ? 'a.m.' : 'p.m.'}';
  }

  Widget _hoursCard(ThemeData theme, NetworkStatus status, Plus15Network net) {
    final color = status.open ? AppPalette.origin : AppPalette.danger;
    final h = net.hours;
    Widget row(String day, List<int> w) => Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(
            children: [
              Expanded(child: Text(day, style: theme.textTheme.bodyMedium)),
              Text('${_clock(w[0])} – ${_clock(w[1])}',
                  style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
            ],
          ),
        );
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.circle, size: 10, color: color),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text('+15 ${status.label.toLowerCase()}',
                    style: theme.textTheme.titleMedium?.copyWith(color: color)),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          row('Monday to Friday', h.weekday),
          row('Weekends & holidays', h.weekendHoliday),
          const SizedBox(height: AppSpacing.sm),
          Text('Closed December 25. Some bridges may keep shorter hours on weekends and holidays.',
              style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }

  Widget _heading(ThemeData theme, String title, int count) => Row(
        children: [
          Expanded(child: Text(title, style: theme.textTheme.titleMedium)),
          Text('$count',
              style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ],
      );

  Widget _note(ThemeData theme, String text) => Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline_rounded, size: 18, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: AppSpacing.sm),
            Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
          ],
        ),
      );

  Widget _closureCard(BuildContext context, WidgetRef ref, Plus15Network net,
      Conditions cond, Closure c, Color accent) {
    final theme = Theme.of(context);
    final bridges = {
      for (final id in cond.edgesClosedBy(c))
        if (net.edgeById[id]?.bridgeNumber != null) net.edgeById[id]!.bridgeNumber!
    }.toList()
      ..sort();
    final target = c.buildings.isNotEmpty ? net.buildingById[c.buildings.first] : null;
    return GlassCard(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      accent: accent,
      onTap: target == null
          ? null
          : () {
              HapticFeedback.lightImpact();
              ref.read(selectedBuildingProvider.notifier).state = target;
              context.go('/map');
            },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.block_rounded, color: accent, size: 18),
              const SizedBox(width: AppSpacing.sm),
              Expanded(child: Text(c.title, style: theme.textTheme.titleSmall)),
              if (target != null)
                Icon(Icons.chevron_right_rounded, color: theme.colorScheme.onSurfaceVariant),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            [
              if (c.start != null && c.start!.isAfter(calgaryNow())) 'From ${_date(c.start)}',
              c.end == null
                  ? 'Until further notice'
                  : '${c.endIsEstimate ? 'Expected to reopen' : 'Reopens'} '
                      '${_date(c.end)}',
            ].join(' · '),
            style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          if (c.reason.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(c.reason, style: theme.textTheme.bodySmall),
          ],
          const SizedBox(height: 2),
          Text('Routes go around it.', style: theme.textTheme.bodySmall),
          if (ref.watch(debugGraphProvider))
            Text('City bridges: ${bridges.join(', ')}', style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}
