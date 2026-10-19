import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/domain/services/reasoning/daily_plan_step_destination.dart';
import 'package:furnace/domain/services/reasoning/daily_study_plan.dart';

DailyPlanStep _step(
  DailyPlanStepKind kind, {
  List<String> questionIds = const <String>[],
  List<String> knowledgePointIds = const <String>[],
  int? cardCount,
  String? actionType,
}) {
  return DailyPlanStep(
    kind: kind,
    priority: 100,
    titleZh: '标题',
    detailZh: '说明',
    estimatedMinutes: 1,
    actionType: actionType,
    knowledgePointIds: knowledgePointIds,
    questionIds: questionIds,
    cardCount: cardCount,
  );
}

void main() {
  group('练习步骤（practiceQuestions）', () {
    test('有题号时去练习页并带题号', () {
      final destination = destinationOf(
        _step(DailyPlanStepKind.practiceQuestions,
            questionIds: const <String>['q1', 'q2']),
      );
      expect(destination.kind, DailyPlanDestinationKind.practiceQuestions);
      expect(destination.isNavigable, isTrue);
      expect(destination.questionIds, <String>['q1', 'q2']);
      expect(destination.cardCount, isNull);
      expect(destination.actionType, isNull);
    });

    test('没有题号时不可导航，但 kind 如实保留', () {
      final destination =
          destinationOf(_step(DailyPlanStepKind.practiceQuestions));
      expect(destination.kind, DailyPlanDestinationKind.practiceQuestions);
      expect(destination.isNavigable, isFalse);
      expect(destination.questionIds, isEmpty);
    });

    test('全是空白题号时不可导航', () {
      final destination = destinationOf(
        _step(
          DailyPlanStepKind.practiceQuestions,
          questionIds: const <String>['', '   ', '\t'],
        ),
      );
      expect(destination.isNavigable, isFalse);
      expect(destination.questionIds, isEmpty);
    });

    test('题号 trim、去空、去重且保持首次出现顺序', () {
      final destination = destinationOf(
        _step(
          DailyPlanStepKind.practiceQuestions,
          questionIds: const <String>[' q2 ', 'q1', 'q2', '', ' q1'],
        ),
      );
      expect(destination.questionIds, <String>['q2', 'q1']);
      expect(destination.isNavigable, isTrue);
    });

    test('不夹带步骤上的到期卡片数与动作 key', () {
      final destination = destinationOf(
        _step(
          DailyPlanStepKind.practiceQuestions,
          questionIds: const <String>['q1'],
          cardCount: 9,
          actionType: 'case_split',
        ),
      );
      expect(destination.cardCount, isNull);
      expect(destination.actionType, isNull);
    });

    test('知识点不是题号：只有知识点时不可导航', () {
      final destination = destinationOf(
        _step(
          DailyPlanStepKind.practiceQuestions,
          knowledgePointIds: const <String>['kp1', 'kp2'],
        ),
      );
      expect(destination.isNavigable, isFalse);
      expect(destination.questionIds, isEmpty);
    });

    test('questionIds 不可变', () {
      final destination = DailyPlanStepDestination(
        kind: DailyPlanDestinationKind.practiceQuestions,
        questionIds: const <String>['q1'],
      );
      expect(() => destination.questionIds.add('q2'), throwsUnsupportedError);
    });

    test('构造后修改输入列表不影响目标', () {
      final source = <String>['q1', 'q2'];
      final destination = DailyPlanStepDestination(
        kind: DailyPlanDestinationKind.practiceQuestions,
        questionIds: source,
      );
      source.add('q3');
      expect(destination.questionIds, <String>['q1', 'q2']);
    });
  });

  group('复习到期卡片（reviewDueCards → ankiReview）', () {
    test('正数卡片数时去复习队列并带卡片数', () {
      final destination = destinationOf(
        _step(DailyPlanStepKind.reviewDueCards, cardCount: 3),
      );
      expect(destination.kind, DailyPlanDestinationKind.ankiReview);
      expect(destination.isNavigable, isTrue);
      expect(destination.cardCount, 3);
      expect(destination.questionIds, isEmpty);
      expect(destination.actionType, isNull);
    });

    test('一张卡片也可导航', () {
      final destination = destinationOf(
        _step(DailyPlanStepKind.reviewDueCards, cardCount: 1),
      );
      expect(destination.isNavigable, isTrue);
      expect(destination.cardCount, 1);
    });

    test('cardCount 为 null 时不可导航', () {
      final destination =
          destinationOf(_step(DailyPlanStepKind.reviewDueCards));
      expect(destination.kind, DailyPlanDestinationKind.ankiReview);
      expect(destination.isNavigable, isFalse);
      expect(destination.cardCount, isNull);
    });

    test('cardCount 为 0 时不可导航且如实保留 0', () {
      final destination = destinationOf(
        _step(DailyPlanStepKind.reviewDueCards, cardCount: 0),
      );
      expect(destination.isNavigable, isFalse);
      expect(destination.cardCount, 0);
    });

    test('cardCount 为负数时不可导航且如实保留', () {
      final destination = destinationOf(
        _step(DailyPlanStepKind.reviewDueCards, cardCount: -2),
      );
      expect(destination.isNavigable, isFalse);
      expect(destination.cardCount, -2);
    });

    test('不夹带题号与动作 key', () {
      final destination = destinationOf(
        _step(
          DailyPlanStepKind.reviewDueCards,
          cardCount: 2,
          questionIds: const <String>['q1'],
          actionType: 'case_split',
        ),
      );
      expect(destination.questionIds, isEmpty);
      expect(destination.actionType, isNull);
    });
  });

  group('补齐思维链（collectChains）', () {
    test('带动作 key 去题库 / 搜索页', () {
      final destination = destinationOf(
        _step(DailyPlanStepKind.collectChains, actionType: 'case_split'),
      );
      expect(destination.kind, DailyPlanDestinationKind.collectChains);
      expect(destination.isNavigable, isTrue);
      expect(destination.actionType, 'case_split');
      expect(destination.questionIds, isEmpty);
      expect(destination.cardCount, isNull);
    });

    test('没有动作 key 也可导航', () {
      final destination = destinationOf(_step(DailyPlanStepKind.collectChains));
      expect(destination.isNavigable, isTrue);
      expect(destination.actionType, isNull);
    });

    test('动作 key 原样透传（不 trim、不猜默认值）', () {
      final destination = destinationOf(
        _step(DailyPlanStepKind.collectChains, actionType: ' case_split '),
      );
      expect(destination.actionType, ' case_split ');
    });

    test('不夹带题号与卡片数', () {
      final destination = destinationOf(
        _step(
          DailyPlanStepKind.collectChains,
          questionIds: const <String>['q1'],
          cardCount: 4,
        ),
      );
      expect(destination.questionIds, isEmpty);
      expect(destination.cardCount, isNull);
    });
  });

  group('补能力动作词表（reviewVocabulary → vocabulary）', () {
    test('去能力动作词表页', () {
      final destination =
          destinationOf(_step(DailyPlanStepKind.reviewVocabulary));
      expect(destination.kind, DailyPlanDestinationKind.vocabulary);
      expect(destination.isNavigable, isTrue);
      expect(destination.questionIds, isEmpty);
      expect(destination.cardCount, isNull);
      expect(destination.actionType, isNull);
    });

    test('不猜动作：步骤上的 actionType 不传到目标', () {
      final destination = destinationOf(
        _step(
          DailyPlanStepKind.reviewVocabulary,
          actionType: 'mystery_move',
          cardCount: 2,
          questionIds: const <String>['q1'],
        ),
      );
      expect(destination.actionType, isNull);
      expect(destination.cardCount, isNull);
      expect(destination.questionIds, isEmpty);
    });
  });

  group('继续保持与没有数据', () {
    test('keepGoing 不可导航（只是节奏，不是任务）', () {
      final destination = destinationOf(_step(DailyPlanStepKind.keepGoing));
      expect(destination.kind, DailyPlanDestinationKind.keepGoing);
      expect(destination.isNavigable, isFalse);
    });

    test('keepGoing 带卡片数也不可导航', () {
      final destination = destinationOf(
        _step(DailyPlanStepKind.keepGoing, cardCount: 5),
      );
      expect(destination.isNavigable, isFalse);
      expect(destination.cardCount, isNull);
    });

    test('noData 映射为 none 且不可导航', () {
      final destination = destinationOf(_step(DailyPlanStepKind.noData));
      expect(destination.kind, DailyPlanDestinationKind.none);
      expect(destination.isNavigable, isFalse);
    });

    test('手动构造 none 即使带题号也不可导航', () {
      final destination = DailyPlanStepDestination(
        kind: DailyPlanDestinationKind.none,
        questionIds: const <String>['q1'],
      );
      expect(destination.isNavigable, isFalse);
    });
  });

  group('值语义', () {
    test('同字段相等且 hashCode 相同', () {
      final a = DailyPlanStepDestination(
        kind: DailyPlanDestinationKind.ankiReview,
        cardCount: 3,
      );
      final b = DailyPlanStepDestination(
        kind: DailyPlanDestinationKind.ankiReview,
        cardCount: 3,
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('归一化后等价：重复题号与单个题号相等', () {
      final a = DailyPlanStepDestination(
        kind: DailyPlanDestinationKind.practiceQuestions,
        questionIds: const <String>['q1', 'q1'],
      );
      final b = DailyPlanStepDestination(
        kind: DailyPlanDestinationKind.practiceQuestions,
        questionIds: const <String>[' q1 '],
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('自身与自身相等', () {
      final destination = DailyPlanStepDestination(
        kind: DailyPlanDestinationKind.collectChains,
      );
      expect(destination == destination, isTrue);
    });

    test('不同 kind 不相等', () {
      final a = DailyPlanStepDestination(
        kind: DailyPlanDestinationKind.keepGoing,
      );
      final b = DailyPlanStepDestination(
        kind: DailyPlanDestinationKind.none,
      );
      expect(a, isNot(b));
    });

    test('题号顺序不同不相等', () {
      final a = DailyPlanStepDestination(
        kind: DailyPlanDestinationKind.practiceQuestions,
        questionIds: const <String>['q1', 'q2'],
      );
      final b = DailyPlanStepDestination(
        kind: DailyPlanDestinationKind.practiceQuestions,
        questionIds: const <String>['q2', 'q1'],
      );
      expect(a, isNot(b));
    });

    test('卡片数不同不相等（含 null）', () {
      final a = DailyPlanStepDestination(
        kind: DailyPlanDestinationKind.ankiReview,
        cardCount: 3,
      );
      final b = DailyPlanStepDestination(
        kind: DailyPlanDestinationKind.ankiReview,
        cardCount: 4,
      );
      final c = DailyPlanStepDestination(
        kind: DailyPlanDestinationKind.ankiReview,
      );
      expect(a, isNot(b));
      expect(a, isNot(c));
    });

    test('动作 key 不同不相等', () {
      final a = DailyPlanStepDestination(
        kind: DailyPlanDestinationKind.collectChains,
        actionType: 'case_split',
      );
      final b = DailyPlanStepDestination(
        kind: DailyPlanDestinationKind.collectChains,
        actionType: 'induction',
      );
      expect(a, isNot(b));
    });

    test('相等的目标在 Set 里只保留一个', () {
      final set = <DailyPlanStepDestination>{
        DailyPlanStepDestination(
          kind: DailyPlanDestinationKind.practiceQuestions,
          questionIds: const <String>['q1'],
        ),
        DailyPlanStepDestination(
          kind: DailyPlanDestinationKind.practiceQuestions,
          questionIds: const <String>['q1', 'q1'],
        ),
      };
      expect(set.length, 1);
    });
  });

  group('JSON', () {
    test('练习目标固定键序', () {
      final json = destinationOf(
        _step(DailyPlanStepKind.practiceQuestions,
            questionIds: const <String>['q1']),
      ).toJson();
      expect(
        json.keys.toList(),
        orderedEquals(<String>[
          'kind',
          'question_ids',
          'card_count',
          'action_type',
          'is_navigable',
        ]),
      );
      expect(json['kind'], 'practiceQuestions');
      expect(json['question_ids'], <String>['q1']);
      expect(json['card_count'], isNull);
      expect(json['action_type'], isNull);
      expect(json['is_navigable'], isTrue);
    });

    test('复习目标 JSON 值', () {
      final json = destinationOf(
        _step(DailyPlanStepKind.reviewDueCards, cardCount: 5),
      ).toJson();
      expect(json['kind'], 'ankiReview');
      expect(json['question_ids'], isEmpty);
      expect(json['card_count'], 5);
      expect(json['action_type'], isNull);
      expect(json['is_navigable'], isTrue);
    });

    test('补齐思维链目标 JSON 值', () {
      final json = destinationOf(
        _step(DailyPlanStepKind.collectChains, actionType: 'case_split'),
      ).toJson();
      expect(json['kind'], 'collectChains');
      expect(json['action_type'], 'case_split');
      expect(json['is_navigable'], isTrue);
    });

    test('词表目标 JSON 值', () {
      final json = destinationOf(
        _step(DailyPlanStepKind.reviewVocabulary),
      ).toJson();
      expect(json['kind'], 'vocabulary');
      expect(json['is_navigable'], isTrue);
    });

    test('keepGoing 与 noData 的 JSON 值', () {
      final keepJson = destinationOf(
        _step(DailyPlanStepKind.keepGoing),
      ).toJson();
      expect(keepJson['kind'], 'keepGoing');
      expect(keepJson['is_navigable'], isFalse);
      final noneJson = destinationOf(_step(DailyPlanStepKind.noData)).toJson();
      expect(noneJson['kind'], 'none');
      expect(noneJson['is_navigable'], isFalse);
    });

    test('不可导航的练习目标 JSON 也如实标记', () {
      final json =
          destinationOf(_step(DailyPlanStepKind.practiceQuestions)).toJson();
      expect(json['kind'], 'practiceQuestions');
      expect(json['question_ids'], isEmpty);
      expect(json['is_navigable'], isFalse);
    });

    test('toJson 的 question_ids 是副本，修改它不影响目标', () {
      final destination = destinationOf(
        _step(DailyPlanStepKind.practiceQuestions,
            questionIds: const <String>['q1']),
      );
      final json = destination.toJson();
      final ids = json['question_ids']! as List<String>;
      ids.add('q9');
      expect(destination.questionIds, <String>['q1']);
    });

    test('可被 jsonEncode 序列化', () {
      final json = destinationOf(
        _step(DailyPlanStepKind.reviewDueCards, cardCount: 2),
      ).toJson();
      final encoded = jsonEncode(json);
      final decoded = jsonDecode(encoded) as Map<String, Object?>;
      expect(decoded['kind'], 'ankiReview');
      expect(decoded['card_count'], 2);
    });
  });

  group('确定性与映射表', () {
    test('同一输入两次调用结果相同', () {
      final step = _step(
        DailyPlanStepKind.practiceQuestions,
        questionIds: const <String>['q1', 'q2'],
      );
      final first = destinationOf(step);
      final second = destinationOf(step);
      expect(first, second);
      expect(first.hashCode, second.hashCode);
      expect(first.toJson(), second.toJson());
    });

    test('六个步骤种类都映射到预期目标与可导航性', () {
      final cases = <(DailyPlanStepKind, DailyPlanDestinationKind, bool)>[
        (
          DailyPlanStepKind.practiceQuestions,
          DailyPlanDestinationKind.practiceQuestions,
          true,
        ),
        (
          DailyPlanStepKind.reviewDueCards,
          DailyPlanDestinationKind.ankiReview,
          true,
        ),
        (
          DailyPlanStepKind.collectChains,
          DailyPlanDestinationKind.collectChains,
          true,
        ),
        (
          DailyPlanStepKind.reviewVocabulary,
          DailyPlanDestinationKind.vocabulary,
          true,
        ),
        (
          DailyPlanStepKind.keepGoing,
          DailyPlanDestinationKind.keepGoing,
          false,
        ),
        (DailyPlanStepKind.noData, DailyPlanDestinationKind.none, false),
      ];
      for (final (stepKind, destinationKind, navigable) in cases) {
        final destination = destinationOf(
          _step(
            stepKind,
            questionIds: const <String>['q1'],
            cardCount: 3,
            actionType: 'case_split',
          ),
        );
        expect(destination.kind, destinationKind,
            reason: 'stepKind: $stepKind');
        expect(
          destination.isNavigable,
          navigable,
          reason: 'stepKind: $stepKind',
        );
      }
    });

    test('映射不修改原步骤的题号 / 卡片数', () {
      final step = _step(
        DailyPlanStepKind.practiceQuestions,
        questionIds: const <String>['q2', 'q2', ' q1 '],
      );
      destinationOf(step);
      expect(step.questionIds, <String>['q2', 'q2', ' q1 ']);
    });
  });
}
