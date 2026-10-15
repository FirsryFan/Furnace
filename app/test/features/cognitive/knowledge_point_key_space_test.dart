// Q8 的端到端哨兵：**真实的两套 id**（`kp-…` 与 `tag-…`）下，观察层必须真的
// 跑起来。
//
// 背景（Q6 实测）：认知快层的图节点是**标签**，而页面/题目手里的 id 是**知识点**。
// 两者混用会让 runner 把每一行、每一个起点都丢掉，于是界面永远显示"这轮没诊断"。
// 这个文件用真实仓储建出**不同**的两个 id 并挂载起来，钉住：
//
// 1. 不带键映射（Q8 之前的行为）时，runner 什么都没跑 —— 这就是缺陷本身；
// 2. 带键映射时 `fastLayerRan == true`，而且结论回到**知识点**键；
// 3. 页面那条 provider（`cognitiveLibraryDiagnosisProvider`）拿到的就是 2 的结果，
//    所以 `cognitiveReadingsProvider` 的 zone 不再是 `unavailable`。
//
// 旧测试没能发现它，是因为它们用同一个字符串同时当标签 id 与知识点 id
// （`test/domain/services/cognitive/library_diagnosis_test.dart`）。

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/app_database_provider.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/repository_providers.dart';
import 'package:furnace/domain/services/cognitive/cognitive_graph.dart';
import 'package:furnace/domain/services/cognitive/cognitive_model.dart';
import 'package:furnace/domain/services/cognitive/knowledge_point_tag_bridge.dart';
import 'package:furnace/domain/services/cognitive/library_diagnosis.dart';
import 'package:furnace/features/anki/application/review_advisory.dart'
    show ReviewZone;
import 'package:furnace/features/cognitive/presentation/cognitive_model_page.dart';

class _FakeModel implements CognitiveModel {
  const _FakeModel();

  @override
  String get id => 'test-fake';

  @override
  double retrievabilityOf(CardState row, {required double nowHours}) => 0.5;

  @override
  double expectedGain(
    CardState row, {
    required double nowHours,
    double closeness = 0.5,
  }) =>
      2.0;

  @override
  List<AdvisorCandidate> orderAdvisory(
    List<AdvisorCandidate> candidates, {
    required double nowHours,
    Set<String> targetKpIds = const {},
  }) =>
      [...candidates]..sort((a, b) => a.row.id.compareTo(b.row.id));

  @override
  ({double r0, double sigma, double r}) modelReadingOf(
    CardState row, {
    required double nowHours,
  }) =>
      (r0: 0.7, sigma: 0.9, r: 0.42);

  @override
  ({double r0, double sigma}) modelStateAfterReview(
    CardState row, {
    required int rating,
    required double nowHours,
    bool reread = false,
    bool reviewedSolution = false,
    double closeness = 0.5,
  }) =>
      (r0: 0.7, sigma: 0.9);
}

void main() {
  late AppDatabase db;
  late ProviderContainer container;
  late String pointId;
  late String tagId;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        cognitiveModelProvider.overrideWithValue(const _FakeModel()),
      ],
    );
    addTearDown(container.dispose);

    // 真实仓储：id 由 `Ids.next('kp')` / `Ids.next('tag')` 生成，因此两套
    // id 天然不同 —— 这正是缺陷发生的条件。
    final anki = container.read(ankiRepositoryProvider);
    final tags = container.read(tagRepositoryProvider);
    final point = await anki.createKnowledgePoint(
      title: '动量守恒',
      content: '系统不受外力时动量守恒。',
    );
    pointId = point.id;
    final tag = await tags.createTag(name: '力学');
    tagId = tag.id;
    await tags.addTagToObject(
      tagId: tag.id,
      objectType: kKnowledgePointObjectType,
      objectId: point.id,
    );

    final state = await anki.getOrCreateUnitCardState(point.id, 'essay');
    await anki.updateUnitCardState(
      state.id,
      repetitions: 3,
      stability: 5,
      difficulty: 5,
      dueAt: 1,
      lastReviewedAt: 1,
    );
  });

  test('the fixture really uses two different id spaces', () {
    expect(pointId, startsWith('kp-'));
    expect(tagId, startsWith('tag-'));
    expect(pointId, isNot(tagId));
  });

  test('without the key bridge the runner silently diagnoses nothing', () async {
    final anki = container.read(ankiRepositoryProvider);
    final states = await anki.unitStatesForKnowledgePoint(pointId);
    final row = states.single;
    final tagRows = await db.select(db.tags).get();

    final diagnosis = LibraryDiagnosisRunner.run(
      tags: [for (final tag in tagRows) CognitiveTag.fromTag(tag)],
      // 知识点 id 当图节点 id 用：starts/targets/rows 全部落空。
      rowsByKnowledgePoint: {pointId: row},
      model: const _FakeModel(),
      nowHours: 1000,
      startKnowledgePointIds: [pointId],
      targetKnowledgePointIds: [pointId],
    );

    expect(diagnosis.fastLayerRan, isFalse);
    expect(diagnosis.byKnowledgePoint, isEmpty);
  });

  test('with the key bridge the same data runs, and verdicts come back keyed by '
      'knowledge point', () async {
    final anki = container.read(ankiRepositoryProvider);
    final states = await anki.unitStatesForKnowledgePoint(pointId);
    final tagRows = await db.select(db.tags).get();

    final diagnosis = LibraryDiagnosisRunner.run(
      tags: [for (final tag in tagRows) CognitiveTag.fromTag(tag)],
      rowsByKnowledgePoint: {pointId: states.single},
      model: const _FakeModel(),
      nowHours: 1000,
      startKnowledgePointIds: [pointId],
      targetKnowledgePointIds: [pointId],
      tagIdsByKnowledgePoint: {pointId: [tagId]},
    );

    expect(diagnosis.fastLayerRan, isTrue);
    // 结论的键是调用方的键空间：没有一个 `tag-…` 漏出去。
    expect(
      diagnosis.byKnowledgePoint.keys,
      everyElement(isNot(startsWith('tag-'))),
    );
  });

  test('the page provider is wired to the bridge end to end', () async {
    final diagnosis =
        await container.read(cognitiveLibraryDiagnosisProvider.future);

    expect(diagnosis.fastLayerRan, isTrue);
    expect(
      diagnosis.byKnowledgePoint.keys,
      everyElement(isNot(startsWith('tag-'))),
    );

    final readings =
        await container.read(cognitiveReadingsProvider.future);
    expect(readings.fastLayerRan, isTrue);
    expect(readings.zoneByKnowledgePoint[pointId], isNotNull);
    expect(
      readings.zoneByKnowledgePoint[pointId],
      isNot(ReviewZone.unavailable),
      reason: '"什么都没诊断"与"诊断过、没毛病"必须是两个样子',
    );
  });
}
