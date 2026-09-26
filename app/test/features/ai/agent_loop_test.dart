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

/// The agent loop is where the user's rules actually take effect, so these
/// tests are about behaviour a user would notice:
///
///  * deletion asks, and asking is not skipped by any mode;
///  * an approved change really lands in the database (which is what makes the
///    main screens refresh by themselves);
///  * a rejected call is told to the model, so it does not simply ask again;
///  * the round cap stops a runaway loop and says so.
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

  /// Runs [action] and returns the state the loop settled on.
  ///
  /// The loop is streaming, so the final state is whatever the last event says;
  /// this waits for the stream to go quiet rather than guessing a delay.
  Future<AgentTurnState> settle(
    AgentLoop loop,
    Future<void> Function() action,
  ) async {
    final states = <AgentTurnState>[];
    final sub = loop.states.listen(states.add);
    await action();
    // Give the broadcast stream a chance to flush its final event.
    await Future<void>.delayed(Duration.zero);
    await sub.cancel();
    return states.isEmpty ? loop.state : states.last;
  }

  group('a plain answer', () {
    test('text is stored and the turn ends', () async {
      final adapter = FakeModelAdapter([
        FakeModelAdapter.answer('你好，有什么可以帮你？'),
      ]);
      final loop = buildLoop(adapter);
      final conversation = await repository.createConversation();

      final state = await settle(
        loop,
        () => loop.sendUserMessage(
            conversationId: conversation.id, text: '在吗'),
      );

      expect(state.generating, isFalse);
      expect(state.hasPending, isFalse);
      expect(state.error, isNull);

      final messages = await repository.listMessages(conversation.id);
      expect(messages.map((m) => m.role), ['user', 'assistant']);
      expect(messages.last.content, '你好，有什么可以帮你？');
    });

    test('the conversation history is sent in order', () async {
      final adapter = FakeModelAdapter([FakeModelAdapter.answer('好的')]);
      final loop = buildLoop(adapter);
      final conversation = await repository.createConversation();

      await settle(loop, () => loop.sendUserMessage(
          conversationId: conversation.id, text: '第一句'));

      final sent = adapter.requests.single.messages;
      // A system prompt, then the user message.
      expect(sent.first.role, 'system');
      expect(sent.first.content, contains('Furnace'));
      expect(sent.last.role, 'user');
      expect(sent.last.content, '第一句');
    });

    test('the tools are declared to the model', () async {
      final adapter = FakeModelAdapter([FakeModelAdapter.answer('好')]);
      final loop = buildLoop(adapter);
      final conversation = await repository.createConversation();
      await settle(loop, () => loop.sendUserMessage(
          conversationId: conversation.id, text: 'hi'));

      final names = adapter.requests.single.tools.map((t) => t.name).toList();
      expect(names, contains('manage_task'));
      expect(names, contains('query_tasks'));
      expect(names, contains('manage_time_block'));
    });

    test('an empty message is ignored rather than sent', () async {
      final adapter = FakeModelAdapter([FakeModelAdapter.answer('x')]);
      final loop = buildLoop(adapter);
      final conversation = await repository.createConversation();
      await settle(loop, () => loop.sendUserMessage(
          conversationId: conversation.id, text: '   '));
      expect(adapter.requests, isEmpty);
    });
  });

  group('auto mode: reversible writes happen immediately', () {
    test('a created task really exists afterwards', () async {
      // This is the "deep integration" claim: the AI acts through the same
      // repository the UI uses, so the Thread screen picks the change up with
      // no refresh code anywhere.
      final adapter = FakeModelAdapter([
        FakeModelAdapter.callTool(
            'manage_task', {'action': 'create', 'title': '买牛奶'}),
        FakeModelAdapter.answer('已经加好了。'),
      ]);
      final loop = buildLoop(adapter);
      final conversation = await repository.createConversation();

      final state = await settle(
        loop,
        () => loop.sendUserMessage(
            conversationId: conversation.id, text: '帮我加个任务：买牛奶'),
      );

      expect(state.hasPending, isFalse);
      expect(state.executed, hasLength(1));
      expect(state.executed.single.result.ok, isTrue);

      // Read through the repository, not the tool.
      final stored = await tasks.getTasks();
      expect(stored.single.title, '买牛奶');
    });

    test('the model is told what happened, then answers', () async {
      final adapter = FakeModelAdapter([
        FakeModelAdapter.callTool(
            'manage_task', {'action': 'create', 'title': '写作业'}),
        FakeModelAdapter.answer('好了。'),
      ]);
      final loop = buildLoop(adapter);
      final conversation = await repository.createConversation();
      await settle(loop, () => loop.sendUserMessage(
          conversationId: conversation.id, text: '加任务'));

      // Second round-trip must include the tool result, or the model cannot know
      // whether its call worked.
      final second = adapter.requests[1].messages;
      final toolMessage = second.lastWhere((m) => m.role == 'tool');
      expect(toolMessage.toolCallId, 'call_1');
      expect(toolMessage.content, contains('写作业'));
    });

    test('several calls in one turn all run', () async {
      final adapter = FakeModelAdapter([
        [
          const ModelToolCall(ToolCallRequest(
            id: 'c1',
            name: 'manage_task',
            rawArguments: '{"action":"create","title":"A"}',
            arguments: {'action': 'create', 'title': 'A'},
          )),
          const ModelToolCall(ToolCallRequest(
            id: 'c2',
            name: 'manage_task',
            rawArguments: '{"action":"create","title":"B"}',
            arguments: {'action': 'create', 'title': 'B'},
          )),
          const ModelTurnDone(finishReason: 'tool_calls'),
        ],
        FakeModelAdapter.answer('两个都加好了。'),
      ]);
      final loop = buildLoop(adapter);
      final conversation = await repository.createConversation();
      await settle(loop, () => loop.sendUserMessage(
          conversationId: conversation.id, text: '加两个任务'));

      final titles = (await tasks.getTasks()).map((t) => t.title).toList();
      expect(titles, containsAll(['A', 'B']));
    });

    test('every executed call is recorded on the ledger', () async {
      final adapter = FakeModelAdapter([
        FakeModelAdapter.callTool(
            'manage_task', {'action': 'create', 'title': '可追溯'}),
        FakeModelAdapter.answer('好'),
      ]);
      final loop = buildLoop(adapter);
      final conversation = await repository.createConversation();
      await settle(loop, () => loop.sendUserMessage(
          conversationId: conversation.id, text: 'x'));

      final actions = await repository.listActions(conversation.id);
      final action = actions.single;
      expect(action.status, AiRepository.statusExecuted);
      expect(action.risk, 'write');
      expect(action.argsJson, contains('可追溯'));
      expect(action.afterJson, isNotNull);
    });
  });

  group('deletion always asks', () {
    test('auto mode stops and asks instead of deleting', () async {
      final task = await tasks.createTask(title: '重要任务');
      final adapter = FakeModelAdapter([
        FakeModelAdapter.callTool(
            'manage_task', {'action': 'delete', 'id': task.id}),
      ]);
      final loop = buildLoop(adapter);
      final conversation = await repository.createConversation();

      final state = await settle(
        loop,
        () => loop.sendUserMessage(
            conversationId: conversation.id, text: '删掉那个任务'),
      );

      // The task is still there, and the user is being asked.
      expect(state.hasPending, isTrue);
      expect(state.pending.single.tool.name, 'manage_task');
      expect(state.pending.single.decision.reason, contains('删除'));
      expect(await tasks.getTasks(), hasLength(1));
    });

    test('approving it deletes', () async {
      final task = await tasks.createTask(title: '删我');
      final adapter = FakeModelAdapter([
        FakeModelAdapter.callTool(
            'manage_task', {'action': 'delete', 'id': task.id}),
        FakeModelAdapter.answer('删掉了。'),
      ]);
      final loop = buildLoop(adapter);
      final conversation = await repository.createConversation();
      await settle(loop, () => loop.sendUserMessage(
          conversationId: conversation.id, text: '删'));

      final state = await settle(
        loop,
        () => loop.approvePending(conversation.id),
      );

      expect(state.hasPending, isFalse);
      expect(await tasks.getTasks(), isEmpty);
    });

    test('rejecting it keeps the task and tells the model', () async {
      final task = await tasks.createTask(title: '别删我');
      final adapter = FakeModelAdapter([
        FakeModelAdapter.callTool(
            'manage_task', {'action': 'delete', 'id': task.id}),
        FakeModelAdapter.answer('好的，不删了。'),
      ]);
      final loop = buildLoop(adapter);
      final conversation = await repository.createConversation();
      await settle(loop, () => loop.sendUserMessage(
          conversationId: conversation.id, text: '删'));

      await settle(loop, () => loop.rejectPending(conversation.id));

      expect(await tasks.getTasks(), hasLength(1),
          reason: 'a rejection must never have a side effect');
      final messages = await repository.listMessages(conversation.id);
      final rejection = messages.lastWhere((m) => m.role == 'tool');
      expect(rejection.content, contains('拒绝'));
      expect(rejection.toolCallId, 'call_1');
    });

    test('a rejected call is still on the ledger as rejected', () async {
      final task = await tasks.createTask(title: 'x');
      final adapter = FakeModelAdapter([
        FakeModelAdapter.callTool(
            'manage_task', {'action': 'delete', 'id': task.id}),
      ]);
      final loop = buildLoop(adapter);
      final conversation = await repository.createConversation();
      await settle(loop, () => loop.sendUserMessage(
          conversationId: conversation.id, text: '删'));
      await settle(loop, () => loop.rejectPending(conversation.id));

      final action = (await repository.listActions(conversation.id)).single;
      expect(action.status, AiRepository.statusRejected);
    });
  });

  group('plan mode: reversible writes are batched', () {
    test('a create waits for one batch approval', () async {
      final adapter = FakeModelAdapter([
        FakeModelAdapter.callTool(
            'manage_task', {'action': 'create', 'title': '等确认'}),
        FakeModelAdapter.answer('加好了。'),
      ]);
      final loop = buildLoop(adapter, mode: AiPermissionMode.plan);
      final conversation = await repository.createConversation();

      final pendingState = await settle(
        loop,
        () => loop.sendUserMessage(conversationId: conversation.id, text: '加任务'),
      );
      expect(pendingState.hasPending, isTrue);
      expect(pendingState.pending.single.decision.disposition.name,
          'batchApproval');
      expect(await tasks.getTasks(), isEmpty,
          reason: 'nothing may happen before the approval');

      await settle(loop, () => loop.approvePending(conversation.id));
      expect((await tasks.getTasks()).single.title, '等确认');
    });
  });

  group('bad model behaviour is handled, not crashed on', () {
    test('an unknown tool is reported back instead of throwing', () async {
      final adapter = FakeModelAdapter([
        FakeModelAdapter.callTool('no_such_tool', {'x': 1}),
        FakeModelAdapter.answer('抱歉，我换个方式。'),
      ]);
      final loop = buildLoop(adapter);
      final conversation = await repository.createConversation();
      final state = await settle(loop, () => loop.sendUserMessage(
          conversationId: conversation.id, text: 'x'));

      expect(state.error, isNull);
      final toolMessage = (await repository.listMessages(conversation.id))
          .lastWhere((m) => m.role == 'tool');
      expect(toolMessage.content, contains('未知工具'));
    });

    test('arguments that failed to parse are reported back', () async {
      final adapter = FakeModelAdapter([
        FakeModelAdapter.callToolWithBadArguments('manage_task'),
        FakeModelAdapter.answer('我重试一下。'),
      ]);
      final loop = buildLoop(adapter);
      final conversation = await repository.createConversation();
      await settle(loop, () => loop.sendUserMessage(
          conversationId: conversation.id, text: 'x'));

      final toolMessage = (await repository.listMessages(conversation.id))
          .lastWhere((m) => m.role == 'tool');
      expect(toolMessage.content, contains('JSON'));
    });

    test('a tool-level validation failure comes back as a result', () async {
      // `create` without a title: the model must be told what was missing.
      final adapter = FakeModelAdapter([
        FakeModelAdapter.callTool('manage_task', {'action': 'create'}),
        FakeModelAdapter.answer('好的。'),
      ]);
      final loop = buildLoop(adapter);
      final conversation = await repository.createConversation();
      await settle(loop, () => loop.sendUserMessage(
          conversationId: conversation.id, text: 'x'));

      final toolMessage = (await repository.listMessages(conversation.id))
          .lastWhere((m) => m.role == 'tool');
      expect(toolMessage.content, contains('title'));
    });

    test('a provider failure surfaces as an error and keeps the turn', () async {
      final adapter = FakeModelAdapter([
        FakeModelAdapter.failure('模型服务返回 401（API key 可能无效或没有权限。）',
            statusCode: 401),
      ]);
      final loop = buildLoop(adapter);
      final conversation = await repository.createConversation();
      final state = await settle(loop, () => loop.sendUserMessage(
          conversationId: conversation.id, text: '你好'));

      expect(state.generating, isFalse);
      expect(state.error, contains('401'));
      // The user's own message is not lost.
      final messages = await repository.listMessages(conversation.id);
      expect(messages.first.content, '你好');
    });

    test('partial text before a failure is kept', () async {
      final adapter = FakeModelAdapter([
        [
          const ModelTextDelta('我查到了一些'),
          const ModelFailure('连接中断'),
        ],
      ]);
      final loop = buildLoop(adapter);
      final conversation = await repository.createConversation();
      await settle(loop, () => loop.sendUserMessage(
          conversationId: conversation.id, text: 'x'));

      final messages = await repository.listMessages(conversation.id);
      expect(messages.last.content, '我查到了一些');
    });
  });

  group('the round cap', () {
    test('a model that never stops is cut off with an explanation', () async {
      // Ten turns of tool calls against a cap of two.
      final adapter = FakeModelAdapter([
        for (var i = 0; i < 10; i++)
          FakeModelAdapter.callTool(
            'query_tasks',
            {'limit': 1},
            id: 'call_$i',
          ),
      ]);
      final loop = buildLoop(adapter, maxRounds: 2);
      final conversation = await repository.createConversation();

      final state = await settle(loop, () => loop.sendUserMessage(
          conversationId: conversation.id, text: '一直查'));

      expect(state.rounds, 2);
      expect(state.generating, isFalse);
      // The stop is explained to the user rather than being a silent truncation.
      expect(state.error, contains('上限'));
      final messages = await repository.listMessages(conversation.id);
      expect(messages.last.content, contains('上限'));
    });
  });

  group('undo', () {
    test('an auto-executed create can be undone', () async {
      final adapter = FakeModelAdapter([
        FakeModelAdapter.callTool(
            'manage_task', {'action': 'create', 'title': '手滑建的'}),
        FakeModelAdapter.answer('好了。'),
      ]);
      final loop = buildLoop(adapter);
      final conversation = await repository.createConversation();
      final state = await settle(loop, () => loop.sendUserMessage(
          conversationId: conversation.id, text: 'x'));

      expect(await tasks.getTasks(), hasLength(1));
      final actionId = state.executed.single.actionId;

      await settle(loop, () => loop.undoExecuted(conversation.id, actionId));
      expect(await tasks.getTasks(), isEmpty,
          reason: 'undo of a create must remove the row');
    });

    test('an undo marks the ledger so the UI can show it', () async {
      final adapter = FakeModelAdapter([
        FakeModelAdapter.callTool(
            'manage_task', {'action': 'create', 'title': 'x'}),
        FakeModelAdapter.answer('好'),
      ]);
      final loop = buildLoop(adapter);
      final conversation = await repository.createConversation();
      final state = await settle(loop, () => loop.sendUserMessage(
          conversationId: conversation.id, text: 'x'));

      final after = await settle(loop,
          () => loop.undoExecuted(conversation.id, state.executed.single.actionId));
      expect(after.executed.single.undone, isTrue);
    });

    test('an update is rolled back to the previous values', () async {
      final task = await tasks.createTask(title: '原名', priority: 1);
      final adapter = FakeModelAdapter([
        FakeModelAdapter.callTool('manage_task', {
          'action': 'update',
          'id': task.id,
          'title': '被改的名字',
        }),
        FakeModelAdapter.answer('改好了'),
      ]);
      final loop = buildLoop(adapter);
      final conversation = await repository.createConversation();
      final state = await settle(loop, () => loop.sendUserMessage(
          conversationId: conversation.id, text: '改名'));
      expect((await tasks.getTasks()).single.title, '被改的名字');

      await settle(loop,
          () => loop.undoExecuted(conversation.id, state.executed.single.actionId));
      final restored = (await tasks.getTasks()).single;
      expect(restored.title, '原名');
      expect(restored.priority, 1);
    });
  });

  group('schedule tools through the loop', () {
    test('a time block is created and lands in the repository', () async {
      final adapter = FakeModelAdapter([
        FakeModelAdapter.callTool('manage_time_block', {
          'action': 'create',
          'title': '早读',
          'start_at': '2026-09-16T07:30:00',
          'end_at': '2026-09-16T07:50:00',
        }),
        FakeModelAdapter.answer('排好了。'),
      ]);
      final loop = buildLoop(adapter);
      final conversation = await repository.createConversation();
      await settle(loop, () => loop.sendUserMessage(
          conversationId: conversation.id, text: '排个早读'));

      final stored = await blocks.getTimeBlocks();
      expect(stored.single.title, '早读');
      expect(stored.single.endAt - stored.single.startAt, 20 * 60 * 1000);
    });

    test('an impossible interval is refused with a readable reason', () async {
      final adapter = FakeModelAdapter([
        FakeModelAdapter.callTool('manage_time_block', {
          'action': 'create',
          'title': '倒着来',
          'start_at': '2026-09-16T10:00:00',
          'end_at': '2026-09-16T09:00:00',
        }),
        FakeModelAdapter.answer('抱歉。'),
      ]);
      final loop = buildLoop(adapter);
      final conversation = await repository.createConversation();
      await settle(loop, () => loop.sendUserMessage(
          conversationId: conversation.id, text: 'x'));

      expect(await blocks.getTimeBlocks(), isEmpty);
      final toolMessage = (await repository.listMessages(conversation.id))
          .lastWhere((m) => m.role == 'tool');
      expect(toolMessage.content, contains('end_at'));
    });
  });
}
