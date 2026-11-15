import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/ai_repository.dart';
import 'package:furnace/data/repositories/anki_repository.dart';
import 'package:furnace/data/repositories/question_repository.dart';
import 'package:furnace/data/repositories/tag_repository.dart';
import 'package:furnace/data/repositories/task_repository.dart';
import 'package:furnace/data/repositories/time_block_repository.dart';
import 'package:furnace/features/ai/domain/ai_tool.dart';
import 'package:furnace/features/ai/domain/approval_engine.dart';
import 'package:furnace/features/ai/domain/tool_registry.dart';
import 'package:furnace/features/ai/tools/paper_tools.dart';

/// `materialize_paper`：把组卷结果真正落成 ThreadFlow 任务树（B1/B4）。
///
/// 验收点：
///  1. compose→materialize：一份卷子 → 1 个 week/day 容器 + 每题 1 个子 task；
///  2. 幂等：同周/同日重复调用不新建第二个容器、不追加事件；
///  3. 稳定 `paperKey`：不传 `paper_key` 时同周重卷复用容器；显式 `paper_key`
///     才是"明确新卷"（同一周可以并存两份卷子）；
///  4. 字段映射：expectedAt/dueAt/remindAt/energy/estimate 与父容器估时；
///  5. 旧行为不变：`compose_paper` 仍只读、不写任何表；
///  6. 安全：写工具不可自动执行（D13b），两种权限模式都逐条确认。
void main() {
  late AppDatabase db;
  late QuestionRepository questions;
  late TagRepository tags;
  late AnkiRepository anki;
  late MaterializePaperTool tool;
  final now = DateTime(2026, 11, 15, 12); // 2026-W46 周日中午

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    questions = QuestionRepository(db);
    tags = TagRepository(db);
    anki = AnkiRepository(db);
    tool = MaterializePaperTool(db: db, clock: () => now);
  });

  tearDown(() async {
    await db.close();
  });

  ToolInvocation invoke(Map<String, Object?> args) => ToolInvocation(
        toolName: tool.name,
        action: tool.name,
        arguments: args,
      );

  Map<String, Object?> payloadOf(ToolResult result) =>
      (result.modelResult! as Map<String, Object?>);

  Future<(String, String)> seedLinked({
    required String stem,
    required String pointTitle,
    String subjectKey = 'math',
    String sourceLevel = 'gaokao',
  }) async {
    final pointId =
        (await anki.createKnowledgePoint(title: pointTitle, content: '')).id;
    final questionId = (await questions.ingest(
      QuestionDraft(
        stem: stem,
        subjectKey: subjectKey,
        sourceLevel: sourceLevel,
      ),
    ))
        .question
        .id;
    final tagId = (await tags.createTag(name: pointTitle)).id;
    await tags.addTagToObject(
      tagId: tagId,
      objectType: 'knowledge_point',
      objectId: pointId,
    );
    await tags.addTagToObject(
      tagId: tagId,
      objectType: 'question',
      objectId: questionId,
    );
    return (questionId, pointId);
  }

  /// 3 道题、3 个知识点（每个点只挂一道，避免每知识点上限影响题数）。
  Future<void> seedThree() async {
    await seedLinked(stem: '动量题 A', pointTitle: '动量守恒');
    await seedLinked(stem: '电场题 B', pointTitle: '电场强度', subjectKey: 'physics');
    await seedLinked(stem: '数列题 C', pointTitle: '等差数列');
  }

  Future<List<Task>> allTasks() => (db.select(db.tasks)).get();

  Future<List<ThreadEventRow>> allEvents() =>
      (db.select(db.threadEvents)).get();

  group('compose → materialize：生成任务树', () {
    test('默认 week：1 个容器 + 每题 1 个子任务，事件走 ThreadFlowWriter', () async {
      await seedThree();

      final result = await tool.run(invoke({'target_count': 3}));
      final payload = payloadOf(result);

      expect(result.ok, isTrue, reason: result.error);
      expect(payload['materialized'], isTrue);
      expect(payload['item_count'], 3);
      expect(payload['created_container'], isTrue);
      expect(payload['container_kind'], 'week');
      expect(payload['paper_key'], 'plan');
      expect(payload['container_source_key'], 'paper:week:2026-W46:plan');
      expect(payload['container_title'], '组卷 · 2026-W46');
      expect(result.summary, contains('已写入 ThreadFlow'));

      final rows = await allTasks();
      expect(rows, hasLength(4), reason: '1 个父容器 + 3 个逐题子任务');

      final container = rows.singleWhere((t) => t.kind == 'week');
      expect(container.id, payload['container_id']);
      expect(container.parentId, isNull);
      expect(container.sourceKey, 'paper:week:2026-W46:plan');
      expect(
          container.expectedAt, DateTime(2026, 11, 9).millisecondsSinceEpoch);
      expect(container.dueAt, DateTime(2026, 11, 16).millisecondsSinceEpoch);
      expect(container.energyRequired, isNull, reason: '容器不写精力');

      final children = rows.where((t) => t.parentId == container.id).toList();
      expect(children, hasLength(3));
      expect(children.every((t) => t.kind == 'task'), isTrue);
      expect(
        children.map((t) => t.sourceKey).toSet(),
        {
          for (final id in payload['created_question_ids']! as List<Object?>)
            'paper:week:2026-W46:plan:$id',
        },
      );
      expect(
        (payload['child_task_ids']! as List<Object?>).length,
        3,
      );

      final events = await allEvents();
      expect(events, hasLength(4), reason: '容器 created + 3 个子任务 created');
      expect(events.every((e) => e.kind == 'created'), isTrue);
    });

    test('同周同日重复调用：同一容器、同一批子任务、行数与事件数不变', () async {
      await seedThree();

      final first = await tool.run(invoke({'target_count': 3}));
      final firstPayload = payloadOf(first);
      final taskCount = (await allTasks()).length;
      final eventCount = (await allEvents()).length;

      final second = await tool.run(invoke({'target_count': 3}));
      final secondPayload = payloadOf(second);

      expect(second.ok, isTrue, reason: second.error);
      expect(secondPayload['materialized'], isTrue);
      expect(secondPayload['created_container'], isFalse,
          reason: '同周重卷不该建第二个容器');
      expect(secondPayload['container_id'], firstPayload['container_id']);
      expect(secondPayload['created_question_ids'], isEmpty);
      expect(secondPayload['child_task_ids'], firstPayload['child_task_ids']);
      expect((await allTasks()).length, taskCount);
      expect((await allEvents()).length, eventCount);
      expect(
        (await allTasks()).where((t) => t.sourceKey!.startsWith('paper:week:')),
        hasLength(4),
      );
    });

    test('同周不同日期（周中 vs 周末）仍是同一个周容器', () async {
      await seedThree();

      final monday = await tool.run(invoke({
        'target_count': 3,
        'window_start': DateTime(2026, 11, 9, 8).millisecondsSinceEpoch,
      }));
      final thursday = await tool.run(invoke({
        'target_count': 3,
        'window_start': DateTime(2026, 11, 12, 8).millisecondsSinceEpoch,
      }));

      expect(payloadOf(monday)['container_id'],
          payloadOf(thursday)['container_id']);
      expect((await allTasks()), hasLength(4));
    });

    test('显式 paper_key = 明确新卷：同一周可以并存第二个容器', () async {
      await seedThree();

      final planA =
          await tool.run(invoke({'target_count': 3, 'paper_key': 'QSET-A'}));
      final planB =
          await tool.run(invoke({'target_count': 3, 'paper_key': 'QSET-B'}));

      expect(planA.ok, isTrue, reason: planA.error);
      expect(planB.ok, isTrue, reason: planB.error);
      expect(
        payloadOf(planB)['container_source_key'],
        'paper:week:2026-W46:QSET-B',
      );
      expect(
        payloadOf(planA)['container_id'],
        isNot(payloadOf(planB)['container_id']),
      );
      expect((await allTasks()), hasLength(8), reason: '两份 4 行任务树');

      // 同一 paper_key 再跑一次仍是复用（幂等键是 paper_key，不是"新卷"这个词）。
      final again =
          await tool.run(invoke({'target_count': 3, 'paper_key': 'QSET-B'}));
      expect(
          payloadOf(again)['container_id'], payloadOf(planB)['container_id']);
      expect((await allTasks()), hasLength(8));
    });
  });

  group('字段映射与估时', () {
    test('expectedAt/dueAt/remindAt/energy/estimate 落到子任务；父容器=子节点之和', () async {
      await seedLinked(stem: '动量题 A', pointTitle: '动量守恒');
      await seedLinked(
          stem: '电场题 B', pointTitle: '电场强度', subjectKey: 'physics');
      final start = DateTime(2026, 11, 9, 9);
      final remind = DateTime(2026, 11, 8, 20);

      final result = await tool.run(invoke({
        'target_count': 2,
        'window_start': start.millisecondsSinceEpoch,
        'remind_at': remind.millisecondsSinceEpoch,
        'energy_required': 6,
        'minutes_per_item': 7,
      }));

      expect(result.ok, isTrue, reason: result.error);
      final payload = payloadOf(result);
      expect(payload['estimate_minutes'], 14);

      final rows = await allTasks();
      final container = rows.singleWhere((t) => t.kind == 'week');
      final children = rows.where((t) => t.parentId == container.id).toList();
      expect(container.expectedAt, start.millisecondsSinceEpoch);
      expect(container.dueAt, DateTime(2026, 11, 16).millisecondsSinceEpoch,
          reason: '终点缺省按起点所在周算');
      expect(container.estimateMinutes, 14);
      expect(container.remindAt, remind.millisecondsSinceEpoch);
      for (final child in children) {
        expect(child.expectedAt, start.millisecondsSinceEpoch);
        expect(child.dueAt, DateTime(2026, 11, 16).millisecondsSinceEpoch);
        expect(child.remindAt, remind.millisecondsSinceEpoch);
        expect(child.energyRequired, 6);
        expect(child.estimateMinutes, 7);
      }
      // 估时会留下 `planned` 事件（走 writer，不直写列）。
      final events = await allEvents();
      expect(events.where((e) => e.kind == 'planned'), hasLength(1));
    });

    test('day 容器：key = paper:day:<yyyy-MM-dd>:plan', () async {
      await seedLinked(stem: '只有一道题', pointTitle: '数列');

      final result = await tool.run(invoke({
        'target_count': 1,
        'container': 'day',
      }));

      expect(result.ok, isTrue, reason: result.error);
      final payload = payloadOf(result);
      expect(payload['container_kind'], 'day');
      expect(payload['container_source_key'], 'paper:day:2026-11-15:plan');
      expect(payload['container_title'], '组卷 · 2026-11-15');
      final container = (await allTasks()).singleWhere((t) => t.kind == 'day');
      expect(
          container.expectedAt, DateTime(2026, 11, 15).millisecondsSinceEpoch);
      expect(container.dueAt, DateTime(2026, 11, 16).millisecondsSinceEpoch);
    });

    test('paper 容器：不挂窗口；key 用题目集合指纹（契约 §R8 兜底）', () async {
      await seedLinked(stem: '只有一道题', pointTitle: '数列');

      final result = await tool.run(invoke({
        'target_count': 1,
        'container': 'paper',
      }));

      expect(result.ok, isTrue, reason: result.error);
      final payload = payloadOf(result);
      expect(payload['container_kind'], 'paper');
      expect(
        payload['container_source_key'],
        'paper:${payload['question_set_key']}',
      );
      final container =
          (await allTasks()).singleWhere((t) => t.kind == 'paper');
      expect(container.expectedAt, isNull);
      expect(container.dueAt, isNull);
    });
  });

  group('不写空计划', () {
    test('题库为空：0 题 → 不落库、不建空容器，如实说原因', () async {
      final result = await tool.run(invoke({'target_count': 3}));

      expect(result.ok, isTrue, reason: result.error);
      final payload = payloadOf(result);
      expect(payload['materialized'], isFalse);
      expect(payload['materialized_reason'], 'empty_plan');
      expect(result.summary, contains('没有落库'));
      expect(await allTasks(), isEmpty);
      expect(await allEvents(), isEmpty);
    });
  });

  group('参数校验：模型能读懂并重试', () {
    test('container 只支持 week/day/paper', () async {
      final result = await tool.run(invoke({'container': 'month'}));

      expect(result.ok, isFalse);
      expect(result.error, contains('只支持 week / day / paper'));
    });

    test('window_end 早于 window_start → 失败并说明是落库参数无效', () async {
      await seedLinked(stem: '只有一道题', pointTitle: '数列');

      final result = await tool.run(invoke({
        'window_start': DateTime(2026, 11, 20).millisecondsSinceEpoch,
        'window_end': DateTime(2026, 11, 10).millisecondsSinceEpoch,
      }));

      expect(result.ok, isFalse);
      expect(result.error, contains('落库参数无效'));
      expect(await allTasks(), isEmpty, reason: '校验失败不该留下半棵树');
    });

    test('精力越界 → 失败（不悄悄夹到 1..10）', () async {
      await seedLinked(stem: '只有一道题', pointTitle: '数列');

      final result = await tool.run(invoke({
        'energy_required': 99,
      }));

      expect(result.ok, isFalse);
      expect(result.error, contains('energyRequired'));
    });
  });

  group('旧行为不变 + 安全', () {
    test('compose_paper 仍然只读：不写 tasks / thread_events', () async {
      await seedThree();
      final compose = ComposePaperTool(db: db);

      expect(compose.readOnly, isTrue);
      final result = await compose.run(ToolInvocation(
        toolName: compose.name,
        action: compose.name,
        arguments: const {'target_count': 3},
      ));

      expect(result.ok, isTrue, reason: result.error);
      expect(await allTasks(), isEmpty);
      expect(await allEvents(), isEmpty);
    });

    test('写工具不可自动执行：两种权限模式都逐条确认', () {
      for (final mode in AiPermissionMode.values) {
        final decision =
            ApprovalEngine(mode: mode).forInvocation(tool, const {});
        expect(decision.risk, ToolRisk.write);
        expect(decision.reversible, isFalse);
        expect(
          decision.disposition,
          ToolDisposition.individualApproval,
          reason: 'mode ${mode.name} 不能自动执行无法撤销的落库',
        );
      }
      expect(tool.readOnly, isFalse);
      expect(tool.reversibleFor(''), isFalse);
    });

    test('注册进 ToolRegistry，且与 compose_paper 是两个工具', () {
      final registry = ToolRegistry.forApp(
        db: db,
        tasks: TaskRepository(db),
        blocks: TimeBlockRepository(db),
        anki: anki,
        tags: tags,
      );

      expect(registry.byName(MaterializePaperTool.toolName),
          isA<MaterializePaperTool>());
      expect(registry.byName('compose_paper'), isA<ComposePaperTool>());
      expect(registry.isReadOnly('compose_paper'), isTrue);
      expect(registry.isReadOnly(MaterializePaperTool.toolName), isFalse);

      final spec = registry.modelSpecs
          .firstWhere((s) => s.name == MaterializePaperTool.toolName);
      expect(spec.description, contains('ThreadFlow'));
      final properties = spec.parameters['properties']! as Map<String, Object?>;
      expect(
        properties.keys,
        containsAll([
          'container',
          'paper_key',
          'window_start',
          'window_end',
          'remind_at',
          'energy_required',
          'minutes_per_item',
          'target_count',
        ]),
      );
    });
  });
}
