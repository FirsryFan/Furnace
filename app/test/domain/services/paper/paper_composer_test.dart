import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/repositories/question_repository.dart'
    show kSourceLevelWeight;
import 'package:furnace/domain/services/paper/paper_composer.dart';
import 'package:furnace/domain/services/scheduling/domain_balance.dart'
    show KnowledgePointReading;
import 'package:furnace/domain/services/scheduling/thread_balance_inputs.dart'
    show ObjectTagLink, TaskKnowledgePointResolver, kQuestionObjectType;

PaperCandidate _candidate({
  required String id,
  String subject = '数学',
  String source = 'gaokao',
  double? difficulty,
  double? quality,
  String? trap,
  List<String> points = const ['kp-1'],
}) =>
    PaperCandidate(
      questionId: id,
      subjectKey: subject,
      sourceLevel: source,
      difficulty: difficulty,
      aiQuality: quality,
      trapNote: trap,
      matchedKnowledgePointIds: points,
    );

KnowledgePointReading _reading(
  String knowledgePointId, {
  bool danger = false,
  bool development = false,
  double? priorR0,
  double priorConfidence = 0,
}) =>
    KnowledgePointReading(
      knowledgePointId: knowledgePointId,
      inDangerZone: danger,
      inDevelopmentZone: development,
      priorR0: priorR0,
      priorConfidence: priorConfidence,
    );

