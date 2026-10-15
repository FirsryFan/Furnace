import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/app_database_provider.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/anki_repository.dart';
import 'package:furnace/data/repositories/question_repository.dart';
import 'package:furnace/data/repositories/tag_repository.dart';
import 'package:furnace/features/questions/application/similar_question_provider.dart';

/// 找相似题（Q12）应用层的验收点：
///
///  * 题目与知识点**共享标签**才相连，题目自己的相似候选据此打分；
///  * 库里已有的思维链是**动作同型**那条信号的来源（没链 = 没信号，不冒充）；
///  * 一道题有多条链时只认最新那条（旧链不参与打分）；
///  * 自己不跟自己配；
///  * 题干为空的题不进候选，但仍能作为"基准题"问相似（回落读题目行）；
///  * 题库里真没有相似题时返回空列表——不凑数、不出题。
void main() {
  late AppDatabase db;
  late QuestionRepository questions;
  late TagRepository tags;
  late AnkiRepository anki;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    questions = QuestionRepository(db);
    tags = TagRepository(db);
    anki = AnkiRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  ProviderContainer container() {
    final container = ProviderContainer(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
    );
    addTearDown(container.dispose);
    return container;
  }

  Future<String> seedQuestion({
    required String stem,
    String subjectKey = '数学',
    String sourceLevel = 'gaokao',
    double? difficulty,
  }) async {
    final ingested = await questions.ingest(
      QuestionDraft(
        stem: stem,
        subjectKey: subjectKey,
        sourceLevel: sourceLevel,
        difficulty: difficulty,
      ),
    );
    return ingested.question.id;
  }

  Future<String> seedKnowledgePoint(String title) async =>
      (await anki.createKnowledgePoint(title: title, content: '')).id;

  /// 题目覆盖知识点的方式：两者挂**同一个**标签（`TaskKnowledgePointResolver` 的规则）。
  Future<void> link({
    required String questionId,
    required String pointId,
    required String tagName,
  }) async {
    final tagId = (await tags.createTag(name: tagName)).id;
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
  }

  /// 给一道题存一条思维链（`actionTypes` 按 idx 顺序写成步骤）。
  Future<void> seedChain({
    required String questionId,
    required List<String> actionTypes,
    DateTime? now,
  }) async {
    await questions.saveChain(
      questionId,
      ReasoningChainDraft(
        model: 'test-model',
        summary: '测试链',
        steps: [
          for (var index = 0; index < actionTypes.length; index++)
            ReasoningStepDraft(
              goal: '第 ${index + 1} 步',
              actionType: actionTypes[index],
            ),
        ],
      ),
      now: now,
    );
  }

  test('共享知识点 + 同型动作序列 → 相似的题入榜，理由讲同型步骤', () async {
    final pointId = await seedKnowledgePoint('动量守恒');
    final focusId = await seedQuestion(stem: '碰撞后两球速度各是多少？');
    final similarId = await seedQuestion(stem: '另一道动量题。');
    final strangerId = await seedQuestion(stem: '完全无关的题。', subjectKey: '语文');
    await link(questionId: focusId, pointId: pointId, tagName: '力学');
    await link(questionId: similarId, pointId: pointId, tagName: '力学');

    await seedChain(
      questionId: focusId,
      actionTypes: ['first_principles', 'sanity_check'],
    );
    await seedChain(
      questionId: similarId,
      actionTypes: ['first_principles', 'sanity_check'],
    );

    final ranked =
        await container().read(similarQuestionsProvider(focusId).future);

    expect(ranked.map((r) => r.questionId).toList(), [similarId]);
    expect(ranked.single.sharedKnowledgePointIds, [pointId]);
    expect(
        ranked.single.sharedActionTypes, ['first_principles', 'sanity_check']);
    expect(ranked.single.reasonZh, contains('同型步骤'));
    expect(ranked.single.reasonZh, isNot(contains(strangerId)));
  });

  test('跨学科但动作同型 → 标成迁移候选', () async {
    final focusId = await seedQuestion(stem: '求最值。');
    final crossId = await seedQuestion(stem: '语文阅读里的论证结构。', subjectKey: '语文');
    await seedChain(
      questionId: focusId,
      actionTypes: ['first_principles', 'invariant_recognition'],
    );
    await seedChain(
      questionId: crossId,
      actionTypes: ['first_principles', 'invariant_recognition'],
    );

    final ranked =
        await container().read(similarQuestionsProvider(focusId).future);

    expect(ranked.single.questionId, crossId);
    expect(ranked.single.crossSubjectTransfer, isTrue);
    expect(ranked.single.reasonZh, contains('跨学科迁移'));
  });

  test('库里没有链时只用结构信号：共享知识点仍然能找到相似题', () async {
    final pointId = await seedKnowledgePoint('电磁感应');
    final focusId = await seedQuestion(stem: '感应电动势多大？');
    final similarId = await seedQuestion(stem: '另一道电磁感应题。');
    await link(questionId: focusId, pointId: pointId, tagName: '电磁学');
    await link(questionId: similarId, pointId: pointId, tagName: '电磁学');

    final ranked =
        await container().read(similarQuestionsProvider(focusId).future);

    expect(ranked.single.questionId, similarId);
    expect(ranked.single.sharedActionTypes, isEmpty);
    expect(ranked.single.reasonZh, isNot(contains('同型步骤')));
  });

  test('一道题有多条链时只认最新那条', () async {
    final pointId = await seedKnowledgePoint('数列');
    final focusId = await seedQuestion(stem: '求通项公式。');
    final inductionId = await seedQuestion(stem: '归纳法那道。');
    final extremeId = await seedQuestion(stem: '取极值那道。');
    await link(questionId: focusId, pointId: pointId, tagName: '数列');
    await link(questionId: inductionId, pointId: pointId, tagName: '数列');
    await link(questionId: extremeId, pointId: pointId, tagName: '数列');

    // 旧链讲归纳，新链讲极端情形——只有新链算数。
    await seedChain(
      questionId: focusId,
      actionTypes: ['induction'],
      now: DateTime(2026, 1, 1),
    );
    await seedChain(
      questionId: focusId,
      actionTypes: ['extreme_case'],
      now: DateTime(2026, 1, 2),
    );
    await seedChain(
      questionId: inductionId,
      actionTypes: ['induction'],
      now: DateTime(2026, 1, 1),
    );
    await seedChain(
      questionId: extremeId,
      actionTypes: ['extreme_case'],
      now: DateTime(2026, 1, 1),
    );

    final ranked =
        await container().read(similarQuestionsProvider(focusId).future);
    final byId = {for (final r in ranked) r.questionId: r};

    // 两道都共享同一个知识点（结构信号一样），差别只在动作序列。
    expect(byId.keys, containsAll([inductionId, extremeId]));
    expect(byId[extremeId]!.sharedActionTypes, ['extreme_case']);
    expect(byId[inductionId]!.sharedActionTypes, isEmpty);
    expect(
      byId[extremeId]!.score,
      greaterThan(byId[inductionId]!.score),
    );
    expect(ranked.first.questionId, extremeId);
  });

  test('题干为空的题不进候选，但仍能作为基准题问相似（回落读题目行）', () async {
    final pointId = await seedKnowledgePoint('概率');
    // 题干为空的题**进不来** `QuestionRepository.ingest`（它直接抛 ArgumentError），
    // 所以这里模拟另一条通路（导入/同步）写进来的脏行：题库快照要跳过它。
    const blankId = 'q-blank';
    final blankAt = DateTime(2026, 1, 1).millisecondsSinceEpoch;
    await db.into(db.questions).insert(
          QuestionsCompanion.insert(
            id: blankId,
            stem: '   ',
            subjectKey: const Value('数学'),
            sourceLevel: const Value('gaokao'),
            createdAt: blankAt,
            updatedAt: blankAt,
          ),
        );
    final otherId = await seedQuestion(stem: '另一道概率题。');
    await link(questionId: blankId, pointId: pointId, tagName: '概率');
    await link(questionId: otherId, pointId: pointId, tagName: '概率');
    await seedChain(questionId: blankId, actionTypes: ['case_split']);

    final provider = container();
    final candidates = await provider.read(similarCandidatesProvider.future);
    expect(candidates.map((c) => c.questionId), isNot(contains(blankId)));

    final focus =
        await provider.read(similarQuestionFocusProvider(blankId).future);
    expect(focus, isNotNull);
    expect(focus!.actionTypes, ['case_split']);
    expect(focus.knowledgePointIds, isEmpty);
  });

  test('不与自己配对；库里没有相似题时返回空列表；不存在的题也是空列表', () async {
    final lonelyId = await seedQuestion(stem: '库里唯一一道题。');

    final provider = container();
    expect(
      await provider.read(similarQuestionsProvider(lonelyId).future),
      isEmpty,
    );
    expect(
      await provider.read(similarQuestionsProvider('q-does-not-exist').future),
      isEmpty,
    );
  });
}
