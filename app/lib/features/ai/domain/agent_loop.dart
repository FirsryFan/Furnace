import 'dart:async';
import 'dart:convert';

// Needed for the `|` operator on drift expressions: it is an extension member,
// so a `show` clause that names only types would hide it.
import 'package:drift/drift.dart';

import '../../../data/database/database.dart';
import '../../../data/repositories/ai_repository.dart';
import '../../../data/repositories/settings_repository.dart';
import '../../../data/skill/skill_prompt.dart';
import '../../../data/skill/skill_runner.dart';
import '../../../data/skill/skill_store.dart';
import '../../../domain/services/cognitive/user_persona.dart';
import '../../../domain/skill/skill_manifest.dart';
import '../../../domain/skill/skill_tool.dart';
import '../infrastructure/ai_attachment_store.dart';
import '../tools/card_group_tools.dart';
import '../tools/deletion_tools.dart';
import '../tools/document_tools.dart';
import '../tools/knowledge_tools.dart';
import '../tools/review_focus_tool.dart';
import '../tools/tag_tools.dart';
import '../tools/schedule_tools.dart';
import '../tools/task_tools.dart';
import 'ai_tool.dart';
import 'approval_engine.dart';
import 'model_adapter.dart';
import 'tool_registry.dart';

/// A tool call waiting for the user's decision.
class PendingCall {
  const PendingCall({
    required this.call,
    required this.tool,
    required this.decision,
    required this.actionId,
  });

  final ToolCallRequest call;
  final AiTool tool;
  final ApprovalDecision decision;

  /// Row id in `ai_actions`, so approval/rejection can be recorded against it.
  final String actionId;

  String get title {
    final args = call.arguments;
    final label = args['title'] ?? args['id'] ?? args['action'];
    return label == null ? tool.name : '$label';
  }
}

/// One model turn that asked for tools, plus the replies gathered so far.
///
/// The provider requires an assistant message carrying `tool_calls` to be
/// followed **immediately** by one tool message per call. That makes a turn an
/// all-or-nothing unit: until every call has a reply, the turn must not appear
/// in the history at all. Modelling the turn explicitly is what keeps that
/// invariant true on *every* path - approval, rejection, auto-execution and
/// failure - instead of only on whichever path was tried first.
class TurnGroup {
  TurnGroup({required this.assistantText, this.assistantReasoning});

  /// Text the model emitted alongside the calls, if any.
  final String? assistantText;

  /// The model's chain of thought for this turn, if the provider streamed one.
  /// Persisted with the assistant row so 思考过程 survives a restart.
  final String? assistantReasoning;

  /// Call ids in order, so the assistant message lists them deterministically.
  final List<String> callIds = [];

  /// One reply per call id. A payload of `null` is impossible: a rejection is
  /// itself a reply, which is why the model stops re-proposing.
  final Map<String, Map<String, Object?>> replies = {};

  /// The assistant message row, once written. Written at most once per turn.
  String? messageId;

  bool get isComplete =>
      callIds.isNotEmpty && callIds.every(replies.containsKey);

  void addReply(String callId, Map<String, Object?> payload) {
    if (!callIds.contains(callId)) {
      callIds.add(callId);
    }
    replies[callId] = payload;
  }
}

/// One executed call, for display and undo.
class ExecutedCall {
  const ExecutedCall({
    required this.toolName,
    required this.summary,
    required this.result,
    required this.actionId,
    required this.undone,
  });

  final String toolName;
  final String summary;
  final ToolResult result;
  final String actionId;
  final bool undone;

  ExecutedCall copyWith({bool? undone}) => ExecutedCall(
        toolName: toolName,
        summary: summary,
        result: result,
        actionId: actionId,
        undone: undone ?? this.undone,
      );
}

/// What one user turn used, as far as the app can measure it.
///
/// One object, produced by the loop and read by the turn/usage panel, so the
/// page never adds numbers up itself and never parses provider JSON. Every
/// figure here is either **measured** - the provider reported it, or a stopwatch
/// timed it - or `null`, which the panel renders as a dash. Nothing is filled in
/// with a plausible-looking number, because a fabricated `0%` cache hit rate
/// reads as a measurement and is not one.
class TurnUsage {
  const TurnUsage({
    this.rounds = 0,
    this.maxRounds = AgentLoop.defaultMaxRounds,
    this.roundsWithUsage = 0,
    this.promptTokens = 0,
    this.completionTokens = 0,
    this.cacheHitPromptTokens,
    this.cacheMissPromptTokens,
    this.generationTime = Duration.zero,
    this.lastPromptTokens,
    this.contextWindowTokens = AgentLoop.defaultContextWindowTokens,
    this.toolCallsExecuted = 0,
    this.toolCallsPending = 0,
    this.toolCallsRejected = 0,
    this.inFlightChars = 0,
    this.inFlightElapsed = Duration.zero,
  });

  /// Model round-trips used by this turn so far.
  final int rounds;

  /// The configured ceiling those rounds are counted against.
  final int maxRounds;

  /// How many of [rounds] actually reported a usage block. Zero means the
  /// provider never reported token counts, which is what turns the token
  /// figures into dashes instead of a confident `0`.
  final int roundsWithUsage;

  /// Prompt tokens summed over the rounds that reported usage.
  final int promptTokens;

  /// Completion tokens summed over the rounds that reported usage.
  final int completionTokens;

  /// Prompt tokens the provider served from its cache, summed the same way.
  /// `null` when no round reported them.
  final int? cacheHitPromptTokens;

  /// Prompt tokens the provider had to process, summed the same way. `null`
  /// when no round reported them.
  final int? cacheMissPromptTokens;

  /// Generation wall time: the sum of the per-round generation durations, i.e.
  /// time spent inside the model's own round-trip. History building, the skill
  /// read, tool execution and waiting for the user's approval are all outside
  /// it, which is what makes [tokensPerSecond] a property of the model rather
  /// than of how slow a tool happened to be.
  final Duration generationTime;

  /// The last round's prompt tokens, i.e. how full the context was when the
  /// model last saw it.
  final int? lastPromptTokens;

  /// The context window the estimate is taken against. Not measured - see
  /// [AgentLoop.defaultContextWindowTokens].
  final int contextWindowTokens;

  /// Tool calls that really ran this turn (auto-approved or approved).
  final int toolCallsExecuted;

  /// Tool calls waiting for the user's decision right now.
  final int toolCallsPending;

  /// Tool calls the user refused this turn.
  final int toolCallsRejected;

  /// Characters streamed in the round currently in flight. Feeds the live rate
  /// only; it is discarded when the round's real token count arrives.
  final int inFlightChars;

  /// Generation time elapsed in the round currently in flight.
  final Duration inFlightElapsed;

  /// Characters per token assumed **only** for the live, in-flight estimate.
  ///
  /// The provider reports token counts when a round ends, never during it, so
  /// the only thing countable mid-stream is the text that has arrived. 2.5 is a
  /// deliberately middle-of-the-road figure: English runs about 4 characters per
  /// token and Chinese closer to 1.5, so a mixed reply lands near this. The live
  /// figure is labelled as an estimate in the UI and is never used for the
  /// frozen one.
  static const double liveCharsPerToken = 2.5;