void main() {
  group('PaperComposer', () {
    test('the source-level table stays in step with the repository weights',
        () {
      // 两张表服务同一个口径（来源分级），顺序必须一致：一张表排错了，
      // 「高考真题优先」就会静默变成「自建题优先」。
      for (final level in kSourceLevelWeight.keys) {
        expect(kSourceLevelPriority[level], isNotNull, reason: level);
      }
      final byRepository = (kSourceLevelWeight.entries.toList()
            ..sort((a, b) => b.value.compareTo(a.value)))
          .map((entry) => entry.key)
          .toList();
      final byPriority = (kSourceLevelPriority.entries.toList()
            ..sort((a, b) => b.value.compareTo(a.value)))
          .map((entry) => entry.key)
          .toList();
      expect(byPriority, byRepository);
    });

    test('a danger zone outranks a well-sourced healthy question', () {
      final plan = PaperComposer.compose(
        candidates: [
          _candidate(id: 'q-healthy', quality: 0.9, points: ['kp-h']),
          _candidate(
            id: 'q-danger',
            source: 'school',
            quality: 0.1,
            points: ['kp-d'],
          ),
        ],
        spec: const PaperSpec(targetCount: 2),
        readings: [
          _reading('kp-d', danger: true),
          _reading('kp-h'),
        ],
      );

      expect(plan.items.map((item) => item.questionId).toList(),
          ['q-danger', 'q-healthy']);
      expect(plan.items.first.zone, PaperZone.danger);
      expect(plan.items.first.need, kDangerNeed);
      expect(plan.items.first.reasonZh, contains('危险区'));
      expect(plan.items.first.improvementNote, isNotEmpty);
    });

    test('the same need prefers the higher source level', () {
      final plan = PaperComposer.compose(
        candidates: [
          _candidate(id: 'q-school', source: 'school', quality: 0.5),
          _candidate(id: 'q-gaokao', source: 'gaokao', quality: 0.5),
        ],
        spec: const PaperSpec(targetCount: 2),
        readings: const [],
      );

      expect(plan.items.first.questionId, 'q-gaokao');
      expect(plan.items.first.zone, PaperZone.unknown);
    });

    test('candidate order in the input never changes the plan', () {
      final forward = PaperComposer.compose(
        candidates: [
          _candidate(id: 'q-a', points: ['kp-1']),
          _candidate(id: 'q-b', points: ['kp-2']),
          _candidate(id: 'q-c', points: ['kp-3']),
        ],
        spec: const PaperSpec(targetCount: 3),
        readings: const [],
      );
      final reversed = PaperComposer.compose(
        candidates: [
          _candidate(id: 'q-c', points: ['kp-3']),
          _candidate(id: 'q-b', points: ['kp-2']),
          _candidate(id: 'q-a', points: ['kp-1']),
        ],
        spec: const PaperSpec(targetCount: 3),
        readings: const [],
      );

      expect(reversed.items.map((item) => item.questionId).toList(),
          forward.items.map((item) => item.questionId).toList());
    });

    test('the per-knowledge-point cap is honoured', () {
      final plan = PaperComposer.compose(
        candidates: [
          _candidate(id: 'q-a', difficulty: 5),
          _candidate(id: 'q-b', difficulty: 6),
        ],
        spec: const PaperSpec(targetCount: 2, perKnowledgePointCap: 1),
        readings: [_reading('kp-1', danger: true)],
      );

      expect(plan.items, hasLength(1));
      expect(plan.byKnowledgePoint['kp-1'], 1);
      expect(plan.isShort, isTrue);
    });

    test('the default cap spreads a paper across the knowledge points', () {
      // 目标 4 道、有 4 个知识点 → 默认每点 1 道；q-5 是第 5 道（同点），
      // 按 id 排在 q-4 之后，所以正确的贪心应该在选中 4 个不同点后就停。
      final plan = PaperComposer.compose(
        candidates: [
          _candidate(id: 'q-1', points: ['kp-1']),
          _candidate(id: 'q-2', points: ['kp-2']),
          _candidate(id: 'q-3', points: ['kp-3']),
          _candidate(id: 'q-4', points: ['kp-4']),
          _candidate(id: 'q-5', points: ['kp-1']),
        ],
        spec: const PaperSpec(targetCount: 4),
        readings: const [],
      );

      expect(plan.items, hasLength(4));
      expect(plan.byKnowledgePoint['kp-1'], 1);
      expect(
          plan.byKnowledgePoint.keys.toSet(), {'kp-1', 'kp-2', 'kp-3', 'kp-4'});
    });

    test('a danger point with no candidates at all is reported as a gap', () {
      final plan = PaperComposer.compose(
        candidates: [
          _candidate(id: 'q-a', points: ['kp-other'])
        ],
        spec: const PaperSpec(targetCount: 3),
        readings: [
          _reading('kp-missing', danger: true),
          _reading('kp-other'),
        ],
      );

      // 用户口径：AI 不出题。凑不出来就如实报缺口，不用模型补。
      expect(plan.uncoveredKnowledgePointIds, ['kp-missing']);
      expect(plan.items.map((item) => item.knowledgePointId).toList(),
          ['kp-other']);
    });

    test('a weak point that lost the race is reported as deferred', () {
      final plan = PaperComposer.compose(
        candidates: [
          _candidate(id: 'q-danger', points: ['kp-d'], quality: 0.9),
          _candidate(id: 'q-dev', points: ['kp-dev'], quality: 0.9),
        ],
        spec: const PaperSpec(targetCount: 1),
        readings: [
          _reading('kp-d', danger: true),
          _reading('kp-dev', development: true),
        ],
      );

      expect(plan.items.map((item) => item.questionId).toList(), ['q-danger']);
      expect(plan.deferredKnowledgePointIds, ['kp-dev']);
      expect(plan.uncoveredKnowledgePointIds, isEmpty);
    });

    test('a missing reading counts as unknown, which beats healthy', () {
      final plan = PaperComposer.compose(
        candidates: [
          _candidate(id: 'q-healthy', points: ['kp-known'], quality: 0.5),
          _candidate(id: 'q-unknown', points: ['kp-unread'], quality: 0.5),
        ],
        spec: const PaperSpec(targetCount: 2),
        readings: [_reading('kp-known')],
      );

      expect(plan.items.first.questionId, 'q-unknown');
      expect(plan.items.first.zone, PaperZone.unknown);
      expect(paperNeedOf(null), kUnknownNeed);
      expect(kUnknownNeed, greaterThan(kHealthyNeed));
    });

    test('subject and source-level filters drop candidates before scoring', () {
      final plan = PaperComposer.compose(
        candidates: [
          _candidate(
              id: 'q-keep', subject: '数学', source: 'provincial_diagnostic'),
          _candidate(id: 'q-wrong-subject', subject: '语文', source: 'gaokao'),
          _candidate(id: 'q-too-low', subject: '数学', source: 'personal'),
        ],
        spec: const PaperSpec(
          targetCount: 5,
          subjectKeys: {'数学'},
          minSourceLevel: 'school',
        ),
        readings: const [],
      );

      expect(plan.candidateCount, 1);
      expect(plan.items.map((item) => item.questionId).toList(), ['q-keep']);
      expect(plan.isShort, isTrue);
    });

    test('target difficulty shifts the order without inventing questions', () {
      final plan = PaperComposer.compose(
        candidates: [
          _candidate(id: 'q-hard', difficulty: 10),
          _candidate(id: 'q-fitting', difficulty: 3),
        ],
        spec: const PaperSpec(targetCount: 2, targetDifficulty: 3),
        readings: const [],
      );

      expect(plan.items.first.questionId, 'q-fitting');
    });

    test('each item explains itself with reason, improvement and background',
        () {
      final plan = PaperComposer.compose(
        candidates: [
          _candidate(
            id: 'q-1',
            difficulty: 7,
            quality: 0.8,
            trap: '容易漏掉定义域',
          ),
        ],
        spec: const PaperSpec(targetCount: 1),
        readings: [
          _reading('kp-1', danger: true, priorR0: 0.42, priorConfidence: 0.5),
        ],
        knowledgePointNames: {'kp-1': '函数单调性'},
        knowledgePointTagPaths: {
          'kp-1': ['数学', '函数', '函数单调性'],
        },
      );

      final item = plan.items.single;
      expect(item.reasonZh, contains('函数单调性'));
      expect(item.reasonZh, contains('危险区'));
      expect(item.reasonZh, contains('R0≈0.42'));
      expect(item.reasonZh, contains('置信度 0.50'));
      expect(item.improvementNote, contains('容易漏掉定义域'));
      expect(item.backgroundZh, '数学 / 函数 / 函数单调性');
      expect(item.matchedKnowledgePointIds, ['kp-1']);
      expect(plan.overallNeed, kDangerNeed);
    });

    test('background falls back from tag path to name to id', () {
      final plan = PaperComposer.compose(
        candidates: [
          _candidate(id: 'q-path', points: ['kp-path']),
          _candidate(id: 'q-name', points: ['kp-name']),
          _candidate(id: 'q-id', points: ['kp-raw']),
          _candidate(id: 'q-none', points: const []),
        ],
        spec: const PaperSpec(targetCount: 4, perKnowledgePointCap: 1),
        readings: const [],
        knowledgePointNames: {'kp-name': '导数', 'kp-path': '不该用到'},
        knowledgePointTagPaths: {
          'kp-path': ['数学', '导数'],
        },
      );

      final byId = {
        for (final item in plan.items) item.questionId: item.backgroundZh,
      };
      expect(byId['q-path'], '数学 / 导数');
      expect(byId['q-name'], '导数');
      expect(byId['q-id'], 'kp-raw');
      expect(byId['q-none'], '未标注知识点');
    });

    test('an empty library yields an empty plan instead of throwing', () {
      final plan = PaperComposer.compose(
        candidates: const [],
        spec: const PaperSpec(targetCount: 5),
        readings: [_reading('kp-1', danger: true)],
      );

      expect(plan.isEmpty, isTrue);
      expect(plan.isShort, isTrue);
      expect(plan.overallNeed, 0);
      expect(plan.uncoveredKnowledgePointIds, ['kp-1']);
      expect(() => plan.toJson(), returnsNormally);
    });

    test('the plan serialises with rounded numbers and a schema tag', () {
      final plan = PaperComposer.compose(
        candidates: [_candidate(id: 'q-1', quality: 0.123456789)],
        spec: const PaperSpec(targetCount: 1),
        readings: [_reading('kp-1', danger: true)],
      );

      final json = plan.toJson();
      expect(json['schema'], 'mindnet.paper_plan/1');
      expect(json['requested_count'], 1);
      expect(json['is_short'], isFalse);
      final items = json['items'] as List<Object?>;
      final first = items.single as Map<String, Object?>;
      expect(first['score'], isA<double>());
      expect(first['score']! as double, closeTo(plan.items.single.score, 1e-6));
      expect(first['background'], isNotNull);
    });

    test('question tags resolve through the shared-tag rule (v12 questions)',
        () {
      // 题目→知识点：与 task 同一条规则（共享标签），只是对象类型换成 'question'。
      final links = [
        const ObjectTagLink(
          tagId: 'tag-math',
          objectType: 'knowledge_point',
          objectId: 'kp-1',
        ),
        const ObjectTagLink(
          tagId: 'tag-math',
          objectType: kQuestionObjectType,
          objectId: 'q-1',
        ),
        const ObjectTagLink(
          tagId: 'tag-orphan',
          objectType: kQuestionObjectType,
          objectId: 'q-orphan',
        ),
      ];
      final resolved = TaskKnowledgePointResolver.resolveFromTagLinks(
        links,
        sourceObjectType: kQuestionObjectType,
      );

      expect(resolved, {
        'q-1': ['kp-1'],
      });

      final plan = PaperComposer.compose(
        candidates: [
          _candidate(id: 'q-1', points: resolved['q-1']!),
          _candidate(id: 'q-orphan', points: const []),
        ],
        spec: const PaperSpec(targetCount: 2, perKnowledgePointCap: 1),
        readings: [_reading('kp-1', danger: true)],
      );

      expect(plan.items.first.matchedKnowledgePointIds, ['kp-1']);
      expect(plan.byKnowledgePoint['kp-1'], 1);
    });

    test(
        'preferred capability actions only nudge the order, they do not filter',
        () {
      final candidates = [
        _candidate(id: 'q-plain', points: const ['kp-1']),
        _candidate(id: 'q-hits', points: const ['kp-1'])
            .withActionTypes(const ['case_split']),
      ];
      final readings = [_reading('kp-1', danger: true)];

      // 没有画像：两道题同分，按 id 兜底（q-hits 先、q-plain 后 都无所谓，
      // 关键是分数相同 → 行为与历史一致）。
      final without = PaperComposer.compose(
        candidates: candidates,
        spec: const PaperSpec(targetCount: 2),
        readings: readings,
      );
      expect(
        without.items.map((item) => item.score).toSet(),
        hasLength(1),
        reason: '没有偏好时，命不命中一个字节都不影响',
      );
      expect(without.items.first.matchedPreferredActions, isEmpty);

      // 有画像：命中 case_split 的那道分数被抬起，排到前面；两道题都还在卷上。
      final withPreferred = PaperComposer.compose(
        candidates: candidates,
        spec: const PaperSpec(targetCount: 2),
        readings: readings,
        preferredActionTypes: const ['case_split'],
      );
      expect(withPreferred.items, hasLength(2));
      expect(withPreferred.items.first.questionId, 'q-hits');
      expect(
        withPreferred.items.first.score,
        greaterThan(withPreferred.items.last.score),
      );
      expect(withPreferred.items.first.matchedPreferredActions, ['case_split']);
      expect(withPreferred.items.first.reasonZh, contains('分类讨论'));
      expect(withPreferred.items.last.matchedPreferredActions, isEmpty);
    });

    test('two preferred actions: hitting both beats hitting one', () {
      final plan = PaperComposer.compose(
        candidates: [
          _candidate(id: 'q-one', points: const ['kp-1'])
              .withActionTypes(const ['case_split']),
          _candidate(id: 'q-two', points: const ['kp-1'])
              .withActionTypes(const ['case_split', 'sanity_check']),
        ],
        spec: const PaperSpec(targetCount: 2),
        readings: [_reading('kp-1', danger: true)],
        preferredActionTypes: const ['case_split', 'sanity_check'],
      );

      expect(plan.items.first.questionId, 'q-two');
      expect(plan.items.first.matchedPreferredActions,
          ['case_split', 'sanity_check']);
      expect(plan.items.last.matchedPreferredActions, ['case_split']);
      // 词表外的 key 不凭空变成中文名，原样留在理由里。
      expect(plan.items.first.reasonZh, contains('回代检验'));
    });
  });
}

/// 测试里给候选加"链上动作"的糖：`PaperCandidate` 是 const 值对象，
/// 没有 copyWith，就地重建一个。
extension on PaperCandidate {
  PaperCandidate withActionTypes(List<String> actionTypes) => PaperCandidate(
        questionId: questionId,
        subjectKey: subjectKey,
        sourceLevel: sourceLevel,
        questionType: questionType,
        difficulty: difficulty,
        aiQuality: aiQuality,
        trapNote: trapNote,
        matchedKnowledgePointIds: matchedKnowledgePointIds,
        actionTypes: actionTypes,
      );
}
