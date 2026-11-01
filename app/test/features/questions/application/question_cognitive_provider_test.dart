/// 题目详情页「MindNet 认知评价」读数层的验收点：
///
///  * 没有知识点 / 没有记忆状态行 / 题目不存在 ⇒ empty，不编读数；
///  * 有知识点且有一行记忆状态 ⇒ 判词、理由、区域、建议都有值；
///  * 测评先验只作为额外读数出现（R0/置信/样本），不冒充观测；
///  * 同一个输入读两次结果一致；
///  * 区域聚合与建议映射是纯函数，单独钉住。
library;

import 'package:drift/drift.dart' show Value;
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
import 'package:furnace/domain/services/cognitive/problem_evaluator.dart'
    show ProblemVerdict;
import 'package:furnace/domain/services/scheduling/thread_balance_inputs.dart'
    show kKnowledgePointObjectType, kQuestionObjectType;
import 'package:furnace/features/anki/application/review_advisory.dart'
    show ReviewZone;
import 'package:furnace/features/questions/application/question_cognitive_provider.dart';

void main() {
  late AppDatabase database;
  late QuestionRepository questions;
  late TagRepository tags;
  late AnkiRepository anki;

  setUp(() {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    questions = QuestionRepository(database);
    tags = TagRepository(database);
    anki = AnkiRepository(database);
  });

  tearDown(() async {
    await database.close();
  });

  ProviderContainer container() {
    final container = ProviderContainer(
      overrides: <Override>[
        appDatabaseProvider.overrideWithValue(database),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  Future<QuestionCognitiveReading> read(
    ProviderContainer container,
    String questionId,
  ) =>
      container.read(questionCognitiveReadingProvider(questionId).future);

  Future<Question> seedQuestion({String stem = '已知二次函数，求最值。'}) async {
    final ingested = await questions.ingest(
      QuestionDraft(stem: stem, answer: '5', subjectKey: 'math'),
    );
    return ingested.question;
  }

  /// 造一个「标签 ↔ 知识点」，可选地给它一行已复习过的卡状态。
  Future<({Tag tag, KnowledgePoint point})> seedKnowledgePoint({
    bool withReviewedCard = true,
  }) async {
    final tag = await tags.createTag(name: '二次函数');
    final point = await anki.createKnowledgePoint(
      title: '二次函数最值',
      content: '配方或对称轴求最值。',
    );
    await tags.addTagToObject(
      tagId: tag.id,
      objectType: kKnowledgePointObjectType,
      objectId: point.id,
    );
    if (withReviewedCard) {
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final state = await anki.getOrCreateUnitCardState(
        point.id,
        'essay:${point.id}',
      );
      await anki.updateUnitCardState(
        state.id,
        stability: 365,
        difficulty: 4,
        lastReviewedAt: nowMs,
        repetitions: 5,
        state: 'review',
      );
      await anki.updateModelState(
        state.id,
        encodingStrength: 0.9,
        savings: 0.8,
      );
    }
    return (tag: tag, point: point);
  }

  Future<void> linkQuestionToTag(Question question, Tag tag) =>
      tags.addTagToObject(
        tagId: tag.id,
        objectType: kQuestionObjectType,
        objectId: question.id,
      );

  group('空态：没有读数就不编', () {
    test('题目没有挂知识点 ⇒ empty，判词/区域/先验都不给', () async {
      final question = await seedQuestion();
      final reading = await read(container(), question.id);

      expect(reading.isEmpty, isTrue);
      expect(reading.questionId, question.id);
      expect(reading.knowledgePointIds, isEmpty);
      expect(reading.judgedKnowledgePointIds, isEmpty);
      expect(reading.verdict, isNull);
      expect(reading.zone, ReviewZone.unavailable);
      expect(reading.suggestion, QuestionCognitiveSuggestion.keepPlan);
      expect(reading.hasPrior, isFalse);
      expect(reading.priorR0, isNull);
      expect(reading.uncalibrated, isTrue);
    });

    test('题目 id 不存在 ⇒ empty，不抛异常', () async {
      final reading = await read(container(), 'q-does-not-exist');

      expect(reading.isEmpty, isTrue);
      expect(reading.questionId, 'q-does-not-exist');
      expect(reading.verdict, isNull);
    });

    test('知识点存在但没有记忆状态行（悬空/未建卡）⇒ empty，不崩', () async {
      final question = await seedQuestion();
      final seeded = await seedKnowledgePoint(withReviewedCard: false);
      await linkQuestionToTag(question, seeded.tag);

      final reading = await read(container(), question.id);

      expect(reading.isEmpty, isTrue);
      expect(reading.knowledgePointIds, <String>[seeded.point.id]);
      expect(reading.judgedKnowledgePointIds, isEmpty);
      expect(reading.verdict, isNull);
    });
  });

  group('有读数：字段映射', () {
    test('题目 ↔ 标签 ↔ 知识点 ↔ 记忆行 ⇒ 判词/理由/区域/建议都有值', () async {
      final question = await seedQuestion();
      final seeded = await seedKnowledgePoint();
      await linkQuestionToTag(question, seeded.tag);

      final reading = await read(container(), question.id);

      expect(reading.isEmpty, isFalse);
      expect(reading.questionId, question.id);
      expect(reading.knowledgePointIds, <String>[seeded.point.id]);
      expect(reading.judgedKnowledgePointIds, <String>[seeded.point.id]);
      expect(reading.verdict, isNotNull);
      expect(reading.reason.trim(), isNotEmpty);
      expect(ReviewZone.values, contains(reading.zone));
      expect(
        QuestionCognitiveSuggestion.values,
        contains(reading.suggestion),
      );
      expect(reading.uncalibrated, isTrue);
      expect(reading.toJson()['verdict'], isNotNull);
      expect(reading.toJson()['zone'], reading.zone.name);
      expect(reading.toJson()['uncalibrated'], isTrue);
    });

    test('同一输入读两次 ⇒ toJson 完全一致（确定性）', () async {
      final question = await seedQuestion();
      final seeded = await seedKnowledgePoint();
      await linkQuestionToTag(question, seeded.tag);

      final first = await read(container(), question.id);
      final second = await read(container(), question.id);

      expect(second.toJson(), first.toJson());
    });

    test('有测评先验 ⇒ R0/置信/样本读回来（先验不是观测）', () async {
      final question = await seedQuestion();
      final seeded = await seedKnowledgePoint();
      await linkQuestionToTag(question, seeded.tag);
      await database.into(database.cognitivePriors).insert(
            CognitivePriorsCompanion.insert(
              knowledgePointId: seeded.point.id,
              source: 'assessment:blended',
              r0: 0.7,
              n: const Value<int>(5),
              createdAt: DateTime.now().millisecondsSinceEpoch,
            ),
          );

      final reading = await read(container(), question.id);

      expect(reading.hasPrior, isTrue);
      expect(reading.priorR0, closeTo(0.7, 1e-9));
      expect(reading.priorSamples, 5);
      // confidence = n / (n + 3) = 5 / 8，见 AssessmentRepository。
      expect(reading.priorConfidence, closeTo(5 / 8, 1e-9));
    });
  });

  group('区域聚合（纯函数）', () {
    test('诊断没跑 ⇒ unavailable，不退化成健康', () {
      expect(
        aggregateCognitiveZone(
          fastLayerRan: false,
          complaints: const <BottleneckType>[BottleneckType.weak],
        ),
        ReviewZone.unavailable,
      );
    });

    test('跑了但没有抱怨 ⇒ healthy', () {
      expect(
        aggregateCognitiveZone(
          fastLayerRan: true,
          complaints: const <BottleneckType>[],
        ),
        ReviewZone.healthy,
      );
    });

    test('多个抱怨按优先次序取：危险 > 发展区 > 死角 > 其它', () {
      expect(
        aggregateCognitiveZone(
          fastLayerRan: true,
          complaints: const <BottleneckType>[
            BottleneckType.weak,
            BottleneckType.danger,
          ],
        ),
        ReviewZone.danger,
      );
      expect(
        aggregateCognitiveZone(
          fastLayerRan: true,
          complaints: const <BottleneckType>[
            BottleneckType.deadEnd,
            BottleneckType.weak,
          ],
        ),
        ReviewZone.proximal,
      );
      expect(
        aggregateCognitiveZone(
          fastLayerRan: true,
          complaints: const <BottleneckType>[BottleneckType.slow],
        ),
        ReviewZone.slow,
      );
    });
  });

  group('建议映射（纯函数）', () {
    test('危险区压过判词 ⇒ 先补先验', () {
      expect(
        cognitiveSuggestionFor(
          verdict: ProblemVerdict.zpd,
          zone: ReviewZone.danger,
        ),
        QuestionCognitiveSuggestion.buildPrior,
      );
    });

    test('发展中区/值得做 ⇒ 现在练', () {
      for (final verdict in <ProblemVerdict>[
        ProblemVerdict.zpd,
        ProblemVerdict.highValue,
      ]) {
        expect(
          cognitiveSuggestionFor(
            verdict: verdict,
            zone: ReviewZone.healthy,
          ),
          QuestionCognitiveSuggestion.practiceNow,
        );
      }
    });

    test('已经会了/偏难/超纲/重复 ⇒ 暂缓', () {
      for (final verdict in <ProblemVerdict>[
        ProblemVerdict.tooEasy,
        ProblemVerdict.tooHard,
        ProblemVerdict.outOfScope,
        ProblemVerdict.redundant,
      ]) {
        expect(
          cognitiveSuggestionFor(
            verdict: verdict,
            zone: ReviewZone.healthy,
          ),
          QuestionCognitiveSuggestion.postpone,
        );
      }
    });

    test('没有判词 ⇒ 按计划（中性兜底）', () {
      expect(
        cognitiveSuggestionFor(
          verdict: null,
          zone: ReviewZone.unavailable,
        ),
        QuestionCognitiveSuggestion.keepPlan,
      );
    });
  });

  group('判词 wire id', () {
    test('六种判词映射与契约措辞一致', () {
      expect(problemVerdictId(ProblemVerdict.tooEasy), 'too_easy');
      expect(problemVerdictId(ProblemVerdict.zpd), 'zpd');
      expect(problemVerdictId(ProblemVerdict.tooHard), 'too_hard');
      expect(problemVerdictId(ProblemVerdict.outOfScope), 'out_of_scope');
      expect(problemVerdictId(ProblemVerdict.redundant), 'redundant');
      expect(problemVerdictId(ProblemVerdict.highValue), 'high_value');
    });
  });
}