  int get totalTokens => promptTokens + completionTokens;

  bool get hasUsage => roundsWithUsage > 0;

  /// Whether anything at all is worth showing. An untouched turn is empty, and
  /// the panel is hidden rather than showing six zeros.
  bool get isEmpty =>
      rounds == 0 &&
      roundsWithUsage == 0 &&
      promptTokens == 0 &&
      completionTokens == 0 &&
      toolCallsExecuted == 0 &&
      toolCallsPending == 0 &&
      toolCallsRejected == 0;

  /// Cache hits as a share of the prompt tokens, or `null` when the provider
  /// did not report the pair.
  ///
  /// `null` and `0.0` are different answers and are kept different: a provider
  /// that reports `0` hits out of `1000` miss tokens is a measurement of no
  /// caching, while a provider that reports neither leaves the question open.
  /// An all-zero pair is treated as "not reported", since a real request cannot
  /// have an empty prompt.
  double? get cacheHitRatio {
    final hit = cacheHitPromptTokens;
    final miss = cacheMissPromptTokens;
    if (hit == null && miss == null) {
      return null;
    }
    final total = (hit ?? 0) + (miss ?? 0);
    if (total <= 0) {
      return null;
    }
    return (hit ?? 0) / total;
  }

  /// Whether only some of this turn's rounds reported cache accounting.
  ///
  /// Derived rather than stored: when every round reports the pair, hits plus
  /// misses account for the whole prompt, so a shortfall means a round stayed
  /// silent. Saying so matters, because otherwise the ratio would look like a
  /// statement about the whole turn while describing a subset of it.
  bool get cacheAccountingIsPartial {
    if (cacheHitPromptTokens == null && cacheMissPromptTokens == null) {
      return false;
    }
    final accounted =
        (cacheHitPromptTokens ?? 0) + (cacheMissPromptTokens ?? 0);
    return accounted < promptTokens;
  }

  /// Completion tokens divided by generation wall time, for the turn as a
  /// whole. `null` when no round was timed, because a rate without a duration
  /// would be an invention.
  ///
  /// The numerator and the denominator cover the same rounds: a round that
  /// reported tokens but no duration never happens in practice (the loop times
  /// every round itself), but if it did, its tokens would be counted in
  /// [totalTokens] and left out of the rate rather than deflating the divisor.
  double? get tokensPerSecond {
    final micros = generationTime.inMicroseconds;
    if (micros <= 0) {
      return null;
    }
    return completionTokens / (micros / Duration.microsecondsPerSecond);
  }

  /// The rate while a round is still being generated: the same definition as
  /// [tokensPerSecond] - completion tokens over generation time, never over the
  /// turn's total time - with the in-flight round contributing an *estimated*
  /// numerator, since the provider has not reported one yet.
  ///
  /// Returns `null` while nothing has been generated at all, in this round or an
  /// earlier one. `0.0` would read as "the model is producing nothing", which is
  /// a different statement from "no token has been produced yet".
  double? get liveTokensPerSecond {
    final micros = (generationTime + inFlightElapsed).inMicroseconds;
    if (micros <= 0) {
      return null;
    }
    final tokens = completionTokens + inFlightChars / liveCharsPerToken;
    if (tokens <= 0) {
      return null;
    }
    return tokens / (micros / Duration.microsecondsPerSecond);
  }

  /// How full the context was on the last round, against
  /// [contextWindowTokens]. An estimate, because the window size is a
  /// configured constant rather than something the endpoint reports.
  double? get contextUsageRatio {
    final last = lastPromptTokens;
    if (last == null || contextWindowTokens <= 0) {
      return null;
    }
    return last / contextWindowTokens;
  }

  TurnUsage copyWith({
    int? rounds,
    int? maxRounds,
    int? roundsWithUsage,
    int? promptTokens,
    int? completionTokens,
    int? cacheHitPromptTokens,
    int? cacheMissPromptTokens,
    Duration? generationTime,
    int? lastPromptTokens,
    int? contextWindowTokens,
    int? toolCallsExecuted,
    int? toolCallsPending,
    int? toolCallsRejected,
    int? inFlightChars,
    Duration? inFlightElapsed,
  }) =>
      TurnUsage(
        rounds: rounds ?? this.rounds,
        maxRounds: maxRounds ?? this.maxRounds,
        roundsWithUsage: roundsWithUsage ?? this.roundsWithUsage,
        promptTokens: promptTokens ?? this.promptTokens,
        completionTokens: completionTokens ?? this.completionTokens,
        cacheHitPromptTokens: cacheHitPromptTokens ?? this.cacheHitPromptTokens,
        cacheMissPromptTokens:
            cacheMissPromptTokens ?? this.cacheMissPromptTokens,
        generationTime: generationTime ?? this.generationTime,
        lastPromptTokens: lastPromptTokens ?? this.lastPromptTokens,
        contextWindowTokens: contextWindowTokens ?? this.contextWindowTokens,
        toolCallsExecuted: toolCallsExecuted ?? this.toolCallsExecuted,
        toolCallsPending: toolCallsPending ?? this.toolCallsPending,
        toolCallsRejected: toolCallsRejected ?? this.toolCallsRejected,
        inFlightChars: inFlightChars ?? this.inFlightChars,
        inFlightElapsed: inFlightElapsed ?? this.inFlightElapsed,
      );
}

/// The conversation as the UI sees it.
class AgentTurnState {
  const AgentTurnState({
    this.generating = false,
    this.streamingText = '',
    this.reasoningText = '',
    this.pending = const [],
    this.pendingTurn,
    this.executed = const [],
    this.error,
    this.cancelled = false,
    this.rounds = 0,
    this.usage = const TurnUsage(),
  });

  /// A model call is in flight.
  final bool generating;

  /// Assistant text received so far in this turn.
  final String streamingText;

  /// Thinking / reasoning text received so far in this turn.
  ///
  /// A separate channel from [streamingText] because it is not the answer: it
  /// is never persisted and never sent back to the provider, and a provider
  /// that does not think simply leaves this empty. A UI that does not show
  /// thinking can ignore it and still be correct.
  final String reasoningText;

  /// Calls that need a decision before anything happens.
  final List<PendingCall> pending;

  /// The turn those calls belong to. Held in memory: an unfinished turn is not
  /// valid history, so it must not reach the database before it is complete.
  final TurnGroup? pendingTurn;

  /// Calls that have already run (automatically or after approval).
  final List<ExecutedCall> executed;

  /// User-facing failure text, e.g. a provider error.
  final String? error;

  /// True when the user stopped this turn before it finished.
  ///
  /// Not a failure: [error] stays null and any answer text received up to the
  /// stop is kept (and persisted if it is not empty). The flag exists so the
  /// UI can say the answer is partial and offer to continue, instead of
  /// showing a message that looks complete.
  final bool cancelled;

  /// How many model round-trips this turn used.
  ///
  /// Mirrors [TurnUsage.rounds]; both come from the loop's one accumulator, so
  /// they cannot disagree. Kept as its own field because it predates the usage
  /// panel and other code and tests read it directly.
  final int rounds;

  /// Everything the turn cost: rounds, tool calls, tokens, timing. This is the
  /// single object the page reads - it never parses provider JSON itself.
  final TurnUsage usage;

