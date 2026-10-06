import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_theme.dart';
import '../../../routing/directions.dart';
import '../../../routing/router.dart';

/// Turn-by-turn instructions generated from the route's graph transitions,
/// drawn as a timeline. Bridge numbers are City ids: debug only.
class StepList extends StatelessWidget {
  final PlannedRoute route;
  /// Highlights the instruction to follow next during live navigation.
  final int? currentStep;
  final bool showDebug;

  const StepList({super.key, required this.route, this.currentStep, this.showDebug = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final steps = route.steps;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Steps', style: theme.textTheme.titleMedium),
        const SizedBox(height: 12),
        for (var i = 0; i < steps.length; i++)
          _step(context, theme, scheme, steps[i], i, i == steps.length - 1)
              .animate()
              .fadeIn(duration: 220.ms, delay: (i * 25).ms),
      ],
    );
  }

  Widget _step(BuildContext context, ThemeData theme, ColorScheme scheme, RouteStep s, int i,
      bool isLast) {
    final current = currentStep == i;
    final color = _color(s, scheme);
    final outdoor = s.kind == 'outdoor' || s.kind == 'approach';
    final landmarks = s.kind == 'arrive' && s.landmarks.isNotEmpty ? s.landmarks : const <String>[];
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 32,
            child: Column(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: current ? color : color.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(_icon(s), size: 16, color: current ? scheme.surface : color),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      decoration: BoxDecoration(
                        color: outdoor ? AppPalette.warning.withValues(alpha: 0.5) : scheme.outlineVariant,
                        borderRadius: BorderRadius.circular(1),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(top: 4, bottom: isLast ? 0 : 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          s.text,
                          style: (current || s.kind == 'arrive'
                                  ? theme.textTheme.titleSmall
                                  : theme.textTheme.bodyMedium)
                              ?.copyWith(height: 1.4),
                        ),
                      ),
                      if (s.distanceM > 0) ...[
                        const SizedBox(width: 12),
                        Text('${s.distanceM.round()} m',
                            style: theme.textTheme.labelMedium?.copyWith(
                                color: scheme.onSurfaceVariant, fontFeatures: AppTheme.tabular)),
                      ],
                    ],
                  ),
                  if (s.caution != null) ...[
                    const SizedBox(height: 6),
                    _note(theme, Icons.warning_amber_rounded, s.caution!, AppPalette.warning),
                  ],
                  if (landmarks.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    _note(theme, Icons.storefront_outlined, landmarks.join(' · '),
                        scheme.onSurfaceVariant),
                  ],
                  if (showDebug && s.bridgeNumbers.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    _note(theme, Icons.signpost_outlined,
                        'City bridge ${s.bridgeNumbers.join(', ')}', scheme.onSurfaceVariant),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _note(ThemeData theme, IconData icon, String text, Color color) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(icon, size: 15, color: color),
          ),
          const SizedBox(width: 6),
          Expanded(child: Text(text, style: theme.textTheme.bodySmall?.copyWith(color: color))),
        ],
      );

  static Color _color(RouteStep s, ColorScheme scheme) => switch (s.kind) {
        'start' || 'approach' => AppPalette.origin,
        'arrive' => AppPalette.destination,
        'outdoor' || 'exit' || 'enter' || 'link' => AppPalette.warning,
        _ => scheme.primary,
      };

  static IconData _icon(RouteStep s) => switch (s.kind) {
        'start' => Icons.trip_origin_rounded,
        'approach' => Icons.my_location_rounded,
        'bridge' => s.caution == 'Stairs only' ? Icons.stairs_rounded : Icons.swap_horiz_rounded,
        'through' => Icons.meeting_room_rounded,
        'link' => Icons.help_outline_rounded,
        'exit' => Icons.logout_rounded,
        'enter' => Icons.login_rounded,
        'outdoor' => Icons.directions_walk_rounded,
        _ => Icons.flag_rounded,
      };
}

bool _isPreviewWarning(String w) =>
    w.startsWith('Preview only') || w.startsWith('The +15 is closed now');

/// Route cautions (amber) and closure notes (neutral), shown above the steps.
/// The closed-now / closed-bridge state is shown by [PreviewBanner] instead.
class RouteNotices extends StatelessWidget {
  final PlannedRoute route;
  const RouteNotices({super.key, required this.route});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final warnings = route.warnings.where((w) => !_isPreviewWarning(w)).toList();
    if (warnings.isEmpty && route.notes.isEmpty) return const SizedBox.shrink();
    Widget row(IconData icon, String text, Color color) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 10),
              Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
            ],
          ),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (warnings.isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: AppPalette.warning.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              children: [
                for (final w in warnings) row(Icons.warning_amber_rounded, w, AppPalette.warning),
              ],
            ),
          ),
        if (warnings.isNotEmpty && route.notes.isNotEmpty) const SizedBox(height: 8),
        for (final n in route.notes)
          row(Icons.info_outline_rounded, n, theme.colorScheme.onSurfaceVariant),
      ],
    );
  }
}

/// The browse-only state: +15 closed now, or a route through a closed bridge.
class PreviewBanner extends StatelessWidget {
  final PlannedRoute route;
  const PreviewBanner({super.key, required this.route});

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];

  @override
  Widget build(BuildContext context) {
    if (!route.previewOnly) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final closures = route.throughClosures;
    final String title, body;
    if (closures.isNotEmpty) {
      final c = closures.first;
      final until = c.end == null
          ? 'until further notice'
          : 'until about ${_months[c.end!.month - 1]} ${c.end!.day}, ${c.end!.year}';
      title = 'Preview: goes through a closed bridge';
      body = '${c.title}. Closed $until. Use this to plan for when it reopens.';
    } else {
      final w = route.warnings.firstWhere((w) => w.startsWith('The +15 is closed now'),
          orElse: () => 'The +15 is closed now.');
      final opens = RegExp(r'\((.*)\)').firstMatch(w)?.group(1);
      title = opens == null ? 'The +15 is closed now' : 'Closed now · $opens';
      body = 'You can browse this route and preview it on the map. '
          'Live navigation starts once the +15 opens.';
    }
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(closures.isNotEmpty ? Icons.block_rounded : Icons.schedule_rounded,
              color: closures.isNotEmpty ? AppPalette.danger : theme.colorScheme.onSecondaryContainer),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleSmall),
                const SizedBox(height: 2),
                Text(body, style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Debug: why the route used each edge (cost breakdown and sources).
class RouteExplanation extends StatelessWidget {
  final PlannedRoute route;
  const RouteExplanation({super.key, required this.route});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mono = theme.textTheme.bodySmall?.copyWith(fontFamily: 'monospace', fontSize: 11);
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      title: Text('Why this route (debug)', style: theme.textTheme.titleSmall),
      subtitle: Text('${route.profile.label} · cost ${route.cost.toStringAsFixed(0)} · '
          '${route.hops.length} edges', style: theme.textTheme.bodySmall),
      children: [
        for (final h in route.hops)
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text(
                '${h.edge.id} ${h.edge.kind}${h.edge.bridgeNumber != null ? ' #${h.edge.bridgeNumber}' : ''} '
                '${h.fromNode}→${h.toNode} · ${h.costNote} · ${h.edge.confidence} '
                '[${h.edge.sources.join(', ')}]',
                style: mono,
              ),
            ),
          ),
      ],
    );
  }
}
