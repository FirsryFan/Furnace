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
import 'package:furnace/domain/services/paper/paper_composer.dart';
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
}