  bool get hasPending => pending.isNotEmpty;
  bool get isIdle => !generating && !hasPending;

  AgentTurnState copyWith({
    bool? generating,
    String? streamingText,
    String? reasoningText,
    List<PendingCall>? pending,
    TurnGroup? pendingTurn,
    List<ExecutedCall>? executed,
    String? error,
    bool? cancelled,
    int? rounds,
    TurnUsage? usage,
    bool clearError = false,
    bool clearPendingTurn = false,
  }) {
    final nextRounds = rounds ?? this.rounds;
    // One writer, one number: `rounds` and `usage.rounds` are stamped together
    // so a caller that passes only one of them cannot produce a panel that
    // disagrees with the state it is drawn from.
    final nextUsage = (usage ?? this.usage).copyWith(rounds: nextRounds);
    return AgentTurnState(
      generating: generating ?? this.generating,
      streamingText: streamingText ?? this.streamingText,
      reasoningText: reasoningText ?? this.reasoningText,
      pending: pending ?? this.pending,
      pendingTurn: clearPendingTurn ? null : (pendingTurn ?? this.pendingTurn),
      executed: executed ?? this.executed,
      error: clearError ? null : (error ?? this.error),
      cancelled: cancelled ?? this.cancelled,
      rounds: nextRounds,
      usage: nextUsage,
    );
  }
}

/// Runs the agent loop: model -> tool calls -> approval -> execution -> model.
///
/// Constraints this file implements, from docs/AI_DESIGN.md §10:
///
///  * **C1** single agent, no orchestration.
///  * **C3** a hard round cap. A model that keeps calling tools must stop, and
///    stop *with an answer*, not with a truncated silence.
///  * **C5** tool results are appended at the end of the history with matching
///    ids. The Chat Completion API does not accept a tool call inserted
///    mid-conversation, so nothing may be spliced in.
///  * **C6** every proposed call gets a result fed back, **including rejected
///    ones** - otherwise the model simply proposes the same thing again.
///
/// It is a plain class, not a provider, so it can be driven directly in tests
/// with a fake adapter.
class AgentLoop {
  AgentLoop({
    required this.adapter,
    required this.registry,
    required this.approval,
    required this.repository,
    required this.db,
    this.attachments,
    this.skills,
    this.skillRunner,
    this.skillPlatform,
    this.maxRounds = defaultMaxRounds,
    this.contextWindowTokens = defaultContextWindowTokens,
  });

  final ModelAdapter adapter;
  final ToolRegistry registry;
  final ApprovalEngine approval;
  final AiRepository repository;
  final AppDatabase db;

  /// Where attached images are stored and read back from.
  ///
  /// Optional so a text-only loop (and every existing test) needs no filesystem:
  /// a loop built without it simply cannot carry images, and says so rather than
  /// sending a message whose photo silently went nowhere.
  final AiAttachmentStore? attachments;

  /// Where installed `.fskill` packages live.
  ///
  /// Optional for the same reason as [attachments]: a loop built without it has
  /// no skills, and its system prompt is byte-identical to the prompt that
  /// existed before skills did. That equality is what makes "skills off" mean
  /// "exactly the old behaviour" rather than "close to it".
  ///
  /// When it is present, its enabled skills supply **both** prompt text and
  /// their declared script tools; see [_turnTools].
  final SkillStore? skills;

  /// The script container used for enabled skills' declared tools.
  ///
  /// Built on demand when absent, so a loop that has no skills never constructs
  /// one and every existing test is unaffected. Injected in tests that need to
  /// drive a caller-supplied container.
  final SkillRunner? skillRunner;

  /// The platform the skill gate is decided for.
  ///
  /// Defaults to [SkillPlatform.current]; injectable for the same reason the
  /// manifest's own gate is: "on Android the tool is absent" has to be testable
  /// without an Android device.
  final SkillPlatform? skillPlatform;

  /// How long the system prompt waits for the skill directory before giving up
  /// and using the built-in rules alone. See [_turnTools].
  static const Duration skillReadTimeout = Duration(seconds: 2);

  /// How long one message's images may take to come off disk before the turn
  /// proceeds without them. See [_imageParts].
  static const Duration imageReadTimeout = Duration(seconds: 10);

  /// Ceiling on model round-trips per user message. Eight is enough for
  /// "look something up, then act on it, then confirm" without letting a loop
  /// run away with the user's credit.
  final int maxRounds;

  /// The default of [maxRounds], named so a usage panel can render "used / cap"
  /// from a state alone.
  ///
  /// The same number as [AiConfig.defaultMaxRounds], and deliberately not a
  /// second literal 8: the user chooses this budget in settings, so the shipped
  /// default has to live in one place or the two would drift the first time it
  /// changes.
  static const int defaultMaxRounds = AiConfig.defaultMaxRounds;

  /// The context window the occupancy figure is estimated against.
  ///
  /// There is no reliable per-model table in this repository, and the endpoint
  /// does not report its window, so this is **one configured number with a
  /// documented default** rather than a measurement: 64k, a conservative
  /// floor that DeepSeek's 64k-context models and every larger window are at
  /// least this big. The panel labels the figure as an estimate for that
  /// reason. Injection exists so a test can pin the arithmetic; changing it is
  /// a one-line edit here, not a lookup table scattered across the UI.
  final int contextWindowTokens;

  /// The 64k default of [contextWindowTokens].
  static const int defaultContextWindowTokens = 65536;

  /// Everything the current turn has cost. Reset when a new turn starts, and
  /// **not** reset by an approval, because approving continues the same turn -
  /// its round-trips and tokens belong to the same user message.
  late _TurnMetrics _metrics = _TurnMetrics(
    maxRounds: maxRounds,
    contextWindowTokens: contextWindowTokens,
  );

  final _states = StreamController<AgentTurnState>.broadcast();
  AgentTurnState _state = const AgentTurnState();

  /// Set by [cancel], checked at every point this loop could start another
  /// round or act on a call. Cleared when a new user message starts a turn, so
  /// a cancel only ever affects the turn it was issued for.
  bool _cancelRequested = false;

  Stream<AgentTurnState> get states => _states.stream;
  AgentTurnState get state => _state;

  /// Stops the turn in flight and keeps whatever text has arrived.
  ///
  /// Safe to call at any time and more than once: a second call does nothing.
  /// The adapter is asked to stop only when it can (see
  /// [ModelAdapterCancellation]); the loop also stops itself at the next event
  /// or round boundary, which is what lets a scripted fake adapter - one that
  /// cannot be interrupted mid-stream - still end cleanly.
  ///
  /// A turn waiting for approval is dropped, not committed: it still has calls
  /// the model never saw an answer to, so writing it would make the next
  /// request invalid. Tool proposals that were already recorded stay on the
  /// ledger for audit; nothing is executed by this call.
  void cancel() {
    if (_cancelRequested) {
      return;
    }
    _cancelRequested = true;
    adapter.cancelActiveTurn();
    if (_state.hasPending) {
      _metrics.toolCallsPending = 0;
      _emit(_state.copyWith(
        generating: false,
        pending: const [],
        clearPendingTurn: true,
        cancelled: true,
        usage: _metrics.snapshot(),
      ));
    }
  }

