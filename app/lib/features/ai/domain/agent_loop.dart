import 'dart:async';
import 'dart:convert';

// Needed for the `|` operator on drift expressions: it is an extension member,
// so a `show` clause that names only types would hide it.
import 'package:drift/drift.dart';

import '../../../data/database/database.dart';
import '../../../data/repositories/ai_repository.dart';
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
  TurnGroup({required this.assistantText});

  /// Text the model emitted alongside the calls, if any.
  final String? assistantText;

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

/// The conversation as the UI sees it.
class AgentTurnState {
  const AgentTurnState({
    this.generating = false,
    this.streamingText = '',
    this.pending = const [],
    this.pendingTurn,
    this.executed = const [],
    this.error,
    this.rounds = 0,
  });

  /// A model call is in flight.
  final bool generating;

  /// Assistant text received so far in this turn.
  final String streamingText;

  /// Calls that need a decision before anything happens.
  final List<PendingCall> pending;

  /// The turn those calls belong to. Held in memory: an unfinished turn is not
  /// valid history, so it must not reach the database before it is complete.
  final TurnGroup? pendingTurn;

  /// Calls that have already run (automatically or after approval).
  final List<ExecutedCall> executed;

  /// User-facing failure text, e.g. a provider error.
  final String? error;

  /// How many model round-trips this turn used.
  final int rounds;

  bool get hasPending => pending.isNotEmpty;
  bool get isIdle => !generating && !hasPending;

