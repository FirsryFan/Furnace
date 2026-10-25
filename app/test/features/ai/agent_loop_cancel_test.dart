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

/// Stopping a turn is a user-visible action with rules of its own: the text
/// already on screen is kept, nothing the model never saw an answer to is
/// written, and the loop must not keep waiting on a provider it cannot
/// interrupt. These tests drive the loop with an adapter the test controls
/// event by event, so a cancel can be placed precisely. The plain streaming
/// and approval behaviour lives in `agent_loop_test.dart`.
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
  }) =>
      AgentLoop(
        adapter: adapter,
        registry: registry,
        approval: ApprovalEngine(mode: mode),
        repository: repository,
        db: db,
        maxRounds: 8,
      );

  /// Waits for [condition] without guessing a delay: the loop delivers states
  /// and events through streams, so a fixed sleep would be a race.
  Future<void> until(bool Function() condition) async {
    for (var i = 0; i < 2000; i++) {
      if (condition()) {
        return;
      }
      await Future<void>.delayed(Duration.zero);
    }
    fail('condition was not reached');
  }

  group('cancelling a streaming turn', () {
    test('keeps the partial answer and flags the state', () async {
      final adapter = _ControlledAdapter();
      final loop = buildLoop(adapter);
      final conversation = await repository.createConversation();

      final sending = loop.sendUserMessage(
        conversationId: conversation.id,
        text: '讲个长故事',
      );
      await adapter.started.future;
      adapter.emit(const ModelTextDelta('从前'));
      await until(() => loop.state.streamingText == '从前');

      loop.cancel();
      await sending.timeout(const Duration(seconds: 5));

      expect(adapter.runCalls, 1);
      expect(adapter.cancelCalls, 1);
      expect(loop.state.generating, isFalse);
      expect(loop.state.cancelled, isTrue);
      expect(loop.state.error, isNull);
      final messages = await repository.listMessages(conversation.id);
      expect(messages.map((m) => m.role), ['user', 'assistant']);
      expect(messages.last.content, '从前');
    });

    test('writes no assistant message when nothing had streamed yet', () async {
      final adapter = _ControlledAdapter();
      final loop = buildLoop(adapter);
      final conversation = await repository.createConversation();

      final sending = loop.sendUserMessage(
        conversationId: conversation.id,
        text: '算了',
      );
      await adapter.started.future;
      loop.cancel();
      await sending.timeout(const Duration(seconds: 5));

      expect(loop.state.cancelled, isTrue);
      final messages = await repository.listMessages(conversation.id);
      expect(messages.map((m) => m.role), ['user']);
    });

    test('cancel is idempotent and asks the adapter once', () async {
      final adapter = _ControlledAdapter();
      final loop = buildLoop(adapter);
      final conversation = await repository.createConversation();

      final sending = loop.sendUserMessage(
        conversationId: conversation.id,
        text: '停',
      );
      await adapter.started.future;
      loop.cancel();
      loop.cancel();
      loop.cancel();
      await sending.timeout(const Duration(seconds: 5));

      expect(adapter.cancelCalls, 1);
      expect(loop.state.cancelled, isTrue);
    });

    test('a turn that finishes normally is not marked as cancelled', () async {
      final adapter = FakeModelAdapter([FakeModelAdapter.answer('好的')]);
      final loop = buildLoop(adapter);
      final conversation = await repository.createConversation();

      await loop.sendUserMessage(
        conversationId: conversation.id,
        text: '在吗',
      );

      expect(loop.state.cancelled, isFalse);
      expect(loop.state.error, isNull);
      final messages = await repository.listMessages(conversation.id);
      expect(messages.map((m) => m.role), ['user', 'assistant']);
      expect(messages.last.content, '好的');
    });
  });

  group('cancelling a pending approval', () {
    test('drops the batch and executes nothing', () async {
      final task = await tasks.createTask(title: '重要任务');
      final adapter = FakeModelAdapter([
        FakeModelAdapter.callTool(
            'manage_task', {'action': 'delete', 'id': task.id}),
      ]);
      final loop = buildLoop(adapter);
      final conversation = await repository.createConversation();

      await loop.sendUserMessage(
        conversationId: conversation.id,
        text: '删掉那个任务',
      );
      expect(loop.state.hasPending, isTrue);

      loop.cancel();

      expect(loop.state.hasPending, isFalse);
      expect(loop.state.cancelled, isTrue);
      expect(await tasks.getTasks(), hasLength(1));
      final messages = await repository.listMessages(conversation.id);
      expect(messages.where((m) => m.role == AiRepository.roleTool), isEmpty);

      // The dropped batch cannot be approved into existence afterwards.
      await loop.approvePending(conversation.id);
      expect(await tasks.getTasks(), hasLength(1));
      expect(loop.state.hasPending, isFalse);
    });
  });

  group('disposing while a turn is in flight', () {
    test('cancels the turn so the send future returns', () async {
      final adapter = _ControlledAdapter();
      final loop = buildLoop(adapter);
      final conversation = await repository.createConversation();

      final sending = loop.sendUserMessage(
        conversationId: conversation.id,
        text: '说点什么',
      );
      await adapter.started.future;

      loop.dispose();
      await sending.timeout(const Duration(seconds: 5));

      expect(adapter.cancelCalls, 1);
    });
  });

  group('the reasoning channel', () {
    test('is surfaced apart from the answer and never stored as it', () async {
      final adapter = _ControlledAdapter();
      final loop = buildLoop(adapter);
      final conversation = await repository.createConversation();

      final sending = loop.sendUserMessage(
        conversationId: conversation.id,
        text: '仔细想',
      );
      await adapter.started.future;

      adapter.emit(const ModelReasoningDelta('先想'));
      await until(() => loop.state.reasoningText == '先想');
      expect(loop.state.streamingText, isEmpty);

      adapter.emit(const ModelTextDelta('答案'));
      await until(() => loop.state.streamingText == '答案');
      expect(loop.state.reasoningText, '先想');

      adapter.emit(const ModelTurnDone(finishReason: 'stop'));
      await adapter.close();
      await sending.timeout(const Duration(seconds: 5));

      expect(loop.state.cancelled, isFalse);
      expect(loop.state.reasoningText, '先想');
      final messages = await repository.listMessages(conversation.id);
      expect(messages.map((m) => m.role), ['user', 'assistant']);
      expect(messages.last.content, '答案');
    });
  });
}

/// A cancellable adapter whose events the test emits one by one, so a cancel
/// can land at an exact point in the stream.
class _ControlledAdapter implements CancellableModelAdapter {
  final StreamController<ModelEvent> _controller =
      StreamController<ModelEvent>();

  /// Completes when the loop has actually subscribed to a turn.
  final Completer<void> started = Completer<void>();

  int runCalls = 0;
  int cancelCalls = 0;

  @override
  Stream<ModelEvent> runTurn({
    required List<ChatMessage> messages,
    required List<ModelToolSpec> tools,
  }) {
    runCalls++;
    if (!started.isCompleted) {
      started.complete();
    }
    return _controller.stream;
  }

  @override
  void cancelActiveTurn() {
    cancelCalls++;
    if (_controller.isClosed) {
      return;
    }
    _controller.add(const ModelTurnCancelled());
    unawaited(_controller.close());
  }

  void emit(ModelEvent event) {
    _controller.add(event);
  }

  Future<void> close() => _controller.close();
}