  /// Releases the state stream. An in-flight turn is cancelled first so the
  /// stream is not left waiting on a provider that will never finish.
  void dispose() {
    cancel();
    _states.close();
  }

  void _emit(AgentTurnState next) {
    _state = next;
    if (!_states.isClosed) {
      _states.add(next);
    }
  }

  /// Sends one user message and drives the loop until the model is done.
  ///
  /// [images] are already written to disk by an [AiAttachmentStore]; they are
  /// registered against the message here, because their `owner_id` is the message
  /// id and the message does not exist until this call.
  ///
  /// Returns normally in every case: provider failures become [error] on the
  /// state, because losing a turn to an exception would throw away the user's
  /// message too.
  Future<void> sendUserMessage({
    required String conversationId,
    required String text,
    List<PendingImage> images = const [],
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty && images.isEmpty) {
      return;
    }
    if (_state.hasPending) {
      // Driving a new turn while a previous one is unresolved would leave the
      // model's tool calls unanswered in the history, and the provider rejects
      // that with a 400. The UI already disables its input here; this guard
      // makes the invariant true for every caller.
      return;
    }
    final store = attachments;
    if (images.isNotEmpty && store == null) {
      // A wiring mistake, not a user mistake: without a store the pictures could
      // not be shown to the model at all. Refusing beats sending a message whose
      // attachment the model never sees.
      _emit(const AgentTurnState(
        error: '图片附件未启用：这次对话没有配置文件存储，图片不会被发送。',
      ));
      return;
    }
    // A new turn: any cancel from the previous one stops applying here, which
    // is what keeps a stopped turn from silently swallowing the next message.
    _cancelRequested = false;
    // A new user message starts a new turn, so the counters start over here and
    // only here: an approval continues the turn it belongs to.
    _metrics = _TurnMetrics(
      maxRounds: maxRounds,
      contextWindowTokens: contextWindowTokens,
    );
    _emit(const AgentTurnState(generating: true));
    final message = await repository.addMessage(
      conversationId: conversationId,
      role: AiRepository.roleUser,
      // An image-only message has no text; storing NULL keeps the empty string
      // out of the history instead of turning it into a text part.
      content: trimmed.isEmpty ? null : trimmed,
    );
    if (images.isNotEmpty) {
      await store!.register(message.id, images);
    }
    await _drive(conversationId);
  }

  /// Executes the calls the user approved, then lets the model continue.
  Future<void> approvePending(String conversationId) async {
    final pending = _state.pending;
    final group = _state.pendingTurn;
    if (pending.isEmpty || group == null) {
      return;
    }
    // The decision has been made, so nothing is waiting on the user any more.
    _metrics.toolCallsPending = 0;
    _emit(_state.copyWith(
      pending: const [],
      pendingTurn: group,
      generating: true,
      usage: _metrics.snapshot(),
    ));
    for (final item in pending) {
      await _execute(conversationId, item, group);
    }
    // The turn is complete now, so it can be recorded as one valid unit and the
    // model can be asked for the next step.
    await _commitTurn(conversationId, group);
    _emit(_state.copyWith(clearPendingTurn: true));
    await _drive(conversationId);
  }

  /// Refuses every pending call.
  ///
  /// A refusal is itself a reply, and it is recorded as one: the provider needs
  /// an answer per call, and the model needs to know it was refused or it will
  /// simply propose the same thing again.
  Future<void> rejectPending(String conversationId) async {
    final pending = _state.pending;
    final group = _state.pendingTurn;
    if (pending.isEmpty || group == null) {
      return;
    }
    for (final item in pending) {
      final payload = <String, Object?>{
        'ok': false,
        'error': '用户拒绝了这次操作',
      };
      group.addReply(item.call.id, payload);
      await repository.updateActionStatus(
        item.actionId,
        status: AiRepository.statusRejected,
        resultJson: jsonEncode(payload),
      );
    }
    // Refused calls are steps the user paid attention to, so they are counted -
    // as refusals, never as executions, or the panel would report work that
    // never happened.
    _metrics.toolCallsPending = 0;
    _metrics.toolCallsRejected += pending.length;
    await _commitTurn(conversationId, group);
    _emit(_state.copyWith(
      pending: const [],
      clearPendingTurn: true,
      usage: _metrics.snapshot(),
    ));
  }

  /// Undoes one executed call by applying its before-snapshot.
  ///
  /// Undoable today: creates/updates/deletes of tasks and time blocks, the
  /// creation of knowledge cards, the creation of tags, the creation of
  /// documents (the file is removed), and the deletions `delete_content`
  /// performs (its snapshot holds the original rows). A call with no snapshot
  /// cannot be undone, and the UI does not offer it.
  Future<void> undoExecuted(String conversationId, String actionId) async {
    final index = _state.executed.indexWhere((e) => e.actionId == actionId);
    if (index < 0) {
      return;
    }
    final entry = _state.executed[index];
    final actions = await repository.listActions(conversationId);
    final record = actions.firstWhere(
      (a) => a.id == actionId,
      orElse: () => throw StateError('action $actionId not found'),
    );
    final ok = await _undo(record);
    if (!ok) {
      _emit(_state.copyWith(
        error: '无法撤销「${entry.toolName}」：该操作没有可用的快照',
      ));
      return;
    }
    await repository.updateActionStatus(
      actionId,
      status: AiRepository.statusRejected,
      resultJson: jsonEncode({'undone': true}),
    );
    final updated = [..._state.executed];
    updated[index] = entry.copyWith(undone: true);
    _emit(_state.copyWith(executed: updated, clearError: true));
  }

  // --- the loop ------------------------------------------------------------

