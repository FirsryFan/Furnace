import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/ai_repository.dart';
import 'package:furnace/data/repositories/task_repository.dart';
import 'package:furnace/data/repositories/time_block_repository.dart';
import 'package:furnace/features/ai/domain/agent_loop.dart';
import 'package:furnace/features/ai/domain/approval_engine.dart';
import 'package:furnace/features/ai/domain/tool_registry.dart';
import 'package:furnace/features/ai/infrastructure/fake_model_adapter.dart';
import 'package:furnace/features/ai/tools/schedule_tools.dart';
import 'package:furnace/features/ai/tools/task_tools.dart';

/// The turn timeline is what turns a silent wait into visible progress: the
/// chat page draws one card per step while the turn is still running. These
/// tests pin the facts a page cannot infer on its own - when a step appears,
/// when it stops running, and what it says when it is over - because a card
/// that keeps spinning after the tool returned is worse than no card at all.
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
      );

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

  test('a plain answer is one finished model step', () async {
    final adapter = FakeModelAdapter([FakeModelAdapter.answer('你好')]);
    final loop = buildLoop(adapter);
    final conversation = await repository.createConversation();

    final state = await settle(
      loop,
      () => loop.sendUserMessage(conversationId: conversation.id, text: '在吗'),
    );

    expect(state.steps, hasLength(1));
    final step = state.steps.single;
    expect(step.kind, AgentStepKind.model);
    expect(step.round, 1);
    expect(step.status, AgentStepStatus.done);
    expect(step.isRunning, isFalse);
    expect(step.finishedAt, isNotNull);
    expect(step.elapsed, isNotNull);
    expect(state.runningStep, isNull);
  });

  test('a tool call gets its own step, with the label and the result',
      () async {
    final adapter = FakeModelAdapter([
      FakeModelAdapter.callTool(
          'manage_task', {'action': 'create', 'title': '买牛奶'}),
      FakeModelAdapter.answer('加好了'),
    ]);
    final loop = buildLoop(adapter);
    final conversation = await repository.createConversation();

    final state = await settle(
      loop,
      () => loop.sendUserMessage(conversationId: conversation.id, text: '加个任务'),
    );

    expect(state.steps, hasLength(3));
    expect(
      state.steps.map((s) => s.kind),
      [
        AgentStepKind.model,
        AgentStepKind.tool,
        AgentStepKind.model,
      ],
    );
    final toolStep = state.steps[1];
    expect(toolStep.toolName, 'manage_task');
    expect(toolStep.round, 1);
    expect(toolStep.detail, '买牛奶');
    expect(toolStep.status, AgentStepStatus.done);
    expect(toolStep.ok, isTrue);
    expect(toolStep.summary, isNotEmpty);
    expect(state.steps.last.round, 2);
    expect(state.steps.last.status, AgentStepStatus.done);
  });

  test('a pending call is waiting, not running', () async {
    final adapter = FakeModelAdapter([
      FakeModelAdapter.callTool(
          'manage_task', {'action': 'create', 'title': '写作业'}),
      FakeModelAdapter.answer('好'),
    ]);
    final loop = buildLoop(adapter, mode: AiPermissionMode.plan);
    final conversation = await repository.createConversation();

    final pendingState = await settle(
      loop,
      () => loop.sendUserMessage(conversationId: conversation.id, text: '加任务'),
    );

    expect(pendingState.hasPending, isTrue);
    expect(pendingState.steps, hasLength(2));
    final toolStep = pendingState.steps.last;
    expect(toolStep.kind, AgentStepKind.tool);
    expect(toolStep.isWaiting, isTrue);
    expect(toolStep.isRunning, isFalse);
    expect(toolStep.finishedAt, isNull);
    expect(pendingState.runningStep, isNull);
  });

  test('approval finishes the waiting step, then runs the next round',
      () async {
    final adapter = FakeModelAdapter([
      FakeModelAdapter.callTool(
          'manage_task', {'action': 'create', 'title': '写作业'}),
      FakeModelAdapter.answer('好'),
    ]);
    final loop = buildLoop(adapter, mode: AiPermissionMode.plan);
    final conversation = await repository.createConversation();
    await settle(
      loop,
      () => loop.sendUserMessage(conversationId: conversation.id, text: '加任务'),
    );

    final state =
        await settle(loop, () => loop.approvePending(conversation.id));

    expect(state.hasPending, isFalse);
    expect(state.steps, hasLength(3));
    final toolStep = state.steps[1];
    expect(toolStep.status, AgentStepStatus.done);
    expect(toolStep.ok, isTrue);
    expect(toolStep.finishedAt, isNotNull);
    expect(state.steps.last.kind, AgentStepKind.model);
    expect(state.steps.last.round, 2);
  });

  test('a refused call is a cancelled step, not a success', () async {
    final adapter = FakeModelAdapter([
      FakeModelAdapter.callTool(
          'manage_task', {'action': 'create', 'title': '写作业'}),
      FakeModelAdapter.answer('好'),
    ]);
    final loop = buildLoop(adapter, mode: AiPermissionMode.plan);
    final conversation = await repository.createConversation();
    await settle(
      loop,
      () => loop.sendUserMessage(conversationId: conversation.id, text: '加任务'),
    );

    final state = await settle(loop, () => loop.rejectPending(conversation.id));

    final toolStep = state.steps[1];
    expect(toolStep.status, AgentStepStatus.cancelled);
    expect(toolStep.ok, isFalse);
    expect(toolStep.isFinished, isTrue);
  });

  test('a provider failure marks the round as failed', () async {
    final adapter = FakeModelAdapter([FakeModelAdapter.failure('网络断了')]);
    final loop = buildLoop(adapter);
    final conversation = await repository.createConversation();

    final state = await settle(
      loop,
      () => loop.sendUserMessage(conversationId: conversation.id, text: '你好'),
    );

    expect(state.error, contains('网络断了'));
    expect(state.steps, hasLength(1));
    expect(state.steps.single.status, AgentStepStatus.failed);
    expect(state.steps.single.ok, isFalse);
    expect(state.steps.single.summary, contains('网络断了'));
  });

  test('an unknown tool is a failed step rather than a silent gap', () async {
    final adapter = FakeModelAdapter([
      FakeModelAdapter.callTool('no_such_tool', {}),
      FakeModelAdapter.answer('好'),
    ]);
    final loop = buildLoop(adapter);
    final conversation = await repository.createConversation();

    final state = await settle(
      loop,
      () => loop.sendUserMessage(conversationId: conversation.id, text: '做事'),
    );

    final toolStep = state.steps[1];
    expect(toolStep.toolName, 'no_such_tool');
    expect(toolStep.status, AgentStepStatus.failed);
    expect(toolStep.summary, contains('未知工具'));
  });

  test('a new user message starts a fresh timeline', () async {
    final adapter = FakeModelAdapter([
      FakeModelAdapter.answer('第一轮回答'),
      FakeModelAdapter.answer('第二轮回答'),
    ]);
    final loop = buildLoop(adapter);
    final conversation = await repository.createConversation();
    await settle(
      loop,
      () => loop.sendUserMessage(conversationId: conversation.id, text: '第一句'),
    );

    final state = await settle(
      loop,
      () => loop.sendUserMessage(conversationId: conversation.id, text: '第二句'),
    );

    expect(state.steps, hasLength(1));
    expect(state.steps.single.round, 1);
  });

  test('cancelling a pending batch closes its waiting step', () async {
    final adapter = FakeModelAdapter([
      FakeModelAdapter.callTool(
          'manage_task', {'action': 'create', 'title': '写作业'}),
      FakeModelAdapter.answer('好'),
    ]);
    final loop = buildLoop(adapter, mode: AiPermissionMode.plan);
    final conversation = await repository.createConversation();
    await settle(
      loop,
      () => loop.sendUserMessage(conversationId: conversation.id, text: '加任务'),
    );

    final state = await settle(loop, () async => loop.cancel());

    expect(state.hasPending, isFalse);
    final toolStep = state.steps[1];
    expect(toolStep.status, AgentStepStatus.cancelled);
    expect(toolStep.isFinished, isTrue);
  });
}
