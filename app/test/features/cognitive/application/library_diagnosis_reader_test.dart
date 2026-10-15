import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/app_database_provider.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/domain/services/cognitive/cognitive_graph.dart';
import 'package:furnace/domain/services/cognitive/cognitive_model.dart';
import 'package:furnace/domain/services/cognitive/fast_diagnosis.dart'
    show BottleneckType;
import 'package:furnace/domain/services/cognitive/library_diagnosis.dart';
import 'package:furnace/features/cognitive/application/library_diagnosis_reader.dart';
import 'package:furnace/features/cognitive/presentation/cognitive_model_page.dart';
import 'package:furnace/features/questions/application/question_corpus_reader.dart';

/// Q13 把认知快层的读表与诊断从页面 provider 里抽成了纯函数
/// （`library_diagnosis_reader.dart`），好让 AI 工具也用上同一份结论。
/// 抽出去的风险只有一个：**页面与工具看到的不再是同一件事**。这个文件就是钉住它的：
///
///  1. 空库 → "没跑"（`fastLayerRan == false`），而不是"健康"；
///  2. 有标签 + 有卡片观测 → 纯函数与页面 provider 的读数**逐字段相同**；
///  3. `readPaperReadings` 的三条诚实路径：没跑 → 空；跑了没结论 → 空（**不是**
///     给每个点编一条"健康"）；诊断出危险区 → 该点有读数。
void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  /// 一个知识点 + 一张卡片观测 + 一个标签挂载（与页面测试同一套种子）。
  Future<void> seedObservedLibrary() async {
    await db.into(db.knowledgePoints).insert(KnowledgePointsCompanion.insert(
          id: 'kp-1',
          title: '光合作用',
          content: '把光能变成化学能',
          createdAt: 1,
          updatedAt: 1,
        ));
    await db.into(db.cardStates).insert(CardStatesCompanion.insert(
          id: 'cs-1',
          createdAt: 1,
          updatedAt: 2,
          dueAt: const Value(1700000000000),
          repetitions: const Value(4),
          knowledgePointId: const Value('kp-1'),
          unitKey: const Value('cloze:0'),
          stability: const Value(12.5),
          difficulty: const Value(6.0),
          encodingStrength: const Value(0.9),
          savings: const Value(0.85),
        ));
    await db.into(db.tags).insert(TagsCompanion.insert(
          id: 't-1',
          name: '生物',
          createdAt: 1,
          updatedAt: 1,
        ));
    await db.into(db.objectTags).insert(ObjectTagsCompanion.insert(
          id: 'ot-1',
          tagId: 't-1',
          objectType: 'knowledge_point',
          objectId: 'kp-1',
          createdAt: 1,
        ));
  }

  group('没跑 ≠ 健康', () {
    test('空库：没有观测也没有标签 → notRun，组卷读数取不到任何东西', () async {
      final inputs = await readCognitiveObservationInputs(db);
      final tagIds = await readKnowledgePointTagIds(db);
      final diagnosis = await readLibraryDiagnosis(
        db,
        model: const MindNetCognitiveModel(),
      );
      final readings = await readPaperReadings(
        db,
        coveredKnowledgePointIds: const {'kp-1'},
        diagnosis: diagnosis,
      );

      expect(inputs.units, isEmpty);
      expect(tagIds, isEmpty);
      expect(diagnosis.fastLayerRan, isFalse);
      expect(readings, isEmpty, reason: '"没跑"必须退化成"没有读数"，不能退化成"健康"');
    });

    test('跑了、但没有任何危险/发展区结论 → 组卷读数仍然是空', () async {
      await seedObservedLibrary();

      final diagnosis = await readLibraryDiagnosis(
        db,
        model: const MindNetCognitiveModel(),
      );
      final readings = await readPaperReadings(
        db,
        coveredKnowledgePointIds: const {'kp-1'},
        diagnosis: diagnosis,
      );

      expect(diagnosis.fastLayerRan, isTrue);
      // 快层给每个判过的节点一个结论，但这里是 `empty`（"看了，没问题"），
      // 不是 danger/weak —— 组卷读数只认后两者。
      expect(
        diagnosis.byKnowledgePoint.values.toSet(),
        {BottleneckType.empty},
      );
      expect(readings, isEmpty, reason: '有观测不等于有结论：不许把"没发现问题"写成一条 healthy 读数');
    });

    test('诊断出危险区的知识点 → 即使题库里没有它的候选也有读数', () async {
      // 危险是"关于时钟的陈述"：同一张图，卡片久未复习 → belief 远高于 reality。
      const staleHours = 100000.0;
      CardState rowOf(String knowledgePointId) => CardState(
            id: 'cs-$knowledgePointId',
            knowledgePointId: knowledgePointId,
            unitKey: 'cloze:s1',
            dueAt: 995000,
            intervalDays: 5,
            ease: 2.5,
            repetitions: 4,
            lapses: 0,
            state: 'review',
            lastReviewedAt: 990000,
            createdAt: 1,
            updatedAt: 2,
            stability: 5,
            difficulty: 5,
            encodingStrength: 1.0,
            savings: 0.8,
            forced: 0,
            forcedStreak: 0,
          );
      final danger = LibraryDiagnosisRunner.run(
        tags: [
          const CognitiveTag(id: 'root', name: 'root'),
          const CognitiveTag(id: 'a', name: 'a', parentId: 'root'),
          const CognitiveTag(id: 'b', name: 'b', parentId: 'root'),
          const CognitiveTag(id: 'c', name: 'c', parentId: 'root'),
        ],
        rowsByKnowledgePoint: {
          for (final id in const ['root', 'a', 'b', 'c']) id: rowOf(id),
        },
        model: const MindNetCognitiveModel(),
        nowHours: staleHours,
        startKnowledgePointIds: const ['root'],
        targetKnowledgePointIds: const ['c'],
      );

      final dangerousIds = [
        for (final entry in danger.byKnowledgePoint.entries)
          if (entry.value == BottleneckType.danger) entry.key,
      ];
      expect(
        dangerousIds,
        isNotEmpty,
        reason: '先确认这个夹具真的造出了危险区',
      );

      final readings = await readPaperReadings(
        db,
        coveredKnowledgePointIds: const {},
        diagnosis: danger,
      );

      expect(
        readings.map((reading) => reading.knowledgePointId),
        containsAll(dangerousIds),
      );
      for (final id in dangerousIds) {
        expect(
          readings
              .firstWhere((reading) => reading.knowledgePointId == id)
              .inDangerZone,
          isTrue,
        );
      }
    });
  });

  group('与页面 provider 同源', () {
    test('观测输入、标签 id、诊断结论三样逐字段一致', () async {
      await seedObservedLibrary();

      final container = ProviderContainer(overrides: [
        appDatabaseProvider.overrideWithValue(db),
      ]);
      addTearDown(container.dispose);

      final inputs = await readCognitiveObservationInputs(db);
      final pageInputs =
          await container.read(cognitiveObservationInputsProvider.future);
      expect(pageInputs.toJson(), inputs.toJson());

      final tagIds = await readKnowledgePointTagIds(db);
      final pageTagIds =
          await container.read(knowledgePointTagIdsProvider.future);
      expect(pageTagIds, tagIds);

      final diagnosis = await readLibraryDiagnosis(
        db,
        model: const MindNetCognitiveModel(),
      );
      final pageDiagnosis =
          await container.read(cognitiveLibraryDiagnosisProvider.future);
      expect(pageDiagnosis.fastLayerRan, diagnosis.fastLayerRan);
      expect(pageDiagnosis.byKnowledgePoint, diagnosis.byKnowledgePoint);
      expect(pageDiagnosis.starts, diagnosis.starts);
      expect(pageDiagnosis.targets, diagnosis.targets);
      expect(
          pageDiagnosis.metacognition.hasRows, diagnosis.metacognition.hasRows);

      expect(diagnosis.fastLayerRan, isTrue, reason: '这个夹具应该让快层跑起来');
      expect(inputs.units, hasLength(1));
      expect(inputs.units.single.cardStateId, 'cs-1');
      expect(tagIds, {
        'kp-1': ['t-1'],
      });
    });
  });
}