  Future<void> _drive(String conversationId) async {
    // The round counter lives on the accumulator rather than in this method,
    // because an approval re-enters _drive for the *same* user turn: a local
    // counter would restart at 1 and both the cap and the panel would report a
    // turn that used fewer round-trips than it really did.
    while (_metrics.rounds < maxRounds) {
      if (_cancelRequested) {
        await _finishCancelled(conversationId, null, null);
        return;
      }
      _metrics.rounds++;
      _metrics.inFlightChars = 0;
      _metrics.inFlightElapsed = Duration.zero;
      _emit(_state.copyWith(
        generating: true,
        rounds: _metrics.rounds,
        usage: _metrics.snapshot(),
        clearError: true,
      ));

      // One read of the skill directory per round: it produces this round's
      // tool list *and* the prompt that accompanies it.
      final turnTools = await _turnTools();
      final history =
          await _buildHistory(conversationId, turnTools.systemPrompt);
      final calls = <ToolCallRequest>[];
      final textBuffer = StringBuffer();
      final reasoningBuffer = StringBuffer();
      String? failure;
      ModelTurnDone? done;
      if (_cancelRequested) {
        // Stopped while the skill directory or the history was being read:
        // nothing has been sent yet, so there is nothing to abort or persist.
        await _finishCancelled(conversationId, null, null);
        return;
      }

      // Times this round only. The adapter's own stopwatch is preferred when it
      // reports one, but a loop-side measurement keeps the figure available for
      // adapters that do not (and for the live rate, which needs a number while
      // the round is still running).
      final roundWatch = Stopwatch()..start();

      turnEvents:
      await for (final event in adapter.runTurn(
        messages: history,
        tools: turnTools.specs,
      )) {
        if (_cancelRequested) {
          break turnEvents;
        }
        switch (event) {
          case ModelTextDelta(:final text):
            textBuffer.write(text);
            _metrics.inFlightChars = textBuffer.length;
            _metrics.inFlightElapsed = roundWatch.elapsed;
            _emit(_state.copyWith(
              generating: true,
              streamingText: textBuffer.toString(),
              usage: _metrics.snapshot(),
            ));
          case ModelReasoningDelta(:final text):
            reasoningBuffer.write(text);
            // Reasoning is shown while it streams but deliberately not fed
            // into streamingText: it is thinking, not the answer.
            _emit(_state.copyWith(
              generating: true,
              reasoningText: reasoningBuffer.toString(),
              usage: _metrics.snapshot(),
            ));
          case ModelToolCall(:final call):
            calls.add(call);
          case ModelTurnDone():
            done = event;
          case ModelTurnCancelled():
            // The adapter stopped because this loop asked it to; setting the
            // flag keeps one code path for a real adapter and for a fake that
            // reports the event directly.
            _cancelRequested = true;
            break turnEvents;
          case ModelFailure(:final message):
            failure = message;
        }
      }
      roundWatch.stop();

      // Fold the round in before the failure check: tokens the provider already
      // generated and billed for are real whether or not the round ended well.
      final roundUsage = done?.usage;
      if (roundUsage != null) {
        _metrics.recordRound(
          roundUsage,
          done?.generationDuration ?? roundWatch.elapsed,
        );
      }
      _metrics.inFlightChars = 0;
      _metrics.inFlightElapsed = Duration.zero;

      if (_cancelRequested) {
        await _finishCancelled(conversationId, textBuffer, reasoningBuffer);
        return;
      }

      if (failure != null) {
        // Keep whatever text arrived before the failure: a partial answer is
        // still an answer. A failure that produced only thinking writes no
        // assistant row: a content-less bubble would read as an empty answer.
        if (textBuffer.isNotEmpty) {
          await repository.addMessage(
            conversationId: conversationId,
            role: AiRepository.roleAssistant,
            content: textBuffer.isEmpty ? null : textBuffer.toString(),
            reasoning: _reasoningOrNull(reasoningBuffer),
          );
        }
        _emit(_state.copyWith(
          generating: false,
          error: failure,
          usage: _metrics.snapshot(),
        ));
        return;
      }

      if (calls.isEmpty) {
        await repository.addMessage(
          conversationId: conversationId,
          role: AiRepository.roleAssistant,
          content: textBuffer.isEmpty ? null : textBuffer.toString(),
          reasoning: _reasoningOrNull(reasoningBuffer),
        );
        _emit(_state.copyWith(
          generating: false,
          streamingText: '',
          rounds: _metrics.rounds,
          usage: _metrics.snapshot(),
        ));
        return;
      }

      final pending = <PendingCall>[];
      final group = TurnGroup(
        assistantText: textBuffer.isEmpty ? null : textBuffer.toString(),
        assistantReasoning: _reasoningOrNull(reasoningBuffer),
      );

      for (final call in calls) {
        final tool = registry.byName(call.name) ?? turnTools.byName(call.name);
        final action = tool?.actionOf(call.arguments) ?? call.name;
        final risk = tool?.riskFor(action) ?? ToolRisk.write;
        final reversible = tool?.reversibleFor(action) ?? false;
        final decision = approval.adjudicate(
          toolName: call.name,
          risk: risk,
          reversible: reversible,
        );

        final record = await repository.recordAction(
          conversationId: conversationId,
          toolCallId: call.id,
          toolName: call.name,
          risk: risk.id,
          argsJson: call.rawArguments,
          status: tool == null
              ? AiRepository.statusFailed
              : AiRepository.statusPending,
          resultJson:
              tool == null ? jsonEncode({'error': '未知工具 ${call.name}'}) : null,
        );

        if (tool == null || call.parseError != null) {
          // Report the problem back to the model instead of dropping the call.
          group.addReply(call.id, {
            'ok': false,
            'error': call.parseError ?? '未知工具 ${call.name}',
          });
          continue;
        }

        final item = PendingCall(
          call: call,
          tool: tool,
          decision: decision,
          actionId: record.id,
        );

        if (decision.runsWithoutAsking) {
          await _execute(conversationId, item, group);
        } else {
          group.callIds.add(call.id);
          pending.add(item);
        }
      }

      if (pending.isNotEmpty) {
        // The turn cannot be written yet: it still has calls with no reply, and
        // a half-answered turn is not a valid history. It is committed by
        // approvePending / rejectPending once the user has decided. The
        // proposals themselves are already on the ledger for audit.
        _metrics.toolCallsPending = pending.length;
        _emit(_state.copyWith(
          generating: false,
          streamingText: textBuffer.toString(),
          pending: pending,
          pendingTurn: group,
          rounds: _metrics.rounds,
          usage: _metrics.snapshot(),
        ));
        return;
      }

      await _commitTurn(conversationId, group);
    }

    // C3: the cap was reached. Say so plainly rather than stopping silently.
    final notice = '已达到本轮工具调用上限（$maxRounds 轮），先停在这里。'
        '如果需要继续，请再发一条消息。';
    await repository.addMessage(
      conversationId: conversationId,
      role: AiRepository.roleAssistant,
      content: notice,
    );
    _emit(_state.copyWith(
      generating: false,
      streamingText: '',
      error: notice,
      rounds: _metrics.rounds,
      usage: _metrics.snapshot(),
    ));
  }

  /// Ends the turn as cancelled.
  ///
  /// Whatever answer text arrived before the stop is persisted, because it is
  /// real output the user may want to keep; nothing else is written. No error
  /// is reported: the user is the one who stopped it, so there is nothing to
  /// explain. Tool calls proposed but never executed are dropped with the turn.
  Future<void> _finishCancelled(
    String conversationId,
    StringBuffer? textBuffer,
    StringBuffer? reasoningBuffer,
  ) async {
    final partial = textBuffer?.toString() ?? '';
    // A turn stopped before its first token leaves nothing on screen, so it
    // writes nothing: persisting thinking alone would create an assistant
    // bubble with no answer (and a write that can outlive the page).
    if (partial.isNotEmpty) {
      await repository.addMessage(
        conversationId: conversationId,
        role: AiRepository.roleAssistant,
        content: partial,
        reasoning:
            reasoningBuffer == null ? null : _reasoningOrNull(reasoningBuffer),
      );
    }
    _metrics.inFlightChars = 0;
    _metrics.inFlightElapsed = Duration.zero;
    _emit(_state.copyWith(
      generating: false,
      cancelled: true,
      rounds: _metrics.rounds,
      usage: _metrics.snapshot(),
    ));
  }

  /// The reasoning text to persist: null when the provider never streamed any
  /// (an empty string would look like "the model thought nothing").
  static String? _reasoningOrNull(StringBuffer buffer) =>
      buffer.isEmpty ? null : buffer.toString();

