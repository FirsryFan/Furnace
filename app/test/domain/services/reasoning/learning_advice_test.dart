// 学习建议聚合：只基于真读数，把洞察 / 画像变成确定性建议清单。
// 口径见 docs/REASONING_LAYER_DESIGN.md §15。

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/domain/services/reasoning/capability_profile.dart';
import 'package:furnace/domain/services/reasoning/chain_insights.dart';
import 'package:furnace/domain/services/reasoning/learning_advice.dart';

ChainInsightStep riskyStep(
  String actionType, {
  int index = 0,
  double risk = 0.9,
}) {
  return ChainInsightStep(
    actionType: actionType,
    index: index,
    stuckRisk: risk,
  );
}

List<ChainInsightStep> stepsFor(
  String actionType,
  int count, {
  int start = 0,
  double risk = 0.9,
}) {
  return <ChainInsightStep>[
    for (var i = 0; i < count; i++)
      ChainInsightStep(
        actionType: actionType,
        index: start + i,
        stuckRisk: risk,
      ),
  ];
}

ChainInsightChain chainOf(
  String chainId, {
  String questionId = 'q1',
  List<ChainInsightStep> steps = const <ChainInsightStep>[],
}) {
  return ChainInsightChain(
    chainId: chainId,
    questionId: questionId,
    steps: steps,
  );
}

ChainInsights aggregateOf(Iterable<ChainInsightChain> chains) {
  return ChainInsights.aggregate(chains: chains);
}

CapabilityReading readingOf(
  String actionType, {
  String? label,
  bool known = true,
  int stepCount = 3,
  int riskyStepCount = 3,
  double? avgStuckRisk = 0.8,
}) {
  return CapabilityReading(
    actionType: actionType,
    label: label ?? actionType,
    known: known,
    stepCount: stepCount,
    riskyStepCount: riskyStepCount,
    avgStuckRisk: avgStuckRisk,
  );
}

LearningAdvicePlan planFor(
  ChainInsights insights, {
  List<CapabilityReading> profile = const <CapabilityReading>[],
  int highRiskMinSteps = 3,
  int maxAdvices = 5,
  int? corpusQuestionCount,
}) {
  return LearningAdvicePlan.build(
    insights: insights,
    profile: profile,
    highRiskMinSteps: highRiskMinSteps,
    maxAdvices: maxAdvices,
    corpusQuestionCount: corpusQuestionCount,
  );
}

List<LearningAdviceKind> kindsOf(LearningAdvicePlan plan) {
  return <LearningAdviceKind>[for (final advice in plan.advices) advice.kind];
}

