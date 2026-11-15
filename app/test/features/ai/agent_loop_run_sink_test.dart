import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/app_database_provider.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/ai_repository.dart';
import 'package:furnace/data/repositories/task_repository.dart';
import 'package:furnace/data/repositories/time_block_repository.dart';
import 'package:furnace/features/ai/application/ai_providers.dart';
import 'package:furnace/features/ai/domain/agent_budget.dart';
import 'package:furnace/features/ai/domain/agent_loop.dart';
import 'package:furnace/features/ai/domain/agent_preset.dart';
import 'package:furnace/features/ai/domain/agent_run.dart' as agent_run;
import 'package:furnace/features/ai/domain/agent_run_sink.dart';
import 'package:furnace/features/ai/domain/approval_engine.dart';
import 'package:furnace/features/ai/domain/step_guard.dart';
import 'package:furnace/features/ai/domain/tool_registry.dart';
import 'package:furnace/features/ai/infrastructure/agent_run_store.dart';
import 'package:furnace/features/ai/infrastructure/fake_model_adapter.dart';
import 'package:furnace/features/ai/tools/schedule_tools.dart';
import 'package:furnace/features/ai/tools/task_tools.dart';

/// 主 `AgentLoop` 接入全局 `AgentRun` / `StepGuard`（设计文档 §3.1 / §7.1 / §7.2）。
///
/// 要锁住的是三件事，按重要性排序：
///
///  * **默认行为不变**：不注入 sink/guard 时一条 `agent_runs` / `agent_steps`
///    都不写，对话结果与旧版一致——这是本任务「无默认行为变化」的验收条件；
///  * **注入后普通对话有 run/steps**：每个用户回合一条 run（覆盖创建、每步、
///    正常结束 / 取消 / 失败 / 被 guard 终止），每个模型回合一条 step；
///  * **guard 判定必须真的拦住循环**：`stop` / `forceAnswer` 之后不再执行本轮
///    工具、不再跑下一轮模型，并且 `stop_reason` 与用户可见的 error 都在。
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
    FakeModelAdapter adapter, {
    AgentRunSink? sink,
    StepGuard? guard,
    AiPermissionMode mode = AiPermissionMode.auto,
    int maxRounds = 8,
  }) =>
      AgentLoop(
        adapter: adapter,
        registry: registry,
        approval: ApprovalEngine(mode: mode),
        repository: repository,
        db: db,
        maxRounds: maxRounds,
        runSink: sink,
        stepGuard: guard,
      );

  /// Runs [action] and returns the state the loop settled on (same helper the
  /// existing loop tests use, so "ended" means the same thing here).
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

  group('默认不注入：行为与旧版一致', () {
    test('不写 agent_runs / agent_steps，对话照常落库', () async {
      final adapter = FakeModelAdapter([FakeModelAdapter.answer('你好')]);
      final loop = buildLoop(adapter);
      final conversation = await repository.createConversation();

      final state = await settle(
        loop,
        () => loop.sendUserMessage(
          conversationId: conversation.id,
          text: '在吗',
        ),
      );

      expect(state.error, isNull);
      expect(await db.select(db.agentRuns).get(), isEmpty);
      expect(await db.select(db.agentSteps).get(), isEmpty);
      final messages = await repository.listMessages(conversation.id);
      expect(messages.map((m) => m.role), ['user', 'assistant']);
      expect(messages.last.content, '你好');
    });

    test('只注入 sink、没有 guard：重复动作不会被拦（旧行为）', () async {
      final adapter = FakeModelAdapter([
        for (var i = 0; i < 3; i++)
          FakeModelAdapter.callTool(
            'query_tasks',
            {'limit': 1},
            id: 'call_$i',
          ),
        FakeModelAdapter.answer('查完了'),
      ]);
      final sink = _FakeSink();
      final loop = buildLoop(adapter, sink: sink);
      final conversation = await repository.createConversation();

      final state = await settle(
        loop,
        () => loop.sendUserMessage(
          conversationId: conversation.id,
          text: '一直查',
        ),
      );

      expect(state.error, isNull);
      expect(adapter.requests, hasLength(4), reason: '三次查询 + 一次回答');
      expect(sink.runs.last.status, agent_run.AgentRunStatus.answered);
      expect(sink.steps, hasLength(4));
    });
  });

  group('注入 sink：普通对话的 run / step', () {
    test('一次工具回合的 run 覆盖创建/终态，每个模型回合一条 step', () async {
      final adapter = FakeModelAdapter([
        FakeModelAdapter.callTool('query_tasks', {'limit': 1}),
        FakeModelAdapter.answer('查完了'),
      ]);
      final sink = _FakeSink();
      final loop = buildLoop(adapter, sink: sink);
      final conversation = await repository.createConversation();

      final state = await settle(
        loop,
        () => loop.sendUserMessage(
          conversationId: conversation.id,
          text: '看看任务',
        ),
      );

      expect(state.error, isNull);
      // 创建时一行 running，正常结束时 answered。
      expect(sink.statuses.first, agent_run.AgentRunStatus.running);
      expect(sink.statuses.last, agent_run.AgentRunStatus.answered);

      // 同一个可变对象会随 run 推进而更新，最终值就是落定的值。
      final run = sink.runs.last;
      expect(run.mode, agent_run.AgentMode.chat);
      expect(run.presetId, 'assistant');
      expect(run.conversationId, conversation.id);
      expect(run.status, agent_run.AgentRunStatus.answered);
      expect(run.phase, agent_run.AgentPhase.present);
      expect(run.stopReason, isNull);
      expect(run.steps, 2);
      expect(run.endedAt, isNotNull);
      expect(run.durationMs, isNotNull);

      // 每个模型回合一条 step：seq 连续、kind=model、带状态指纹。
      expect(sink.steps, hasLength(2));
      expect(
        sink.steps.map((step) => step.kind),
        everyElement(agent_run.AgentStepKind.model),
      );
      expect(sink.steps.map((step) => step.seq), [0, 1]);
      expect(
        sink.steps.map((step) => step.runId).toSet(),
        {run.id},
      );
      for (final step in sink.steps) {
        expect(step.phase, agent_run.AgentPhase.solve);
        expect(step.stateFingerprint, isNotEmpty);
        expect(step.summary, contains('回合'));
      }
    });

    test('AgentRunStoreSink 把 run / step 真正写进 v45 表', () async {
      final adapter = FakeModelAdapter([FakeModelAdapter.answer('好了')]);
      final loop = buildLoop(
        adapter,
        sink: AgentRunStoreSink(AgentRunStore(db)),
      );
      final conversation = await repository.createConversation();

      await settle(
        loop,
        () => loop.sendUserMessage(
          conversationId: conversation.id,
          text: '在吗',
        ),
      );

      final runs = await db.select(db.agentRuns).get();
      expect(runs, hasLength(1));
      expect(runs.single.mode, 'chat');
      expect(runs.single.presetId, 'assistant');
      expect(runs.single.status, 'answered');
      expect(runs.single.stopReason, isNull);
      expect(runs.single.conversationId, conversation.id);
      expect(runs.single.endedAt, isNotNull);
      expect(runs.single.steps, 1);

      final steps = await db.select(db.agentSteps).get();
      expect(steps, hasLength(1));
      expect(steps.single.runId, runs.single.id);
      expect(steps.single.seq, 0);
      expect(steps.single.kind, 'model');
      expect(steps.single.phase, 'solve');
      expect(steps.single.status, 'ok');
      expect(steps.single.stateFingerprint, isNotNull);
    });

    test('模型失败：run 终态 failed + stop_reason=error，step 标记失败', () async {
      final adapter = FakeModelAdapter([FakeModelAdapter.failure('网络断了')]);
      final sink = _FakeSink();
      final loop = buildLoop(adapter, sink: sink);
      final conversation = await repository.createConversation();

      final state = await settle(
        loop,
        () => loop.sendUserMessage(
          conversationId: conversation.id,
          text: '在吗',
        ),
      );

      expect(state.error, '网络断了');
      final run = sink.runs.last;
      expect(run.status, agent_run.AgentRunStatus.failed);
      expect(run.stopReason, StopReason.error);
      expect(sink.steps, hasLength(1));
      expect(sink.steps.single.status, agent_run.AgentStepStatus.failed);
    });

    test('用户取消：run 终态 stopped + stop_reason=cancelled', () async {
      final task = await tasks.createTask(title: '重要任务');
      final adapter = FakeModelAdapter([
        FakeModelAdapter.callTool(
          'manage_task',
          {'action': 'delete', 'id': task.id},
        ),
      ]);
      final sink = _FakeSink();
      final loop = buildLoop(adapter, sink: sink);
      final conversation = await repository.createConversation();

      await settle(
        loop,
        () => loop.sendUserMessage(
          conversationId: conversation.id,
          text: '删掉那个任务',
        ),
      );
      expect(loop.state.hasPending, isTrue);
      expect(sink.statuses.last, agent_run.AgentRunStatus.running);

      loop.cancel();
      // cancel() 是同步入口；run 的落定是它发起的异步写入，等一个事件循环。
      await Future<void>.delayed(Duration.zero);

      final run = sink.runs.last;
      expect(run.status, agent_run.AgentRunStatus.stopped);
      expect(run.stopReason, StopReason.cancelled);
      expect(await tasks.getTasks(), hasLength(1));
    });

    test('sink 写失败不改变本轮结果（回答照常落库、不抛异常）', () async {
      final adapter = FakeModelAdapter([FakeModelAdapter.answer('照常回答')]);
      final sink = _FakeSink()..throwOnWrite = true;
      final loop = buildLoop(adapter, sink: sink);
      final conversation = await repository.createConversation();

      final state = await settle(
        loop,
        () => loop.sendUserMessage(
          conversationId: conversation.id,
          text: '在吗',
        ),
      );

      expect(state.error, isNull);
      final messages = await repository.listMessages(conversation.id);
      expect(messages.last.content, '照常回答');
    });

    test('学生 preset 会话在拒绝分支返回，不创建 run', () async {
      final adapter = FakeModelAdapter([FakeModelAdapter.answer('不该被调用')]);
      final sink = _FakeSink();
      final loop = buildLoop(adapter, sink: sink);
      final conversation = await repository.createConversation(
        agentPreset: AgentPreset.studentSolver,
      );

      final state = await settle(
        loop,
        () => loop.sendUserMessage(
          conversationId: conversation.id,
          text: '做题',
        ),
      );

      expect(state.error, contains('学生模式'));
      expect(adapter.requests, isEmpty);
      expect(sink.runs, isEmpty);
      expect(sink.steps, isEmpty);
      expect(await db.select(db.agentRuns).get(), isEmpty);
    });
  });

  group('注入 StepGuard：判定真的终止循环', () {
    test('stop（max_steps）：不发第二轮、不执行提议的工具、写 stop_reason', () async {
      final adapter = FakeModelAdapter([
        FakeModelAdapter.callTool('query_tasks', {'limit': 1}),
        FakeModelAdapter.answer('不该到这里'),
      ]);
      final sink = _FakeSink();
      final loop = buildLoop(
        adapter,
        sink: sink,
        // 一轮就超过步数预算，让停止点确定。
        guard: StepGuard(budget: RunBudget.chat.copyWith(maxSteps: 1)),
      );
      final conversation = await repository.createConversation();

      final state = await settle(
        loop,
        () => loop.sendUserMessage(
          conversationId: conversation.id,
          text: '查一下',
        ),
      );

      expect(adapter.requests, hasLength(1), reason: '第二轮不允许发生');
      expect(state.generating, isFalse);
      expect(state.error, isNotNull);
      expect(state.error, contains('max_steps'));
      expect(state.executed, isEmpty, reason: '本轮提议的工具不能执行');
      expect(await tasks.getTasks(), isEmpty);

      final run = sink.runs.last;
      expect(run.status, agent_run.AgentRunStatus.stopped);
      expect(run.stopReason, StopReason.maxSteps);
      expect(sink.steps, hasLength(1), reason: '只记录实际发生的那一轮');
      expect(sink.steps.single.stateFingerprint, isNotEmpty);
    });

    test('forceAnswer（repeated_action）：终止本轮，不再执行第三次调用', () async {
      final adapter = FakeModelAdapter([
        for (var i = 0; i < 3; i++)
          FakeModelAdapter.callTool(
            'query_tasks',
            {'limit': 1},
            id: 'call_$i',
          ),
        FakeModelAdapter.answer('不该到这里'),
      ]);
      final sink = _FakeSink();
      final loop = buildLoop(
        adapter,
        sink: sink,
        guard: StepGuard(budget: RunBudget.chat),
      );
      final conversation = await repository.createConversation();

      final state = await settle(
        loop,
        () => loop.sendUserMessage(
          conversationId: conversation.id,
          text: '一直查同一个东西',
        ),
      );

      // 第三次判定是重复，第三次提议的工具与下一轮模型都不再发生。
      expect(adapter.requests, hasLength(3));
      expect(state.error, isNotNull);
      expect(state.error, contains('repeated_action'));

      final run = sink.runs.last;
      expect(run.status, agent_run.AgentRunStatus.stopped);
      expect(run.stopReason, StopReason.repeatedAction);
      expect(sink.steps, hasLength(3));
    });

    test('同一 loop 的第二条消息不会继承上一次 run 的 guard 历史', () async {
      // 第一轮：1 次 query（不触发）；第二轮：2 次 query（不触发）。若 guard
      // 不 reset，第二轮第 2 个回合会凑成第 3 次重复而被 forceAnswer。
      final adapter = FakeModelAdapter([
        FakeModelAdapter.callTool('query_tasks', {'limit': 1}, id: 'a1'),
        FakeModelAdapter.answer('第一问'),
        FakeModelAdapter.callTool('query_tasks', {'limit': 1}, id: 'b1'),
        FakeModelAdapter.callTool('query_tasks', {'limit': 1}, id: 'b2'),
        FakeModelAdapter.answer('第二问'),
      ]);
      final sink = _FakeSink();
      final loop = buildLoop(
        adapter,
        sink: sink,
        guard: StepGuard(budget: RunBudget.chat),
      );
      final conversation = await repository.createConversation();

      await settle(
        loop,
        () => loop.sendUserMessage(
          conversationId: conversation.id,
          text: '第一句',
        ),
      );
      final firstRun = sink.runs.last;
      expect(firstRun.status, agent_run.AgentRunStatus.answered);

      final second = await settle(
        loop,
        () => loop.sendUserMessage(
          conversationId: conversation.id,
          text: '第二句',
        ),
      );

      expect(adapter.requests, hasLength(5));
      expect(second.error, isNull);
      final secondRun = sink.runs.last;
      expect(secondRun.status, agent_run.AgentRunStatus.answered);
      expect(secondRun.id, isNot(firstRun.id));
      expect(sink.steps, hasLength(5));
    });
  });

  group('应用接线', () {
    test('agentLoopProvider 注入 AgentRunStoreSink 与 chat budget 的 guard',
        () async {
      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          modelAdapterProvider.overrideWithValue(FakeModelAdapter(const [])),
        ],
      );
      addTearDown(container.dispose);
      await container.read(aiConfigProvider.future);
      final conversation = await repository.createConversation();

      final loop = container.read(agentLoopProvider(conversation.id));

      expect(loop, isNotNull, reason: '替换了 adapter 就必须造出 loop');
      expect(loop!.runSink, isA<AgentRunStoreSink>());
      expect(loop.stepGuard, isNotNull);
      expect(loop.stepGuard!.budget.maxSteps, RunBudget.chat.maxSteps);
      expect(
        loop.stepGuard!.budget.maxReasoningTokens,
        RunBudget.chat.maxReasoningTokens,
        reason: '普通对话没有 reasoning 预算',
      );
    });

    test('经 provider 构建的 loop 真的写 agent_runs / agent_steps', () async {
      final adapter = FakeModelAdapter([FakeModelAdapter.answer('好了')]);
      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          modelAdapterProvider.overrideWithValue(adapter),
        ],
      );
      addTearDown(container.dispose);
      await container.read(aiConfigProvider.future);
      final conversation = await repository.createConversation();
      final loop = container.read(agentLoopProvider(conversation.id))!;

      await loop.sendUserMessage(
        conversationId: conversation.id,
        text: '在吗',
      );

      final runs = await db.select(db.agentRuns).get();
      expect(runs, hasLength(1));
      expect(runs.single.conversationId, conversation.id);
      expect(runs.single.mode, 'chat');
      expect(runs.single.status, 'answered');
      final steps = await db.select(db.agentSteps).get();
      expect(steps, hasLength(1));
      expect(steps.single.runId, runs.single.id);
    });
  });
}

/// A sink that records every call in memory, so a test can assert on the run
/// lifecycle without a database — and can be told to fail, which is how the
/// "an audit write must not decide the turn" contract gets a test.
class _FakeSink implements AgentRunSink {
  final List<agent_run.AgentRunState> runs = [];
  final List<agent_run.AgentRunStatus> statuses = [];
  final List<agent_run.AgentStep> steps = [];

  /// When true every write throws; the loop must still finish the turn.
  bool throwOnWrite = false;

  @override
  Future<void> saveRun(agent_run.AgentRunState run) async {
    if (throwOnWrite) {
      throw StateError('sink write failed');
    }
    runs.add(run);
    statuses.add(run.status);
  }

  @override
  Future<void> appendStep(agent_run.AgentStep step) async {
    if (throwOnWrite) {
      throw StateError('sink write failed');
    }
    steps.add(step);
  }
}
