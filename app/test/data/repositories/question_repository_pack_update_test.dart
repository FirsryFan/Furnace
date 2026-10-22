/// 题库包再导入的数据层原语（轮次一百四十五）：
///  - `updateFromPack`：按包记录给已有题打补丁（空值不覆盖、选项整体替换、
///    标签只补不删、整个更新一个事务）；
///  - `questionIdsByZujuanQuestionId`：组卷网 qid → 本地题目 id 的确定性索引。
///
/// 这里钉的是「补什么、不动什么」的口径；把包解析成这些参数的接线由服务层做。
library;

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/question_repository.dart';
import 'package:furnace/data/repositories/tag_repository.dart';

void main() {
  late AppDatabase db;
  late QuestionRepository repo;
  late TagRepository tags;

  final t0 = DateTime.fromMillisecondsSinceEpoch(1700000000000);
  final t1 = DateTime.fromMillisecondsSinceEpoch(1700000005000);
  final t2 = DateTime.fromMillisecondsSinceEpoch(1700000010000);

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = QuestionRepository(db);
    tags = TagRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  Future<Question> seed(
    String stem, {
    DateTime? now,
    String? answer,
    String? solution,
    String? zujuanQuestionId,
    List<QuestionOptionDraft> options = const <QuestionOptionDraft>[],
    Set<String> tagIds = const <String>{},
  }) async =>
      (await repo.ingest(
        QuestionDraft(
          stem: stem,
          answer: answer,
          solution: solution,
          zujuanQuestionId: zujuanQuestionId,
          options: options,
          tagIds: tagIds,
        ),
        now: now ?? t0,
      ))
          .question;

  test('答案与解析：非空覆盖并 trim，null / 空串 / 全空白都不覆盖', () async {
    final row = await seed('补答案的题', answer: '旧答案', solution: '旧解析');

    expect(
      await repo.updateFromPack(
        questionId: row.id,
        stem: '补答案的题',
        answer: '  新答案  ',
        solution: '新解析',
        now: t1,
      ),
      1,
    );
    var latest = (await repo.byId(row.id))!;
    expect(latest.answer, '新答案');
    expect(latest.solution, '新解析');

    await repo.updateFromPack(
      questionId: row.id,
      stem: '补答案的题',
      answer: null,
      solution: '   ',
      now: t2,
    );
    latest = (await repo.byId(row.id))!;
    expect(latest.answer, '新答案', reason: 'null 不动');
    expect(latest.solution, '新解析', reason: '全空白不动');
  });

  test('题干总会覆盖（trim）并按新题干重算指纹', () async {
    final row = await seed('旧题干的甲乙丙');
    final oldFingerprint = row.stemFingerprint;

    expect(
      await repo.updateFromPack(
        questionId: row.id,
        stem: '  新题干的丁戊己  ',
        now: t1,
      ),
      1,
    );

    final latest = (await repo.byId(row.id))!;
    expect(latest.stem, '新题干的丁戊己');
    expect(latest.stemFingerprint, stemFingerprint('新题干的丁戊己'));
    expect(latest.stemFingerprint, isNot(oldFingerprint));
    expect(await repo.findByFingerprint(oldFingerprint), isNull);
    expect((await repo.findByFingerprint(latest.stemFingerprint))?.id, row.id);
  });

  test('题干 trim 空抛 ArgumentError，库不变', () async {
    final row = await seed('不能清空的题');
    await expectLater(
      repo.updateFromPack(questionId: row.id, stem: '   ', now: t1),
      throwsArgumentError,
    );
    final latest = (await repo.byId(row.id))!;
    expect(latest.stem, '不能清空的题');
    expect(latest.updatedAt, t0.millisecondsSinceEpoch);
  });

  test('选项非空：旧选项行整体删掉，按 sortOrder 读回新选项', () async {
    final row = await seed(
      '带选项的题',
      options: const [
        QuestionOptionDraft(label: 'A', content: '旧甲', isCorrect: true),
        QuestionOptionDraft(label: 'B', content: '旧乙', sortOrder: 1),
      ],
    );
    final oldOptions = await repo.optionsOf(row.id);
    expect(oldOptions, hasLength(2));

    await repo.updateFromPack(
      questionId: row.id,
      stem: '带选项的题',
      options: const [
        QuestionOptionDraft(
          label: 'C',
          content: '新丙',
          isCorrect: true,
          sortOrder: 2,
        ),
        QuestionOptionDraft(label: 'A', content: '新甲'),
      ],
      now: t1,
    );

    final options = await repo.optionsOf(row.id);
    expect(options.map((option) => option.label), ['A', 'C']);
    expect(options.map((option) => option.content), ['新甲', '新丙']);
    expect(options.map((option) => option.isCorrect), [false, true]);
    expect(options.map((option) => option.questionId).toSet(), {row.id});
    expect(
      options.map((option) => option.id).toSet(),
      isNot(containsAll(oldOptions.map((option) => option.id))),
      reason: '旧选项行是删掉重建，不是原地改内容',
    );
  });

  test('选项空列表：保留旧选项（包记录没带选项）', () async {
    final row = await seed(
      '选项要留着的题',
      options: const [
        QuestionOptionDraft(label: 'A', content: '甲', isCorrect: true),
        QuestionOptionDraft(label: 'B', content: '乙', sortOrder: 1),
      ],
    );
    final before = await repo.optionsOf(row.id);

    await repo.updateFromPack(
      questionId: row.id,
      stem: '选项要留着的题',
      now: t1,
    );

    final after = await repo.optionsOf(row.id);
    expect(after.map((option) => option.id), before.map((option) => option.id));
    expect(after.map((option) => option.content), ['甲', '乙']);
  });

  test('additionalTagIds 只补挂缺失的标签，不删已有标签，重复调用不重复挂', () async {
    final fn = await tags.createTag(name: '函数');
    final mono = await tags.createTag(name: '单调性');
    final row = await seed('补标签的题', tagIds: {fn.id});
    expect(await repo.tagIdsOf(row.id), [fn.id]);

    await repo.updateFromPack(
      questionId: row.id,
      stem: '补标签的题',
      additionalTagIds: {mono.id, '  ', mono.id},
      now: t1,
    );
    expect((await repo.tagIdsOf(row.id)).toSet(), {fn.id, mono.id});

    await repo.updateFromPack(
      questionId: row.id,
      stem: '补标签的题',
      additionalTagIds: {mono.id},
      now: t2,
    );
    expect(
      await repo.tagIdsOf(row.id),
      hasLength(2),
      reason: 'object_tags 有唯一键，insertOrIgnore 不重复挂',
    );
  });

  test('题名 / 题号 / createdAt 绝不覆盖，updatedAt 跟着 now 走', () async {
    final row = await seed('保护题名题号的题', now: t0);
    await repo.setQuestionTitle(row.id, '手写题名', now: t0);

    expect(
      await repo.updateFromPack(questionId: row.id, stem: '改过题干', now: t1),
      1,
    );

    final latest = (await repo.byId(row.id))!;
    expect(latest.title, '手写题名');
    expect(latest.serialNo, row.serialNo);
    expect(latest.createdAt, t0.millisecondsSinceEpoch);
    expect(latest.updatedAt, t1.millisecondsSinceEpoch);
  });

  test('题目不存在 / questionId 空白：返回 0，不抛也不建行', () async {
    expect(await repo.updateFromPack(questionId: 'q-nope', stem: '幽灵题'), 0);
    expect(await repo.updateFromPack(questionId: '   ', stem: '空白 id'), 0);
    expect(await db.select(db.questions).get(), isEmpty);
  });

  test('多字段同时更新：答案 / 来源 / 难度 / 组卷网 id / 加工状态', () async {
    final row = await seed('多字段一起改的题');

    expect(
      await repo.updateFromPack(
        questionId: row.id,
        stem: '多字段一起改的题',
        answer: '选 B',
        solution: '解析全文',
        subjectKey: 'physics',
        questionType: 'single_choice',
        sourceLevel: 'gaokao',
        sourceLabel: '2024 湖南师大附中月考',
        year: 2024,
        region: '湖南',
        sourceUrl: 'https://zujuan.xkw.com/10q35583902.html',
        zujuanQuestionId: '35583902',
        zujuanBankId: '10',
        difficulty: 7.5,
        difficultySource: 'manual',
        trapNote: '单位换算',
        origin: 'ai_scan',
        state: 'processed',
        now: t1,
      ),
      1,
    );

    final latest = (await repo.byId(row.id))!;
    expect(latest.answer, '选 B');
    expect(latest.solution, '解析全文');
    expect(latest.subjectKey, 'physics');
    expect(latest.questionType, 'single_choice');
    expect(latest.sourceLevel, 'gaokao');
    expect(latest.sourceLabel, '2024 湖南师大附中月考');
    expect(latest.year, 2024);
    expect(latest.region, '湖南');
    expect(latest.sourceUrl, 'https://zujuan.xkw.com/10q35583902.html');
    expect(latest.zujuanQuestionId, '35583902');
    expect(latest.zujuanBankId, '10');
    expect(latest.difficulty, 7.5);
    expect(latest.difficultySource, 'manual');
    expect(latest.trapNote, '单位换算');
    expect(latest.origin, 'ai_scan');
    expect(latest.state, 'processed');
    expect(latest.updatedAt, t1.millisecondsSinceEpoch);
  });

  test('非空列也守空值不覆盖：学科 / 题型 / 来源分级 / 来源说明 / origin / state', () async {
    final ingested = await repo.ingest(
      const QuestionDraft(
        stem: '非空列不许被空串冲掉',
        subjectKey: 'physics',
        questionType: 'single_choice',
        sourceLevel: 'gaokao',
        sourceLabel: '出处文字',
        origin: 'ai_scan',
        state: 'processed',
      ),
      now: t0,
    );

    await repo.updateFromPack(
      questionId: ingested.question.id,
      stem: '非空列不许被空串冲掉',
      subjectKey: '',
      questionType: '  ',
      sourceLevel: null,
      sourceLabel: '   ',
      origin: '',
      state: null,
      now: t1,
    );

    final latest = (await repo.byId(ingested.question.id))!;
    expect(latest.subjectKey, 'physics');
    expect(latest.questionType, 'single_choice');
    expect(latest.sourceLevel, 'gaokao');
    expect(latest.sourceLabel, '出处文字');
    expect(latest.origin, 'ai_scan');
    expect(latest.state, 'processed');
  });

  test('qid 索引：跳过空 qid，同一个 qid 取 updatedAt 最新的那一行', () async {
    final older = await seed('索引题甲', zujuanQuestionId: ' 35583902 ', now: t0);
    final newer = await seed('索引题乙', zujuanQuestionId: '35583902', now: t1);
    await seed('索引题丙');
    await seed('索引题丁', zujuanQuestionId: '   ', now: t2);

    var index = await repo.questionIdsByZujuanQuestionId();
    expect(index, {'35583902': newer.id});

    // 把旧那行的 updatedAt 顶到最新：索引跟着换行，key 仍然只有一条。
    await repo.updateFromPack(
      questionId: older.id,
      stem: '索引题甲',
      zujuanQuestionId: '35583902',
      now: t2,
    );
    index = await repo.questionIdsByZujuanQuestionId();
    expect(index, {'35583902': older.id});
  });

  test('qid 索引：同一 updatedAt 时按 id 升序取第一行', () async {
    final ms = t0.millisecondsSinceEpoch;
    for (final id in ['q-zzz', 'q-aaa']) {
      await db.into(db.questions).insert(
            QuestionsCompanion.insert(
              id: id,
              stem: '撞时间戳的 $id',
              zujuanQuestionId: const Value('42'),
              createdAt: ms,
              updatedAt: ms,
            ),
          );
    }

    expect(await repo.questionIdsByZujuanQuestionId(), {'42': 'q-aaa'});
  });
}
