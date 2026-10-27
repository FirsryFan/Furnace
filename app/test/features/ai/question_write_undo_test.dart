import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/ai_repository.dart';
import 'package:furnace/data/repositories/question_repository.dart';
import 'package:furnace/data/repositories/tag_repository.dart';
import 'package:furnace/features/ai/domain/agent_loop.dart';
import 'package:furnace/features/ai/domain/approval_engine.dart';
import 'package:furnace/features/ai/domain/model_adapter.dart';
import 'package:furnace/features/ai/domain/tool_registry.dart';
import 'package:furnace/features/ai/infrastructure/fake_model_adapter.dart';
import 'package:furnace/features/ai/tools/question_write_tools.dart';

/// `create_questions` 是 AI 收题的唯一写口（用户 2026-10-27 取消手动收题入口后，
/// 拍照 / 粘贴的题由 agent 誊写进题库）。工具本身由 `question_write_tools_test`
/// 覆盖；本文件只覆盖 loop 接线：撤销白名单里漏了它，或者撤销把「题库本来就有
/// 的重复题」也删了，都会让工具报告已撤销、库却错了。
void main() {
  late AppDatabase db;
  late TagRepository tags;
  late QuestionRepository questions;
  late AiRepository repository;
  late ToolRegistry registry;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    tags = TagRepository(db);
    questions = QuestionRepository(db);
    repository = AiRepository(db);
    registry = ToolRegistry([
      CreateQuestionsTool(db: db, tags: tags),
    ]);
  });

  tearDown(() async {
    await db.close();
  });

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

  /// Runs one user turn scripted by [turns] and returns what the loop settled on.
  Future<({AgentTurnState state, String conversationId, AgentLoop loop})>
      runTurn(List<List<ModelEvent>> turns) async {
    final loop = AgentLoop(
      adapter: FakeModelAdapter(turns),
      registry: registry,
      approval: const ApprovalEngine(mode: AiPermissionMode.auto),
      repository: repository,
      db: db,
    );
    final conversation = await repository.createConversation();
    final state = await settle(
      loop,
      () => loop.sendUserMessage(conversationId: conversation.id, text: 'x'),
    );
    return (state: state, conversationId: conversation.id, loop: loop);
  }

  Map<String, Object?> snapshotOf(AgentTurnState state) {
    final json = state.executed.single.result.afterJson;
    expect(json, isNotNull, reason: 'create_questions 必须留下撤销快照');
    final decoded = jsonDecode(json!);
    expect(decoded, isA<Map<String, Object?>>());
    return decoded as Map<String, Object?>;
  }

  group('create_questions through the loop', () {
    test('undo deletes only the questions this call created', () async {
      final seeded = await questions.ingest(const QuestionDraft(
        stem: '已有题：三角形内角和是 180 度',
        answer: '180 度',
      ));

      final turn = await runTurn([
        FakeModelAdapter.callTool('create_questions', {
          'questions': [
            {'stem': '已有题：三角形内角和是 180 度'},
            {'stem': '新题：求 y = x^2 - 4x + 3 的顶点坐标'},
          ],
        }),
        FakeModelAdapter.answer('收好了。'),
      ]);

      final executed = turn.state.executed.single;
      expect(executed.result.ok, isTrue);
      final snapshot = snapshotOf(turn.state);
      // 两道题都进了题库（一道新建、一道本来就有），但快照里的 created_ids
      // 只记新建的那道——撤销删它，重复题必须留下。
      expect(snapshot['question_ids'], hasLength(2));
      expect(snapshot['created_ids'], hasLength(1));
      expect(await db.select(db.questions).get(), hasLength(2));

      await settle(
        turn.loop,
        () => turn.loop.undoExecuted(turn.conversationId, executed.actionId),
      );

      final remaining = await db.select(db.questions).get();
      expect(
        remaining.map((question) => question.id),
        [seeded.question.id],
        reason: '撤销只能删本次新建的题，题库原有的重复题不能被删',
      );
      expect(turn.loop.state.error, isNull);
      expect(turn.loop.state.executed.single.undone, isTrue);
    });

    test('undo still succeeds when a created question was deleted by hand',
        () async {
      final turn = await runTurn([
        FakeModelAdapter.callTool('create_questions', {
          'questions': [
            {'stem': '新题：写出牛顿第二定律的表达式'},
          ],
        }),
        FakeModelAdapter.answer('收好了。'),
      ]);

      final executed = turn.state.executed.single;
      expect(executed.result.ok, isTrue);
      final createdIds = snapshotOf(turn.state)['created_ids']! as List;
      final createdId = createdIds.single as String;
      // 用户在撤销之前自己把题删了：撤销不该因为「找不到行」就报失败。
      await questions.deleteQuestion(createdId);
      expect(await db.select(db.questions).get(), isEmpty);

      await settle(
        turn.loop,
        () => turn.loop.undoExecuted(turn.conversationId, executed.actionId),
      );

      expect(turn.loop.state.error, isNull);
      expect(turn.loop.state.executed.single.undone, isTrue);
    });
  });
}
