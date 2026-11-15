/// `TagKnowledgeIndex`（契约 §4.3 的标签知识入口统一只读索引）。
///
/// 钉住的口径：
///  * 查题 / 查卡 / 查任务各自走 `object_tags` 与 知识点 → 卡模板，不猜关系；
///  * 默认只看直挂，`includeDescendants` 才按 `parent_id` 子树统计；
///  * 数量 = 真实存在的行数；悬空链接只进 `missingTargets`，不补假行；
///  * `content_refs` 没有 tag 列，所以**没有标签关系的题不会出现**；
///  * 卡组沿祖先链解析（最近一个配置过复习计划的标签）。
library;

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/anki_repository.dart';
import 'package:furnace/data/repositories/content_ref_repository.dart';
import 'package:furnace/data/repositories/question_repository.dart';
import 'package:furnace/data/repositories/review_plan_repository.dart';
import 'package:furnace/data/repositories/tag_repository.dart';
import 'package:furnace/data/repositories/task_repository.dart';
import 'package:furnace/domain/services/thread/thread_status.dart';
import 'package:furnace/features/tags/application/tag_knowledge_index.dart';

void main() {
  late AppDatabase db;
  late TagRepository tags;
  late QuestionRepository questions;
  late AnkiRepository anki;
  late TaskRepository tasks;
  late ReviewPlanRepository reviewPlans;
  late TagKnowledgeIndex index;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    tags = TagRepository(db);
    questions = QuestionRepository(db);
    anki = AnkiRepository(db);
    tasks = TaskRepository(db);
    reviewPlans = ReviewPlanRepository(db, anki);
    index = TagKnowledgeIndex(
      tags: tags,
      questions: questions,
      anki: anki,
      tasks: tasks,
      reviewPlans: reviewPlans,
    );
  });

  tearDown(() async {
    await db.close();
  });

  /// 一个标签（可指定父标签）。
  Future<Tag> seedTag(String name, {String? parentId}) =>
      tags.createTag(name: name, parentId: parentId);

  /// 一道题（可带题名/挂标签）。
  Future<Question> seedQuestion(
    String stem, {
    Set<String> tagIds = const <String>{},
    String? title,
  }) async {
    final question =
        (await questions.ingest(QuestionDraft(stem: stem, tagIds: tagIds)))
            .question;
    if (title != null) {
      await questions.setQuestionTitle(question.id, title);
      return (await questions.byId(question.id))!;
    }
    return question;
  }

  /// 一个知识点 + 一张卡；知识点挂到 [tagId] 上。
  Future<CardTemplate> seedCard({
    required String tagId,
    required String knowledgePointTitle,
    required String front,
  }) async {
    final point = await anki.createKnowledgePoint(
      title: knowledgePointTitle,
      content: '内容',
    );
    await tags.addTagToObject(
      tagId: tagId,
      objectType: 'knowledge_point',
      objectId: point.id,
    );
    return anki.createTemplate(
      knowledgePointId: point.id,
      type: 'fill_blank',
      question: front,
      answer: '答案',
    );
  }

  /// 一条任务并挂到标签上。
  Future<Task> seedTask(
    String title, {
    required String tagId,
    String status = 'todo',
  }) async {
    final task = await tasks.createTask(title: title, status: status);
    await tags.addTagToObject(
      tagId: tagId,
      objectType: 'task',
      objectId: task.id,
    );
    return task;
  }

  test('同一个标签：题 / 卡 / 任务各自按真实链接出现，数量等于行数', () async {
    final root = await seedTag('物理');
    final child = await seedTag('力学', parentId: root.id);

    final first = await seedQuestion(
      '求小球的加速度',
      tagIds: {child.id},
      title: '牛顿第二定律',
    );
    final second = await seedQuestion('求摩擦力', tagIds: {child.id});
    final card = await seedCard(
      tagId: child.id,
      knowledgePointTitle: '受力分析',
      front: '重力的方向是？',
    );
    final task = await seedTask('完成力学练习', tagId: child.id);

    final snapshot = await index.snapshot(child.id);

    expect(snapshot.isMissingTag, isFalse);
    expect(snapshot.questions.map((q) => q.id).toList(), <String>[
      first.id,
      second.id,
    ]);
    // 题名优先、没题名的行回落题干摘要（由页面决定怎么显示，这里只保证行存在）。
    expect(snapshot.questions.first.title, '牛顿第二定律');
    expect(snapshot.questions[1].title, isNull);
    expect(snapshot.cards, hasLength(1));
    expect(snapshot.cards.single.template.id, card.id);
    expect(snapshot.cards.single.knowledgePointTitle, '受力分析');
    expect(snapshot.tasks.map((t) => t.id).toList(), <String>[task.id]);
    expect(snapshot.knowledgePointCount, 1);
    expect(snapshot.missingTargets, 0);
    expect(snapshot.isEmpty, isFalse);
  });

  test('默认只看直挂；含子标签才把子树上的链接算进来', () async {
    final root = await seedTag('数学');
    final child = await seedTag('函数', parentId: root.id);
    await seedQuestion('求二次函数最小值', tagIds: {child.id});
    final card = await seedCard(
      tagId: child.id,
      knowledgePointTitle: '二次函数',
      front: '顶点式？',
    );
    await seedTask('复习函数', tagId: child.id);

    final direct = await index.snapshot(root.id);
    expect(direct.questions, isEmpty);
    expect(direct.cards, isEmpty);
    expect(direct.tasks, isEmpty);
    expect(direct.knowledgePointCount, 0);

    final subtree = await index.snapshot(root.id, includeDescendants: true);
    expect(subtree.questions, hasLength(1));
    expect(subtree.cards.single.template.id, card.id);
    expect(subtree.tasks, hasLength(1));
    expect(subtree.knowledgePointCount, 1);
  });

  test('标签不存在：如实返回 isMissingTag，不抛错', () async {
    final snapshot = await index.snapshot('tag-does-not-exist');
    expect(snapshot.isMissingTag, isTrue);
    expect(snapshot.isEmpty, isTrue);
    expect(snapshot.questions, isEmpty);
    expect(snapshot.cards, isEmpty);
    expect(snapshot.tasks, isEmpty);
  });

  test('悬空链接只计入 missingTargets，不补假行', () async {
    final tag = await seedTag('化学');
    await tags.addTagToObject(
      tagId: tag.id,
      objectType: 'question',
      objectId: 'q-deleted',
    );
    await tags.addTagToObject(
      tagId: tag.id,
      objectType: 'task',
      objectId: 'task-deleted',
    );

    final snapshot = await index.snapshot(tag.id);

    expect(snapshot.questions, isEmpty);
    expect(snapshot.tasks, isEmpty);
    expect(snapshot.missingTargets, 2);
    expect(snapshot.isEmpty, isTrue);
  });

  test('content_refs 不能当标签关系：没有 object_tags 的题不出现', () async {
    final tag = await seedTag('语文');
    final question = await seedQuestion('文言文断句');
    // 有内容引用、但没有标签链接。
    await ContentRefRepository(db).upsert(
      contentId: 'Q-CH0001',
      objectType: 'question',
      objectId: question.id,
      role: 'source_package',
    );

    final snapshot = await index.snapshot(tag.id);
    expect(snapshot.questions, isEmpty);
    expect(await ContentRefRepository(db).listForObject(
      objectType: 'question',
      objectId: question.id,
    ), hasLength(1));
  });

  test('题目顺序按题号升序（没编号的排最后），同号再按 id 稳定', () async {
    final tag = await seedTag('英语');
    final serialOne = await seedQuestion('第一题', tagIds: {tag.id});
    final serialTwo = await seedQuestion('第二题', tagIds: {tag.id});
    final unnumbered = await seedQuestion('老题', tagIds: {tag.id});
    // 去掉编号，模拟更早版本/导入前的题。
    await (db.update(db.questions)
          ..where((t) => t.id.equals(unnumbered.id)))
        .write(const QuestionsCompanion(
      serialNo: Value<int?>(null),
    ));

    final snapshot = await index.snapshot(tag.id);
    expect(
      snapshot.questions.map((q) => q.serialNo).toList(),
      <int?>[serialOne.serialNo, serialTwo.serialNo, null],
    );
  });

  test('卡片按知识点标题 → sortOrder → id 排，且同一条模板只出现一次', () async {
    final tag = await seedTag('生物');
    final cardB = await seedCard(
      tagId: tag.id,
      knowledgePointTitle: 'B 细胞',
      front: 'B 卡',
    );
    final cardA = await seedCard(
      tagId: tag.id,
      knowledgePointTitle: 'A 细胞',
      front: 'A 卡',
    );
    // 历史直挂：同一条模板再挂一条 object_tags(card_template)，不能出现两行。
    await tags.addTagToObject(
      tagId: tag.id,
      objectType: 'card_template',
      objectId: cardA.id,
    );

    final snapshot = await index.snapshot(tag.id);
    expect(snapshot.cards, hasLength(2));
    expect(snapshot.cards.map((c) => c.id).toList(), <String>[
      cardA.id,
      cardB.id,
    ]);
  });

  test('任务顺序：待办/进行中在前，已完成在后', () async {
    final tag = await seedTag('任务');
    final done = await seedTask('已完成的', tagId: tag.id, status: 'done');
    final todo = await seedTask('待办', tagId: tag.id);
    final blocked = await seedTask('卡住', tagId: tag.id, status: 'blocked');

    final snapshot = await index.snapshot(tag.id);
    expect(
      snapshot.tasks.map((t) => t.id).toList(),
      <String>[todo.id, blocked.id, done.id],
    );
    expect(ThreadStatus.fromStorage(snapshot.tasks.last.status),
        ThreadStatus.done);
  });

  test('卡组沿祖先链解析；没有任何上级卡组时为 null', () async {
    final root = await seedTag('化学');
    final child = await seedTag('平衡', parentId: root.id);
    await reviewPlans.setGroupPlan(
      tagId: root.id,
      newCardsPerDay: 10,
      reviewCardsPerDay: 20,
    );

    final childSnapshot = await index.snapshot(child.id);
    expect(childSnapshot.reviewGroup, isNotNull);
    expect(childSnapshot.reviewGroup!.tagId, root.id);
    expect(childSnapshot.reviewGroup!.tagPath, '化学');

    final other = await seedTag('没有卡组');
    final otherSnapshot = await index.snapshot(other.id);
    expect(otherSnapshot.reviewGroup, isNull);
  });

  test('空标签：三块都为空、missingTargets 为 0、isEmpty', () async {
    final tag = await seedTag('空标签');
    final snapshot = await index.snapshot(tag.id);
    expect(snapshot.questions, isEmpty);
    expect(snapshot.cards, isEmpty);
    expect(snapshot.tasks, isEmpty);
    expect(snapshot.knowledgePointCount, 0);
    expect(snapshot.missingTargets, 0);
    expect(snapshot.isEmpty, isTrue);
  });
}
