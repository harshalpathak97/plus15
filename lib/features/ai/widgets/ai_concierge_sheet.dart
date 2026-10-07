import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../shared/widgets/contact.dart';
import '../../../routing/network.dart';
import '../../../shared/providers/providers.dart';
import '../models/ai_message.dart';
import '../services/ai_service.dart';

const _quickPrompts = [
  'Coffee near Bankers Hall',
  'Food courts open now',
  'Bankers Hall to The Bow',
  'Step-free route to City Hall',
];

/// Opens the Ask +15 chat above every tab and the nav bar, optionally
/// asking [initialPrompt] straight away.
Future<void> showAiConcierge(BuildContext context, {String? initialPrompt}) =>
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      builder: (_) => _AiConciergeSheet(initialPrompt),
    );

class _AiConciergeSheet extends ConsumerStatefulWidget {
  const _AiConciergeSheet(this.initialPrompt);

  final String? initialPrompt;

  @override
  ConsumerState<_AiConciergeSheet> createState() => _AiConciergeSheetState();
}

class _AiConciergeSheetState extends ConsumerState<_AiConciergeSheet> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _openReasoning = <String>{};

  AiNotifier get _ai => ref.read(aiProvider.notifier);

  /// Nothing is sent before the user agrees to share it with the AI service.
  late bool _consented = _ai.hasConsent;

  @override
  void initState() {
    super.initState();
    _sendInitial();
  }

  void _sendInitial() {
    final prompt = widget.initialPrompt;
    if (prompt != null && _consented) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _send(prompt));
    }
  }

  Future<void> _agree() async {
    await _ai.giveConsent();
    if (!mounted) return;
    setState(() => _consented = true);
    _sendInitial();
  }

  /// Play policy: users can flag an offensive or harmful AI answer.
  void _report(AiMessage answer) {
    final messages = ref.read(aiProvider);
    final i = messages.indexOf(answer);
    final question = i > 0 ? messages[i - 1].text : '';
    openMail(
      context,
      subject: 'Plus 15 - Report an Ask +15 answer',
      body: 'What is wrong with this answer?\n\n\n'
          '---\nQuestion: $question\n\nAnswer: ${answer.text}\n',
    );
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _send(String text) {
    if (text.trim().isEmpty || _ai.isBusy) return;
    _input.clear();
    _ai.send(text);
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  void _showRoute(AiNavigation n, NetBuilding to, List<NetBuilding> buildings) {
    // "current" / "my location": start from the phone's location (outside
    // the +15 that walks you to the nearest door first).
    final from = resolveBuilding(n.from, buildings);
    if (from != null) {
      ref.read(routeFromMyLocationProvider.notifier).state = false;
      ref.read(routeFromProvider.notifier).state = from;
    } else if (ref.read(locationStreamProvider).valueOrNull != null) {
      ref.read(routeFromMyLocationProvider.notifier).state = true;
    }
    ref.read(routeToProvider.notifier).state = to;
    _leaveTo('/route?auto=1');
  }

  void _showOnMap(NetBuilding b) {
    ref.read(selectedBuildingProvider.notifier).state = b;
    _leaveTo('/map');
  }

  void _leaveTo(String location) {
    final router = GoRouter.of(context);
    Navigator.of(context).pop();
    router.go(location);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final muted = theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant);
    final messages = ref.watch(aiProvider);
    final buildings = ref.watch(buildingsProvider).valueOrNull ?? const <NetBuilding>[];
    final inset = MediaQuery.viewInsetsOf(context).bottom;

    return FractionallySizedBox(
      heightFactor: 0.88,
      child: Padding(
        padding: EdgeInsets.only(bottom: inset),
        child: SafeArea(
          top: false,
          bottom: inset == 0,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.sm, AppSpacing.sm),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Ask +15', style: theme.textTheme.titleLarge),
                          Text('AI answers can be wrong. Check before you go.', style: muted),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'New chat',
                      onPressed: messages.isEmpty ? null : _ai.clear,
                      icon: const Icon(Icons.add_comment_outlined),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: _ai.isConfigured && !_consented
                    ? _consent(theme, muted)
                    : messages.isNotEmpty
                    ? ListView.builder(
                        controller: _scroll,
                        reverse: true, // keeps the newest tokens in view
                        padding: const EdgeInsets.all(AppSpacing.lg),
                        itemCount: messages.length,
                        itemBuilder: (context, i) =>
                            _bubble(messages[messages.length - 1 - i], buildings),
                      )
                    : !_ai.isConfigured
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(AppSpacing.xxl),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.chat_bubble_outline_rounded,
                                      size: 40, color: cs.onSurfaceVariant),
                                  const SizedBox(height: AppSpacing.md),
                                  Text("Ask AI isn't set up in this build",
                                      textAlign: TextAlign.center,
                                      style: theme.textTheme.titleMedium),
                                  const SizedBox(height: AppSpacing.xs),
                                  Text(
                                    'Search and Directions still work. Builds made with an '
                                    'AI_PROXY_URL can answer questions here.',
                                    textAlign: TextAlign.center,
                                    style: muted,
                                  ),
                                ],
                              ),
                            ),
                          )
                        : ListView(
                            padding: const EdgeInsets.all(AppSpacing.lg),
                            children: [
                              Text(
                                'Ask about places, food and routes on the +15. Answers use '
                                "the app's buildings, shops and route planner.",
                                style: theme.textTheme.bodyMedium
                                    ?.copyWith(color: cs.onSurfaceVariant, height: 1.45),
                              ),
                              const SizedBox(height: AppSpacing.md),
                              Wrap(
                                spacing: AppSpacing.sm,
                                runSpacing: AppSpacing.sm,
                                children: [
                                  for (final p in _quickPrompts)
                                    OutlinedButton(onPressed: () => _send(p), child: Text(p)),
                                ],
                              ),
                            ],
                          ),
              ),
              if (_ai.isConfigured && _consented) ...[
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                      AppSpacing.lg, AppSpacing.sm, AppSpacing.sm, AppSpacing.sm),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _input,
                          minLines: 1,
                          maxLines: 4,
                          textInputAction: TextInputAction.send,
                          textCapitalization: TextCapitalization.sentences,
                          onChanged: (_) => setState(() {}),
                          onSubmitted: _send,
                          decoration:
                              const InputDecoration(hintText: 'Ask about places, food or routes…'),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      IconButton.filled(
                        tooltip: 'Send',
                        onPressed: _ai.isBusy || _input.text.trim().isEmpty
                            ? null
                            : () => _send(_input.text),
                        icon: const Icon(Icons.arrow_upward_rounded),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _bubble(AiMessage m, List<NetBuilding> buildings) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final muted = theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant);
    final reasoning = m.reasoning ?? '';
    final open = _openReasoning.contains(m.id);
    final offers = [
      for (final n in m.offers)
        if (resolveBuilding(n.to, buildings) case final b?) (n, b),
    ];
    final focus = m.actionType == AiActionType.focus
        ? resolveBuilding(m.actionTarget ?? '', buildings)
        : null;

    return Align(
      alignment: m.isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.85),
        margin: const EdgeInsets.only(bottom: AppSpacing.sm),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: m.isUser ? cs.primaryContainer : cs.surfaceContainerHigh,
          borderRadius: AppRadii.rCard,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (kDebugMode && reasoning.isNotEmpty) ...[
              TextButton.icon(
                onPressed: () => setState(
                    () => open ? _openReasoning.remove(m.id) : _openReasoning.add(m.id)),
                icon: Icon(open ? Icons.expand_less_rounded : Icons.expand_more_rounded),
                label: const Text('Reasoning'),
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(0, 48),
                  textStyle: theme.textTheme.labelLarge,
                ),
              ),
              if (open)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: SelectableText(reasoning, style: muted),
                ),
            ],
            if (m.text.isNotEmpty)
              SelectableText(
                m.text,
                style: theme.textTheme.bodyMedium?.copyWith(
                  height: 1.45,
                  color: m.isUser ? cs.onPrimaryContainer : cs.onSurface,
                ),
              ),
            if (m.isStreaming)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
                child: SizedBox(width: 48, child: LinearProgressIndicator(minHeight: 2)),
              ),
            if (m.queued) ...[
              Text('Still thinking. This can take up to a minute.', style: muted),
              TextButton(onPressed: _ai.answerQuickly, child: const Text('Get a quick answer')),
            ],
            for (final (n, b) in offers)
              Container(
                margin: const EdgeInsets.only(top: AppSpacing.sm),
                padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.sm, AppSpacing.sm),
                decoration: BoxDecoration(
                  color: cs.surface,
                  borderRadius: AppRadii.rControl,
                  border: Border.all(color: cs.outlineVariant),
                ),
                child: Row(
                  children: [
                    Icon(Icons.directions_walk_rounded, size: 20, color: cs.primary),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(n.place == null ? 'Directions to ${b.name}' : n.place!,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleSmall),
                          if (n.place != null)
                            Text(b.name,
                                maxLines: 1, overflow: TextOverflow.ellipsis, style: muted),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    FilledButton(
                      onPressed: () => _showRoute(n, b, buildings),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 48),
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                      ),
                      child: Text(offers.length > 1 ? 'Go' : 'Show route'),
                    ),
                  ],
                ),
              ),
            if (focus != null)
              TextButton.icon(
                onPressed: () => _showOnMap(focus),
                icon: const Icon(Icons.map_outlined),
                label: const Text('Show on map'),
              ),
            if (!m.isUser && !m.isStreaming && m.text.isNotEmpty)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () => _report(m),
                  icon: const Icon(Icons.flag_outlined, size: 18),
                  label: const Text('Report'),
                  style: TextButton.styleFrom(foregroundColor: cs.onSurfaceVariant),
                ),
              ),
            if (kDebugMode && m.answeredBy != null && m.answeredBy != primaryModel)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xs),
                child: Text(
                  m.quick ? 'Answered by quick model' : 'Answered by fallback model',
                  style: muted,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _consent(ThemeData theme, TextStyle? muted) {
    Widget item(IconData icon, String text) => Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 20, color: theme.colorScheme.primary),
              const SizedBox(width: AppSpacing.md),
              Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
            ],
          ),
        );
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        Text('Before you ask', style: theme.textTheme.titleMedium),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Ask +15 answers using a third-party AI service. To answer, the app sends it:',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: AppSpacing.md),
        item(Icons.chat_outlined, 'Your questions and the earlier messages in this chat.'),
        item(Icons.near_me_outlined,
            'Roughly where you are on the +15 (the nearest door or walkway), never your GPS coordinates.'),
        item(Icons.bookmark_border_rounded,
            'Your saved places, the trip open in Navigate, and whether you prefer step-free routes.'),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'No account or name is attached, and the app keeps nothing on a server. '
          "Don't include personal details in your questions.",
          style: muted,
        ),
        TextButton(
          onPressed: () => openLink(context, AppConstants.privacyUrl),
          child: const Text('Privacy policy'),
        ),
        const SizedBox(height: AppSpacing.md),
        FilledButton(onPressed: _agree, child: const Text('Agree and continue')),
        const SizedBox(height: AppSpacing.sm),
        OutlinedButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Not now'),
        ),
      ],
    );
  }
}
