import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/question_repository.dart';

/// 题库仓储的三条不变量（`docs/QUESTION_BANK_DESIGN.md` §1/§2）：
///
///  * **只追加**：题干入库后不被加工改写，加工只碰加工列；
///  * **同题不漏两次**：指纹挡住排版的差异，同指纹入库返回既有题目；
///  * **排序是"先给谁"**：来源分级 > AI 质量 > 时间 > id，低价值题只压后不删。
void main() {
  late AppDatabase db;
  late QuestionRepository repo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = QuestionRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> seedTag(String id) => db.into(db.tags).insert(
        TagsCompanion.insert(
          id: id,
          name: id,
          createdAt: 1700000000000,
          updatedAt: 1700000000000,
        ),
      );

  test('题干指纹忽略空白与标点，同题不会入库两次', () async {
    final first = await repo.ingest(
      const QuestionDraft(stem: '求 f(x)=x²+1 的最小值。'),
    );
    final second = await repo.ingest(
      const QuestionDraft(stem: ' 求f(x) = x² + 1 的最小值 '),
    );

    expect(first.created, isTrue);
    expect(second.created, isFalse, reason: '同一道题排版不同不该再进一条');
    expect(second.question.id, first.question.id);
    expect(await repo.all(), hasLength(1));
  });

  test('题干为空当场拒绝', () async {
    expect(
      () => repo.ingest(const QuestionDraft(stem: '   ')),
      throwsArgumentError,
    );
  });

  test('选项与标签边原样回来，加工不改题干', () async {
    await seedTag('t1');
    final ingested = await repo.ingest(
      const QuestionDraft(
        stem: '光合作用的场所是（  ）',
        answer: '叶绿体',
        options: [
          QuestionOptionDraft(label: 'A', content: '线粒体'),
          QuestionOptionDraft(label: 'B', content: '叶绿体', isCorrect: true),
        ],
        tagIds: {'t1'},
      ),
    );

    expect(await repo.optionsOf(ingested.question.id), hasLength(2));
    expect(await repo.tagIdsOf(ingested.question.id), ['t1']);

    await repo.updateProcessing(
      ingested.question.id,
      state: 'processed',
      trapNote: '把"场所"读成"能量转换"',
      difficulty: 4.5,
      difficultySource: 'prior',
      aiQuality: 0.8,
    );

    final after = (await repo.byId(ingested.question.id))!;
    expect(after.stem, ingested.question.stem, reason: '题干是只追加的');
    expect(after.state, 'processed');
    expect(after.trapNote, '把"场所"读成"能量转换"');
    expect(after.difficulty, 4.5);
    expect(after.difficultySource, 'prior');
    expect(after.aiQuality, 0.8);
    expect(after.updatedAt, greaterThanOrEqualTo(after.createdAt));
  });

  test('来源元信息事后能改：只动那四列，题干/答案/加工列一个字不动', () async {
    final ingested = await repo.ingest(
      const QuestionDraft(
        stem: '已知 x^2-5x+6=0，求两根之和。',
        answer: '5',
        solution: '韦达定理',
        sourceLevel: 'unknown',
        questionType: 'solution',
      ),
    );
    await repo.updateProcessing(
      ingested.question.id,
      state: 'processed',
      trapNote: '把系数看错',
      difficulty: 3,
    );
    final before = (await repo.byId(ingested.question.id))!;

    await repo.updateSource(
      ingested.question.id,
      sourceLevel: 'gaokao',
      sourceLabel: '2024 湖南师大附中月考',
      year: 2024,
      region: '湖南',
    );

    final after = (await repo.byId(ingested.question.id))!;
    expect(after.sourceLevel, 'gaokao');
    expect(after.sourceLabel, '2024 湖南师大附中月考');
    expect(after.year, 2024);
    expect(after.region, '湖南');
    // 题干 / 答案 / 解析 / 加工列都不归这个口子管。
    expect(after.stem, before.stem);
    expect(after.answer, before.answer);
    expect(after.solution, before.solution);
    expect(after.state, before.state);
    expect(after.trapNote, before.trapNote);
    expect(after.difficulty, before.difficulty);
    expect(after.updatedAt, greaterThanOrEqualTo(before.updatedAt));
  });

  test('来源分级只认词表里的值：写错当场拒绝，不改任何一列', () async {
    final ingested = await repo.ingest(
      const QuestionDraft(stem: '来源分级写错的题', sourceLevel: 'school'),
    );

    await expectLater(
      repo.updateSource(ingested.question.id, sourceLevel: 'gaokao_2024'),
      throwsA(
        isA<ArgumentError>().having(
          (error) => error.message,
          'message',
          allOf(contains('未知的来源分级'), contains('gaokao')),
        ),
      ),
    );
    expect((await repo.byId(ingested.question.id))!.sourceLevel, 'school');
  });

  test('只改来源分级时，来源说明/年份/地区保持原样', () async {
    final ingested = await repo.ingest(
      const QuestionDraft(
        stem: '只改分级',
        sourceLabel: '某校月考',
        year: 2023,
        region: '湖北',
      ),
    );

    await repo.updateSource(ingested.question.id, sourceLevel: 'elite_school');

    final after = (await repo.byId(ingested.question.id))!;
    expect(after.sourceLevel, 'elite_school');
    expect(after.sourceLabel, '某校月考');
    expect(after.year, 2023);
    expect(after.region, '湖北');
  });

  test('检索按来源分级与质量排序，低价值题只是压后', () async {
    // 时间顺序刻意反过来：自建题最新，但这不该让它排第一。
    await repo.ingest(
      const QuestionDraft(stem: '自建题', sourceLevel: 'personal'),
      now: DateTime.fromMillisecondsSinceEpoch(4000),
    );
    await repo.ingest(
      const QuestionDraft(
        stem: '高考真题',
        sourceLevel: 'gaokao',
        aiQuality: 0.4,
      ),
      now: DateTime.fromMillisecondsSinceEpoch(1000),
    );
    await repo.ingest(
      const QuestionDraft(
        stem: '名校题低分',
        sourceLevel: 'elite_school',
        aiQuality: 0.2,
      ),
      now: DateTime.fromMillisecondsSinceEpoch(2000),
    );
    await repo.ingest(
      const QuestionDraft(
        stem: '名校题高分',
        sourceLevel: 'elite_school',
        aiQuality: 0.9,
      ),
      now: DateTime.fromMillisecondsSinceEpoch(3000),
    );

    final ordered = await repo.search();
    expect(
      ordered.map((q) => q.stem).toList(),
      ['高考真题', '名校题高分', '名校题低分', '自建题'],
    );
    expect(ordered, hasLength(4), reason: '低分题不删，只在后面');
  });

  test('检索支持标签、来源、状态、题目子串与分页', () async {
    await seedTag('t1');
    await seedTag('t2');
    await repo.ingest(
      const QuestionDraft(
        stem: '带电粒子在磁场中运动',
        subjectKey: 'physics',
        sourceLevel: 'gaokao',
        tagIds: {'t1'},
      ),
    );
    await repo.ingest(
      const QuestionDraft(
        stem: '文言实词解释',
        subjectKey: 'chinese',
        sourceLevel: 'school',
        tagIds: {'t2'},
      ),
    );

    expect(
      (await repo.search(tagIds: {'t1'})).map((q) => q.subjectKey),
      ['physics'],
    );
    expect(await repo.search(tagIds: const {}), isEmpty);
    expect(await repo.search(sourceLevels: {'school'}), hasLength(1));
    expect(await repo.search(states: {'raw'}), isEmpty,
        reason: '默认入库状态是 structured');
    expect(await repo.search(stemContains: '磁场'), hasLength(1));
    expect(await repo.search(stemContains: '%'), isEmpty,
        reason: '百分号要被转义，不能当成通配符');
    expect(await repo.search(limit: 1), hasLength(1));
    expect(await repo.search(offset: 2), isEmpty);
  });

  test('删题目会显式清掉选项、标签边、推理链与步骤', () async {
    await seedTag('t1');
    final ingested = await repo.ingest(
      const QuestionDraft(stem: '要删的题', tagIds: {'t1'}),
    );
    final id = ingested.question.id;
    final chainId = await repo.saveChain(
      id,
      const ReasoningChainDraft(
        steps: [ReasoningStepDraft(goal: '第一步')],
      ),
    );

    await repo.deleteQuestion(id);

    expect(await repo.byId(id), isNull);
    expect(await repo.optionsOf(id), isEmpty);
    expect(await repo.tagIdsOf(id), isEmpty);
    expect(await repo.chainsOf(id), isEmpty);
    expect(await repo.stepsOf(chainId), isEmpty);
    // 标签本身不能被连带删掉。
    expect(await db.select(db.tags).get(), hasLength(1));
  });

  test('一条链的步骤按 idx 顺序回来，stepCount 与 stuckRisk 都被收拾过', () async {
    final ingested = await repo.ingest(const QuestionDraft(stem: '多步推导题'));
    final id = ingested.question.id;
    final chainId = await repo.saveChain(
      id,
      const ReasoningChainDraft(
        summary: '先建模再消元',
        steps: [
          ReasoningStepDraft(goal: '建模', actionType: 'modeling'),
          ReasoningStepDraft(
            goal: '消元',
            actionType: 'elimination',
            stuckRisk: -0.3,
            knowledgeHints: ['kp1'],
          ),
          ReasoningStepDraft(goal: '回代检验', actionType: 'substitution_check'),
        ],
      ),
    );

    final chains = await repo.chainsOf(id);
    expect(chains.single.stepCount, 3);
    final steps = await repo.stepsOf(chainId);
    expect(steps.map((s) => s.idx), [0, 1, 2]);
    expect(steps.map((s) => s.goal), ['建模', '消元', '回代检验']);
    expect(steps[1].stuckRisk, 0.0, reason: 'stuckRisk 负值钳到 0');
    expect(steps[1].knowledgeHints, '["kp1"]');
    expect((await repo.byId(id))!.state, 'processed');
  });

  test('题目编号：入库依次 1、2；重复入库不占新号；删题后高水位不让旧号被接手', () async {
    final first = await repo.ingest(const QuestionDraft(stem: '编号测试一'));
    final second = await repo.ingest(const QuestionDraft(stem: '编号测试二'));
    expect(first.question.serialNo, 1);
    expect(second.question.serialNo, 2);

    // 同指纹再入库：返回既有题，号码不动（去重发生在分配之前）。
    final again = await repo.ingest(const QuestionDraft(stem: '编号测试一'));
    expect(again.created, isFalse);
    expect(again.question.serialNo, 1);

    // v33（轮次一百六十三）起，高水位表记着这个库发出去过的最大号：删掉最大号
    // 那题之后，下一道题拿 3——旧号 2 不会被接手（§11「发出即永久保留」）。
    await repo.deleteQuestion(second.question.id);
    final third = await repo.ingest(const QuestionDraft(stem: '编号测试三'));
    expect(third.question.serialNo, 3);
    expect(second.question.serialNo, 2);
  });

  test('老库没有高水位行：第一次 ingest 按现存最大号 + 1，之后由高水位接手', () async {
    final first = await repo.ingest(const QuestionDraft(stem: '高水位一'));
    final second = await repo.ingest(const QuestionDraft(stem: '高水位二'));
    expect(first.question.serialNo, 1);
    expect(second.question.serialNo, 2);

    // 模拟刚迁移完的 v32 老库：高水位表还是空的（历史发放号无从回填）。
    await db.delete(db.questionSerialCounters).go();
    final third = await repo.ingest(const QuestionDraft(stem: '高水位三'));
    expect(third.question.serialNo, 3, reason: '没有高水位时退回现存最大 + 1');

    final counter = await db.select(db.questionSerialCounters).getSingle();
    expect(counter.lastIssued, 3, reason: '这次分配把高水位写进去');

    // 从此以后就只走高水位：删掉最大号也不会倒回去。
    await repo.deleteQuestion(third.question.id);
    final fourth = await repo.ingest(const QuestionDraft(stem: '高水位四'));
    expect(fourth.question.serialNo, 4);
  });

  test('同时入库多道题：编号互不重复，高水位落在最后一号', () async {
    final results =
        await Future.wait(<Future<({Question question, bool created})>>[
      for (var i = 0; i < 6; i++) repo.ingest(QuestionDraft(stem: '并发编号 $i')),
    ]);
    final serials = results.map((r) => r.question.serialNo).toList();
    expect(serials.toSet(), hasLength(6), reason: '并发入库不能撞号');
    expect(serials.toSet(), <int>{1, 2, 3, 4, 5, 6});

    final counter = await db.select(db.questionSerialCounters).getSingle();
    expect(counter.lastIssued, 6);
  });

  test('包导入后的补号把高水位抬到现存最大号：删掉带号题也不会被接手', () async {
    final ingested = await repo.ingest(const QuestionDraft(stem: '模拟带号导入'));
    // v24 包自带号，restoreTable 直接写 serial_no——这里用 UPDATE 模拟。
    await db.customStatement(
      'UPDATE questions SET serial_no = 50 WHERE id = ?',
      [ingested.question.id],
    );
    await db.backfillQuestionSerialNumbers();

    // 补号之后还没入库过就先删掉这道题：没有抬水位的话下一题会拿 1。
    await repo.deleteQuestion(ingested.question.id);
    final next = await repo.ingest(const QuestionDraft(stem: '导入后新题'));
    expect(next.question.serialNo, 51);

    final counter = await db.select(db.questionSerialCounters).getSingle();
    expect(counter.lastIssued, 51);
  });

  test('按题号检索：findBySerialNo 精确命中，0、负数与不存在的号返回 null', () async {
    final first = await repo.ingest(const QuestionDraft(stem: '按号识别一'));
    final second = await repo.ingest(const QuestionDraft(stem: '按号识别二'));

    final found = await repo.findBySerialNo(2);
    expect(found, isNotNull);
    expect(found!.id, second.question.id);
    expect(found.stem, '按号识别二');
    expect((await repo.findBySerialNo(1))!.id, first.question.id);

    // 号从 1 开始（v24 题号规则），0 与负数不做注定查不到的查询。
    expect(await repo.findBySerialNo(0), isNull);
    expect(await repo.findBySerialNo(-1), isNull);
    expect(await repo.findBySerialNo(999), isNull);
  });

  test('search(serialNos:) 按组过滤；空集没有命中；null 不过滤', () async {
    final first = await repo.ingest(const QuestionDraft(stem: '过滤题一'));
    final second = await repo.ingest(const QuestionDraft(stem: '过滤题二'));
    final third = await repo.ingest(const QuestionDraft(stem: '过滤题三'));

    final picked = await repo.search(serialNos: <int>{1, 3});
    expect(picked.map((q) => q.serialNo).toSet(), <int>{1, 3});
    expect(
      picked.map((q) => q.id).toSet(),
      <String>{first.question.id, third.question.id},
    );

    // 空集与 tagIds 空集同一语义：用户明确要一组号，而这组号是空的。
    expect(await repo.search(serialNos: <int>{}), isEmpty);

    final all = await repo.search(serialNos: null);
    expect(all, hasLength(3));
    expect(all.map((q) => q.serialNo).toSet(), <int>{1, 2, 3});

    // 与题干过滤相与（组内还要匹配题干）。
    final both = await repo.search(
      serialNos: <int>{1, 2},
      stemContains: '过滤题二',
    );
    expect(both.single.id, second.question.id);
  });
}
