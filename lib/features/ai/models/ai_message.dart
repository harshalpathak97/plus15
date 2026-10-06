enum AiActionType { none, navigate, focus }

/// One "take me there" offer from a reply: [place] is the shop, if any.
typedef AiNavigation = ({String from, String to, String? place});

/// One chat bubble. Assistant replies stream in ([isStreaming]) and may end
/// with one action tag, which [parseActions] turns into [actionType].
class AiMessage {
  final String id;
  final String text;

  /// Streamed reasoning ("thinking"), when the model sends it.
  final String? reasoning;
  final bool isUser;
  final DateTime timestamp;
  final bool isStreaming;

  /// Kimi has been silent for a while: queued on NVIDIA's servers.
  final bool queued;

  /// The user stopped waiting for Kimi and asked the quick model.
  final bool quick;

  /// The model that wrote this reply; null for user messages and failures.
  final String? answeredBy;
  final AiActionType actionType;
  final String? actionFrom;
  final String? actionTo;
  final String? actionTarget;

  /// Every place the reply offers directions to (up to 3), in order.
  final List<AiNavigation> navigations;

  const AiMessage({
    required this.id,
    required this.text,
    this.reasoning,
    required this.isUser,
    required this.timestamp,
    this.isStreaming = false,
    this.queued = false,
    this.quick = false,
    this.answeredBy,
    this.actionType = AiActionType.none,
    this.actionFrom,
    this.actionTo,
    this.actionTarget,
    this.navigations = const [],
  });

  AiMessage copyWith({
    String? id,
    String? text,
    String? reasoning,
    bool? isUser,
    DateTime? timestamp,
    bool? isStreaming,
    bool? queued,
    bool? quick,
    String? answeredBy,
    AiActionType? actionType,
    String? actionFrom,
    String? actionTo,
    String? actionTarget,
    List<AiNavigation>? navigations,
  }) {
    return AiMessage(
      id: id ?? this.id,
      text: text ?? this.text,
      reasoning: reasoning ?? this.reasoning,
      isUser: isUser ?? this.isUser,
      timestamp: timestamp ?? this.timestamp,
      isStreaming: isStreaming ?? this.isStreaming,
      queued: queued ?? this.queued,
      quick: quick ?? this.quick,
      answeredBy: answeredBy ?? this.answeredBy,
      actionType: actionType ?? this.actionType,
      actionFrom: actionFrom ?? this.actionFrom,
      actionTo: actionTo ?? this.actionTo,
      actionTarget: actionTarget ?? this.actionTarget,
      navigations: navigations ?? this.navigations,
    );
  }

  /// The directions this reply offers: [navigations], or the single
  /// navigate action of older replies.
  List<AiNavigation> get offers => navigations.isNotEmpty
      ? navigations
      : actionType == AiActionType.navigate && actionTo != null
          ? [(from: actionFrom ?? 'current', to: actionTo!, place: null)]
          : const [];

  /// Parses action tags embedded in AI response, e.g.:
  /// [ACTION:NAVIGATE|from=The Core|to=Bankers Hall|place=Starbucks]
  /// [ACTION:FOCUS|name=Scotia Centre]
  /// A reply may offer up to three places; all tags are removed from the text.
  static AiMessage parseActions(AiMessage msg) {
    final navRegex = RegExp(
      r'\[ACTION:NAVIGATE\|from=([^|\]]+)\|to=([^|\]]+)(?:\|place=([^|\]]+))?\]',
      caseSensitive: false,
    );
    final focusRegex = RegExp(r'\[ACTION:FOCUS\|name=([^|\]]+)\]', caseSensitive: false);
    final navs = <AiNavigation>[
      for (final m in navRegex.allMatches(msg.text))
        (from: m.group(1)!.trim(), to: m.group(2)!.trim(), place: m.group(3)?.trim()),
    ];
    final unique = <AiNavigation>[];
    for (final n in navs) {
      if (unique.length < 3 && !unique.any((u) => u.to == n.to && u.place == n.place)) unique.add(n);
    }
    final focus = focusRegex.firstMatch(msg.text);
    final text = msg.text.replaceAll(navRegex, '').replaceAll(focusRegex, '').trim();
    if (unique.isNotEmpty) {
      return msg.copyWith(
        text: text,
        actionType: AiActionType.navigate,
        actionFrom: unique.first.from,
        actionTo: unique.first.to,
        navigations: unique,
      );
    }
    if (focus != null) {
      return msg.copyWith(
          text: text, actionType: AiActionType.focus, actionTarget: focus.group(1)!.trim());
    }
    return msg.copyWith(text: text);
  }
}