void main() {
  group('枚举与序列化契约', () {
    test('LearningAdviceKind 枚举顺序固定（排序的同类兜底依据）', () {
      expect(
        LearningAdviceKind.values.map((kind) => kind.name).toList(),
        <String>[
          'practiceAction',
          'collectChains',
          'reviewVocabulary',
          'keepGoing',
          'noData',
        ],
      );
    });

    test('LearningAdvice.toJson 字段完整且使用 snake_case', () {
      final advice = LearningAdvice(
        kind: LearningAdviceKind.practiceAction,
        priority: 101,
        titleZh: '练「分类讨论」',
        detailZh: '细节',
        actionType: 'case_split',
        actionLabelZh: '分类讨论',
        questionCount: 2,
        stepCount: 4,
        highRiskStepCount: 3,
        knowledgePointIds: const <String>['kp_a', 'kp_b'],
      );
      final json = advice.toJson();
      expect(json.keys.toSet(), <String>{
        'kind',
        'priority',
        'title_zh',
        'detail_zh',
        'action_type',
        'action_label_zh',
        'question_count',
        'step_count',
        'high_risk_step_count',
        'knowledge_point_ids',
      });
      expect(json['kind'], 'practiceAction');
      expect(json['priority'], 101);
      expect(json['action_type'], 'case_split');
      expect(json['action_label_zh'], '分类讨论');
      expect(json['question_count'], 2);
      expect(json['step_count'], 4);
      expect(json['high_risk_step_count'], 3);
      expect(json['knowledge_point_ids'], <String>['kp_a', 'kp_b']);
      expect(() => jsonEncode(advice.toJson()), returnsNormally);
    });

    test('LearningAdvice 的 knowledgePointIds 不可变', () {
      final advice = LearningAdvice(
        kind: LearningAdviceKind.practiceAction,
        priority: 100,
        titleZh: '标题',
        detailZh: '细节',
        knowledgePointIds: const <String>['kp_a'],
      );
      expect(
        () => advice.knowledgePointIds.add('kp_b'),
        throwsUnsupportedError,
      );
    });

    test('LearningAdvicePlan.empty 是显式空态', () {
      final plan = LearningAdvicePlan.empty();
      expect(plan.advices, isEmpty);
      expect(plan.isEmpty, isTrue);
      expect(plan.isNotEmpty, isFalse);
      expect(plan.length, 0);
      expect(plan.toJson()['advice_count'], 0);
      expect(plan.toJson()['is_empty'], true);
    });

    test('LearningAdvicePlan.toJson 列出每条建议', () {
      final plan = planFor(aggregateOf(const <ChainInsightChain>[]));
      final json = plan.toJson();
      expect(json.keys.toSet(), <String>{
        'advice_count',
        'is_empty',
        'advices',
      });
      expect(json['advice_count'], 1);
      expect(json['is_empty'], false);
      expect(json['advices'], isA<List<Object?>>());
      expect(() => jsonEncode(json), returnsNormally);
    });

    test('plan.advices 不可变', () {
      final plan = planFor(aggregateOf(const <ChainInsightChain>[]));
      expect(
        () => plan.advices.add(
          LearningAdvice(
            kind: LearningAdviceKind.noData,
            priority: 999,
            titleZh: '附加',
            detailZh: '附加',
          ),
        ),
        throwsUnsupportedError,
      );
    });
  });

  group('空输入与 noData', () {
    test('完全空输入返回一条 noData，不抛异常', () {
      final plan = planFor(aggregateOf(const <ChainInsightChain>[]));
      expect(plan.advices, hasLength(1));
      expect(plan.isEmpty, isFalse);
      final advice = plan.advices.single;
      expect(advice.kind, LearningAdviceKind.noData);
      expect(advice.priority, 500);
      expect(advice.titleZh, contains('没有'));
      expect(advice.actionType, isNull);
      expect(advice.actionLabelZh, isNull);
      expect(advice.questionCount, isNull);
      expect(advice.stepCount, isNull);
      expect(advice.highRiskStepCount, isNull);
      expect(advice.knowledgePointIds, isEmpty);
      expect(advice.detailZh, contains('没有传题库题数'));
    });

    test('空输入 + 题库 0 题：noData 说明题库也还没有题', () {
      final plan = planFor(
        aggregateOf(const <ChainInsightChain>[]),
        corpusQuestionCount: 0,
      );
      final advice = plan.advices.single;
      expect(advice.kind, LearningAdviceKind.noData);
      expect(advice.detailZh, contains('题库里也还没有题目'));
    });

    test('空输入 + 题库 10 题：先给 collectChains，而不是 noData', () {
      final plan = planFor(
        aggregateOf(const <ChainInsightChain>[]),
        corpusQuestionCount: 10,
      );
      expect(plan.advices, hasLength(1));
      final advice = plan.advices.single;
      expect(advice.kind, LearningAdviceKind.collectChains);
      expect(advice.priority, 200);
      expect(advice.questionCount, 10);
      expect(advice.detailZh, contains('10 道题'));
      expect(advice.detailZh, contains('还没有任何解题链'));
      expect(kindsOf(plan), isNot(contains(LearningAdviceKind.noData)));
    });

    test('题库题数传负数按 0 处理，空输入仍是 noData', () {
      final plan = planFor(
        aggregateOf(const <ChainInsightChain>[]),
        corpusQuestionCount: -5,
      );
      expect(plan.advices.single.kind, LearningAdviceKind.noData);
    });

    test('空输入不会虚构题目数/步数', () {
      final plan = planFor(aggregateOf(const <ChainInsightChain>[]));
      final advice = plan.advices.single;
      expect(advice.questionCount, isNull);
      expect(advice.stepCount, isNull);
      expect(advice.highRiskStepCount, isNull);
      expect(advice.toJson()['question_count'], isNull);
    });
  });

  group('practiceAction 触发条件与阈值', () {
    test('默认阈值 3：恰好 3 个高风险步给练习建议并写清真实读数', () {
      final insights = aggregateOf(<ChainInsightChain>[
        chainOf(
          'c1',
          steps: <ChainInsightStep>[
            ...stepsFor('case_split', 3),
            riskyStep('case_split', index: 10, risk: 0.1),
          ],
        ),
      ]);
      final plan = planFor(insights);
      expect(plan.advices, hasLength(1));
      final advice = plan.advices.single;
      expect(advice.kind, LearningAdviceKind.practiceAction);
      expect(advice.priority, 100);
      expect(advice.actionType, 'case_split');
      expect(advice.actionLabelZh, '分类讨论');
      expect(advice.questionCount, 1);
      expect(advice.stepCount, 4);
      expect(advice.highRiskStepCount, 3);
      expect(advice.titleZh, contains('分类讨论'));
      expect(advice.detailZh, contains('4 步'));
      expect(advice.detailZh, contains('1 道题'));
      expect(advice.detailZh, contains('3 步高风险'));
      expect(advice.detailZh, isNot(contains('肯定能提高')));
    });

    test('默认阈值 3：2 个高风险步不够，回到 keepGoing', () {
      final insights = aggregateOf(<ChainInsightChain>[
        chainOf('c1', steps: stepsFor('case_split', 2)),
      ]);
      final plan = planFor(insights);
      expect(kindsOf(plan), <LearningAdviceKind>[LearningAdviceKind.keepGoing]);
    });

    test('自定义阈值 5：5 个高风险步给练习建议', () {
      final insights = aggregateOf(<ChainInsightChain>[
        chainOf('c1', steps: stepsFor('case_split', 5)),
      ]);
      final plan = planFor(insights, highRiskMinSteps: 5);
      expect(kindsOf(plan),
          <LearningAdviceKind>[LearningAdviceKind.practiceAction]);
      expect(plan.advices.single.highRiskStepCount, 5);
      expect(plan.advices.single.detailZh, contains('阈值 5 步'));
    });

    test('自定义阈值 5：4 个高风险步不够', () {
      final insights = aggregateOf(<ChainInsightChain>[
        chainOf('c1', steps: stepsFor('case_split', 4)),
      ]);
      final plan = planFor(insights, highRiskMinSteps: 5);
      expect(kindsOf(plan), <LearningAdviceKind>[LearningAdviceKind.keepGoing]);
    });

    test('阈值 0 按 1 处理（1 个高风险步也够格）', () {
      final insights = aggregateOf(<ChainInsightChain>[
        chainOf('c1', steps: stepsFor('case_split', 1)),
      ]);
      final plan = planFor(insights, highRiskMinSteps: 0);
      expect(kindsOf(plan),
          <LearningAdviceKind>[LearningAdviceKind.practiceAction]);
    });

    test('阈值负数按 1 处理（1 个高风险步也够格）', () {
      final insights = aggregateOf(<ChainInsightChain>[
        chainOf('c1', steps: stepsFor('case_split', 1)),
      ]);
      final plan = planFor(insights, highRiskMinSteps: -3);
      expect(kindsOf(plan),
          <LearningAdviceKind>[LearningAdviceKind.practiceAction]);
    });

    test('跨两道题的读数如实进 advice 字段', () {
      final insights = aggregateOf(<ChainInsightChain>[
        chainOf('c1', questionId: 'q1', steps: stepsFor('case_split', 3)),
        chainOf(
          'c2',
          questionId: 'q2',
          steps: stepsFor('case_split', 1, start: 10, risk: 0.1),
        ),
      ]);
      final plan = planFor(insights);
      final advice = plan.advices.single;
      expect(advice.questionCount, 2);
      expect(advice.stepCount, 4);
      expect(advice.highRiskStepCount, 3);
      expect(advice.detailZh, contains('2 道题'));
    });

    test('多个练习建议按高风险步数降序编号', () {
      final insights = aggregateOf(<ChainInsightChain>[
        chainOf(
          'c1',
          steps: <ChainInsightStep>[
            ...stepsFor('case_split', 3),
            ...stepsFor('induction', 5, start: 10),
          ],
        ),
      ]);
      final plan = planFor(insights);
      expect(plan.advices, hasLength(2));
      expect(plan.advices[0].actionType, 'induction');
      expect(plan.advices[0].priority, 100);
      expect(plan.advices[1].actionType, 'case_split');
      expect(plan.advices[1].priority, 101);
    });

    test('高风险步数相同时按 actionType 字典序编号', () {
      final insights = aggregateOf(<ChainInsightChain>[
        chainOf(
          'c1',
          steps: <ChainInsightStep>[
            ...stepsFor('case_split', 3),
            ...stepsFor('analogy_transfer', 3, start: 10),
          ],
        ),
      ]);
      final plan = planFor(insights);
      expect(
        <String?>[for (final advice in plan.advices) advice.actionType],
        <String>['analogy_transfer', 'case_split'],
      );
      expect(plan.advices[0].priority, 100);
      expect(plan.advices[1].priority, 101);
    });

    test('未知动作即使高风险也不进练习建议', () {
      final insights = aggregateOf(<ChainInsightChain>[
        chainOf('c1', steps: stepsFor('mystery_move', 3)),
      ]);
      final plan = planFor(insights);
      expect(kindsOf(plan),
          <LearningAdviceKind>[LearningAdviceKind.reviewVocabulary]);
      expect(plan.advices.single.actionType, isNull);
      expect(insights.unknownActions, hasLength(1));
    });
  });

  group('能力动作画像作为补充证据', () {
    test('画像里有足够高风险步给练习建议，题数如实留空', () {
      final plan = planFor(
        aggregateOf(const <ChainInsightChain>[]),
        profile: <CapabilityReading>[
          readingOf('case_split',
              label: '分类讨论', stepCount: 5, riskyStepCount: 3),
        ],
      );
      expect(plan.advices, hasLength(1));
      final advice = plan.advices.single;
      expect(advice.kind, LearningAdviceKind.practiceAction);
      expect(advice.actionType, 'case_split');
      expect(advice.actionLabelZh, '分类讨论');
      expect(advice.stepCount, 5);
      expect(advice.highRiskStepCount, 3);
      expect(advice.questionCount, isNull);
      expect(advice.detailZh, contains('题目数暂无读数'));
    });

    test('画像读数未达阈值时给 keepGoing，不编练习建议', () {
      final plan = planFor(
        aggregateOf(const <ChainInsightChain>[]),
        profile: <CapabilityReading>[
          readingOf('case_split', stepCount: 2, riskyStepCount: 2),
        ],
      );
      expect(kindsOf(plan), <LearningAdviceKind>[LearningAdviceKind.keepGoing]);
      expect(plan.advices.single.detailZh, contains('能力动作画像'));
    });

    test('同一动作同时出现在洞察与画像时只给一条，优先用洞察读数', () {
      final insights = aggregateOf(<ChainInsightChain>[
        chainOf('c1', steps: stepsFor('case_split', 3)),
      ]);
      final plan = planFor(
        insights,
        profile: <CapabilityReading>[
          readingOf('case_split', stepCount: 9, riskyStepCount: 5),
        ],
      );
      expect(plan.advices, hasLength(1));
      final advice = plan.advices.single;
      expect(advice.kind, LearningAdviceKind.practiceAction);
      expect(advice.stepCount, 3);
      expect(advice.highRiskStepCount, 3);
      expect(advice.questionCount, 1);
    });

    test('画像里的未知动作不进练习建议', () {
      final plan = planFor(
        aggregateOf(const <ChainInsightChain>[]),
        profile: <CapabilityReading>[
          readingOf('mystery_move',
              known: false, stepCount: 3, riskyStepCount: 3),
        ],
      );
      expect(kindsOf(plan), <LearningAdviceKind>[LearningAdviceKind.keepGoing]);
    });

    test('画像补充的风险动作与洞察里的未知动作各给一条', () {
      final insights = aggregateOf(<ChainInsightChain>[
        chainOf('c1', steps: stepsFor('mystery_move', 1)),
      ]);
      final plan = planFor(
        insights,
        profile: <CapabilityReading>[
          readingOf('case_split',
              label: '分类讨论', stepCount: 3, riskyStepCount: 3),
        ],
      );
      expect(
        kindsOf(plan),
        <LearningAdviceKind>[
          LearningAdviceKind.practiceAction,
          LearningAdviceKind.reviewVocabulary,
        ],
      );
    });

    test('不传 profile 与显式传空列表行为一致', () {
      final insights = aggregateOf(<ChainInsightChain>[
        chainOf('c1', steps: stepsFor('case_split', 3)),
      ]);
      final withoutProfile = planFor(insights);
      final emptyProfile =
          planFor(insights, profile: const <CapabilityReading>[]);
      expect(
        emptyProfile.toJson(),
        withoutProfile.toJson(),
      );
    });

    test('画像里无效的 riskyStepCount（负数）不触发练习建议', () {
      final plan = planFor(
        aggregateOf(const <ChainInsightChain>[]),
        profile: <CapabilityReading>[
          readingOf('case_split', stepCount: 0, riskyStepCount: -1),
        ],
      );
      expect(kindsOf(plan), <LearningAdviceKind>[LearningAdviceKind.keepGoing]);
    });
  });

  group('collectChains（有题缺链）', () {
    test('题库题数大于洞察覆盖题数时给 collectChains 并写清缺口', () {
      final insights = aggregateOf(<ChainInsightChain>[
        chainOf('c1', steps: stepsFor('case_split', 3)),
      ]);
      final plan = planFor(insights, corpusQuestionCount: 10);
      expect(
        kindsOf(plan),
        <LearningAdviceKind>[
          LearningAdviceKind.practiceAction,
          LearningAdviceKind.collectChains,
        ],
      );
      final collect = plan.advices[1];
      expect(collect.priority, 200);
      expect(collect.questionCount, 10);
      expect(collect.detailZh, contains('10 道题'));
      expect(collect.detailZh, contains('1 道题'));
      expect(collect.detailZh, contains('9 道题没有解题链'));
    });

    test('题库题数等于覆盖题数时不给 collectChains', () {
      final insights = aggregateOf(<ChainInsightChain>[
        chainOf('c1', steps: stepsFor('case_split', 3)),
      ]);
      final plan = planFor(insights, corpusQuestionCount: 1);
      expect(kindsOf(plan),
          <LearningAdviceKind>[LearningAdviceKind.practiceAction]);
    });

    test('题库题数小于覆盖题数（数据不一致）时不虚构缺口', () {
      final insights = aggregateOf(<ChainInsightChain>[
        chainOf('c1', questionId: 'q1', steps: stepsFor('case_split', 3)),
        chainOf(
          'c2',
          questionId: 'q2',
          steps: stepsFor('case_split', 1, start: 10, risk: 0.1),
        ),
      ]);
      expect(insights.questionCount, 2);
      final plan = planFor(insights, corpusQuestionCount: 1);
      expect(kindsOf(plan), isNot(contains(LearningAdviceKind.collectChains)));
    });

    test('有题缺链但没有任何链时只给 collectChains，不给 keepGoing', () {
      final plan = planFor(
        aggregateOf(const <ChainInsightChain>[]),
        corpusQuestionCount: 3,
      );
      expect(kindsOf(plan),
          <LearningAdviceKind>[LearningAdviceKind.collectChains]);
    });

    test('不传题库题数就绝不产出 collectChains', () {
      final plan = planFor(aggregateOf(const <ChainInsightChain>[]));
      expect(kindsOf(plan), <LearningAdviceKind>[LearningAdviceKind.noData]);
    });
  });

  group('reviewVocabulary（词表外动作）', () {
    test('两个未知动作合成一条建议，原串原样列出', () {
      final insights = aggregateOf(<ChainInsightChain>[
        chainOf(
          'c1',
          steps: <ChainInsightStep>[
            riskyStep('mystery_one', index: 0),
            riskyStep('mystery_two', index: 1),
          ],
        ),
      ]);
      final plan = planFor(insights);
      expect(plan.advices, hasLength(1));
      final advice = plan.advices.single;
      expect(advice.kind, LearningAdviceKind.reviewVocabulary);
      expect(advice.priority, 300);
      expect(advice.actionType, isNull);
      expect(advice.actionLabelZh, isNull);
      expect(advice.stepCount, 2);
      expect(advice.detailZh, contains('「mystery_one」'));
      expect(advice.detailZh, contains('「mystery_two」'));
      expect(advice.detailZh, contains('词表还不认识'));
      expect(advice.detailZh, contains('不是没问题'));
    });

    test('更多未知动作只列前 5 个并说明总数', () {
      final actions = <String>[
        'alpha_move',
        'beta_move',
        'delta_move',
        'epsilon_move',
        'gamma_move',
        'zeta_move',
      ];
      final insights = aggregateOf(<ChainInsightChain>[
        chainOf(
          'c1',
          steps: <ChainInsightStep>[
            for (var i = 0; i < actions.length; i++)
              riskyStep(actions[i], index: i),
          ],
        ),
      ]);
      final plan = planFor(insights);
      final advice = plan.advices.single;
      expect(advice.kind, LearningAdviceKind.reviewVocabulary);
      expect(advice.stepCount, 6);
      expect(advice.detailZh, contains('只列前 5 个'));
      expect(advice.detailZh, contains('共 6 个'));
      expect(advice.detailZh, contains('「alpha_move」'));
      expect(advice.detailZh, contains('「gamma_move」'));
      expect(advice.detailZh, isNot(contains('「zeta_move」')));
    });

    test('未知动作与练习建议并存时按 priority 排序', () {
      final insights = aggregateOf(<ChainInsightChain>[
        chainOf(
          'c1',
          steps: <ChainInsightStep>[
            ...stepsFor('case_split', 3),
            riskyStep('mystery_move', index: 10),
          ],
        ),
      ]);
      final plan = planFor(insights);
      expect(
        kindsOf(plan),
        <LearningAdviceKind>[
          LearningAdviceKind.practiceAction,
          LearningAdviceKind.reviewVocabulary,
        ],
      );
      expect(plan.advices[0].priority, lessThan(plan.advices[1].priority));
    });
  });

  group('keepGoing（数据健康）', () {
    test('有读数但没到阈值时给一条 keepGoing', () {
      final insights = aggregateOf(<ChainInsightChain>[
        chainOf('c1', steps: stepsFor('case_split', 2)),
      ]);
      final plan = planFor(insights);
      final advice = plan.advices.single;
      expect(advice.kind, LearningAdviceKind.keepGoing);
      expect(advice.priority, 400);
      expect(advice.detailZh, contains('条链'));
      expect(advice.detailZh, contains('没有词表外动作'));
      expect(advice.actionType, isNull);
    });

    test('有练习建议时不再给 keepGoing', () {
      final insights = aggregateOf(<ChainInsightChain>[
        chainOf('c1', steps: stepsFor('case_split', 3)),
      ]);
      expect(
        kindsOf(planFor(insights)),
        isNot(contains(LearningAdviceKind.keepGoing)),
      );
    });

    test('有未知动作建议时不再给 keepGoing', () {
      final insights = aggregateOf(<ChainInsightChain>[
        chainOf('c1', steps: stepsFor('mystery_move', 1)),
      ]);
      expect(
        kindsOf(planFor(insights)),
        isNot(contains(LearningAdviceKind.keepGoing)),
      );
    });

    test('有 collectChains 时不再给 keepGoing', () {
      final plan = planFor(
        aggregateOf(const <ChainInsightChain>[]),
        corpusQuestionCount: 3,
      );
      expect(kindsOf(plan),
          <LearningAdviceKind>[LearningAdviceKind.collectChains]);
    });
  });

  group('排序与截断', () {
    test('三个优先带按 practice → collect → review 排序', () {
      final insights = aggregateOf(<ChainInsightChain>[
        chainOf(
          'c1',
          steps: <ChainInsightStep>[
            ...stepsFor('case_split', 3),
            riskyStep('mystery_move', index: 10),
          ],
        ),
      ]);
      final plan = planFor(insights, corpusQuestionCount: 10);
      expect(
        kindsOf(plan),
        <LearningAdviceKind>[
          LearningAdviceKind.practiceAction,
          LearningAdviceKind.collectChains,
          LearningAdviceKind.reviewVocabulary,
        ],
      );
      expect(
        <int>[for (final advice in plan.advices) advice.priority],
        <int>[100, 200, 300],
      );
    });

    test('maxAdvices 截断保留排序靠前的建议', () {
      final insights = aggregateOf(<ChainInsightChain>[
        chainOf(
          'c1',
          steps: <ChainInsightStep>[
            ...stepsFor('case_split', 3),
            ...stepsFor('induction', 5, start: 10),
            riskyStep('mystery_move', index: 20),
          ],
        ),
      ]);
      final plan = planFor(insights, maxAdvices: 2);
      expect(plan.advices, hasLength(2));
      expect(plan.advices[0].actionType, 'induction');
      expect(plan.advices[1].actionType, 'case_split');
      expect(plan.isNotEmpty, isTrue);
    });

    test('maxAdvices 为 0 时按 1 处理，截断后不是空计划', () {
      final insights = aggregateOf(<ChainInsightChain>[
        chainOf('c1', steps: stepsFor('case_split', 3)),
      ]);
      final plan = planFor(insights, maxAdvices: 0);
      expect(plan.advices, hasLength(1));
      expect(plan.isEmpty, isFalse);
      expect(plan.advices.single.kind, LearningAdviceKind.practiceAction);
    });

    test('maxAdvices 为负数时按 1 处理', () {
      final plan = planFor(
        aggregateOf(const <ChainInsightChain>[]),
        maxAdvices: -2,
      );
      expect(plan.advices, hasLength(1));
      expect(plan.isEmpty, isFalse);
    });

    test('同输入重复构建输出完全一致', () {
      final insights = aggregateOf(<ChainInsightChain>[
        chainOf(
          'c1',
          steps: <ChainInsightStep>[
            ...stepsFor('case_split', 3),
            riskyStep('mystery_move', index: 10),
          ],
        ),
      ]);
      final first = planFor(insights, corpusQuestionCount: 10);
      final second = planFor(insights, corpusQuestionCount: 10);
      expect(second.toJson(), first.toJson());
    });

    test('截断不改变未截断构建的结果', () {
      final insights = aggregateOf(<ChainInsightChain>[
        chainOf(
          'c1',
          steps: <ChainInsightStep>[
            ...stepsFor('case_split', 3),
            ...stepsFor('induction', 5, start: 10),
          ],
        ),
      ]);
      final full = planFor(insights);
      final truncatedA = planFor(insights, maxAdvices: 1);
      final truncatedB = planFor(insights, maxAdvices: 1);
      expect(truncatedA.toJson(), truncatedB.toJson());
      expect(full.advices, hasLength(2));
      expect(truncatedA.advices, hasLength(1));
    });
  });

  group('无效读数不参与', () {
    test('NaN 风险只计入无效读数，不触发练习建议', () {
      final insights = aggregateOf(<ChainInsightChain>[
        chainOf(
          'c1',
          steps: <ChainInsightStep>[
            const ChainInsightStep(
              actionType: 'case_split',
              index: 0,
              stuckRisk: double.nan,
            ),
            const ChainInsightStep(
              actionType: 'case_split',
              index: 1,
              stuckRisk: double.nan,
            ),
          ],
        ),
      ]);
      expect(insights.invalidRiskStepCount, 2);
      expect(insights.highRiskStepCount, 0);
      final plan = planFor(insights);
      expect(kindsOf(plan), <LearningAdviceKind>[LearningAdviceKind.keepGoing]);
    });

    test('无穷大风险不参与高风险计数', () {
      final insights = aggregateOf(<ChainInsightChain>[
        chainOf(
          'c1',
          steps: <ChainInsightStep>[
            const ChainInsightStep(
              actionType: 'case_split',
              index: 0,
              stuckRisk: double.infinity,
            ),
          ],
        ),
      ]);
      expect(insights.highRiskStepCount, 0);
      expect(kindsOf(planFor(insights)),
          <LearningAdviceKind>[LearningAdviceKind.keepGoing]);
    });
  });
}
