// 动作 × 知识点交叉读数（chain_insights.dart），以及学习建议把交叉读数
// 填进 knowledgePointIds（learning_advice.dart）。纯逻辑测试。

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/domain/services/reasoning/chain_insights.dart';
import 'package:furnace/domain/services/reasoning/learning_advice.dart';

ChainInsightStep step(
  String actionType, {
  int? index,
  double? stuckRisk,
  List<String> hints = const <String>[],
}) {
  return ChainInsightStep(
    actionType: actionType,
    index: index,
    stuckRisk: stuckRisk,
    knowledgeHints: hints,
  );
}

ChainInsightChain chain(
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

ChainInsights aggregate(Iterable<ChainInsightChain> chains) {
  return ChainInsights.aggregate(chains: chains);
}

List<ChainActionKnowledgePointGroup> crossOf(ChainInsights insights) {
  return insights.highRiskByActionAndKnowledgePoint;
}

ChainActionKnowledgePointGroup? groupOf(
  ChainInsights insights,
  String actionType,
  String knowledgePointId,
) {
  for (final group in crossOf(insights)) {
    if (group.actionType == actionType &&
        group.knowledgePointId == knowledgePointId) {
      return group;
    }
  }
  return null;
}

List<String> pairsOf(ChainInsights insights) {
  return <String>[
    for (final group in crossOf(insights))
      '${group.actionType}|${group.knowledgePointId}',
  ];
}

LearningAdvicePlan planFor(ChainInsights insights) {
  return LearningAdvicePlan.build(insights: insights);
}

LearningAdvice practiceAdviceFor(LearningAdvicePlan plan, String actionType) {
  return plan.advices.firstWhere(
    (advice) =>
        advice.kind == LearningAdviceKind.practiceAction &&
        advice.actionType == actionType,
  );
}

void main() {
  group('动作 × 知识点交叉聚合', () {
    test('同一动作的不同知识点分开计数', () {
      final insights = aggregate(<ChainInsightChain>[
        chain('c1', steps: <ChainInsightStep>[
          step('case_split', index: 0, stuckRisk: 0.9, hints: <String>['函数']),
          step('case_split', index: 1, stuckRisk: 0.8, hints: <String>['函数']),
          step('case_split', index: 2, stuckRisk: 0.7, hints: <String>['数列']),
        ]),
      ]);
      expect(crossOf(insights), hasLength(2));
      final func = groupOf(insights, 'case_split', '函数')!;
      expect(func.highRiskStepCount, 2);
      expect(func.questionCount, 1);
      expect(func.chainCount, 1);
      expect(groupOf(insights, 'case_split', '数列')!.highRiskStepCount, 1);
    });

    test('低风险与无风险步不进交叉读数', () {
      final insights = aggregate(<ChainInsightChain>[
        chain('c1', steps: <ChainInsightStep>[
          step('case_split', index: 0, stuckRisk: 0.9, hints: <String>['函数']),
          step('case_split', index: 1, stuckRisk: 0.3, hints: <String>['函数']),
          step('case_split', index: 2, hints: <String>['函数']),
        ]),
      ]);
      expect(groupOf(insights, 'case_split', '函数')!.highRiskStepCount, 1);
    });

    test('空白知识点被忽略，前后空白被 trim 后归并', () {
      final insights = aggregate(<ChainInsightChain>[
        chain('c1', steps: <ChainInsightStep>[
          step(
            'case_split',
            index: 0,
            stuckRisk: 0.9,
            hints: <String>[' 函数 ', '', '   ', '函数'],
          ),
          step(
            'case_split',
            index: 1,
            stuckRisk: 0.8,
            hints: <String>['  函数  '],
          ),
        ]),
      ]);
      expect(crossOf(insights), hasLength(1));
      expect(crossOf(insights).single.knowledgePointId, '函数');
      expect(crossOf(insights).single.highRiskStepCount, 2);
    });

    test('一步带多个知识点时分别计入，重复知识点只算一次', () {
      final insights = aggregate(<ChainInsightChain>[
        chain('c1', steps: <ChainInsightStep>[
          step(
            'case_split',
            index: 0,
            stuckRisk: 0.9,
            hints: <String>['函数', '数列', '函数'],
          ),
        ]),
      ]);
      expect(crossOf(insights), hasLength(2));
      expect(groupOf(insights, 'case_split', '函数')!.highRiskStepCount, 1);
      expect(groupOf(insights, 'case_split', '数列')!.highRiskStepCount, 1);
    });

    test('链数与题数按集合去重', () {
      final insights = aggregate(<ChainInsightChain>[
        chain('c1', questionId: 'q1', steps: <ChainInsightStep>[
          step('case_split', index: 0, stuckRisk: 0.9, hints: <String>['函数']),
          step('case_split', index: 1, stuckRisk: 0.8, hints: <String>['函数']),
        ]),
        chain('c2', questionId: 'q2', steps: <ChainInsightStep>[
          step('case_split', index: 0, stuckRisk: 0.7, hints: <String>['函数']),
        ]),
      ]);
      final func = groupOf(insights, 'case_split', '函数')!;
      expect(func.highRiskStepCount, 3);
      expect(func.chainCount, 2);
      expect(func.questionCount, 2);
    });

    test('不同动作的同一知识点分成两条交叉读数', () {
      final insights = aggregate(<ChainInsightChain>[
        chain('c1', steps: <ChainInsightStep>[
          step('case_split', index: 0, stuckRisk: 0.9, hints: <String>['函数']),
          step('induction', index: 1, stuckRisk: 0.8, hints: <String>['函数']),
        ]),
      ]);
      expect(crossOf(insights), hasLength(2));
      expect(groupOf(insights, 'case_split', '函数')!.highRiskStepCount, 1);
      expect(groupOf(insights, 'induction', '函数')!.highRiskStepCount, 1);
    });

    test('未知动作也保留原串，不被吞掉', () {
      final insights = aggregate(<ChainInsightChain>[
        chain('c1', steps: <ChainInsightStep>[
          step(
            'mystery_move',
            index: 0,
            stuckRisk: 0.9,
            hints: <String>['函数'],
          ),
        ]),
      ]);
      expect(groupOf(insights, 'mystery_move', '函数')!.highRiskStepCount, 1);
    });

    test('阈值生效：默认 0.6 进，0.9 阈值时 0.8 不进', () {
      final chains = <ChainInsightChain>[
        chain('c1', steps: <ChainInsightStep>[
          step('case_split', index: 0, stuckRisk: 0.8, hints: <String>['函数']),
        ]),
      ];
      expect(crossOf(aggregate(chains)).single.highRiskStepCount, 1);
      final strict = ChainInsights.aggregate(
        chains: chains,
        highRiskThreshold: 0.9,
      );
      expect(crossOf(strict), isEmpty);
    });

    test('空输入返回空交叉读数', () {
      expect(crossOf(aggregate(const <ChainInsightChain>[])), isEmpty);
    });

    test('交叉读数列表不可变', () {
      final insights = aggregate(<ChainInsightChain>[
        chain('c1', steps: <ChainInsightStep>[
          step('case_split', index: 0, stuckRisk: 0.9, hints: <String>['函数']),
        ]),
      ]);
      expect(
        () => crossOf(insights).add(
          const ChainActionKnowledgePointGroup(
            actionType: 'case_split',
            knowledgePointId: 'x',
            highRiskStepCount: 0,
            questionCount: 0,
            chainCount: 0,
          ),
        ),
        throwsUnsupportedError,
      );
    });
  });

  group('交叉读数排序确定性', () {
    test('高危步数降序优先', () {
      final insights = aggregate(<ChainInsightChain>[
        chain('c1', questionId: 'q1', steps: <ChainInsightStep>[
          step('case_split', index: 0, stuckRisk: 0.9, hints: <String>['函数']),
          step('case_split', index: 1, stuckRisk: 0.9, hints: <String>['函数']),
        ]),
        chain('c2', questionId: 'q2', steps: <ChainInsightStep>[
          step('case_split', index: 0, stuckRisk: 0.9, hints: <String>['函数']),
          step('case_split', index: 1, stuckRisk: 0.9, hints: <String>['数列']),
          step('symmetry', index: 2, stuckRisk: 0.9, hints: <String>['函数']),
        ]),
        chain('c3', questionId: 'q3', steps: <ChainInsightStep>[
          step('symmetry', index: 0, stuckRisk: 0.9, hints: <String>['函数']),
        ]),
      ]);
      expect(pairsOf(insights), <String>[
        'case_split|函数',
        'symmetry|函数',
        'case_split|数列',
      ]);
    });

    test('同高危步数时链数降序', () {
      final insights = aggregate(<ChainInsightChain>[
        chain('c1', questionId: 'q1', steps: <ChainInsightStep>[
          step(
            'case_split',
            index: 0,
            stuckRisk: 0.9,
            hints: <String>['kp_many_chains'],
          ),
          step(
            'case_split',
            index: 1,
            stuckRisk: 0.9,
            hints: <String>['kp_one_chain'],
          ),
        ]),
        chain('c2', questionId: 'q2', steps: <ChainInsightStep>[
          step(
            'case_split',
            index: 0,
            stuckRisk: 0.9,
            hints: <String>['kp_many_chains'],
          ),
        ]),
      ]);
      expect(
        crossOf(insights).map((group) => group.knowledgePointId).toList(),
        <String>['kp_many_chains', 'kp_one_chain'],
      );
    });

    test('全平局时按 actionType 升序、再按知识点 id 升序', () {
      final insights = aggregate(<ChainInsightChain>[
        chain('c1', steps: <ChainInsightStep>[
          step('case_split', index: 0, stuckRisk: 0.9, hints: <String>['b']),
          step('case_split', index: 1, stuckRisk: 0.9, hints: <String>['a']),
          step(
            'analogy_transfer',
            index: 2,
            stuckRisk: 0.9,
            hints: <String>['a'],
          ),
        ]),
      ]);
      expect(pairsOf(insights), <String>[
        'analogy_transfer|a',
        'case_split|a',
        'case_split|b',
      ]);
    });

    test('重复聚合得到逐字节相同的 JSON（确定性）', () {
      final chains = <ChainInsightChain>[
        chain('c1', steps: <ChainInsightStep>[
          step('case_split', index: 0, stuckRisk: 0.9, hints: <String>['函数']),
          step('symmetry', index: 1, stuckRisk: 0.8, hints: <String>['数列']),
        ]),
      ];
      final first = aggregate(chains);
      final second = aggregate(chains);
      expect(jsonEncode(first.toJson()), jsonEncode(second.toJson()));
    });
  });

  group('交叉读数 toJson', () {
    test('新增键与旧键并存，旧 toJson 字段不破坏', () {
      final insights = aggregate(<ChainInsightChain>[
        chain('c1', steps: <ChainInsightStep>[
          step('case_split', index: 0, stuckRisk: 0.9, hints: <String>['函数']),
        ]),
      ]);
      final json = insights.toJson();
      final cross =
          (json['high_risk_by_action_and_knowledge_point']! as List<Object?>)
              .single as Map<String, Object?>;
      expect(cross['action_type'], 'case_split');
      expect(cross['knowledge_point_id'], '函数');
      expect(cross['high_risk_step_count'], 1);
      expect(cross['question_count'], 1);
      expect(cross['chain_count'], 1);
      expect(json['high_risk_by_question'], isA<List<Object?>>());
      expect(json['high_risk_by_knowledge_point'], isA<List<Object?>>());
      expect(json['high_risk_step_count'], 1);
      expect(json['chain_count'], 1);
      final decoded = jsonDecode(jsonEncode(json)) as Map<String, Object?>;
      expect(
        decoded['high_risk_by_action_and_knowledge_point'],
        isA<List<Object?>>(),
      );
    });
  });

  group('练习建议填知识点', () {
    test('按高危步数降序、同数按知识点 id 升序取知识点', () {
      final insights = aggregate(<ChainInsightChain>[
        chain('c1', steps: <ChainInsightStep>[
          step('case_split', index: 0, stuckRisk: 0.9, hints: <String>['函数']),
          step('case_split', index: 1, stuckRisk: 0.9, hints: <String>['函数']),
          step('case_split', index: 2, stuckRisk: 0.9, hints: <String>['数列']),
          step('case_split', index: 3, stuckRisk: 0.9, hints: <String>['集合']),
        ]),
      ]);
      final advice = practiceAdviceFor(planFor(insights), 'case_split');
      expect(advice.knowledgePointIds, <String>['函数', '数列', '集合']);
    });

    test('高危险步数压过知识点 id 字典序', () {
      final insights = aggregate(<ChainInsightChain>[
        chain('c1', steps: <ChainInsightStep>[
          step('case_split', index: 0, stuckRisk: 0.9, hints: <String>['kp_z']),
          step('case_split', index: 1, stuckRisk: 0.9, hints: <String>['kp_z']),
          step('case_split', index: 2, stuckRisk: 0.9, hints: <String>['kp_a']),
        ]),
      ]);
      final advice = practiceAdviceFor(planFor(insights), 'case_split');
      expect(advice.knowledgePointIds, <String>['kp_z', 'kp_a']);
    });

    test('每条建议最多 3 个知识点，超出截断', () {
      final insights = aggregate(<ChainInsightChain>[
        chain('c1', steps: <ChainInsightStep>[
          for (var i = 0; i < 5; i++)
            step(
              'case_split',
              index: i,
              stuckRisk: 0.9,
              hints: <String>['kp_${String.fromCharCode(97 + i)}'],
            ),
        ]),
      ]);
      final advice = practiceAdviceFor(planFor(insights), 'case_split');
      expect(LearningAdvicePlan.maxKnowledgePointIds, 3);
      expect(advice.knowledgePointIds, <String>['kp_a', 'kp_b', 'kp_c']);
    });

    test('没有交叉读数时知识点是空列表，不编造', () {
      final insights = aggregate(<ChainInsightChain>[
        chain('c1', steps: <ChainInsightStep>[
          step('case_split', index: 0, stuckRisk: 0.9),
          step('case_split', index: 1, stuckRisk: 0.9),
          step('case_split', index: 2, stuckRisk: 0.9),
        ]),
      ]);
      final advice = practiceAdviceFor(planFor(insights), 'case_split');
      expect(advice.knowledgePointIds, isEmpty);
    });

    test('只取该动作自己的知识点，不串其它动作', () {
      final insights = aggregate(<ChainInsightChain>[
        chain('c1', steps: <ChainInsightStep>[
          step('case_split', index: 0, stuckRisk: 0.9, hints: <String>['函数']),
          step('case_split', index: 1, stuckRisk: 0.9, hints: <String>['函数']),
          step('case_split', index: 2, stuckRisk: 0.9, hints: <String>['函数']),
          step('induction', index: 3, stuckRisk: 0.9, hints: <String>['数列']),
          step('induction', index: 4, stuckRisk: 0.9, hints: <String>['数列']),
          step('induction', index: 5, stuckRisk: 0.9, hints: <String>['数列']),
        ]),
      ]);
      final plan = planFor(insights);
      expect(
        practiceAdviceFor(plan, 'case_split').knowledgePointIds,
        <String>['函数'],
      );
      expect(
        practiceAdviceFor(plan, 'induction').knowledgePointIds,
        <String>['数列'],
      );
    });

    test('非练习类建议的知识点保持空列表', () {
      final review = planFor(aggregate(<ChainInsightChain>[
        chain('c1', steps: <ChainInsightStep>[
          step('mystery_move', index: 0, stuckRisk: 0.9, hints: <String>['函数']),
          step('mystery_move', index: 1, stuckRisk: 0.9, hints: <String>['函数']),
          step('mystery_move', index: 2, stuckRisk: 0.9, hints: <String>['函数']),
        ]),
      ]));
      final reviewAdvice = review.advices.firstWhere(
        (advice) => advice.kind == LearningAdviceKind.reviewVocabulary,
      );
      expect(reviewAdvice.knowledgePointIds, isEmpty);

      final keepGoing = planFor(aggregate(<ChainInsightChain>[
        chain('c1', steps: <ChainInsightStep>[
          step('case_split', index: 0, stuckRisk: 0.9, hints: <String>['函数']),
        ]),
      ]));
      final keepAdvice = keepGoing.advices.firstWhere(
        (advice) => advice.kind == LearningAdviceKind.keepGoing,
      );
      expect(keepAdvice.knowledgePointIds, isEmpty);

      final noData = planFor(aggregate(const <ChainInsightChain>[]));
      expect(noData.advices.single.knowledgePointIds, isEmpty);

      final collect = LearningAdvicePlan.build(
        insights: aggregate(const <ChainInsightChain>[]),
        corpusQuestionCount: 10,
      );
      expect(
        collect.advices.single.knowledgePointIds,
        isEmpty,
      );
    });

    test('建议 toJson 带 knowledge_point_ids 且旧字段不变', () {
      final insights = aggregate(<ChainInsightChain>[
        chain('c1', questionId: 'q1', steps: <ChainInsightStep>[
          step('case_split', index: 0, stuckRisk: 0.9, hints: <String>['函数']),
          step('case_split', index: 1, stuckRisk: 0.9, hints: <String>['函数']),
          step('case_split', index: 2, stuckRisk: 0.9, hints: <String>['数列']),
          step('case_split', index: 3, stuckRisk: 0.1),
        ]),
      ]);
      final advice = practiceAdviceFor(planFor(insights), 'case_split');
      final json = advice.toJson();
      expect(json['kind'], 'practiceAction');
      expect(json['action_type'], 'case_split');
      expect(json['question_count'], 1);
      expect(json['step_count'], 4);
      expect(json['high_risk_step_count'], 3);
      expect(json['knowledge_point_ids'], <String>['函数', '数列']);
    });

    test('knowledgePointIds 不可变', () {
      final insights = aggregate(<ChainInsightChain>[
        chain('c1', steps: <ChainInsightStep>[
          step('case_split', index: 0, stuckRisk: 0.9, hints: <String>['函数']),
          step('case_split', index: 1, stuckRisk: 0.9, hints: <String>['函数']),
          step('case_split', index: 2, stuckRisk: 0.9, hints: <String>['函数']),
        ]),
      ]);
      final advice = practiceAdviceFor(planFor(insights), 'case_split');
      expect(
        () => advice.knowledgePointIds.add('x'),
        throwsUnsupportedError,
      );
    });

    test('同输入两次构建建议清单一致（确定性）', () {
      final insights = aggregate(<ChainInsightChain>[
        chain('c1', steps: <ChainInsightStep>[
          step('case_split', index: 0, stuckRisk: 0.9, hints: <String>['函数']),
          step('case_split', index: 1, stuckRisk: 0.9, hints: <String>['函数']),
          step('case_split', index: 2, stuckRisk: 0.9, hints: <String>['数列']),
          step('symmetry', index: 3, stuckRisk: 0.9, hints: <String>['集合']),
        ]),
      ]);
      final first = planFor(insights);
      final second = planFor(insights);
      expect(jsonEncode(first.toJson()), jsonEncode(second.toJson()));
      expect(
        first.advices.map((advice) => advice.knowledgePointIds).toList(),
        second.advices.map((advice) => advice.knowledgePointIds).toList(),
      );
    });
  });
}
