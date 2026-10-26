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

/// docs/REVIEW_FEEDBACK.md §4a 的「思考落库」：生成时的思考过程要跟着助手消息
/// 一起留在历史里，否则页面一刷新就只剩答案，折叠块点开是空的。
///
/// The loop has exactly four ways to write an assistant row and all four must
/// carry the reasoning: a plain answer, an answer that is pure thinking, a
/// failed round that kept partial output, and a committed tool turn whose text
/// lives on the group. The cancel path (partial answer) is covered here too
/// because it is the fifth writer.
void main() {
  late AppDatabase db;
  late AiRepository repository;
  late ToolRegistry registry;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repository = AiRepository(db);
    registry = ToolRegistry([
      QueryTasksTool(TaskRepository(db), db),
      QueryScheduleTool(TimeBlockRepository(db)),
    ]);
  });

  tearDown(() async {
    await db.close();
  });

  AgentLoop buildLoop(ModelAdapter adapter) => AgentLoop(
        adapter: adapter,
        registry: registry,
        approval: const ApprovalEngine(mode: AiPermissionMode.auto),
        repository: repository,
        db: db,
        maxRounds: 8,
      );

  Future<void> until(bool Function() condition) async {
    for (var i = 0; i < 2000; i++) {
      if (condition()) {
        return;
      }
      await Future<void>.delayed(Duration.zero);
    }
    fail('condition was not reached');
  }

  test('普通回答：思考文本跟着助手消息落库', () async {
    final loop = buildLoop(FakeModelAdapter([
      [
        const ModelReasoningDelta('先想清楚再答。'),
        const ModelTextDelta('答案是 42。'),
        const ModelTurnDone(finishReason: 'stop'),
      ],
    ]));
    final conversation = await repository.createConversation();

    await loop.sendUserMessage(conversationId: conversation.id, text: '为什么');
    loop.dispose();

    final messages = await repository.listMessages(conversation.id);
    expect(messages.map((m) => m.role), ['user', 'assistant']);
    expect(messages.last.content, '答案是 42。');
    expect(messages.last.reasoning, '先想清楚再答。');
  });

  test('只有思考没有答案：行还在，content 为 null，思考不丢', () async {
    final loop = buildLoop(FakeModelAdapter([
      [
        const ModelReasoningDelta('这个问题不值得回答。'),
        const ModelTurnDone(finishReason: 'stop'),
      ],
    ]));
    final conversation = await repository.createConversation();

    await loop.sendUserMessage(conversationId: conversation.id, text: '嗯');
    loop.dispose();

    final messages = await repository.listMessages(conversation.id);
    expect(messages.length, 2);
    expect(messages.last.content, isNull);
    expect(messages.last.reasoning, '这个问题不值得回答。');
  });

  test('失败但保住了部分输出：思考文本一起保留', () async {
    final loop = buildLoop(FakeModelAdapter([
      [
        const ModelReasoningDelta('算到一半。'),
        const ModelTextDelta('先写一半'),
        const ModelFailure('连接被重置'),
      ],
    ]));
    final conversation = await repository.createConversation();

    await loop.sendUserMessage(conversationId: conversation.id, text: '算一下');
    loop.dispose();

    final messages = await repository.listMessages(conversation.id);
    expect(messages.last.content, '先写一半');
    expect(messages.last.reasoning, '算到一半。');
    expect(loop.state.error, '连接被重置');
  });

  test('工具轮（TurnGroup 提交）：思考落在带工具调用的助手消息上', () async {
    final loop = buildLoop(FakeModelAdapter([
      [
        const ModelReasoningDelta('先查一下任务。'),
        ...FakeModelAdapter.callTool('query_tasks', const {}),
      ],
      [
        const ModelReasoningDelta('查完了，总结。'),
        ...FakeModelAdapter.answer('你没有任务。'),
      ],
    ]));
    final conversation = await repository.createConversation();

    await loop.sendUserMessage(conversationId: conversation.id, text: '我有任务吗');
    loop.dispose();

    final messages = await repository.listMessages(conversation.id);
    final assistants =
        messages.where((m) => m.role == AiRepository.roleAssistant).toList();
    expect(assistants.length, 2);
    expect(assistants.first.reasoning, '先查一下任务。');
    expect(assistants.last.reasoning, '查完了，总结。');
    expect(assistants.last.content, '你没有任务。');
  });

  test('用户中途停止：半截答案与思考一起落库', () async {
    final adapter = _ControlledAdapter();
    final loop = buildLoop(adapter);
    final conversation = await repository.createConversation();

    final sending = loop.sendUserMessage(
      conversationId: conversation.id,
      text: '讲清楚',
    );
    await adapter.started.future;
    adapter.emit(const ModelReasoningDelta('先想前半'));
    await until(() => loop.state.reasoningText == '先想前半');
    adapter.emit(const ModelTextDelta('前半句'));
    await until(() => loop.state.streamingText == '前半句');

    loop.cancel();
    await sending.timeout(const Duration(seconds: 5));
    loop.dispose();

    final messages = await repository.listMessages(conversation.id);
    expect(messages.last.content, '前半句');
    expect(messages.last.reasoning, '先想前半');
    expect(loop.state.cancelled, isTrue);
  });

  test('停止在第一个字之前：不写一条没有答案的空行', () async {
    final adapter = _ControlledAdapter();
    final loop = buildLoop(adapter);
    final conversation = await repository.createConversation();

    final sending = loop.sendUserMessage(
      conversationId: conversation.id,
      text: '先别说',
    );
    await adapter.started.future;
    adapter.emit(const ModelReasoningDelta('想一想'));
    await until(() => loop.state.reasoningText == '想一想');

    loop.cancel();
    await sending.timeout(const Duration(seconds: 5));
    loop.dispose();

    final messages = await repository.listMessages(conversation.id);
    expect(messages.map((m) => m.role), ['user'], reason: '没有答案就不落助手行：气泡会空');
    expect(loop.state.cancelled, isTrue);
  });
}

/// Emits events one by one so a cancel can land at an exact point.
class _ControlledAdapter implements CancellableModelAdapter {
  final StreamController<ModelEvent> _controller =
      StreamController<ModelEvent>();
  final Completer<void> started = Completer<void>();

  @override
  Stream<ModelEvent> runTurn({
    required List<ChatMessage> messages,
    required List<ModelToolSpec> tools,
  }) {
    if (!started.isCompleted) {
      started.complete();
    }
    return _controller.stream;
  }

  @override
  void cancelActiveTurn() {
    if (_controller.isClosed) {
      return;
    }
    _controller.add(const ModelTurnCancelled());
    unawaited(_controller.close());
  }

  void emit(ModelEvent event) => _controller.add(event);
}
