import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/app_database_provider.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/anki_repository.dart';
import 'package:furnace/data/repositories/question_repository.dart';
import 'package:furnace/data/repositories/tag_repository.dart';
import 'package:furnace/domain/services/cognitive/fast_diagnosis.dart'
    show BottleneckType;
import 'package:furnace/domain/services/cognitive/library_diagnosis.dart';
import 'package:furnace/domain/services/paper/paper_quality_report.dart';
import 'package:furnace/domain/services/reasoning/capability_action.dart';
import 'package:furnace/features/cognitive/presentation/cognitive_model_page.dart'
    show cognitiveLibraryDiagnosisProvider;
import 'package:furnace/features/questions/application/paper_plan_provider.dart';
import 'package:furnace/features/questions/application/paper_quality_provider.dart';

/// 组卷质量报告在应用层的接线验收（`docs/PAPER_COMPOSER_DESIGN.md` §22）：
///
///  * 判据本身是纯逻辑（domain 层已有 37 例），这里只验**数据装配**：
///    空卷也出报告、难度读数从题库候选回填而不是当 0、学科名走中文标签、
///    provider 的输出与直接 `build` 完全一致；
///  * 难度读数缺失不伪造：报告自己会说 `difficulty_data_unavailable`。
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

  /// 组卷 provider 的依赖：空诊断 = 没有图谱结论（不等于健康）。
  ProviderContainer containerWith() {
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        cognitiveLibraryDiagnosisProvider.overrideWith(
          (ref) async => const LibraryDiagnosis(
            byKnowledgePoint: <String, BottleneckType>{},
            fastLayerRan: false,
          ),
        ),
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

  List<String> codesOf(PaperQualityReport report) =>
      report.warnings.map((warning) => warning.code).toList();

  test('空库：报告是空卷，只出 empty_plan（页面不用先判空）', () async {
    final container = containerWith();
    final report = await container.read(paperQualityReportProvider.future);

    expect(report.isEmpty, isTrue);
    expect(report.questionCount, 0);
    expect(report.requestedCount, 10);
    expect(report.fillRatio, 0);
    expect(codesOf(report), <String>[PaperQualityCodes.emptyPlan]);
    expect(report.warnings.single.severity, PaperQualitySeverity.error);
    expect(report.warnings.single.messageZh, contains('卷面是空的'));
  });

  test('有题但没难度读数：难度分布为空，info 说未评估，不拿 0 冒充', () async {
    await seedQuestion(stem: '一、无难度读数');
    await seedQuestion(stem: '二、无难度读数');
    await seedQuestion(stem: '三、无难度读数');
    final container = containerWith();
    final report = await container.read(paperQualityReportProvider.future);

    expect(report.questionCount, 3);
    expect(report.difficultyDistribution, isEmpty);
    final codes = codesOf(report);
    expect(codes, contains(PaperQualityCodes.difficultyDataUnavailable));
    expect(codes, isNot(contains(PaperQualityCodes.difficultyDataPartial)));
    expect(codes, isNot(contains(PaperQualityCodes.difficultyFlat)));
    expect(codes, isNot(contains(PaperQualityCodes.difficultyFarFromTarget)));
  });

  test('题库有难度读数：分布按 1 位小数档，不再报未评估', () async {
    await seedQuestion(stem: '易题', difficulty: 2);
    await seedQuestion(stem: '中档题', difficulty: 3);
    await seedQuestion(stem: '难题', difficulty: 4);
    final container = containerWith();
    final report = await container.read(paperQualityReportProvider.future);

    expect(report.questionCount, 3);
    expect(
      report.difficultyDistribution.map((bucket) => bucket.key),
      <String>['2.0', '3.0', '4.0'],
    );
    expect(
      report.difficultyDistribution.map((bucket) => bucket.count),
      <int>[1, 1, 1],
    );
    expect(report.difficultyDistribution.first.ratio, closeTo(1 / 3, 1e-9));
    expect(report.difficultyDistribution.first.labelZh, '难度 2.0');
    final codes = codesOf(report);
    expect(codes, isNot(contains(PaperQualityCodes.difficultyDataUnavailable)));
    expect(codes, isNot(contains(PaperQualityCodes.difficultyDataPartial)));
  });

  test('只有部分题有难度：显式说部分读数，不把缺的当 0', () async {
    await seedQuestion(stem: '有读数的题一', difficulty: 2);
    await seedQuestion(stem: '有读数的题二', difficulty: 2);
    await seedQuestion(stem: '没读数的题');
    final container = containerWith();
    final report = await container.read(paperQualityReportProvider.future);

    expect(report.questionCount, 3);
    final partial = report.warnings.singleWhere(
      (warning) => warning.code == PaperQualityCodes.difficultyDataPartial,
    );
    expect(partial.severity, PaperQualitySeverity.info);
    expect(partial.evidence['known_count'], '2');
    expect(partial.evidence['missing_count'], '1');
    expect(
      report.difficultyDistribution.single.count,
      2,
      reason: '只有两道题有读数，分布只按这两道算',
    );
  });

  test('目标难度拉远：difficulty_far_from_target 带均值与目标证据', () async {
    await seedQuestion(stem: '简单题一', difficulty: 2);
    await seedQuestion(stem: '简单题二', difficulty: 2);
    await seedQuestion(stem: '简单题三', difficulty: 2);
    final container = containerWith();
    container.read(paperSpecProvider.notifier).setTargetDifficulty(8);
    final report = await container.read(paperQualityReportProvider.future);

    final far = report.warnings.singleWhere(
      (warning) => warning.code == PaperQualityCodes.difficultyFarFromTarget,
    );
    expect(far.severity, PaperQualitySeverity.warning);
    expect(far.evidence['mean'], '2.00');
    expect(far.evidence['target'], '8.00');
    expect(far.messageZh, contains('偏离目标'));
  });

  test('学科名走中文标签：math → 数学，缺失回退键', () async {
    await seedQuestion(stem: '数学题一', subjectKey: 'math');
    await seedQuestion(stem: '数学题二', subjectKey: 'math');
    await seedQuestion(stem: '化学题', subjectKey: 'chemistry');
    await seedQuestion(stem: '未知学科题', subjectKey: 'astronomy');
    final container = containerWith();
    final report = await container.read(paperQualityReportProvider.future);

    final labels = <String, String>{
      for (final bucket in report.subjectDistribution)
        bucket.key: bucket.labelZh,
    };
    expect(labels['math'], CapabilityAction.subjectLabelsZh['math']);
    expect(labels['math'], '数学');
    expect(labels['chemistry'], '化学');
    expect(labels['astronomy'], 'astronomy');
    expect(report.subjectDistribution.map((bucket) => bucket.key), <String>[
      'astronomy',
      'chemistry',
      'math',
    ]);
  });

  test('挂上知识点：覆盖率与覆盖数来自卷面，不再报没有知识点', () async {
    final tagId = (await tags.createTag(name: '函数')).id;
    final pointId = await seedKnowledgePoint('函数单调性');
    final first = await seedQuestion(stem: '第一个挂知识点的题');
    final second = await seedQuestion(stem: '第二个挂知识点的题');
    await link(tagId: tagId, pointId: pointId, questionId: first);
    await link(tagId: tagId, pointId: pointId, questionId: second);
    final container = containerWith();
    final report = await container.read(paperQualityReportProvider.future);

    expect(report.coveredKnowledgePointCount, 1);
    expect(report.knowledgePointCoverage, 1);
    expect(report.uncoveredKnowledgePointIds, isEmpty);
    final codes = codesOf(report);
    expect(codes, isNot(contains(PaperQualityCodes.noKnowledgePoints)));
    expect(codes, isNot(contains(PaperQualityCodes.knowledgePointGap)));
  });

  test('provider 与直接 build 一致（同一份输入同一份报告）', () async {
    await seedQuestion(
        stem: '工程题一', difficulty: 3, sourceLevel: 'elite_school');
    await seedQuestion(stem: '工程题二', difficulty: 5);
    final container = containerWith();
    final report = await container.read(paperQualityReportProvider.future);
    final plan = await container.read(paperPlanProvider.future);
    final difficulties =
        await container.read(paperQualityDifficultiesProvider.future);
    final names =
        await container.read(paperKnowledgePointLabelsProvider.future);
    final spec = container.read(paperSpecProvider);
    final direct = PaperQualityReport.build(
      plan: plan,
      subjectNames: CapabilityAction.subjectLabelsZh,
      knowledgePointNames: names,
      difficultyByQuestionId: difficulties,
      targetDifficulty: spec.targetDifficulty,
    );

    expect(direct.questionCount, report.questionCount);
    expect(direct.fillRatio, report.fillRatio);
    expect(direct.difficultyDistribution.length,
        report.difficultyDistribution.length);
    expect(codesOf(direct), codesOf(report));
    expect(direct.toJson(), report.toJson());
  });

  test('学科筛到不存在的学科：卷子空、报告仍是 empty_plan，不抛', () async {
    await seedQuestion(stem: '一道数学题');
    final container = containerWith();
    container.read(paperSpecProvider.notifier).toggleSubject('biology');
    final report = await container.read(paperQualityReportProvider.future);

    expect(report.isEmpty, isTrue);
    expect(codesOf(report), <String>[PaperQualityCodes.emptyPlan]);
  });
}
