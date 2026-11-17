// 「用户消息已落库」这件事必须在本回合**模型被调用之前**就到页面上。
//
// 2026-11-17 用户反馈：发出消息后对话区没有反应，等 agent 思考结束、开始输出时，
// 用户消息和思维链才一起突然出现。根因是页面只在回合结束时重读已存消息，而循环
// 在调用模型之前就把用户消息写库了。修法在 domain 层：状态带 `userMessageId`，
// 页面一看到新的 id 就重读。
//
// 这些测试钉住的是 domain 侧的契约（页面层由 ai_streaming_usage_test.dart 的
// widget 测试覆盖）：
//
//  * 模型开始被调用的那一刻，`loop.state.userMessageId` 已经是落库行的 id；
//  * 状态流里「带上 id」的那一帧早于任何 reasoning / 正文增量；
//  * 一轮结束时 id 仍在（页面因此只重读一次），下一轮换成新的 id。
import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/ai_repository.dart';
import 'package:furnace/features/ai/domain/agent_loop.dart';
import 'package:furnace/features/ai/domain/ai_tool.dart';
import 'package:furnace/features/ai/domain/approval_engine.dart';
import 'package:furnace/features/ai/domain/model_adapter.dart';
import 'package:furnace/features/ai/domain/tool_registry.dart';

/// A model that stops right after `runTurn` is entered, so the test can look at
/// the loop's state **at the moment the provider is called** and then release
/// the stream by hand.
class _GatedAdapter implements ModelAdapter {
  _GatedAdapter({required this.onRunTurn});

  /// Runs synchronously when the loop subscribes, i.e. exactly when the model
  /// call starts.
  final void Function() onRunTurn;

  final Completer<void> started = Completer<void>();
  final Completer<void> release = Completer<void>();

  int runCalls = 0;

  @override
  Stream<ModelEvent> runTurn({
    required List<ChatMessage> messages,
    required List<ModelToolSpec> tools,
  }) async* {
    runCalls++;
    if (!started.isCompleted) {
      started.complete();
    }
    onRunTurn();
    await release.future;
    yield const ModelReasoningDelta('先想一下');
    yield const ModelTextDelta('答案是 42。');
    yield const ModelTurnDone(finishReason: 'stop');
  }
}

/// Advances real async work (the loop is streaming) until [condition] holds.
Future<void> until(
  bool Function() condition, {
  required String reason,
}) async {
  for (var i = 0; i < 2000; i++) {
    if (condition()) {
      return;
    }
    await Future<void>.delayed(Duration.zero);
  }
  fail('$reason（等待超时）');
}

void main() {
  late AppDatabase db;
  late AiRepository repository;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repository = AiRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  test('模型被调用时，状态已经带着已落库的用户消息 id', () async {
    late AgentLoop loop;
    String? idWhenModelCalled;
    final adapter = _GatedAdapter(
      onRunTurn: () => idWhenModelCalled = loop.state.userMessageId,
    );
    loop = AgentLoop(
      adapter: adapter,
      registry: ToolRegistry(const <AiTool>[]),
      approval: const ApprovalEngine(mode: AiPermissionMode.auto),
      repository: repository,
      db: db,
    );
    final conversation = await repository.createConversation();

    final states = <AgentTurnState>[];
    final sub = loop.states.listen(states.add);
    final sending = loop.sendUserMessage(
      conversationId: conversation.id,
      text: '你好，流式测试',
    );
    await until(() => adapter.started.isCompleted, reason: '模型调用未开始');

    expect(
      idWhenModelCalled,
      isNotNull,
      reason: '模型开始被调用的那一刻，状态里必须已经有用户消息 id',
    );
    // 这个 id 就是已落库的那一行：此刻还没写助手消息，所以只有一行 user。
    final rows = await repository.listMessages(conversation.id);
    expect(rows.single.id, idWhenModelCalled);
    expect(rows.single.role, AiRepository.roleUser);
    expect(rows.single.content, '你好，流式测试');

    // 状态流里带 id 的那一帧生成中。
    final idIndex =
        states.indexWhere((s) => s.userMessageId == idWhenModelCalled);
    expect(idIndex, greaterThanOrEqualTo(0),
        reason: '状态流里应出现带用户消息 id 的一帧');
    expect(states[idIndex].generating, isTrue,
        reason: '用户消息上屏时本轮已经在生成');

    adapter.release.complete();
    await sending;

    // 而且这一帧早于任何 reasoning / 正文增量：用户消息不是等模型开口才出现的。
    final firstDeltaIndex = states.indexWhere(
      (s) => s.reasoningText.isNotEmpty || s.streamingText.isNotEmpty,
    );
    expect(firstDeltaIndex, greaterThan(idIndex),
        reason: '用户消息那一帧必须早于第一个模型增量');
    await sub.cancel();

    // 一轮结束后 id 保留：页面靠「id 变了没」决定是否重读，一轮只重读一次。
    expect(loop.state.userMessageId, idWhenModelCalled);
  });

  test('下一轮换成新的用户消息 id', () async {
    late AgentLoop loop;
    final adapter = _GatedAdapter(onRunTurn: () {});
    loop = AgentLoop(
      adapter: adapter,
      registry: ToolRegistry(const <AiTool>[]),
      approval: const ApprovalEngine(mode: AiPermissionMode.auto),
      repository: repository,
      db: db,
    );
    final conversation = await repository.createConversation();

    final first = loop.sendUserMessage(
      conversationId: conversation.id,
      text: '第一句',
    );
    await until(() => adapter.started.isCompleted, reason: '第一轮模型未开始');
    adapter.release.complete();
    await first;
    final firstId = loop.state.userMessageId;
    expect(firstId, isNotNull);

    final second = loop.sendUserMessage(
      conversationId: conversation.id,
      text: '第二句',
    );
    await until(
      () =>
          loop.state.userMessageId != null &&
          loop.state.userMessageId != firstId,
      reason: '第二轮没有换上新的用户消息 id',
    );
    await second;

    final rows = await repository.listMessages(conversation.id);
    final userIds = rows
        .where((row) => row.role == AiRepository.roleUser)
        .map((row) => row.id)
        .toList();
    expect(userIds, [firstId, loop.state.userMessageId]);
  });
}