  AgentTurnState copyWith({
    bool? generating,
    String? streamingText,
    List<PendingCall>? pending,
    TurnGroup? pendingTurn,
    List<ExecutedCall>? executed,
    String? error,
    int? rounds,
    bool clearError = false,
    bool clearPendingTurn = false,
  }) =>
      AgentTurnState(
        generating: generating ?? this.generating,
        streamingText: streamingText ?? this.streamingText,
        pending: pending ?? this.pending,
        pendingTurn: clearPendingTurn ? null : (pendingTurn ?? this.pendingTurn),
        executed: executed ?? this.executed,
        error: clearError ? null : (error ?? this.error),
        rounds: rounds ?? this.rounds,
      );
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
    this.maxRounds = 8,
  });

  final ModelAdapter adapter;
  final ToolRegistry registry;
  final ApprovalEngine approval;
  final AiRepository repository;
  final AppDatabase db;

  /// Ceiling on model round-trips per user message. Eight is enough for
  /// "look something up, then act on it, then confirm" without letting a loop
  /// run away with the user's credit.
  final int maxRounds;

  final _states = StreamController<AgentTurnState>.broadcast();
  AgentTurnState _state = const AgentTurnState();

  Stream<AgentTurnState> get states => _states.stream;
  AgentTurnState get state => _state;

  void dispose() => _states.close();

  void _emit(AgentTurnState next) {
    _state = next;
    if (!_states.isClosed) {
      _states.add(next);
    }
  }

  /// Sends one user message and drives the loop until the model is done.
  ///
  /// Returns normally in every case: provider failures become [error] on the
  /// state, because losing a turn to an exception would throw away the user's
  /// message too.
  Future<void> sendUserMessage({
    required String conversationId,
    required String text,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      return;
    }
    if (_state.hasPending) {
      // Driving a new turn while a previous one is unresolved would leave the
      // model's tool calls unanswered in the history, and the provider rejects
      // that with a 400. The UI already disables its input here; this guard
      // makes the invariant true for every caller.
      return;
    }
    _emit(const AgentTurnState(generating: true));
    await repository.addMessage(
      conversationId: conversationId,
      role: AiRepository.roleUser,
      content: trimmed,
    );
    await _drive(conversationId);
  }

  /// Executes the calls the user approved, then lets the model continue.
  Future<void> approvePending(String conversationId) async {
    final pending = _state.pending;
    final group = _state.pendingTurn;
    if (pending.isEmpty || group == null) {
      return;
    }
    _emit(_state.copyWith(
      pending: const [],
      pendingTurn: group,
      generating: true,
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
    await _commitTurn(conversationId, group);
    _emit(_state.copyWith(pending: const [], clearPendingTurn: true));
  }

  /// Undoes one executed call by applying its before-snapshot.
  ///
  /// Only create/update/delete of tasks and time blocks are undoable today; a
  /// call with no snapshot cannot be undone and the UI does not offer it.
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
    var rounds = 0;
    while (rounds < maxRounds) {
      rounds++;
      _emit(_state.copyWith(generating: true, rounds: rounds, clearError: true));

      final history = await _buildHistory(conversationId);
      final calls = <ToolCallRequest>[];
      final textBuffer = StringBuffer();
      String? failure;

      await for (final event in adapter.runTurn(
        messages: history,
        tools: registry.modelSpecs,
      )) {
        switch (event) {
          case ModelTextDelta(:final text):
            textBuffer.write(text);
            _emit(_state.copyWith(
              generating: true,
              streamingText: textBuffer.toString(),
            ));
          case ModelToolCall(:final call):
            calls.add(call);
          case ModelTurnDone():
            break;
          case ModelFailure(:final message):
            failure = message;
        }
      }

      if (failure != null) {
        // Keep whatever text arrived before the failure: a partial answer is
        // still an answer.
        if (textBuffer.isNotEmpty) {
          await repository.addMessage(
            conversationId: conversationId,
            role: AiRepository.roleAssistant,
            content: textBuffer.toString(),
          );
        }
        _emit(_state.copyWith(generating: false, error: failure));
        return;
      }

      if (calls.isEmpty) {
        await repository.addMessage(
          conversationId: conversationId,
          role: AiRepository.roleAssistant,
          content: textBuffer.isEmpty ? null : textBuffer.toString(),
        );
        _emit(_state.copyWith(
          generating: false,
          streamingText: '',
          rounds: rounds,
        ));
        return;
      }

      final pending = <PendingCall>[];
      final group = TurnGroup(
        assistantText: textBuffer.isEmpty ? null : textBuffer.toString(),
      );

      for (final call in calls) {
        final tool = registry.byName(call.name);
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
          resultJson: tool == null
              ? jsonEncode({'error': '未知工具 ${call.name}'})
              : null,
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
        _emit(_state.copyWith(
          generating: false,
          streamingText: textBuffer.toString(),
          pending: pending,
          pendingTurn: group,
          rounds: rounds,
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
      rounds: rounds,
    ));
  }

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
      // A real failure (database, disk) must not kill the conversation.
      result = ToolResult.failure('执行失败：$e');
    }

    await repository.updateActionStatus(
      item.actionId,
      status: result.ok
          ? AiRepository.statusExecuted
          : AiRepository.statusFailed,
      beforeJson: result.beforeJson,
      afterJson: result.afterJson,
      resultJson: jsonEncode(result.toModelJson()),
    );

    // The reply joins the turn instead of being written on its own: a tool
    // message without its assistant message is exactly what the provider
    // rejects.
    group.addReply(item.call.id, result.toModelJson());

    _emit(_state.copyWith(executed: [
      ..._state.executed,
      ExecutedCall(
        toolName: item.tool.name,
        summary: result.summary,
        result: result,
        actionId: item.actionId,
        undone: false,
      ),
    ]));
  }

  /// Rebuilds the provider-facing history from storage.
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
  Future<List<ChatMessage>> _buildHistory(String conversationId) async {
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
      ChatMessage.system(_systemPrompt()),
    ];

    for (final row in rows) {
      switch (row.role) {
        case AiRepository.roleUser:
          messages.add(ChatMessage.user(row.content ?? ''));
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
                  jsonEncode({'ok': action.status == AiRepository.statusExecuted}),
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

  String _systemPrompt() {
    final now = DateTime.now();
    final date =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    return '你是 Furnace 的助手，直接操作用户的任务、日程、标签与复习数据。\n'
        '今天的日期是 $date。\n'
        '规则：\n'
        '1. 需要知道现状时先用查询工具，不要凭猜测回答。\n'
        '2. 涉及修改时，先查清楚再动手；能一次完成的不要拆成多次。\n'
        '3. 删除类操作需要用户逐条确认，这是设计如此，不要因此反复重试。\n'
        '4. 用中文回答，简洁直接，不要复述你已经做过的事的细节。';
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
      case 'manage_task':
        await restoreTask(db, map);
        return true;
      case 'manage_time_block':
        await restoreTimeBlock(db, map);
        return true;
      default:
        return false;
    }
  }

  bool _isCreate(AiActionRecord record) {
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
      case 'manage_task':
        final task = map['task'] as Map?;
        final id = task?['id'] as String?;
        if (id == null) {
          return false;
        }
        await (db.delete(db.tasks)..where((t) => t.id.equals(id))).go();
        await (db.delete(db.taskDependencies)
              ..where((t) => t.taskId.equals(id) | t.dependsOnTaskId.equals(id)))
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
