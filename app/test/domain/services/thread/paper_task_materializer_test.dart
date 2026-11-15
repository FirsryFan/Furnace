import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/tag_repository.dart';
import 'package:furnace/data/repositories/task_repository.dart';
import 'package:furnace/domain/services/paper/paper_composer.dart';
import 'package:furnace/domain/services/scheduling/thread_balance_inputs.dart'
    show ObjectTagLink, TaskKnowledgePointResolver;
import 'package:furnace/domain/services/thread/paper_task_materializer.dart';
import 'package:furnace/domain/services/thread/thread_event_kind.dart';
import 'package:furnace/domain/services/thread/thread_flow_writer.dart';
import 'package:furnace/domain/services/thread/thread_node_kind.dart';

/// `PaperTaskMaterializer`（task-73 + task-78，2026-11-15）：组卷结果 → ThreadFlow
/// 任务树 + 内容引用 + 任务标签。
///
/// 要锁的行为（每条都能单独失败）：
///
///  * 一次物化 = 1 个父容器 + 每题 1 个子节点，`kind` / `source_key` / `parent_id`
///    与契约 §3.2 的键格式一致；
///  * 同一天 / 同一周重复物化：复用同一批节点，不新增行、不追加事件；
///  * 子节点字段映射：expectedAt←窗口起点、dueAt←窗口终点、remindAt、estimate、
///    energy；缺的字段保持 null（不猜）；
///  * 父容器 estimate = 子节点之和；任一子节点没有估时 → 父容器也为 null；
///  * 卷子内容不变时 `paperKeyOf` 稳定；显式 `paperKey` 可在重新组卷时保持同一容器；
///  * 内容引用：每个子任务一条 `role=paper_item` 的 content_ref；显式 `QSET-…`
///    paperKey 才给父容器写 `role=source_package`；引用里没有正文；
///  * 任务标签：只挂**库里已有**的标签（题目标签的学科根 + 知识点直挂标签），
///    缺失跳过并计数，物化器不建标签；重复物化不重复挂；
///  * 半路失败（同 source_key 换了 kind）整个事务回滚，不留半棵树；
///  * 非法输入（容器种类 / 缺窗口 / 非法估时 / 非法精力 / 窗口倒置）直接抛错。
void main() {
  late AppDatabase db;
  late ThreadFlowWriter writer;
  late TagRepository tags;
  late PaperTaskMaterializer materializer;

  final windowStart = DateTime(2026, 11, 10, 19); // 2026-W46 周二
  final windowEnd = DateTime(2026, 11, 15, 23, 59);
  final remindAt = DateTime(2026, 11, 10, 20);
  final fixedAt = DateTime.fromMillisecondsSinceEpoch(1700000000000);

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    writer = ThreadFlowWriter(db);
    tags = TagRepository(db);
    materializer = PaperTaskMaterializer(db, writer: writer, tags: tags);
  });

  tearDown(() async {
    await db.close();
  });

  PaperPlan planOf(List<String> questionIds, {int? requestedCount}) {
    return PaperPlan(
      items: [
        for (var index = 0; index < questionIds.length; index++)
          PaperItem(
            questionId: questionIds[index],
            subjectKey: index.isEven ? 'physics' : 'math',
            sourceLevel: 'gaokao',
            questionType: 'choice',
            knowledgePointId: 'kp-$index',
            matchedKnowledgePointIds: <String>['kp-$index'],
            zone: index.isEven ? PaperZone.danger : PaperZone.development,
            need: 1,
            quality: 0.8,
            score: 0.9,
            reasonZh: '危险区优先（${questionIds[index]}）',
            improvementNote: '注意边界',
            backgroundZh: '力学/运动学',
          ),
      ],
      uncoveredKnowledgePointIds: const <String>[],
      deferredKnowledgePointIds: const <String>[],
      byKnowledgePoint: <String, int>{
        for (var index = 0; index < questionIds.length; index++) 'kp-$index': 1,
      },
      candidateCount: questionIds.length,
      requestedCount: requestedCount ?? questionIds.length,
      overallNeed: 1,
      weights: const PaperWeights(),
    );
  }

  PaperMaterializeRequest requestOf(
    PaperPlan plan, {
    ThreadNodeKind containerKind = ThreadNodeKind.day,
    String? paperKey,
    DateTime? start,
    DateTime? end,
    DateTime? remind,
    int? energy,
    int? minutesPerItem,
    String? containerTitle,
    List<String> containerTagIds = const <String>[],
  }) {
    return PaperMaterializeRequest(
      plan: plan,
      containerKind: containerKind,
      paperKey: paperKey,
      windowStart: start ?? windowStart,
      windowEnd: end ?? windowEnd,
      remindAt: remind,
      energyRequired: energy,
      minutesPerItem: minutesPerItem,
      containerTitle: containerTitle,
      containerTagIds: containerTagIds,
      at: fixedAt,
    );
  }

  Future<List<Task>> allTasks() => db.select(db.tasks).get();

  Future<List<String>> eventKindsOf(String taskId) async {
    final rows = await (db.select(db.threadEvents)
          ..where((e) => e.taskId.equals(taskId)))
        .get();
    return <String>[for (final row in rows) row.kind]..sort();
  }

  Future<int> eventCount() async =>
      (await db.select(db.threadEvents).get()).length;

  group('物化结构：父容器 + 每题子节点', () {
    test('day 容器：kind/source_key/parent 与契约键格式一致', () async {
      final plan = planOf(<String>['Q-PH0001', 'Q-MA0001']);
      final tree = await materializer.materialize(requestOf(plan));

      final key = PaperTaskMaterializer.paperKeyOf(plan);
      expect(tree.createdContainer, isTrue);
      expect(tree.createdQuestionIds, <String>['Q-PH0001', 'Q-MA0001']);
      expect(tree.container.kind, ThreadNodeKind.day.id);
      expect(tree.container.parentId, isNull);
      expect(
        tree.container.sourceKey,
        'paper:day:2026-11-10:$key',
      );
      expect(tree.container.title, '组卷 · 2026-11-10（2 题）');

      expect(tree.items, hasLength(2));
      for (final child in tree.items) {
        expect(child.kind, ThreadNodeKind.task.id);
        expect(child.parentId, tree.container.id);
      }
      expect(
        tree.items.first.sourceKey,
        'paper:day:2026-11-10:$key:Q-PH0001',
      );
      expect(
        tree.items[1].sourceKey,
        'paper:day:2026-11-10:$key:Q-MA0001',
      );
      expect(tree.items.first.title, '第 1 题 · Q-PH0001');
      expect(tree.items[1].title, '第 2 题 · Q-MA0001');
    });

    test('week 容器：source_key 用 ISO 周标签（2026-11-15 → 2026-W46）', () async {
      final plan = planOf(<String>['Q-PH0001']);
      final tree = await materializer.materialize(
        requestOf(plan, containerKind: ThreadNodeKind.week),
      );

      final key = PaperTaskMaterializer.paperKeyOf(plan);
      expect(
        tree.container.sourceKey,
        'paper:week:2026-W46:$key',
      );
      expect(tree.container.title, '组卷 · 2026-W46（1 题）');
      expect(
        tree.items.single.sourceKey,
        'paper:week:2026-W46:$key:Q-PH0001',
      );
    });

    test('paper 容器：无日期标签，kind=paper', () async {
      final plan = planOf(<String>['Q-PH0001']);
      final tree = await materializer.materialize(
        PaperMaterializeRequest(
          plan: plan,
          containerKind: ThreadNodeKind.paper,
          paperKey: 'QSET-20261115-01',
          at: fixedAt,
        ),
      );

      expect(tree.container.kind, ThreadNodeKind.paper.id);
      expect(tree.container.sourceKey, 'paper:QSET-20261115-01');
      expect(
        tree.items.single.sourceKey,
        'paper:QSET-20261115-01:Q-PH0001',
      );
    });

    test('空卷：只建容器，不建子节点', () async {
      final plan = planOf(<String>[]);
      final tree = await materializer.materialize(requestOf(plan));

      expect(tree.items, isEmpty);
      expect(tree.createdQuestionIds, isEmpty);
      expect(await allTasks(), hasLength(1));
      expect(tree.container.estimateMinutes, isNull);
    });

    test('任务树查询：children 全部挂在容器下，容器本身 parent 为 null', () async {
      final plan = planOf(<String>['Q-1', 'Q-2', 'Q-3']);
      final tree = await materializer.materialize(requestOf(plan));
      final repository = TaskRepository(db);

      final children = await repository.getTasks(parentId: tree.container.id);
      expect(children.map((t) => t.id).toSet(),
          tree.items.map((t) => t.id).toSet());
      final root = await repository.getTaskById(tree.container.id);
      expect(root!.parentId, isNull);
    });
  });

  group('幂等：同日 / 同周重复物化不新增', () {
    test('同一天同一份卷子跑两次：同一批节点、不新增行、不追加事件', () async {
      final plan = planOf(<String>['Q-PH0001', 'Q-MA0001']);
      final request = requestOf(plan);

      final first = await materializer.materialize(request);
      final tasksAfterFirst = await allTasks();
      final eventsAfterFirst = await eventCount();

      final second = await materializer.materialize(requestOf(plan));

      expect(second.createdContainer, isFalse);
      expect(second.createdQuestionIds, isEmpty);
      expect(second.container.id, first.container.id);
      expect(
        second.items.map((t) => t.id).toList(),
        first.items.map((t) => t.id).toList(),
      );
      expect(await allTasks(), hasLength(tasksAfterFirst.length));
      expect(await eventCount(), eventsAfterFirst);
    });

    test('同一周不同天（周二/周四）物化同一份卷子：复用同一个 week 容器',
        () async {
      final plan = planOf(<String>['Q-PH0001']);
      final first = await materializer.materialize(
        requestOf(
          plan,
          containerKind: ThreadNodeKind.week,
          start: DateTime(2026, 11, 10, 19),
        ),
      );
      final second = await materializer.materialize(
        requestOf(
          plan,
          containerKind: ThreadNodeKind.week,
          start: DateTime(2026, 11, 12, 8),
        ),
      );

      expect(second.createdContainer, isFalse);
      expect(second.container.id, first.container.id);
      expect(await allTasks(), hasLength(2));
    });

    test('同一天不同时刻（早上/晚上）物化：日期标签相同，复用容器', () async {
      final plan = planOf(<String>['Q-PH0001']);
      final first = await materializer.materialize(
        requestOf(plan, start: DateTime(2026, 11, 15, 8)),
      );
      final second = await materializer.materialize(
        requestOf(plan, start: DateTime(2026, 11, 15, 20)),
      );

      expect(second.container.id, first.container.id);
      expect(second.container.sourceKey, first.container.sourceKey);
    });

    test('显式 paperKey 在重新组卷（题目增减）时保持同一容器，新子节点只加一份',
        () async {
      const paperKey = 'QSET-20261110-01';
      final first = await materializer.materialize(
        requestOf(planOf(<String>['Q-1', 'Q-2', 'Q-3']), paperKey: paperKey),
      );
      final second = await materializer.materialize(
        requestOf(
          planOf(<String>['Q-1', 'Q-2', 'Q-3', 'Q-4']),
          paperKey: paperKey,
        ),
      );

      expect(second.container.id, first.container.id);
      expect(second.createdContainer, isFalse);
      expect(second.createdQuestionIds, <String>['Q-4']);
      expect(second.items, hasLength(4));
      expect(await allTasks(), hasLength(5), reason: '1 个容器 + 4 道子题');
    });

    test('内容不同的两份卷子各自建容器（paperHash 就是卷子身份）', () async {
      final first = await materializer.materialize(
        requestOf(planOf(<String>['Q-1'])),
      );
      final second = await materializer.materialize(
        requestOf(planOf(<String>['Q-2'])),
      );

      expect(second.container.id, isNot(first.container.id));
      expect(second.container.sourceKey,
          isNot(first.container.sourceKey));
      expect(await allTasks(), hasLength(4));
    });
  });

  group('字段映射：不猜缺失值', () {
    test('窗口起点→expectedAt，窗口终点→dueAt，remindAt/energy 原样落到子节点',
        () async {
      final plan = planOf(<String>['Q-PH0001', 'Q-MA0001']);
      final tree = await materializer.materialize(
        requestOf(plan, remind: remindAt, energy: 6),
      );

      for (final child in tree.items) {
        expect(child.expectedAt, windowStart.millisecondsSinceEpoch);
        expect(child.dueAt, windowEnd.millisecondsSinceEpoch);
        expect(child.remindAt, remindAt.millisecondsSinceEpoch);
        expect(child.energyRequired, 6);
        expect(child.status, 'todo');
      }
      expect(tree.container.expectedAt, windowStart.millisecondsSinceEpoch);
      expect(tree.container.dueAt, windowEnd.millisecondsSinceEpoch);
      expect(tree.container.remindAt, remindAt.millisecondsSinceEpoch);
      expect(tree.container.energyRequired, isNull,
          reason: '契约 §3.2：容器节点不写精力');
    });

    test('没给的调度字段保持 null（不默认成 0 / 不猜）', () async {
      final plan = planOf(<String>['Q-PH0001']);
      final tree = await materializer.materialize(
        PaperMaterializeRequest(
          plan: plan,
          containerKind: ThreadNodeKind.day,
          windowStart: DateTime(2026, 11, 15),
          at: fixedAt,
        ),
      );

      final child = tree.items.single;
      expect(child.dueAt, isNull);
      expect(child.remindAt, isNull);
      expect(child.energyRequired, isNull);
      expect(child.estimateMinutes, isNull);
      expect(tree.container.dueAt, isNull);
      expect(tree.container.remindAt, isNull);
      expect(tree.container.estimateMinutes, isNull);
    });

    test('标题/描述来自 PaperItem 的可解释字段', () async {
      final plan = planOf(<String>['Q-PH0001']);
      final tree = await materializer.materialize(requestOf(plan));
      final child = tree.items.single;

      final description = child.description ?? '';
      expect(description, contains('为什么排它：危险区优先（Q-PH0001）'));
      expect(description, contains('提升点：注意边界'));
      expect(description, contains('知识背景：力学/运动学'));
      expect(description, contains('分区：危险区'));
      expect(description, contains('学科：physics'));
      expect(description, contains('主知识点：kp-0'));
    });
  });

  group('父容器估时 = 子节点之和', () {
    test('每题 7 分钟 × 3 题 → 子节点 7，容器 21', () async {
      final tree = await materializer.materialize(
        requestOf(planOf(<String>['Q-1', 'Q-2', 'Q-3']), minutesPerItem: 7),
      );

      expect(tree.items.map((t) => t.estimateMinutes).toList(), <int>[7, 7, 7]);
      expect(tree.container.estimateMinutes, 21);
      expect(tree.estimateMinutes, 21);
    });

    test('任一子节点没有估时 → 容器也不写估时（未知不冒充 0）', () async {
      final plan = planOf(<String>['Q-1', 'Q-2']);
      await materializer.materialize(
        requestOf(plan, paperKey: 'QSET-MIXED'),
      );
      final tree = await materializer.materialize(
        requestOf(plan, paperKey: 'QSET-MIXED', minutesPerItem: 5),
      );

      // 子节点是复用行，第一次没估时，第二次不会改写已有子节点。
      expect(tree.items.map((t) => t.estimateMinutes).toSet(), <int?>{null});
      expect(tree.container.estimateMinutes, isNull);
    });

    test('子节点增加后重算容器估时（7 × 4 = 28）', () async {
      const paperKey = 'QSET-GROW';
      await materializer.materialize(
        requestOf(
          planOf(<String>['Q-1', 'Q-2', 'Q-3']),
          paperKey: paperKey,
          minutesPerItem: 7,
        ),
      );
      final grown = await materializer.materialize(
        requestOf(
          planOf(<String>['Q-1', 'Q-2', 'Q-3', 'Q-4']),
          paperKey: paperKey,
          minutesPerItem: 7,
        ),
      );

      expect(grown.items, hasLength(4));
      expect(grown.container.estimateMinutes, 28);
    });
  });

  group('ThreadFlowWriter 事件', () {
    test('每个节点 exactly 一条 created；容器算了估时再留一条 planned', () async {
      final tree = await materializer.materialize(
        requestOf(planOf(<String>['Q-1', 'Q-2']), minutesPerItem: 5),
      );

      expect(await eventKindsOf(tree.container.id),
          <String>[ThreadEventKind.created.id, ThreadEventKind.planned.id]);
      for (final child in tree.items) {
        expect(await eventKindsOf(child.id), <String>[ThreadEventKind.created.id]);
      }
      expect(await eventCount(), 4, reason: '容器 created+planned + 2 条子节点 created');
    });

    test('重复物化不追加任何事件（planned 也幂等）', () async {
      final plan = planOf(<String>['Q-1', 'Q-2']);
      await materializer.materialize(
        requestOf(plan, paperKey: 'QSET-IDEM', minutesPerItem: 5),
      );
      final before = await eventCount();

      await materializer.materialize(
        requestOf(plan, paperKey: 'QSET-IDEM', minutesPerItem: 5),
      );
      expect(await eventCount(), before);
    });

    test('没有估时就不写 planned（created 之外不虚构排期事实）', () async {
      final tree = await materializer.materialize(
        requestOf(planOf(<String>['Q-1'])),
      );
      expect(await eventKindsOf(tree.container.id),
          <String>[ThreadEventKind.created.id]);
    });
  });

  group('内容引用：question ↔ task（不写正文）', () {
    test('每个子任务一条 paper_item 引用；引用里没有理由/建议/背景正文', () async {
      final tree = await materializer.materialize(
        requestOf(planOf(<String>['Q-PH0001', 'Q-MA0001'])),
      );

      final rows = await db.select(db.contentRefs).get();
      expect(rows, hasLength(2), reason: '派生 paperKey 不写容器引用');
      final first = rows.singleWhere((r) => r.contentId == 'Q-PH0001');
      expect(first.objectType, 'task');
      expect(first.objectId, tree.items.first.id);
      expect(first.role, 'paper_item');
      expect(first.subject, 'physics');
      // version/hash 未知就不给，且必须成对为空（契约 §2.3）。
      expect(first.contentVersion, isNull);
      expect(first.contentHash, isNull);

      // 只存引用摘要：题干/答案/解析/理由/建议/背景一个字都不进 content_refs。
      final metadata = first.metadataJson ?? '';
      expect(metadata, contains('knowledge_point_id'));
      expect(metadata, contains('source_level'));
      expect(metadata, isNot(contains('危险区优先')));
      expect(metadata, isNot(contains('注意边界')));
      expect(metadata, isNot(contains('力学/运动学')));
    });

    test('显式 QSET paperKey 才给父容器写 source_package；派生键/plan 不写', () async {
      final explicit = await materializer.materialize(
        requestOf(planOf(<String>['Q-PH0001']), paperKey: 'QSET-20261115-01'),
      );
      final containerRefs = (await db.select(db.contentRefs).get())
          .where((r) => r.objectId == explicit.container.id)
          .toList();
      expect(containerRefs, hasLength(1));
      expect(containerRefs.single.contentId, 'QSET-20261115-01');
      expect(containerRefs.single.role, 'source_package');
      expect(containerRefs.single.objectType, 'task');
      expect(explicit.refs.sourcePackageRefEnsured, isTrue);

      final derived = await materializer.materialize(
        requestOf(planOf(<String>['Q-MA0001'])),
      );
      expect(
        (await db.select(db.contentRefs).get())
            .where((r) => r.objectId == derived.container.id),
        isEmpty,
        reason: '题集指纹不是内容 id',
      );
      expect(derived.refs.sourcePackageRefEnsured, isFalse);

      // AI 工具的默认 paper_key='plan' 是幂等键，不是内容 id：同样不写。
      final synthetic = await materializer.materialize(
        requestOf(planOf(<String>['Q-CH0001']), paperKey: 'plan'),
      );
      expect(
        (await db.select(db.contentRefs).get())
            .where((r) => r.objectId == synthetic.container.id),
        isEmpty,
      );
    });

    test('重复物化不新增引用（唯一键幂等）', () async {
      final plan = planOf(<String>['Q-PH0001', 'Q-MA0001']);
      final first = await materializer.materialize(
        requestOf(plan, paperKey: 'QSET-20261115-02'),
      );
      final rowsAfterFirst = (await db.select(db.contentRefs).get()).length;

      final second = await materializer.materialize(
        requestOf(plan, paperKey: 'QSET-20261115-02'),
      );

      expect((await db.select(db.contentRefs).get()).length, rowsAfterFirst);
      expect(second.container.id, first.container.id);
      expect(second.refs.paperItemRefsEnsured, first.refs.paperItemRefsEnsured);
    });
  });

  group('任务标签：只引用已存在的标签', () {
    Future<(Tag, Tag, Tag, Tag)> seedTagTree() async {
      final physicsRoot = await tags.createTag(name: '物理');
      final mathRoot = await tags.createTag(name: '数学');
      final momentum = await tags.createTag(
        name: '动量守恒',
        parentId: physicsRoot.id,
      );
      final sequence = await tags.createTag(name: '等差', parentId: mathRoot.id);
      await tags.addTagToObject(
        tagId: momentum.id,
        objectType: 'knowledge_point',
        objectId: 'kp-0',
      );
      await tags.addTagToObject(
        tagId: sequence.id,
        objectType: 'knowledge_point',
        objectId: 'kp-1',
      );
      // 第 1 题：直挂学科根（学科标签走 3a）。
      await tags.addTagToObject(
        tagId: physicsRoot.id,
        objectType: 'question',
        objectId: 'Q-PH0001',
      );
      // 第 2 题：只挂了一个非学科根（文化课/自定义章节）→ 3a 不命中，走 3b
      // "按学科名找顶层标签"，且**不许**把文化课根挂到任务上。
      final culture = await tags.createTag(name: '文化课');
      final custom = await tags.createTag(name: '自定义章节', parentId: culture.id);
      await tags.addTagToObject(
        tagId: custom.id,
        objectType: 'question',
        objectId: 'Q-MA0001',
      );
      return (physicsRoot, mathRoot, momentum, sequence);
    }

    test('子任务挂学科根 + 知识点标签；父容器挂学科并集；非学科根不挂', () async {
      final (physicsRoot, mathRoot, momentum, sequence) = await seedTagTree();
      final tagCountBefore = (await db.select(db.tags).get()).length;

      final tree = await materializer.materialize(
        requestOf(planOf(<String>['Q-PH0001', 'Q-MA0001'])),
      );

      Future<Set<String>> taskTagIds(String taskId) async => {
            for (final tag in await tags.tagsForObject(
              objectType: 'task',
              objectId: taskId,
            ))
              tag.id,
          };

      expect(
        await taskTagIds(tree.items[0].id),
        {physicsRoot.id, momentum.id},
      );
      expect(
        await taskTagIds(tree.items[1].id),
        {mathRoot.id, sequence.id},
        reason: '题目标签的根不是学科根时按学科名找现成顶层标签，不挂文化课',
      );
      expect(
        await taskTagIds(tree.container.id),
        {physicsRoot.id, mathRoot.id},
        reason: '父容器挂子题学科标签的并集',
      );
      expect(tree.refs.taskTagLinksCreated, 6);
      expect(tree.refs.subjectTagMisses, 0);
      expect(tree.refs.knowledgePointTagMisses, 0);
      expect(tree.refs.hasMisses, isFalse);
      expect((await db.select(db.tags).get()).length, tagCountBefore,
          reason: '物化器不创建标签');

      // 任务与知识点共享标签 → 段落 B 的唯一规则能反推"任务在练哪个知识点"。
      final links = [
        for (final row in await db.select(db.objectTags).get())
          ObjectTagLink(
            tagId: row.tagId,
            objectType: row.objectType,
            objectId: row.objectId,
          ),
      ];
      final resolved = TaskKnowledgePointResolver.resolveFromTagLinks(links);
      expect(resolved[tree.items[0].id], ['kp-0']);
      expect(resolved[tree.items[1].id], ['kp-1']);
    });

    test('缺失标签跳过并计数：不建标签、不写 object_tags', () async {
      final tree = await materializer.materialize(
        requestOf(planOf(<String>['Q-PH0001', 'Q-MA0001'])),
      );

      expect(await db.select(db.objectTags).get(), isEmpty);
      expect(await db.select(db.tags).get(), isEmpty, reason: '物化器不创建标签');
      expect(tree.refs.taskTagLinksCreated, 0);
      expect(tree.refs.subjectTagMisses, 2);
      expect(tree.refs.knowledgePointTagMisses, 2);
      expect(tree.refs.hasMisses, isTrue);
    });

    test('显式 containerTagIds：存在的挂上，不存在的跳过并记入 missing', () async {
      final physics = await tags.createTag(name: '物理');
      final tree = await materializer.materialize(
        requestOf(
          planOf(<String>['Q-PH0001']),
          paperKey: 'QSET-20261115-03',
          containerTagIds: <String>[physics.id, 'tag-missing'],
        ),
      );

      final containerTags = await tags.tagsForObject(
        objectType: 'task',
        objectId: tree.container.id,
      );
      expect(containerTags.map((t) => t.id).toSet(), {physics.id});
      expect(tree.refs.missingContainerTagIds, <String>['tag-missing']);
      expect(await db.select(db.tags).get(), hasLength(1),
          reason: '缺失的标签 id 只跳过，不补建');
    });

    test('重复物化：标签链接行数不变，第二次新增 0', () async {
      await seedTagTree();
      final plan = planOf(<String>['Q-PH0001', 'Q-MA0001']);

      final first = await materializer.materialize(requestOf(plan));
      final linksAfterFirst = (await db.select(db.objectTags).get()).length;
      final tagsAfterFirst = (await db.select(db.tags).get()).length;
      // 预置 4 条（2 条知识点标签 + 2 条题目标签）+ 本任务树 6 条（子题各 2 + 容器 2）。
      expect(linksAfterFirst, 10);
      expect(first.refs.taskTagLinksCreated, 6);

      final second = await materializer.materialize(requestOf(plan));
      expect(second.container.id, first.container.id);
      expect((await db.select(db.objectTags).get()).length, linksAfterFirst);
      expect((await db.select(db.tags).get()).length, tagsAfterFirst);
      expect(second.refs.taskTagLinksCreated, 0);
    });
  });

  group('写入范围：不写正文、不写完成/作答事实', () {
    test('没有可用标签时 object_tags 为空；content_refs 只有逐题引用', () async {
      final tree = await materializer.materialize(
        requestOf(
          planOf(<String>['Q-1', 'Q-2']),
          minutesPerItem: 5,
          energy: 4,
        ),
      );

      expect((await db.select(db.contentRefs).get()).length, 2);
      expect(tree.refs.paperItemRefsEnsured, 2);
      expect(await db.select(db.objectTags).get(), isEmpty);
      expect(await db.select(db.completionLogs).get(), isEmpty);
      expect(await db.select(db.questionAttempts).get(), isEmpty);
      expect(await allTasks(), hasLength(3));
      expect(await eventCount(), 4);
    });
  });

  group('失败与回滚', () {
    test('子节点 source_key 已属于别的 kind：整棵树回滚，不留半棵树', () async {
      final plan = planOf(<String>['Q-1', 'Q-2']);
      final childKey = PaperTaskMaterializer.itemSourceKey(
        containerKind: ThreadNodeKind.day,
        paperKey: PaperTaskMaterializer.paperKeyOf(plan),
        questionId: 'Q-2',
        windowStart: windowStart,
      );
      await writer.ensureTask(
        title: '占位节点',
        kind: ThreadNodeKind.week,
        sourceKey: childKey,
        at: fixedAt,
      );
      expect(await eventCount(), 1);

      await expectLater(
        materializer.materialize(requestOf(plan)),
        throwsA(isA<StateError>()),
      );

      final remaining = await allTasks();
      expect(remaining, hasLength(1), reason: '容器和 Q-1 子节点都不该留下');
      expect(remaining.single.sourceKey, childKey);
      expect(await eventCount(), 1);
      // 引用/标签与任务树同一个事务：失败后一行都不该留下。
      expect(await db.select(db.contentRefs).get(), isEmpty);
      expect(await db.select(db.objectTags).get(), isEmpty);
    });

    test('非法输入直接抛错，不落任何行', () async {
      final plan = planOf(<String>['Q-1']);
      Future<void> expectArgumentError(PaperMaterializeRequest request) async {
        await expectLater(
          materializer.materialize(request),
          throwsA(isA<ArgumentError>()),
        );
      }

      // 容器种类只能是 week/day/paper。
      await expectArgumentError(
        requestOf(plan, containerKind: ThreadNodeKind.task),
      );
      await expectArgumentError(
        requestOf(plan, containerKind: ThreadNodeKind.review),
      );
      // week/day 必须有日期标签。
      await expectArgumentError(
        PaperMaterializeRequest(
          plan: plan,
          containerKind: ThreadNodeKind.week,
          at: fixedAt,
        ),
      );
      // 估时/精力越界。
      await expectArgumentError(
        requestOf(plan, minutesPerItem: 0),
      );
      await expectArgumentError(
        requestOf(plan, energy: 0),
      );
      await expectArgumentError(
        requestOf(plan, energy: 11),
      );
      // 窗口倒置。
      await expectArgumentError(
        requestOf(
          plan,
          start: DateTime(2026, 11, 16),
          end: DateTime(2026, 11, 15),
        ),
      );

      expect(await allTasks(), isEmpty);
      expect(await eventCount(), 0);
    });
  });

  group('键与 ISO 周工具', () {
    test('isoWeekLabel：年边界按周四定年、53 周年份正确', () {
      expect(PaperTaskMaterializer.isoWeekLabel(DateTime(2026, 11, 15)),
          '2026-W46');
      expect(PaperTaskMaterializer.isoWeekLabel(DateTime(2026, 11, 10)),
          '2026-W46');
      expect(PaperTaskMaterializer.isoWeekLabel(DateTime(2026, 1, 1)),
          '2026-W01');
      expect(PaperTaskMaterializer.isoWeekLabel(DateTime(2025, 12, 29)),
          '2026-W01');
      expect(PaperTaskMaterializer.isoWeekLabel(DateTime(2024, 12, 30)),
          '2025-W01');
      expect(PaperTaskMaterializer.isoWeekLabel(DateTime(2021, 1, 1)),
          '2020-W53');
      expect(PaperTaskMaterializer.isoWeekLabel(DateTime(2026, 12, 31)),
          '2026-W53');
    });

    test('paperKeyOf 与题序无关、与题目集合有关', () {
      final a = planOf(<String>['Q-1', 'Q-2', 'Q-3']);
      final b = planOf(<String>['Q-3', 'Q-1', 'Q-2']);
      final c = planOf(<String>['Q-1', 'Q-2']);
      expect(PaperTaskMaterializer.paperKeyOf(a),
          PaperTaskMaterializer.paperKeyOf(b));
      expect(PaperTaskMaterializer.paperKeyOf(a),
          isNot(PaperTaskMaterializer.paperKeyOf(c)));
    });

    test('静态键工具与落库键一致', () async {
      final plan = planOf(<String>['Q-PH0001']);
      final key = PaperTaskMaterializer.paperKeyOf(plan);
      final tree = await materializer.materialize(
        requestOf(plan, containerKind: ThreadNodeKind.week),
      );

      expect(
        tree.container.sourceKey,
        PaperTaskMaterializer.containerSourceKey(
          containerKind: ThreadNodeKind.week,
          paperKey: key,
          windowStart: windowStart,
        ),
      );
      expect(
        tree.items.single.sourceKey,
        PaperTaskMaterializer.itemSourceKey(
          containerKind: ThreadNodeKind.week,
          paperKey: key,
          questionId: 'Q-PH0001',
          windowStart: windowStart,
        ),
      );
    });
  });
}