  /// Writes a completed turn: the assistant message, then one tool reply per
  /// call, in call order.
  ///
  /// The group is committed **once**; a second call is a no-op, which is what
  /// makes approve/reject idempotent and safe to retry.
  Future<void> _commitTurn(String conversationId, TurnGroup group) async {
    if (group.messageId != null || !group.isComplete) {
      return;
    }
    final message = await repository.addMessage(
      conversationId: conversationId,
      role: AiRepository.roleAssistant,
      content: group.assistantText,
      reasoning: group.assistantReasoning,
    );
    group.messageId = message.id;
    for (final callId in group.callIds) {
      await repository.addMessage(
        conversationId: conversationId,
        role: AiRepository.roleTool,
        toolCallId: callId,
        content: jsonEncode(group.replies[callId]),
      );
      await repository.attachMessageId(
        conversationId: conversationId,
        toolCallId: callId,
        messageId: message.id,
      );
    }
  }

  /// Runs one approved (or auto-approved) call and records the outcome.
  ///
  /// The reply is added to [group] rather than written directly, so the turn is
  /// only persisted once it is complete.
  Future<void> _execute(
    String conversationId,
    PendingCall item,
    TurnGroup group,
  ) async {
    final alreadyReplied = group.replies.containsKey(item.call.id);
    if (alreadyReplied) {
      return;
    }
    final record = (await repository.listActions(conversationId))
        .where((a) => a.id == item.actionId)
        .toList();
    final alreadyDone = record.isNotEmpty &&
        (record.first.status == AiRepository.statusExecuted ||
            record.first.status == AiRepository.statusRejected);
    if (alreadyDone) {
      group.addReply(
        item.call.id,
        jsonDecode(record.first.resultJson ?? '{}').cast<String, Object?>(),
      );
      return;
    }

    ToolResult result;
    try {
      result = await item.tool.run(ToolInvocation(
        toolName: item.tool.name,
        action: item.tool.actionOf(item.call.arguments),
        arguments: item.call.arguments,
        callId: item.call.id,
      ));
    } on ToolArgError catch (e) {
      result = ToolResult.failure(e.message);
    } catch (e) {
      // A real failure (database, disk, a process that would not start) must not
      // kill the conversation.
      result = ToolResult.failure('执行失败：$e');
    }

    // Counted here and not in `_drive`, because this is the one place a call
    // really runs: the two early returns above are replays of an earlier call,
    // and counting those would report the same step twice.
    _metrics.toolCallsExecuted++;

    await repository.updateActionStatus(
      item.actionId,
      status:
          result.ok ? AiRepository.statusExecuted : AiRepository.statusFailed,
      beforeJson: result.beforeJson,
      afterJson: result.afterJson,
      resultJson: jsonEncode(result.toModelJson()),
    );

    // The reply joins the turn instead of being written on its own: a tool
    // message without its assistant message is exactly what the provider
    // rejects.
    group.addReply(item.call.id, result.toModelJson());

    _emit(_state.copyWith(
      executed: [
        ..._state.executed,
        ExecutedCall(
          toolName: item.tool.name,
          summary: result.summary,
          result: result,
          actionId: item.actionId,
          undone: false,
        ),
      ],
      usage: _metrics.snapshot(),
    ));
  }

  /// Rebuilds the provider-facing history from storage.
  ///
  /// [systemPrompt] is passed in rather than built here because the skill read
  /// that produces it also produces this turn's skill tools (see [_turnTools]);
  /// reading the skill directory twice per round would risk the prompt and the
  /// tool list describing two different sets of skills.
  ///
  /// Rebuilt every round rather than kept in memory: the database is the source
  /// of truth, so a restart mid-conversation loses nothing, and the loop cannot
  /// drift from what the user sees.
  ///
  /// A tool-calling turn is emitted as a **contiguous group** - the assistant
  /// message followed by one tool message per call - because the provider
  /// rejects a history where a `tool_call_id` is not answered immediately
  /// afterwards. Grouping also makes the order independent of the order the
  /// rows happened to be written in (the assistant message is written last, see
  /// [_drive], precisely so an incomplete turn never exists on disk).
  Future<List<ChatMessage>> _buildHistory(
    String conversationId,
    String systemPrompt,
  ) async {
    final rows = await repository.listMessages(conversationId);
    final actions = await repository.listCommittedActions(conversationId);

    final byMessage = <String, List<AiActionRecord>>{};
    for (final action in actions) {
      final messageId = action.messageId;
      if (messageId == null) {
        continue;
      }
      byMessage.putIfAbsent(messageId, () => []).add(action);
    }

    final messages = <ChatMessage>[
      ChatMessage.system(systemPrompt),
    ];

    for (final row in rows) {
      switch (row.role) {
        case AiRepository.roleUser:
          // The images stored for this message go straight back into the
          // request: a follow-up question about the same photo has to be able to
          // see it, exactly like the turn it arrived in.
          messages.add(ChatMessage.user(
            row.content ?? '',
            images: await _imageParts(row.id),
          ));
        case AiRepository.roleAssistant:
          final turn = byMessage[row.id];
          if (turn == null || turn.isEmpty) {
            if (row.content == null || row.content!.isEmpty) {
              continue;
            }
            messages.add(ChatMessage.assistant(content: row.content));
            break;
          }
          // The turn's tool calls, then their answers, in the order the calls
          // were made. Ordering by the call list (not by row timestamps) keeps
          // request and reply paired even if a reply was written late.
          messages.add(ChatMessage.assistant(
            content: row.content,
            toolCalls: [
              for (final action in turn)
                if (action.toolCallId != null)
                  ToolCallRequest(
                    id: action.toolCallId!,
                    name: action.toolName,
                    rawArguments: action.argsJson ?? '{}',
                    arguments: _decodeArgs(action.argsJson ?? '{}'),
                  ),
            ],
          ));
          for (final action in turn) {
            if (action.toolCallId == null) {
              continue;
            }
            messages.add(ChatMessage.tool(
              action.resultJson ??
                  jsonEncode(
                      {'ok': action.status == AiRepository.statusExecuted}),
              toolCallId: action.toolCallId!,
            ));
          }
        case AiRepository.roleTool:
          // Committed turns already emitted their tool replies above. A `tool`
          // row without a matching committed action would be an orphan, and
          // sending one is exactly what the provider rejects.
          break;
        case AiRepository.roleSystem:
          messages.add(ChatMessage.system(row.content ?? ''));
      }
    }
    return messages;
  }

