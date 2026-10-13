// Usage as the *loop* produces it.
//
// The panel reads one object - AgentTurnState.usage - so these tests drive the
// real loop with scripted adapters and assert on that object: that two rounds
// add up, that an approval continues the same turn instead of restarting its
// counters, that refused calls are counted as refusals, and that a provider
// which reports nothing leaves the unmeasurable figures null.
import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/ai_repository.dart';
import 'package:furnace/data/repositories/task_repository.dart';
import 'package:furnace/data/repositories/time_block_repository.dart';
import 'package:furnace/features/ai/domain/agent_loop.dart';
import 'package:furnace/features/ai/domain/approval_engine.dart';
import 'package:furnace/features/ai/domain/model_adapter.dart';
import 'package:furnace/features/ai/domain/tool_registry.dart';
import 'package:furnace/features/ai/infrastructure/fake_model_adapter.dart';
import 'package:furnace/features/ai/tools/schedule_tools.dart';
import 'package:furnace/features/ai/tools/task_tools.dart';

/// A model that takes real wall time *outside* the generation it reports.
///
/// The delay stands in for everything the loop does around a round - running a
/// tool, waiting for an approval - which must not end up in the tokens/s
/// denominator.
class _SlowOutsideGenerationAdapter implements ModelAdapter {
  _SlowOutsideGenerationAdapter(this.delay);

  final Duration delay;

  @override
  Stream<ModelEvent> runTurn({
    required List<ChatMessage> messages,
    required List<ModelToolSpec> tools,
  }) async* {
    await Future<void>.delayed(delay);
    yield const ModelTextDelta('好');
    yield const ModelTurnDone(
      finishReason: 'stop',
      promptTokens: 20,
      completionTokens: 100,
      generationDuration: Duration(seconds: 2),
    );
  }
}

/// A model whose second piece of text waits for the test to release it, so the
/// mid-stream state can be inspected while the turn is still running.
class _GatedStreamAdapter implements ModelAdapter {
  final Completer<void> gate = Completer<void>();

  @override
  Stream<ModelEvent> runTurn({
    required List<ChatMessage> messages,
    required List<ModelToolSpec> tools,
  }) async* {
    // A real delay before the first character, so "generation time so far" is
    // unambiguously non-zero when the delta is observed.
    await Future<void>.delayed(const Duration(milliseconds: 20));
    yield const ModelTextDelta('part one');
    await gate.future;
    yield const ModelTextDelta(' part two');
    yield const ModelTurnDone(
      finishReason: 'stop',
      promptTokens: 30,
      completionTokens: 40,
      generationDuration: Duration(milliseconds: 500),
    );
  }
}

