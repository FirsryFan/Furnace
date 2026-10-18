import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/app_database_provider.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/anki_repository.dart';
import 'package:furnace/data/repositories/assessment_repository.dart';
import 'package:furnace/data/repositories/question_repository.dart';
import 'package:furnace/data/repositories/tag_repository.dart';
import 'package:furnace/domain/services/cognitive/fast_diagnosis.dart';
import 'package:furnace/domain/services/cognitive/library_diagnosis.dart';
import 'package:furnace/domain/services/paper/domain_quota.dart';
import 'package:furnace/domain/services/paper/paper_composer.dart';
import 'package:furnace/domain/services/paper/subject_quota.dart';
import 'package:furnace/domain/services/scheduling/cognitive_readings.dart';
import 'package:furnace/features/cognitive/presentation/cognitive_model_page.dart'
    show cognitiveLibraryDiagnosisProvider;
import 'package:furnace/features/questions/application/paper_plan_provider.dart';

/// 组卷 provider（Q9 的接线，`docs/PAPER_COMPOSER_DESIGN.md`）的验收点：
///
///  * 题库 → 候选（题干为空的题不进来）；
///  * 题目与知识点**共享标签**才相连，危险区的题因此排上来，理由行念名字；
///  * 诊断"这轮没跑"是**未知**，不是健康；
///  * **只有测评先验、没有诊断结论**的点不进打分读数（先验 ≠ 观测）；
///  * 组卷要求（学科/题量/来源下限/难度）改一个数，卷子真的跟着变。
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

  ProviderContainer containerWith(LibraryDiagnosis diagnosis) {
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        cognitiveLibraryDiagnosisProvider
            .overrideWith((ref) async => diagnosis),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  Future<String> seedQuestion({
    required String stem,
    String subjectKey = '数学',
    String sourceLevel = 'gaokao',
    double? difficulty,
    double? aiQuality,
  }) async {
    final ingested = await questions.ingest(
      QuestionDraft(
        stem: stem,
        subjectKey: subjectKey,
        sourceLevel: sourceLevel,
        difficulty: difficulty,
        aiQuality: aiQuality,
      ),
    );
    return ingested.question.id;
  }

  Future<String> seedKnowledgePoint(String title) async =>
      (await anki.createKnowledgePoint(title: title, content: '')).id;

  /// 给一道题落一条链：`steps` 是 (action, stuckRisk) 序列，用于能力动作画像。
  Future<void> seedChain({
    required String questionId,
    required List<({String action, double? risk})> steps,
  }) async {
    await db.into(db.reasoningChains).insert(
          ReasoningChainsCompanion.insert(
            id: 'chain-$questionId',
            questionId: questionId,
            createdAt: 1,
            summary: const Value(''),
            stepCount: Value(steps.length),
          ),
        );
    for (var i = 0; i < steps.length; i++) {
      await db.into(db.reasoningSteps).insert(
            ReasoningStepsCompanion.insert(
              id: 'step-$questionId-$i',
              chainId: 'chain-$questionId',
              idx: i,
              goal: '第 $i 步',
              actionType: Value(steps[i].action),
              stuckRisk: Value(steps[i].risk),
              createdAt: 1,
            ),
          );
    }
  }

  /// 题目覆盖某个知识点的方式：两者挂**同一个**标签。
  Future<void> link({
    required String tagId,
    required String pointId,
    String? questionId,
  }) async {
    await tags.addTagToObject(
      tagId: tagId,
      objectType: 'knowledge_point',
      objectId: pointId,
    );
    if (questionId != null) {
      await tags.addTagToObject(
        tagId: tagId,
        objectType: 'question',
        objectId: questionId,
      );
    }
  }

  LibraryDiagnosis ran(Map<String, BottleneckType> verdicts) =>
      LibraryDiagnosis(byKnowledgePoint: verdicts, fastLayerRan: true);

  test('能力动作画像 → 组卷：命中"我最该练的动作"的题排前面，理由行说出来', () async {
    final tagId = (await tags.createTag(name: '概率')).id;
    final pointId = await seedKnowledgePoint('条件概率');
    // 两道条件相同的题（同一知识点、同一来源分级、都没难度/质量分），
    // 差别只在"有没有解题链、链里是什么动作"。
    final withChain = await seedQuestion(stem: '有链的那道题：抽取两次。');
    final withoutChain = await seedQuestion(stem: '没链的那道题：抽取两次。');
    await link(tagId: tagId, pointId: pointId, questionId: withChain);
    await link(tagId: tagId, pointId: pointId, questionId: withoutChain);
    // 画像只认"平均风险过线"的动作：这里分类讨论 0.9，明显该练。
    await seedChain(
      questionId: withChain,
      steps: <({String action, double? risk})>[
        (action: 'case_split', risk: 0.9),
        (action: 'case_split', risk: 0.8),
      ],
    );

    final container = containerWith(ran({pointId: BottleneckType.danger}));
    final plan = await container.read(paperPlanProvider.future);

    expect(plan.items, hasLength(2), reason: '两道题都进卷，只是次序不同');
    final first = plan.items.first;
    expect(first.questionId, withChain);
    expect(first.matchedPreferredActions, <String>['case_split']);
    expect(first.reasonZh, contains('分类讨论'), reason: '动作说人话，不摆 key');
    expect(first.reasonZh, contains('能力动作画像'));
    expect(first.toJson()['matched_preferred_actions'], <String>['case_split']);
    // 没链的那道题照旧进卷，不因为"没解过"被排除；它只是没有命中项。
    final second = plan.items[1];
    expect(second.questionId, withoutChain);
    expect(second.matchedPreferredActions, isEmpty);
    expect(second.reasonZh, isNot(contains('能力动作画像')));
  });

  test('关掉能力动作偏好：加成消失，卷子与"没有画像"逐项一致', () async {
    final tagId = (await tags.createTag(name: '统计')).id;
    final pointId = await seedKnowledgePoint('抽样分布');
    // 按 id 兜底时 q-a 在前；有链的是 q-b —— 只有加成能把 q-b 推到前面。
    final withoutChain = await seedQuestion(stem: 'a 没链的题', subjectKey: '数学');
    final withChain = await seedQuestion(stem: 'b 有链的题', subjectKey: '数学');
    await link(tagId: tagId, pointId: pointId, questionId: withoutChain);
    await link(tagId: tagId, pointId: pointId, questionId: withChain);
    await seedChain(
      questionId: withChain,
      steps: <({String action, double? risk})>[
        (action: 'case_split', risk: 0.9),
      ],
    );

    final container = containerWith(ran({pointId: BottleneckType.danger}));
    container
        .read(paperSpecProvider.notifier)
        .setPreferCapabilityActions(false);
    final plan = await container.read(paperPlanProvider.future);

    expect(plan.preferredActionTypes, isEmpty);
    expect(
      plan.items.map((item) => item.questionId).toSet(),
      <String>{withoutChain, withChain},
      reason: '两道题都进卷，只是不再按动作偏好排序',
    );
    expect(
      plan.items.every((item) => item.matchedPreferredActions.isEmpty),
      isTrue,
    );
    expect(
      plan.items.every((item) => !item.reasonZh.contains('能力动作画像')),
      isTrue,
    );
  });

  test('题库为空：给出空卷，不抛异常', () async {
    final container = containerWith(LibraryDiagnosis.notRun);
    final plan = await container.read(paperPlanProvider.future);

    expect(plan.items, isEmpty);
    expect(plan.candidateCount, 0);
    expect(plan.requestedCount, 10);
    expect(plan.overallNeed, 0.0);
  });

  test('题目与知识点共享标签 → 危险区的题进卷，理由行念名字而不是 id', () async {
    final tagId = (await tags.createTag(name: '函数')).id;
    final pointId = await seedKnowledgePoint('二次函数最值');
    final questionId =
        await seedQuestion(stem: '求 f(x)=x²-2x+3 在 [0,3] 上的最小值。');
    await link(tagId: tagId, pointId: pointId, questionId: questionId);

    final container = containerWith(ran({pointId: BottleneckType.danger}));
    final plan = await container.read(paperPlanProvider.future);

    final item = plan.items.single;
    expect(item.questionId, questionId);
    expect(item.knowledgePointId, pointId);
    expect(item.matchedKnowledgePointIds, [pointId]);
    expect(item.zone, PaperZone.danger);
    expect(item.need, closeTo(kDangerNeed, 1e-9));
    expect(item.reasonZh, contains('函数'));
    expect(item.reasonZh, contains('危险区'));
    expect(item.reasonZh, isNot(contains('kp-')));
    expect(item.improvementNote, isNotEmpty);
    expect(item.backgroundZh, contains('函数'));
    expect(plan.uncoveredKnowledgePointIds, isEmpty);
  });

  test('诊断这轮没跑：全部按未知，不冒充健康', () async {
    final tagId = (await tags.createTag(name: '数列')).id;
    final pointId = await seedKnowledgePoint('数列通项');
    final questionId = await seedQuestion(stem: '求等差数列通项。');
    await link(tagId: tagId, pointId: pointId, questionId: questionId);

    final container = containerWith(LibraryDiagnosis.notRun);
    final plan = await container.read(paperPlanProvider.future);

    final item = plan.items.single;
    expect(item.zone, PaperZone.unknown);
    expect(item.need, closeTo(kUnknownNeed, 1e-9));
    expect(item.reasonZh, contains('按未知处理'));
    expect(plan.overallNeed, closeTo(kUnknownNeed, 1e-9));
  });

  test('没挂知识点的题也进卷，理由行说清楚它没挂点', () async {
    final orphan = await seedQuestion(stem: '一道还没挂知识点的高考题。');
    final container = containerWith(LibraryDiagnosis.notRun);
    final plan = await container.read(paperPlanProvider.future);

    final item = plan.items.single;
    expect(item.questionId, orphan);
    expect(item.knowledgePointId, isNull);
    expect(item.zone, PaperZone.unknown);
    expect(item.reasonZh, contains('还没有挂知识点'));
  });

  test('只有测评先验、没有诊断结论的点不当作健康（先验 ≠ 观测）', () async {
    final tagId = (await tags.createTag(name: '三角')).id;
    final pointId = await seedKnowledgePoint('正弦定理');
    final questionId = await seedQuestion(stem: '用正弦定理解三角形。');
    await link(tagId: tagId, pointId: pointId, questionId: questionId);
    await db.into(db.cognitivePriors).insert(
          CognitivePriorsCompanion.insert(
            knowledgePointId: pointId,
            source: 'assessment:self',
            r0: 0.35,
            n: const Value(3),
            createdAt: DateTime.now().millisecondsSinceEpoch,
          ),
        );

    final container = containerWith(ran(const <String, BottleneckType>{}));
    final plan = await container.read(paperPlanProvider.future);

    final item = plan.items.single;
    expect(item.zone, PaperZone.unknown);
    expect(item.need, closeTo(kUnknownNeed, 1e-9));
    expect(item.reasonZh, isNot(contains('R0≈')));

    // 对照（这就是必须过滤的原因）：适配器**确实**为"只有先验"的点产出了读数，
    // 而组卷器把"不是危险区、也不是发展区"读成健康（need 0.15，**低于**未知的
    // 0.35）。provider 不过滤的话，"没测过"就会被当成"学得好"。
    final priors = await AssessmentRepository(db).priorEstimatesFor([pointId]);
    final reading = CognitiveReadingsAdapter.readingsFor(
      knowledgePointIds: [pointId],
      diagnosisByKnowledgePoint: const <String, BottleneckType>{},
      priors: priors,
    ).single;
    expect(paperZoneOf(reading), PaperZone.healthy);
  });

  test('学科筛选、题量、来源下限都真的进卷', () async {
    final mathA = await seedQuestion(stem: '数学题 A');
    await seedQuestion(stem: '数学题 B', sourceLevel: 'personal');
    final chinese = await seedQuestion(
      stem: '语文题',
      subjectKey: '语文',
      sourceLevel: 'personal',
    );

    final container = containerWith(LibraryDiagnosis.notRun);
    final spec = container.read(paperSpecProvider.notifier);

    // 默认：不限学科、10 题 → 三题都是候选。
    var plan = await container.read(paperPlanProvider.future);
    expect(plan.candidateCount, 3);
    expect(plan.requestedCount, 10);

    spec.toggleSubject('语文');
    plan = await container.read(paperPlanProvider.future);
    expect(plan.candidateCount, 1);
    expect(plan.items.single.questionId, chinese);

    spec.clearSubjects();
    spec.setMinSourceLevel('gaokao');
    plan = await container.read(paperPlanProvider.future);
    // 来源下限挡掉两道人分题（`personal` 的优先级低于 `gaokao`）。
    expect(plan.candidateCount, 1);
    expect(plan.items.single.questionId, mathA);

    spec.setMinSourceLevel(null);
    spec.setTargetCount(1);
    plan = await container.read(paperPlanProvider.future);
    expect(plan.requestedCount, 1);
    expect(plan.items, hasLength(1));
    // 同为"未知"档时按来源分级挑：高考真题 > 自建题。
    expect(plan.items.single.questionId, mathA);
  });

  test('难度贴合在给了目标难度后才起作用', () async {
    final easy = await seedQuestion(stem: '简单题', difficulty: 2);
    await seedQuestion(stem: '难题', difficulty: 9);

    final container = containerWith(LibraryDiagnosis.notRun);
    final spec = container.read(paperSpecProvider.notifier);
    spec.setTargetCount(1);

    // 不给目标难度：难度贴合的权重恒为中性，先按来源分级挑（同为 `gaokao` 时
    // 按题目 id 兜底），这里只要确认两题都在候选里。
    var plan = await container.read(paperPlanProvider.future);
    expect(plan.candidateCount, 2);

    spec.setTargetDifficulty(2);
    plan = await container.read(paperPlanProvider.future);
    expect(plan.items.single.questionId, easy);
  });

  test('危险区知识点题库里一道候选都没有 → 进"该去收题"清单', () async {
    final tagId = (await tags.createTag(name: '导数')).id;
    final pointId = await seedKnowledgePoint('导数极值');
    // 只挂知识点、不给它配题：这就是"该去收题"的情形。
    await link(tagId: tagId, pointId: pointId);
    await seedQuestion(stem: '一道和它无关的题。');

    final container = containerWith(ran({pointId: BottleneckType.danger}));
    final plan = await container.read(paperPlanProvider.future);

    expect(plan.uncoveredKnowledgePointIds, [pointId]);
    expect(plan.deferredKnowledgePointIds, isEmpty);
    // 题库里唯一那道题没挂点，仍然进卷，只是按未知处理。
    expect(plan.items.single.zone, PaperZone.unknown);
  });

  test('组卷要求的钳位、清空与二次点击取消', () async {
    final container = containerWith(LibraryDiagnosis.notRun);
    final spec = container.read(paperSpecProvider.notifier);

    // 默认：10 题、不限学科、不设难度/来源下限。
    expect(container.read(paperSpecProvider).targetCount, 10);
    expect(container.read(paperSpecProvider).subjectKeys, isEmpty);
    expect(container.read(paperSpecProvider).minSourceLevel, isNull);

    spec.setTargetCount(0);
    expect(container.read(paperSpecProvider).targetCount, 1);
    spec.setTargetCount(999);
    expect(container.read(paperSpecProvider).targetCount, 200);

    spec.toggleSubject(' 数学 ');
    expect(container.read(paperSpecProvider).subjectKeys, {'数学'});
    spec.toggleSubject('数学');
    expect(container.read(paperSpecProvider).subjectKeys, isEmpty);
    spec.toggleSubject('   ');
    expect(container.read(paperSpecProvider).subjectKeys, isEmpty);

    spec.setPerKnowledgePointCap(3);
    expect(container.read(paperSpecProvider).perKnowledgePointCap, 3);
    spec.setPerKnowledgePointCap(null);
    expect(container.read(paperSpecProvider).perKnowledgePointCap, isNull);

    spec.setMinSourceLevel(' gaokao ');
    expect(container.read(paperSpecProvider).minSourceLevel, 'gaokao');
    spec.setMinSourceLevel(null);
    expect(container.read(paperSpecProvider).minSourceLevel, isNull);

    spec.setTargetDifficulty(11);
    expect(container.read(paperSpecProvider).targetDifficulty, 10.0);
    spec.setTargetDifficulty(double.nan);
    expect(container.read(paperSpecProvider).targetDifficulty, isNull);

    // reset：回到默认要求。
    spec.toggleSubject('数学');
    spec.setTargetCount(3);
    spec.setMinSourceLevel('elite_school');
    spec.reset();
    final afterReset = container.read(paperSpecProvider);
    expect(afterReset.targetCount, 10);
    expect(afterReset.subjectKeys, isEmpty);
    expect(afterReset.minSourceLevel, isNull);
    expect(afterReset.perKnowledgePointCap, isNull);
    expect(afterReset.targetDifficulty, isNull);
  });

  group('学科配额（可选；默认不启用时与旧行为一致）', () {
    test('setter：整表/单科上限/单科保底/清空/reset 的语义', () {
      final container = containerWith(LibraryDiagnosis.notRun);
      final spec = container.read(paperSpecProvider.notifier);
      PaperSpec read() => container.read(paperSpecProvider);

      expect(read().subjectQuota, isNull, reason: '默认不启用配额');

      spec.setSubjectQuota(const SubjectQuota(
        maxPerSubject: <String, int>{'数学': 2},
      ));
      // SubjectQuota 是配置（未解析），上限/保底按原表读。
      Map<String, int> maxOf() => read().subjectQuota!.maxPerSubject;
      Map<String, int> minOf() => read().subjectQuota!.minPerSubject;

      expect(maxOf()['数学'], 2);
      expect(minOf()['数学'], isNull);

      // 单科保底：同一个表上追加，不把已有上限挤掉。
      spec.setSubjectMin('语文', 3);
      expect(maxOf()['数学'], 2);
      expect(minOf()['语文'], 3);
      expect(minOf()['数学'], isNull);

      spec.setSubjectMax('数学', 5);
      expect(maxOf()['数学'], 5);
      expect(minOf()['语文'], 3);

      // 删除单科上限：max < 0 或 null 都表示"去掉这一科"。
      spec.setSubjectMax('数学', null);
      expect(maxOf()['数学'], isNull);
      expect(minOf()['语文'], 3);

      // 单科键空白：忽略，不改状态。
      spec.setSubjectMax('   ', 2);
      expect(maxOf()['语文'], isNull);

      // 空表 = 不启用（回到 null，而不是一个空壳配额）。
      spec.clearSubjectQuota();
      expect(read().subjectQuota, isNull);

      spec.setSubjectQuota(const SubjectQuota(
        maxPerSubject: <String, int>{'数学': 1},
        minPerSubject: <String, int>{'语文': 2},
      ));
      expect(read().subjectQuota, isNotNull);
      spec.reset();
      expect(read().subjectQuota, isNull, reason: 'reset 应清掉配额');
    });

    test('空 SubjectQuota 视同不启用', () {
      final container = containerWith(LibraryDiagnosis.notRun);
      final spec = container.read(paperSpecProvider.notifier);

      spec.setSubjectQuota(const SubjectQuota());
      expect(container.read(paperSpecProvider).subjectQuota, isNull);
    });

    test('卷子真的按学科配额排题：上限生效、被挡的候选进缺口清单', () async {
      await seedQuestion(stem: '数学题 A');
      await seedQuestion(stem: '数学题 B');
      await seedQuestion(stem: '语文题', subjectKey: '语文');

      final container = containerWith(LibraryDiagnosis.notRun);
      final spec = container.read(paperSpecProvider.notifier);
      spec.setSubjectQuota(const SubjectQuota(
        maxPerSubject: <String, int>{'数学': 1},
      ));
      final plan = await container.read(paperPlanProvider.future);

      expect(plan.subjectQuota, isNotNull);
      expect(plan.bySubject, <String, int>{'数学': 1, '语文': 1});
      expect(
        plan.items.map((item) => item.subjectKey).toSet(),
        <String>{'数学', '语文'},
      );
      expect(plan.quotaBlockedQuestions, hasLength(1));
      expect(plan.quotaBlockedQuestions.single.subjectKey, '数学');
      expect(plan.quotaBlockedQuestions.single.subjectLimit, 1);
    });
  });

  group('领域配额（可选；默认不启用时与旧行为一致）', () {
    /// 领域 = 标签路径的第一段（`物理/力学` → `物理`）。先建顶层领域标签，
    /// 再给每道题建一个子标签；题目与知识点挂同一个子标签才连得上。
    Future<String> seedDomainTag(String domain) async =>
        (await tags.createTag(name: domain)).id;

    Future<void> seedDomainQuestion({
      required String domainTagId,
      required String stem,
      required String pointTitle,
      required String childTag,
      String subjectKey = '数学',
    }) async {
      final questionId = await seedQuestion(stem: stem, subjectKey: subjectKey);
      final pointId = await seedKnowledgePoint(pointTitle);
      final tagId =
          (await tags.createTag(name: childTag, parentId: domainTagId)).id;
      await link(tagId: tagId, pointId: pointId, questionId: questionId);
    }

    test('setter：整表/单域上限/单域保底/清空/空白键/reset 的语义', () {
      final container = containerWith(LibraryDiagnosis.notRun);
      final spec = container.read(paperSpecProvider.notifier);
      PaperSpec read() => container.read(paperSpecProvider);

      expect(read().domainQuota, isNull, reason: '默认不启用领域配额');

      spec.setDomainQuota(const DomainQuota(
        maxPerDomain: <String, int>{'物理': 2},
      ));
      // DomainQuota 是配置（未解析），上限/保底按原表读。
      Map<String, int> maxOf() => read().domainQuota!.maxPerDomain;
      Map<String, int> minOf() => read().domainQuota!.minPerDomain;

      expect(maxOf()['物理'], 2);
      expect(minOf()['物理'], isNull);

      // 单域保底：同一个表上追加，不把已有上限挤掉。
      spec.setDomainMin('化学', 3);
      expect(maxOf()['物理'], 2);
      expect(minOf()['化学'], 3);
      expect(minOf()['物理'], isNull);

      spec.setDomainMax('物理', 5);
      expect(maxOf()['物理'], 5);
      expect(minOf()['化学'], 3);

      // 删除单域上限：max < 0 或 null 都表示"去掉这个领域"。
      spec.setDomainMax('物理', null);
      expect(maxOf()['物理'], isNull);
      expect(minOf()['化学'], 3);

      // 单域键空白：忽略，不改状态。
      spec.setDomainMax('   ', 2);
      expect(maxOf()['化学'], isNull);

      // 空表 = 不启用（回到 null，而不是一个空壳配额）。
      spec.clearDomainQuota();
      expect(read().domainQuota, isNull);

      spec.setDomainQuota(const DomainQuota(
        maxPerDomain: <String, int>{'物理': 1},
        minPerDomain: <String, int>{'化学': 2},
      ));
      expect(read().domainQuota, isNotNull);
      spec.reset();
      expect(read().domainQuota, isNull, reason: 'reset 应清掉领域配额');
    });

    test('空 DomainQuota 视同不启用', () {
      final container = containerWith(LibraryDiagnosis.notRun);
      final spec = container.read(paperSpecProvider.notifier);

      spec.setDomainQuota(const DomainQuota());
      expect(container.read(paperSpecProvider).domainQuota, isNull);
    });

    test('默认不启用：卷子的领域四字段为空，toJson 不出现领域键', () async {
      final physics = await seedDomainTag('物理');
      await seedDomainQuestion(
        domainTagId: physics,
        stem: '一道物理题。',
        pointTitle: '动量守恒',
        childTag: '力学',
      );
      await seedQuestion(stem: '一道数学题。');

      final container = containerWith(LibraryDiagnosis.notRun);
      final plan = await container.read(paperPlanProvider.future);

      expect(plan.items, hasLength(2));
      expect(plan.domainQuota, isNull);
      expect(plan.byDomain, isEmpty);
      expect(plan.quotaBlockedByDomain, isEmpty);
      expect(plan.domainShortfalls, isEmpty);
      expect(plan.uncoveredDomains, isEmpty);
      final json = plan.toJson();
      for (final key in <String>[
        'by_domain',
        'quota_blocked_by_domain',
        'domain_shortfalls',
        'domain_quota',
      ]) {
        expect(json.containsKey(key), isFalse, reason: '没启用领域配额不该出现 $key');
      }
    });

    test('卷子真的按领域配额排题：上限生效、被挡的候选进清单', () async {
      final physics = await seedDomainTag('物理');
      final math = await seedDomainTag('数学');
      await seedDomainQuestion(
        domainTagId: physics,
        stem: '物理题 A',
        pointTitle: '动量守恒',
        childTag: '力学',
        subjectKey: 'physics',
      );
      await seedDomainQuestion(
        domainTagId: physics,
        stem: '物理题 B',
        pointTitle: '电磁感应',
        childTag: '电磁学',
        subjectKey: 'physics',
      );
      await seedDomainQuestion(
        domainTagId: physics,
        stem: '物理题 C',
        pointTitle: '光的折射',
        childTag: '光学',
        subjectKey: 'physics',
      );
      await seedDomainQuestion(
        domainTagId: math,
        stem: '数学题 A',
        pointTitle: '等差数列',
        childTag: '数列',
      );

      final container = containerWith(LibraryDiagnosis.notRun);
      final spec = container.read(paperSpecProvider.notifier);
      spec.setDomainQuota(const DomainQuota(
        maxPerDomain: <String, int>{'物理': 1},
      ));
      final plan = await container.read(paperPlanProvider.future);

      expect(plan.domainQuota, isNotNull);
      expect(plan.byDomain, <String, int>{'物理': 1, '数学': 1});
      expect(plan.items, hasLength(2));
      expect(plan.quotaBlockedByDomain, hasLength(2));
      expect(
        plan.quotaBlockedByDomain.map((row) => row.domain).toSet(),
        <String>{'物理'},
      );
      expect(plan.quotaBlockedByDomain.first.domainLimit, 1);
      expect(plan.domainShortfalls, isEmpty);
      expect(plan.uncoveredDomains, isEmpty);
    });

    test('保底缺口：物理要 3 道只有 1 道，如实报 selected/available', () async {
      final physics = await seedDomainTag('物理');
      await seedDomainQuestion(
        domainTagId: physics,
        stem: '唯一一道物理题。',
        pointTitle: '动量守恒',
        childTag: '力学',
        subjectKey: 'physics',
      );
      await seedQuestion(stem: '一道数学题。');

      final container = containerWith(LibraryDiagnosis.notRun);
      final spec = container.read(paperSpecProvider.notifier);
      spec.setDomainQuota(const DomainQuota(
        minPerDomain: <String, int>{'物理': 3},
      ));
      final plan = await container.read(paperPlanProvider.future);

      expect(plan.domainShortfalls, hasLength(1));
      final shortfall = plan.domainShortfalls.single;
      expect(shortfall.domain, '物理');
      expect(shortfall.minimumCount, 3);
      expect(shortfall.selectedCount, 1);
      expect(shortfall.availableCount, 1);
      expect(shortfall.isUncovered, isFalse);
      expect(plan.uncoveredDomains, isEmpty);
    });

    test('保底领域题库里没有题：缺口在收题，不在配额', () async {
      await seedQuestion(stem: '一道数学题。');

      final container = containerWith(LibraryDiagnosis.notRun);
      final spec = container.read(paperSpecProvider.notifier);
      spec.setDomainQuota(const DomainQuota(
        minPerDomain: <String, int>{'化学': 1},
      ));
      final plan = await container.read(paperPlanProvider.future);

      expect(plan.domainShortfalls, hasLength(1));
      final missing = plan.domainShortfalls.single;
      expect(missing.domain, '化学');
      expect(missing.selectedCount, 0);
      expect(missing.availableCount, 0);
      expect(missing.isUncovered, isTrue);
      expect(plan.uncoveredDomains, <String>['化学']);
    });
  });

  group('手工指定/排除（provider 状态与卷子）', () {
    test('setter 语义：整表设置 / toggle / 空集回 null / clear / reset', () {
      final container = containerWith(LibraryDiagnosis.notRun);
      final spec = container.read(paperSpecProvider.notifier);
      PaperSpec read() => container.read(paperSpecProvider);

      expect(read().manualIncludeQuestionIds, isNull);
      expect(read().manualExcludeQuestionIds, isNull);

      spec.setManualIncludeIds(<String>{'q-b', 'q-a'});
      expect(read().manualIncludeQuestionIds, <String>{'q-a', 'q-b'});
      spec.setManualExcludeIds(<String>{'q-c'});
      expect(read().manualExcludeQuestionIds, <String>{'q-c'});

      // 已在名单里 → 移除；不在 → 加入。
      spec.toggleManualInclude('q-a');
      expect(read().manualIncludeQuestionIds, <String>{'q-b'});
      spec.toggleManualInclude('q-c');
      expect(read().manualIncludeQuestionIds, <String>{'q-b', 'q-c'});

      // 排除名单删空回到"不启用"（null），不留空壳。
      spec.toggleManualExclude('q-c');
      expect(read().manualExcludeQuestionIds, isNull);

      // 整表传空集 = 启用但无操作（与 null 语义不同，composer 文档里写清了）。
      spec.setManualIncludeIds(<String>{});
      expect(read().manualIncludeQuestionIds, <String>{});

      spec.clearManualSelection();
      expect(read().manualIncludeQuestionIds, isNull);
      expect(read().manualExcludeQuestionIds, isNull);

      spec.setManualIncludeIds(<String>{'q-a'});
      spec.setManualExcludeIds(<String>{'q-b'});
      spec.reset();
      expect(read().manualIncludeQuestionIds, isNull);
      expect(read().manualExcludeQuestionIds, isNull);
    });

    test('toggle 空白 id 被忽略，不清空已有名单', () {
      final container = containerWith(LibraryDiagnosis.notRun);
      final spec = container.read(paperSpecProvider.notifier);
      spec.setManualIncludeIds(<String>{'q-a'});

      spec.toggleManualInclude('   ');
      expect(container.read(paperSpecProvider).manualIncludeQuestionIds,
          <String>{'q-a'});
      spec.toggleManualExclude('');
      expect(
          container.read(paperSpecProvider).manualExcludeQuestionIds, isNull);
    });

    test('卷子真的按手工名单排题：必收绕过知识点上限、冲突按排除、目标数挤掉如实报', () async {
      final q1 = await seedQuestion(stem: '必收题一。');
      final q2 = await seedQuestion(stem: '必收题二。');
      final q3 = await seedQuestion(stem: '被排除的题。');

      final container = containerWith(LibraryDiagnosis.notRun);
      final spec = container.read(paperSpecProvider.notifier);
      spec.setTargetCount(10);
      spec.setManualIncludeIds(<String>{q1, q2, q3});
      spec.setManualExcludeIds(<String>{q3});
      var plan = await container.read(paperPlanProvider.future);

      expect(plan.manualSelectionEnabled, isTrue);
      expect(plan.manualIncludedCount, 2);
      expect(
          plan.items.map((item) => item.questionId).toSet(), <String>{q1, q2});
      expect(plan.manualConflictQuestionIds, <String>{q3});
      expect(plan.manualMissingQuestionIds, isEmpty);
      final json = plan.toJson();
      expect(json['manual_included_count'], 2);
      expect(json['manual_conflict_question_ids'], <String>[q3]);

      // target_count = 1 装不下两道必收题：其余进 skipped，不静默丢。
      spec.setTargetCount(1);
      plan = await container.read(paperPlanProvider.future);
      expect(plan.manualIncludedCount, 1);
      expect(plan.manualSkippedQuestionIds, hasLength(1));
      expect(plan.items, hasLength(1));
    });

    test('默认不启用：手工字段为空，toJson 不出现手工键', () async {
      final q1 = await seedQuestion(stem: '一道普通题。');
      final container = containerWith(LibraryDiagnosis.notRun);
      final plan = await container.read(paperPlanProvider.future);

      expect(plan.manualSelectionEnabled, isFalse);
      expect(plan.manualIncludedCount, 0);
      expect(plan.manualMissingQuestionIds, isEmpty);
      expect(plan.manualSkippedQuestionIds, isEmpty);
      expect(plan.manualConflictQuestionIds, isEmpty);
      final json = plan.toJson();
      for (final key in <String>[
        'manual_included_count',
        'manual_missing_question_ids',
        'manual_skipped_question_ids',
        'manual_conflict_question_ids',
      ]) {
        expect(json.containsKey(key), isFalse, reason: '没启用手工选择不该出现 $key');
      }
      expect(plan.items.single.questionId, q1);
    });
  });
}