  Map<String, Object?> _decodeArgs(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return decoded.cast<String, Object?>();
      }
    } on FormatException {
      // The original failure is already on the ledger; an empty map keeps the
      // history readable.
    }
    return const {};
  }

  /// The stored images of one message, as provider content parts.
  ///
  /// An empty list for every message without pictures, which is what keeps the
  /// text-only request shape untouched.
  ///
  /// Bounded for the same reason as [_systemPrompt]'s skill read: reading a
  /// picture means resolving the app support directory, and a turn must never be
  /// able to freeze on that. The store's own policy already treats an unreadable
  /// picture as a droppable one, so a stall gets the same answer - this message
  /// goes without its image rather than not at all. The ceiling is generous on
  /// purpose: it exists to catch a stall, not a slow disk.
  Future<List<ChatImagePart>> _imageParts(String messageId) async {
    final store = attachments;
    if (store == null) {
      return const [];
    }
    try {
      return await store.partsForMessage(messageId).timeout(imageReadTimeout);
    } catch (_) {
      return const [];
    }
  }

  /// The system prompt: the fixed rules, plus whatever the user's enabled
  /// skills contribute.
  ///
  /// The base text is built here and the skill block is appended by
  /// [SkillPrompt.build] - a pure function, so "which skills reached the model,
  /// and in what order" is answerable by a test without a conversation.
  String _systemPrompt(String rules, List<InstalledSkill> enabled) =>
      SkillPrompt.build(rules, enabled);

  /// Everything one model round needs from the skill directory: the system
  /// prompt, and the declared tools of the same enabled skills.
  ///
  /// **One read, two uses.** A round reads the skills exactly once, because two
  /// reads could see two different states - a skill enabled between them would
  /// either describe itself in the prompt while being absent from the tool list,
  /// or the reverse - and the honest answer to "what is enabled right now" has
  /// to be a single answer. A disabled skill contributes nothing here, which is
  /// what makes "disabled means disabled" true for tools as well as for prompt
  /// text (spec §5.5).
  ///
  /// The read is advisory and bounded for exactly the reasons the skill prompt
  /// always was: the install directory can be slow or absent (a widget test has
  /// no `path_provider`), and "no skills this turn" is an acceptable answer while
  /// "the assistant never answers" is not.
  Future<_TurnTools> _turnTools() async {
    final rules = _baseRules(await _userPersonaBlock());
    final store = skills;
    if (store == null) {
      return _TurnTools(systemPrompt: rules, builtInTools: registry.all);
    }
    try {
      final enabled = await store.enabled().timeout(skillReadTimeout);
      return _TurnTools(
        systemPrompt: _systemPrompt(rules, enabled),
        builtInTools: registry.all,
        skillTools: [
          for (final skill in enabled)
            ...declareSkillTools(
              skill: skill,
              runner: skillRunner ?? const SkillRunner(),
              platform: skillPlatform ?? SkillPlatform.current,
            ),
        ],
      );
    } catch (_) {
      return _TurnTools(systemPrompt: rules, builtInTools: registry.all);
    }
  }

  /// The persona paragraph for this turn: the user's own description of
  /// themselves (schema v35), or `''` when they never wrote one.
  ///
  /// Advisory and bounded exactly like the skill read: a missing database, a
  /// missing column or a corrupt row must never stop a turn. "No persona" is an
  /// acceptable answer; "the assistant never answers" is not.
  ///
  /// `''` is load-bearing: [_baseRules] weaves this in so that a user without a
  /// persona gets the **byte-identical** prompt they got before this feature
  /// existed (docs/PERSONA_DESIGN.md §5).
  Future<String> _userPersonaBlock() async {
    try {
      final raw = await SettingsRepository(db).getUserPersona();
      return userPersonaPromptBlock(raw);
    } catch (_) {
      return '';
    }
  }

  /// The date, the persona and the rules that predate skills.
  ///
  /// `personaBlock` is empty for "the user never wrote one" (see
  /// [_userPersonaBlock]); when it is non-empty it lands as its own paragraph
  /// between the date and the rules, so the rules a model reads stay last and
  /// the persona reads as background rather than as an instruction.
  ///
  /// With an empty `personaBlock` the output is byte-identical to what the loop
  /// sent before persona existed, so that "no persona" keeps meaning "the old
  /// behaviour exactly" (as "skills disabled" does).
  String _baseRules(String personaBlock) {
    final now = DateTime.now();
    final date =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    const base = '你是 Furnace 的助手，直接操作用户的任务、日程、标签与复习数据。';
    final persona = personaBlock.isEmpty ? '' : '$personaBlock\n';
    return '$base\n'
        '今天的日期是 $date。\n'
        '$persona'
        '规则：\n'
        '1. 需要知道现状时先用查询工具，不要凭猜测回答。\n'
        '2. 涉及修改时，先查清楚再动手；能一次完成的不要拆成多次。\n'
        '3. 删除类操作需要用户逐条确认，这是设计如此，不要因此反复重试。\n'
        '4. 要动某个标签、闪存卡或卡片时，先用 query_content 找到它的 id 再操作；'
        '要新增标签就调 create_tags（可指定父标签的 id 或路径，用来搭标签树）；'
        '要把闪存卡挂进卡组（卡组就是标签）就调 link_card_tags，'
        '卡如果已经带完整来源路径，可以用 from_source_paths 批量匹配（先 dry_run 预览）；'
        '要给卡组设每天的新卡/复习量就调 manage_review_plan（先用 query_content(kind: review_plan) 看现状）；'
        '用户说"下周要考试、把某一部分提前进复习"时调 focus_review（标签子树下未来几天到期的卡提前到今天，'
        '默认 dry_run 只预览，确认后再写）；'
        '不要凭记忆猜名字，猜错只会得到"找不到"，而查是免费的。\n'
        '5. 用中文回答，简洁直接，不要复述你已经做过的事的细节。\n'
        '6. 要"生成文档 / 导出文件"时用 create_document，文档是写在'
        '<appSupport>/documents 里的文件；把返回的 path 原样告诉用户，'
        '不要声称已经发送、上传或分享过任何东西。';
  }

  /// Applies a before-snapshot. Returns false when the action has none.
  Future<bool> _undo(AiActionRecord record) async {
    // A `create` has no "before" - nothing existed. It is undone by removing
    // what it produced, so this branch has to come first: checking for a
    // before-snapshot at the top would refuse to undo every creation.
    if (_isCreate(record)) {
      final after = record.afterJson;
      if (after == null) {
        return false;
      }
      return _deleteCreated(record.toolName, after);
    }

    final before = record.beforeJson;
    if (before == null) {
      return false;
    }
    final snapshot = jsonDecode(before);
    if (snapshot is! Map) {
      return false;
    }
    final map = snapshot.cast<String, Object?>();

    switch (record.toolName) {
      case DeleteContentTool.toolName:
        // Deletion is the only action whose snapshot holds rows from several
        // tables; the tool writes them parents-first so this one call is enough.
        return restoreDeletedContent(db, map);
      case 'manage_task':
        await restoreTask(db, map);
        return true;
      case 'manage_time_block':
        await restoreTimeBlock(db, map);
        return true;
      case ManageReviewPlanTool.toolName:
        // A plan set/clear is undone by putting the previous row back; a
        // first-time set has no old row and undo clears the plan (null snapshot).
        return restoreReviewPlan(db, map);
      case ReviewFocusTool.toolName:
        // Pulled cards are undone by writing each `due_at` back to the value
        // the before-snapshot recorded.
        return restoreReviewFocus(db, map);
      default:
        return false;
    }
  }

  bool _isCreate(AiActionRecord record) {
    // `create_knowledge_cards` creates a set of rows, so its "before" state is
    // "nothing existed" just like `manage_task(create)` - it simply has no
    // `action` argument to say so. `link_card_tags` is the same shape: undo is
    // "remove the links it made", not "restore an old row".
    if (record.toolName == CreateTagsTool.toolName ||
        record.toolName == CreateKnowledgeCardsTool.toolName ||
        record.toolName == LinkCardTagsTool.toolName ||
        record.toolName == CreateDocumentTool.toolName) {
      return true;
    }
    final args = _decodeArgs(record.argsJson ?? '{}');
    return args['action'] == 'create';
  }

  /// Undo for a create: delete the row it produced.
  Future<bool> _deleteCreated(String toolName, String afterJson) async {
    final decoded = jsonDecode(afterJson);
    if (decoded is! Map) {
      return false;
    }
    final map = decoded.cast<String, Object?>();
    switch (toolName) {
      case CreateTagsTool.toolName:
        return deleteCreatedTags(db, map);
      case CreateKnowledgeCardsTool.toolName:
        return deleteCreatedKnowledgeCards(db, map);
      case LinkCardTagsTool.toolName:
        // Undo for the link half: remove exactly the object_tags rows this call
        // added, leaving cards the user grouped themselves untouched.
        return unlinkCardTags(db, map);
      case CreateDocumentTool.toolName:
        // A document is a file, not a row: the snapshot names the file and the
        // helper deletes exactly that one (tools/document_tools.dart).
        return deleteCreatedDocuments(map);
      case 'manage_task':
        final task = map['task'] as Map?;
        final id = task?['id'] as String?;
        if (id == null) {
          return false;
        }
        await (db.delete(db.tasks)..where((t) => t.id.equals(id))).go();
        await (db.delete(db.taskDependencies)
              ..where(
                  (t) => t.taskId.equals(id) | t.dependsOnTaskId.equals(id)))
            .go();
        return true;
      case 'manage_time_block':
        final id = map['id'] as String?;
        if (id == null) {
          return false;
        }
        await (db.delete(db.timeBlocks)..where((t) => t.id.equals(id))).go();
        return true;
      default:
        return false;
    }
  }
}