void main() {
  late AppDatabase db;
  late TaskRepository tasks;
  late TimeBlockRepository blocks;
  late AiRepository repository;
  late ToolRegistry registry;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    tasks = TaskRepository(db);
    blocks = TimeBlockRepository(db);
    repository = AiRepository(db);
    registry = ToolRegistry([
      QueryTasksTool(tasks, db),
      ManageTaskTool(tasks, db),
      QueryScheduleTool(blocks),
      ManageTimeBlockTool(blocks, db),
    ]);
  });

  tearDown(() async {
    await db.close();
  });

  AgentLoop buildLoop(
    ModelAdapter adapter, {
    AiPermissionMode mode = AiPermissionMode.auto,
    int maxRounds = AgentLoop.defaultMaxRounds,
    int contextWindowTokens = AgentLoop.defaultContextWindowTokens,
  }) =>
      AgentLoop(
        adapter: adapter,
        registry: registry,
        approval: ApprovalEngine(mode: mode),
        repository: repository,
        db: db,
        maxRounds: maxRounds,
        contextWindowTokens: contextWindowTokens,
      );

  /// Runs [action] and returns the state the loop settled on.
  Future<AgentTurnState> settle(
    AgentLoop loop,
    Future<void> Function() action,
  ) async {
    final states = <AgentTurnState>[];
    final sub = loop.states.listen(states.add);
    await action();
    await Future<void>.delayed(Duration.zero);
    await sub.cancel();
    return states.isEmpty ? loop.state : states.last;
  }

  test('two rounds accumulate, and the last prompt is the context', () async {
    final adapter = FakeModelAdapter([
      [
        const ModelToolCall(ToolCallRequest(
          id: 'c1',
          name: 'query_tasks',
          rawArguments: '{"limit":1}',
          arguments: {'limit': 1},
        )),
        const ModelTurnDone(
          finishReason: 'tool_calls',
          promptTokens: 1000,
          completionTokens: 40,
          cacheHitPromptTokens: 900,
          cacheMissPromptTokens: 100,
          generationDuration: Duration(seconds: 2),
        ),
      ],
      [
        const ModelTextDelta('好了'),
        const ModelTurnDone(
          finishReason: 'stop',
          promptTokens: 1200,
          completionTokens: 60,
          cacheHitPromptTokens: 1000,
          cacheMissPromptTokens: 200,
          generationDuration: Duration(seconds: 1),
        ),
      ],
    ]);
    final loop = buildLoop(adapter);
    final conversation = await repository.createConversation();

    final state = await settle(
      loop,
      () => loop.sendUserMessage(conversationId: conversation.id, text: '查一下'),
    );

    final usage = state.usage;
    expect(state.rounds, 2);
    expect(usage.rounds, 2);
    expect(usage.maxRounds, AgentLoop.defaultMaxRounds);
    expect(usage.roundsWithUsage, 2);
    expect(usage.promptTokens, 2200);
    expect(usage.completionTokens, 100);
    expect(usage.totalTokens, 2300);
    // 1900 hits out of the 2200 prompt tokens actually reported.
    expect(usage.cacheHitRatio, closeTo(1900 / 2200, 1e-12));
    expect(usage.cacheAccountingIsPartial, isFalse);
    // (2 s + 1 s) of generation for 100 completion tokens.
    expect(usage.tokensPerSecond, closeTo(100 / 3, 1e-9));
    // Context occupancy is the *last* round's prompt, not the sum.
    expect(usage.lastPromptTokens, 1200);
    expect(usage.contextUsageRatio, closeTo(1200 / 65536, 1e-12));
    expect(usage.toolCallsExecuted, 1);
    expect(usage.toolCallsPending, 0);
    expect(usage.toolCallsRejected, 0);
  });

  test('the rate divides by generation time, not by the turn wall time',
      () async {
    // The adapter spends 150 ms doing something that is not generation, and
    // reports a 2 s generation window for 100 completion tokens.
    final loop = buildLoop(
      _SlowOutsideGenerationAdapter(const Duration(milliseconds: 150)),
    );
    final conversation = await repository.createConversation();

    final state = await settle(
      loop,
      () => loop.sendUserMessage(conversationId: conversation.id, text: '你好'),
    );

    // Exactly 50: the 150 ms is nowhere in the arithmetic. Dividing by the
    // loop's own elapsed time would have produced 46.5 or a random float.
    expect(state.usage.tokensPerSecond, closeTo(50, 1e-9));
  });

  test('the live rate is available while the round is still streaming',
      () async {
    final adapter = _GatedStreamAdapter();
    final loop = buildLoop(adapter);
    final conversation = await repository.createConversation();

    final states = <AgentTurnState>[];
    final sub = loop.states.listen(states.add);
    final send = loop.sendUserMessage(
      conversationId: conversation.id,
      text: '写一段',
    );

    // Wait for the first delta to reach the state, then look at what the panel
    // would have been drawing at that moment.
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (states.every((s) => s.streamingText.isEmpty) &&
        DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }
    final mid = states.lastWhere((s) => s.streamingText.isNotEmpty);
    expect(mid.generating, isTrue);
    expect(mid.streamingText, 'part one');
    expect(mid.usage.inFlightChars, 'part one'.length);
    expect(mid.usage.liveTokensPerSecond, isNotNull,
        reason: 'the in-flight round has characters and elapsed time');
    // Nothing has been reported yet, so the frozen figures stay unmeasured.
    expect(mid.usage.hasUsage, isFalse);
    expect(mid.usage.tokensPerSecond, isNull);

    adapter.gate.complete();
    await send;
    await Future<void>.delayed(Duration.zero);
    await sub.cancel();

    final done = states.last;
    expect(done.generating, isFalse);
    expect(done.usage.completionTokens, 40);
    expect(done.usage.inFlightChars, 0,
        reason: 'the estimate is dropped once real usage arrives');
    expect(done.usage.tokensPerSecond, closeTo(80, 1e-9));
  });

  test('an approval continues the same turn instead of restarting it',
      () async {
    final adapter = FakeModelAdapter([
      FakeModelAdapter.callTool(
        'query_tasks',
        {'limit': 5},
        id: 'call_read',
      ),
      [
        const ModelTextDelta('好了'),
        const ModelTurnDone(
          finishReason: 'stop',
          promptTokens: 300,
          completionTokens: 10,
          generationDuration: Duration(seconds: 1),
        ),
      ],
    ]);
    final loop = buildLoop(adapter, mode: AiPermissionMode.plan);
    final conversation = await repository.createConversation();

    final pending = await settle(
      loop,
      () => loop.sendUserMessage(conversationId: conversation.id, text: '先看看'),
    );
    expect(pending.usage.rounds, 1);
    expect(pending.usage.toolCallsPending, 1);
    expect(pending.usage.toolCallsExecuted, 0);

    final approved = await settle(
      loop,
      () => loop.approvePending(conversation.id),
    );
    expect(approved.rounds, 2,
        reason: 'round 2 belongs to the same user message as round 1');
    expect(approved.usage.rounds, 2);
    expect(approved.usage.toolCallsPending, 0);
    expect(approved.usage.toolCallsExecuted, 1);
    expect(approved.usage.completionTokens, 10);
  });

  test('refused calls are counted as refusals, never as executions', () async {
    final adapter = FakeModelAdapter([
      [
        const ModelToolCall(ToolCallRequest(
          id: 'c1',
          name: 'manage_task',
          rawArguments: '{"action":"delete","id":"a"}',
          arguments: {'action': 'delete', 'id': 'a'},
        )),
        const ModelToolCall(ToolCallRequest(
          id: 'c2',
          name: 'manage_task',
          rawArguments: '{"action":"delete","id":"b"}',
          arguments: {'action': 'delete', 'id': 'b'},
        )),
        const ModelTurnDone(finishReason: 'tool_calls'),
      ],
    ]);
    final loop = buildLoop(adapter);
    final conversation = await repository.createConversation();

    final pending = await settle(
      loop,
      () => loop.sendUserMessage(conversationId: conversation.id, text: '删'),
    );
    expect(pending.usage.toolCallsPending, 2);

    final rejected = await settle(
      loop,
      () => loop.rejectPending(conversation.id),
    );
    expect(rejected.usage.toolCallsPending, 0);
    expect(rejected.usage.toolCallsRejected, 2);
    expect(rejected.usage.toolCallsExecuted, 0);
  });

  test('a provider that reports nothing leaves the figures unmeasured',
      () async {
    // `ModelTurnDone` with no token counts at all: an older endpoint, or one
    // that ignores stream_options.include_usage.
    final adapter = FakeModelAdapter([
      [
        const ModelTextDelta('好的'),
        const ModelTurnDone(finishReason: 'stop'),
      ],
    ]);
    final loop = buildLoop(adapter);
    final conversation = await repository.createConversation();

    final state = await settle(
      loop,
      () => loop.sendUserMessage(conversationId: conversation.id, text: '在吗'),
    );

    // Rounds were still counted, because the loop knows how many it made.
    expect(state.usage.rounds, 1);
    expect(state.usage.isEmpty, isFalse);
    // The token figures were not, and are dashes rather than zeros.
    expect(state.usage.hasUsage, isFalse);
    expect(state.usage.totalTokens, 0);
    expect(state.usage.cacheHitRatio, isNull);
    expect(state.usage.tokensPerSecond, isNull);
    expect(state.usage.contextUsageRatio, isNull);
  });

  test('the next user message starts a new turn with fresh usage', () async {
    final adapter = FakeModelAdapter([
      [
        const ModelTextDelta('第一轮'),
        const ModelTurnDone(
          finishReason: 'stop',
          promptTokens: 900,
          completionTokens: 90,
          generationDuration: Duration(seconds: 3),
        ),
      ],
      [
        const ModelTextDelta('第二轮'),
        const ModelTurnDone(
          finishReason: 'stop',
          promptTokens: 100,
          completionTokens: 10,
          generationDuration: Duration(seconds: 1),
        ),
      ],
    ]);
    final loop = buildLoop(adapter);
    final conversation = await repository.createConversation();

    await settle(loop, () => loop.sendUserMessage(
        conversationId: conversation.id, text: '第一句'));
    final second = await settle(loop, () => loop.sendUserMessage(
        conversationId: conversation.id, text: '第二句'));

    expect(second.usage.rounds, 1);
    expect(second.usage.promptTokens, 100,
        reason: 'the previous turn must not bleed into this one');
    expect(second.usage.completionTokens, 10);
    expect(second.usage.tokensPerSecond, closeTo(10, 1e-9));
  });

  test('the cap is reported against the configured value', () async {
    final adapter = FakeModelAdapter([
      for (var i = 0; i < 5; i++)
        FakeModelAdapter.callTool('query_tasks', {'limit': 1}, id: 'call_$i'),
    ]);
    final loop = buildLoop(adapter, maxRounds: 3);
    final conversation = await repository.createConversation();

    final state = await settle(
      loop,
      () => loop.sendUserMessage(conversationId: conversation.id, text: '一直查'),
    );

    expect(state.rounds, 3);
    expect(state.usage.rounds, 3);
    expect(state.usage.maxRounds, 3,
        reason: 'the panel shows used/cap, so the cap has to travel with it');
  });
}