/// The declared script tools of one enabled skill, wired to [runner].
///
/// A skill's tools are derived from two places that have to agree: `tools/*.json`
/// says what the model may ask for, and `manifest.json`'s `scripts[]` says which
/// file that becomes. The join is by name ([SkillToolDeclaration.name] against
/// [SkillScriptDeclaration.name]), and a declaration with no script is still
/// built - with `script: null` - so the model can be told why the call cannot
/// run instead of the tool silently not existing.
///
/// A pure function of (skill, runner, platform), which is what lets the gating
/// rule be tested without a conversation, a database or a device.
List<SkillTool> declareSkillTools({
  required InstalledSkill skill,
  required SkillRunner runner,
  required SkillPlatform platform,
}) {
  final byName = <String, SkillScriptDeclaration>{
    for (final script in skill.manifest.scripts) script.name: script,
  };
  return [
    for (final declaration in skill.tools)
      SkillTool(
        skill: skill,
        declaration: declaration,
        script: byName[declaration.name],
        runner: runner,
        platform: platform,
      ),
  ];
}

/// What one model round offers: the tools the provider sees, and the system
/// prompt built from the same read of the skill directory.
///
/// Keeping them in one object is the point. The two are produced together
/// because they must agree about which skills are enabled; a round that offered
/// a tool from a skill the prompt did not mention (or the reverse) would be a
/// state the user never asked for.
class _TurnTools {
  _TurnTools({
    required this.systemPrompt,
    required List<AiTool> builtInTools,
    List<SkillTool> skillTools = const [],
  })  : specs = [
          for (final tool in builtInTools)
            if (tool.availableOnCurrentPlatform)
              ModelToolSpec(
                name: tool.name,
                description: tool.description,
                parameters: tool.parameters,
              ),
          for (final tool in skillTools)
            if (tool.availableOnCurrentPlatform)
              ModelToolSpec(
                name: tool.name,
                description: tool.description,
                parameters: tool.parameters,
              ),
        ],
        _byName = {
          for (final tool in skillTools) tool.name: tool,
        };

  final String systemPrompt;

  /// The provider-facing declarations for this round: the registry's tools for
  /// this platform, followed by the enabled skills' script tools.
  ///
  /// A skill tool is included only when [AiTool.availableOnCurrentPlatform]
  /// says so, which is the §5.5 gate: on a platform without a Node runtime the
  /// tools are **absent from the list**, not present and failing when called.
  final List<ModelToolSpec> specs;

  final Map<String, SkillTool> _byName;

  /// The skill tool named [name], or `null` - which is how a call to a skill
  /// that is not enabled right now reaches the loop's "unknown tool" path and is
  /// recorded as a failure rather than executed.
  SkillTool? byName(String name) => _byName[name];
}

/// The mutable accumulation behind [TurnUsage].
///
/// [TurnUsage] has to stay immutable - the page rebuilds off the state object -
/// while the loop adds to the same totals from several places: the streaming
/// loop, tool execution and the approval handlers. Keeping those writes in one
/// small object is what stops each of them from inventing its own addend.
class _TurnMetrics {
  _TurnMetrics({required this.maxRounds, required this.contextWindowTokens});

  final int maxRounds;
  final int contextWindowTokens;

  int rounds = 0;
  int roundsWithUsage = 0;
  int promptTokens = 0;
  int completionTokens = 0;
  int? cacheHitPromptTokens;
  int? cacheMissPromptTokens;
  Duration generationTime = Duration.zero;
  int? lastPromptTokens;
  int toolCallsExecuted = 0;
  int toolCallsPending = 0;
  int toolCallsRejected = 0;
  int inFlightChars = 0;
  Duration inFlightElapsed = Duration.zero;

  /// Folds one finished round in.
  ///
  /// [generation] is the round's generation wall time. Cache tokens accumulate
  /// only for rounds that reported them: a round that stayed silent must not be
  /// treated as a round that cached nothing, or the ratio would drift towards
  /// zero for a reason that has nothing to do with caching.
  void recordRound(ModelUsage usage, Duration generation) {
    roundsWithUsage++;
    promptTokens += usage.promptTokens;
    completionTokens += usage.completionTokens;
    lastPromptTokens = usage.promptTokens;
    generationTime += generation;
    final hit = usage.cacheHitPromptTokens;
    if (hit != null) {
      cacheHitPromptTokens = (cacheHitPromptTokens ?? 0) + hit;
    }
    final miss = usage.cacheMissPromptTokens;
    if (miss != null) {
      cacheMissPromptTokens = (cacheMissPromptTokens ?? 0) + miss;
    }
  }

  TurnUsage snapshot() => TurnUsage(
        rounds: rounds,
        maxRounds: maxRounds,
        roundsWithUsage: roundsWithUsage,
        promptTokens: promptTokens,
        completionTokens: completionTokens,
        cacheHitPromptTokens: cacheHitPromptTokens,
        cacheMissPromptTokens: cacheMissPromptTokens,
        generationTime: generationTime,
        lastPromptTokens: lastPromptTokens,
        contextWindowTokens: contextWindowTokens,
        toolCallsExecuted: toolCallsExecuted,
        toolCallsPending: toolCallsPending,
        toolCallsRejected: toolCallsRejected,
        inFlightChars: inFlightChars,
        inFlightElapsed: inFlightElapsed,
      );
}
