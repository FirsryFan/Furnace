// 思维链洞察聚合：跨链按能力动作 / 卡点 / 题目 / 知识点聚合，口径与
// capability_profile.dart、capability_action_discovery.dart 保持一致。

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/domain/services/reasoning/capability_action.dart';
import 'package:furnace/domain/services/reasoning/capability_action_overlay.dart';
import 'package:furnace/domain/services/reasoning/chain_insights.dart';
import 'package:furnace/domain/services/reasoning/reasoning_prompt.dart';

ChainInsightStep step(
  String actionType, {
  int? index,
  double? stuckRisk,
  bool? knownAction,
  List<String> hints = const <String>[],
  DateTime? occurredAt,
}) {
  return ChainInsightStep(
    actionType: actionType,
    index: index,
    stuckRisk: stuckRisk,
    knownAction: knownAction,
    knowledgeHints: hints,
    occurredAt: occurredAt,
  );
}

ChainInsightChain chain(
  String chainId, {
  String questionId = 'q1',
  List<ChainInsightStep> steps = const <ChainInsightStep>[],
  DateTime? occurredAt,
}) {
  return ChainInsightChain(
    chainId: chainId,
    questionId: questionId,
    steps: steps,
    occurredAt: occurredAt,
  );
}

ChainInsights aggregate(
  Iterable<ChainInsightChain> chains, {
  CapabilityActionCatalog? catalog,
  double highRiskThreshold = ChainInsights.defaultHighRiskThreshold,
}) {
  return ChainInsights.aggregate(
    chains: chains,
    catalog: catalog,
    highRiskThreshold: highRiskThreshold,
  );
}

/// 一个合法 overlay：内置词表 + 用户自定义的 formula_rewrite。
CapabilityActionCatalog customCatalog() {
  return const CapabilityActionOverlay(
    customActions: <CustomCapabilityAction>[
      CustomCapabilityAction(
        key: 'formula_rewrite',
        labelZh: '公式改写',
        labelEn: 'Formula rewrite',
        subjectHints: <String>['math'],
      ),
    ],
  ).catalog;
}

ChainActionInsight actionOf(ChainInsights insights, String actionType) {
  return insights.actions.firstWhere((item) => item.actionType == actionType);
}

void main() {
  group('基础聚合', () {
    test('空输入返回空聚合且不抛', () {
      final insights = aggregate(const <ChainInsightChain>[]);
      expect(insights.isEmpty, isTrue);
      expect(insights.isNotEmpty, isFalse);
      expect(insights.chainCount, 0);
      expect(insights.stepCount, 0);
      expect(insights.questionCount, 0);
      expect(insights.actions, isEmpty);
      expect(insights.customActions, isEmpty);
      expect(insights.unknownActions, isEmpty);
      expect(insights.neverUsedActions, isEmpty);
      expect(insights.highRiskByQuestion, isEmpty);
      expect(insights.highRiskByKnowledgePoint, isEmpty);
      expect(insights.toJson()['step_count'], 0);
    });

    test('按动作聚合步数与去重题数', () {
      final insights = aggregate(<ChainInsightChain>[
        chain('c1', steps: <ChainInsightStep>[
          step('case_split', index: 0),
          step('symmetry', index: 1),
        ]),
        chain('c2', questionId: 'q2', steps: <ChainInsightStep>[
          step('case_split', index: 0),
        ]),
        chain('c3', steps: <ChainInsightStep>[
          step('case_split', index: 0),
        ]),
      ]);
      expect(insights.chainCount, 3);
      expect(insights.stepCount, 4);
      expect(insights.questionCount, 2);
      expect(insights.actions, hasLength(2));
      final caseSplit = actionOf(insights, 'case_split');
      expect(caseSplit.stepCount, 3);
      expect(caseSplit.questionCount, 2);
      expect(caseSplit.known, isTrue);
      expect(caseSplit.label, '分类讨论');
      expect(caseSplit.averageStuckRisk, isNull);
      expect(caseSplit.maxStuckRisk, isNull);
      expect(actionOf(insights, 'symmetry').questionCount, 1);
    });

    test('同一题目的多条链不重复计题数', () {
      final insights = aggregate(<ChainInsightChain>[
        chain('c1', steps: <ChainInsightStep>[step('case_split', index: 0)]),
        chain('c2', steps: <ChainInsightStep>[step('case_split', index: 0)]),
      ]);
      expect(insights.chainCount, 2);
      expect(insights.questionCount, 1);
      expect(actionOf(insights, 'case_split').questionCount, 1);
    });

    test('空 questionId 不计题数但照统计动作', () {
      final insights = aggregate(<ChainInsightChain>[
        chain('c1', questionId: '', steps: <ChainInsightStep>[
          step('case_split', index: 0, stuckRisk: 0.9),
        ]),
      ]);
      expect(insights.questionCount, 0);
      expect(insights.stepCount, 1);
      final insight = actionOf(insights, 'case_split');
      expect(insight.questionCount, 0);
      expect(insight.highRiskStepCount, 1);
      expect(insight.highRiskQuestionCount, 0);
      expect(insights.highRiskByQuestion, isEmpty);
    });

    test('knownActionRatio 按已知步占比', () {
      final insights = aggregate(<ChainInsightChain>[
        chain('c1', steps: <ChainInsightStep>[
          step('case_split', index: 0),
          step('symmetry', index: 1),
          step('mystery_move', index: 2),
        ]),
      ]);
      expect(
        actionOf(insights, 'case_split').knownActionRatio,
        closeTo(1.0, 1e-12),
      );
      expect(
        actionOf(insights, 'mystery_move').knownActionRatio,
        closeTo(0.0, 1e-12),
      );
      expect(
        actionOf(insights, 'mystery_move').known,
        isFalse,
      );
    });

    test('平均与最高风险只算有读数的步', () {
      final insights = aggregate(<ChainInsightChain>[
        chain('c1', steps: <ChainInsightStep>[
          step('case_split', index: 0, stuckRisk: 0.2),
          step('case_split', index: 1),
          step('case_split', index: 2, stuckRisk: 0.8),
        ]),
      ]);
      final insight = actionOf(insights, 'case_split');
      expect(insight.stepCount, 3);
      expect(insight.averageStuckRisk, closeTo(0.5, 1e-12));
      expect(insight.maxStuckRisk, 0.8);
      expect(insight.highRiskStepCount, 1);
    });

    test('全部无读数时平均与最高为 null 而不是 0', () {
      final insights = aggregate(<ChainInsightChain>[
        chain('c1', steps: <ChainInsightStep>[
          step('case_split', index: 0),
          step('symmetry', index: 1),
        ]),
      ]);
      for (final insight in insights.actions) {
        expect(insight.averageStuckRisk, isNull);
        expect(insight.maxStuckRisk, isNull);
      }
      expect(insights.highRiskStepCount, 0);
    });

    test('未知动作的 label 退回 actionType 原串', () {
      final insights = aggregate(<ChainInsightChain>[
        chain('c1', steps: <ChainInsightStep>[step('mystery_move', index: 0)]),
      ]);
      final insight = actionOf(insights, 'mystery_move');
      expect(insight.label, 'mystery_move');
      expect(insight.known, isFalse);
      expect(insight.custom, isFalse);
      expect(insights.unknownActions, hasLength(1));
    });

    test('全部步被丢弃时 isEmpty 为真', () {
      final insights = aggregate(<ChainInsightChain>[
        chain('c1', steps: <ChainInsightStep>[step('   ', index: 0)]),
      ]);
      expect(insights.stepCount, 0);
      expect(insights.isEmpty, isTrue);
      expect(insights.chainCount, 1);
    });
  });

  group('最近出现时间', () {
    final t1 = DateTime.utc(2026, 10, 1, 8);
    final t2 = DateTime.utc(2026, 10, 2, 8);
    final t3 = DateTime.utc(2026, 10, 3, 8);

    test('lastSeenAt 取步时间的最大值', () {
      final insights = aggregate(<ChainInsightChain>[
        chain('c1', steps: <ChainInsightStep>[
          step('case_split', index: 0, occurredAt: t1),
          step('case_split', index: 1, occurredAt: t3),
          step('case_split', index: 2, occurredAt: t2),
        ]),
      ]);
      expect(actionOf(insights, 'case_split').lastSeenAt, t3);
    });

    test('步没有时间戳时用链时间兜底', () {
      final insights = aggregate(<ChainInsightChain>[
        chain('c1', occurredAt: t2, steps: <ChainInsightStep>[
          step('case_split', index: 0),
        ]),
      ]);
      expect(actionOf(insights, 'case_split').lastSeenAt, t2);
    });

    test('步时间优先于链时间', () {
      final insights = aggregate(<ChainInsightChain>[
        chain('c1', occurredAt: t1, steps: <ChainInsightStep>[
          step('case_split', index: 0, occurredAt: t3),
        ]),
      ]);
      expect(actionOf(insights, 'case_split').lastSeenAt, t3);
    });

    test('一个时间戳都没有时为 null', () {
      final insights = aggregate(<ChainInsightChain>[
        chain('c1', steps: <ChainInsightStep>[step('case_split', index: 0)]),
      ]);
      expect(actionOf(insights, 'case_split').lastSeenAt, isNull);
    });
  });

  group('风险读数与阈值', () {
    test('默认阈值 0.6，等于阈值算高危', () {
      final insights = aggregate(<ChainInsightChain>[
        chain('c1', steps: <ChainInsightStep>[
          step('case_split', index: 0, stuckRisk: 0.6),
        ]),
      ]);
      expect(insights.highRiskThreshold, 0.6);
      expect(insights.highRiskStepCount, 1);
      expect(insights.highRiskChainCount, 1);
    });

    test('自定义阈值生效', () {
      final insights = aggregate(
        <ChainInsightChain>[
          chain('c1', steps: <ChainInsightStep>[
            step('case_split', index: 0, stuckRisk: 0.7),
            step('case_split', index: 1, stuckRisk: 0.8),
          ]),
        ],
        highRiskThreshold: 0.8,
      );
      expect(insights.highRiskThreshold, 0.8);
      expect(insights.highRiskStepCount, 1);
      expect(insights.highRiskThreshold == 0.8, isTrue);
    });

    test('NaN 风险按无读数处理并计数', () {
      final insights = aggregate(<ChainInsightChain>[
        chain('c1', steps: <ChainInsightStep>[
          step('case_split', index: 0, stuckRisk: double.nan),
        ]),
      ]);
      expect(insights.invalidRiskStepCount, 1);
      expect(insights.stepCount, 1);
      expect(insights.highRiskStepCount, 0);
      final insight = actionOf(insights, 'case_split');
      expect(insight.stepCount, 1);
      expect(insight.averageStuckRisk, isNull);
      expect(insight.maxStuckRisk, isNull);
    });

    test('正负无穷风险按无读数处理', () {
      final insights = aggregate(<ChainInsightChain>[
        chain('c1', steps: <ChainInsightStep>[
          step('case_split', index: 0, stuckRisk: double.infinity),
          step('case_split', index: 1, stuckRisk: double.negativeInfinity),
        ]),
      ]);
      expect(insights.invalidRiskStepCount, 2);
      expect(insights.highRiskStepCount, 0);
      expect(actionOf(insights, 'case_split').averageStuckRisk, isNull);
    });

    test('负风险夹到 0 并计数，不算高危', () {
      final insights = aggregate(<ChainInsightChain>[
        chain('c1', steps: <ChainInsightStep>[
          step('case_split', index: 0, stuckRisk: -0.5),
        ]),
      ]);
      expect(insights.clampedRiskStepCount, 1);
      expect(actionOf(insights, 'case_split').maxStuckRisk, 0.0);
      expect(insights.highRiskStepCount, 0);
    });

    test('超过 1 的风险夹到 1 并计数，算高危', () {
      final insights = aggregate(<ChainInsightChain>[
        chain('c1', steps: <ChainInsightStep>[
          step('case_split', index: 0, stuckRisk: 1.5),
        ]),
      ]);
      expect(insights.clampedRiskStepCount, 1);
      expect(actionOf(insights, 'case_split').maxStuckRisk, 1.0);
      expect(insights.highRiskStepCount, 1);
    });

    test('越界值夹取后参与平均', () {
      final insights = aggregate(<ChainInsightChain>[
        chain('c1', steps: <ChainInsightStep>[
          step('case_split', index: 0, stuckRisk: -1),
          step('case_split', index: 1, stuckRisk: 3),
        ]),
      ]);
      expect(insights.clampedRiskStepCount, 2);
      expect(
        actionOf(insights, 'case_split').averageStuckRisk,
        closeTo(0.5, 1e-12),
      );
    });

    test('阈值非有限时退回默认 0.6', () {
      for (final bad in <double>[
        double.nan,
        double.infinity,
        double.negativeInfinity,
      ]) {
        final insights = aggregate(
          <ChainInsightChain>[
            chain('c1', steps: <ChainInsightStep>[
              step('case_split', index: 0, stuckRisk: 0.6),
            ]),
          ],
          highRiskThreshold: bad,
        );
        expect(insights.highRiskThreshold, 0.6);
        expect(insights.highRiskStepCount, 1);
      }
    });

    test('阈值越界被夹到 0..1', () {
      final high = aggregate(
        <ChainInsightChain>[
          chain('c1', steps: <ChainInsightStep>[
            step('case_split', index: 0, stuckRisk: 0.0),
          ]),
        ],
        highRiskThreshold: -5,
      );
      expect(high.highRiskThreshold, 0.0);
      expect(high.highRiskStepCount, 1);
      final low = aggregate(<ChainInsightChain>[], highRiskThreshold: 5);
      expect(low.highRiskThreshold, 1.0);
    });

    test('无风险读数的步不进高危', () {
      final insights = aggregate(<ChainInsightChain>[
        chain('c1', steps: <ChainInsightStep>[step('case_split', index: 0)]),
      ]);
      expect(insights.highRiskStepCount, 0);
      expect(insights.highRiskChainCount, 0);
      expect(insights.highRiskByQuestion, isEmpty);
    });
  });

  group('卡点维度', () {
    test('高危步数与高危链数按链去重', () {
      final insights = aggregate(<ChainInsightChain>[
        chain('c1', steps: <ChainInsightStep>[
          step('case_split', index: 0, stuckRisk: 0.9),
          step('symmetry', index: 1, stuckRisk: 0.8),
        ]),
        chain('c2', questionId: 'q2', steps: <ChainInsightStep>[
          step('case_split', index: 0, stuckRisk: 0.7),
        ]),
      ]);
      expect(insights.highRiskStepCount, 3);
      expect(insights.highRiskChainCount, 2);
      final caseSplit = actionOf(insights, 'case_split');
      expect(caseSplit.highRiskStepCount, 2);
      expect(caseSplit.highRiskChainCount, 2);
      expect(caseSplit.highRiskQuestionCount, 2);
    });

    test('高危按题目聚合并按高危步数降序', () {
      final insights = aggregate(<ChainInsightChain>[
        chain('c1', steps: <ChainInsightStep>[
          step('case_split', index: 0, stuckRisk: 0.9),
          step('case_split', index: 1, stuckRisk: 0.7),
        ]),
        chain('c2', questionId: 'q2', steps: <ChainInsightStep>[
          step('reduction', index: 0, stuckRisk: 0.8),
        ]),
        chain('c3', steps: <ChainInsightStep>[
          step('symmetry', index: 0, stuckRisk: 0.9),
        ]),
      ]);
      expect(insights.highRiskByQuestion, hasLength(2));
      final first = insights.highRiskByQuestion[0];
      expect(first.key, 'q1');
      expect(first.highRiskStepCount, 3);
      expect(first.chainCount, 2);
      expect(first.questionCount, 1);
      expect(insights.highRiskByQuestion[1].key, 'q2');
    });

    test('知识点去空白并在同一步内去重', () {
      final insights = aggregate(<ChainInsightChain>[
        chain('c1', steps: <ChainInsightStep>[
          step(
            'case_split',
            index: 0,
            stuckRisk: 0.9,
            hints: <String>['函数', '', '  ', '函数'],
          ),
        ]),
      ]);
      expect(insights.highRiskByKnowledgePoint, hasLength(1));
      final group = insights.highRiskByKnowledgePoint.single;
      expect(group.key, '函数');
      expect(group.highRiskStepCount, 1);
      expect(group.questionCount, 1);
      expect(group.chainCount, 1);
    });

    test('低于阈值不记知识点', () {
      final insights = aggregate(<ChainInsightChain>[
        chain('c1', steps: <ChainInsightStep>[
          step('case_split', index: 0, stuckRisk: 0.3, hints: <String>['函数']),
        ]),
      ]);
      expect(insights.highRiskByKnowledgePoint, isEmpty);
    });

    test('同一步多个知识点各记一次', () {
      final insights = aggregate(<ChainInsightChain>[
        chain('c1', steps: <ChainInsightStep>[
          step(
            'case_split',
            index: 0,
            stuckRisk: 0.9,
            hints: <String>['函数', '导数'],
          ),
        ]),
      ]);
      expect(insights.highRiskByKnowledgePoint, hasLength(2));
      for (final group in insights.highRiskByKnowledgePoint) {
        expect(group.highRiskStepCount, 1);
      }
    });

    test('知识点计数跨步累加', () {
      final insights = aggregate(<ChainInsightChain>[
        chain('c1', steps: <ChainInsightStep>[
          step('case_split', index: 0, stuckRisk: 0.9, hints: <String>['函数']),
          step('case_split', index: 1, stuckRisk: 0.8, hints: <String>['函数']),
        ]),
      ]);
      final group = insights.highRiskByKnowledgePoint.single;
      expect(group.key, '函数');
      expect(group.highRiskStepCount, 2);
      expect(group.chainCount, 1);
    });

    test('卡点维度同分时按 key 升序稳定排序', () {
      final insights = aggregate(<ChainInsightChain>[
        chain('c1', questionId: 'b', steps: <ChainInsightStep>[
          step('case_split', index: 0, stuckRisk: 0.9),
        ]),
        chain('c2', questionId: 'a', steps: <ChainInsightStep>[
          step('case_split', index: 0, stuckRisk: 0.9),
        ]),
      ]);
      final keys = insights.highRiskByQuestion
          .map((group) => group.key)
          .toList(growable: false);
      expect(keys, <String>['a', 'b']);
    });
  });

  group('覆盖与冷门动作', () {
    test('注入自定义词表后自定义动作被识别', () {
      final catalog = customCatalog();
      final insights = aggregate(
        <ChainInsightChain>[
          chain('c1', steps: <ChainInsightStep>[
            step('formula_rewrite', index: 0, stuckRisk: 0.8),
          ]),
        ],
        catalog: catalog,
      );
      final insight = actionOf(insights, 'formula_rewrite');
      expect(insight.known, isTrue);
      expect(insight.custom, isTrue);
      expect(insight.label, '公式改写');
      expect(insights.customActions, hasLength(1));
      expect(insights.customActions.single.actionType, 'formula_rewrite');
      expect(insights.unknownActions, isEmpty);
    });

    test('不注入词表时自定义动作算未知', () {
      final insights = aggregate(<ChainInsightChain>[
        chain('c1', steps: <ChainInsightStep>[
          step('formula_rewrite', index: 0),
        ]),
      ]);
      final insight = actionOf(insights, 'formula_rewrite');
      expect(insight.known, isFalse);
      expect(insight.custom, isFalse);
      expect(insights.customActions, isEmpty);
      expect(insights.unknownActions, hasLength(1));
    });

    test('注入自定义词表后内置动作仍是已知', () {
      final insights = aggregate(
        <ChainInsightChain>[
          chain('c1', steps: <ChainInsightStep>[step('case_split', index: 0)]),
        ],
        catalog: customCatalog(),
      );
      final insight = actionOf(insights, 'case_split');
      expect(insight.known, isTrue);
      expect(insight.custom, isFalse);
      expect(insights.customActions, isEmpty);
    });

    test('unknownActions 只列当前词表不认识的', () {
      final insights = aggregate(
        <ChainInsightChain>[
          chain('c1', steps: <ChainInsightStep>[
            step('case_split', index: 0),
            step('formula_rewrite', index: 1),
            step('mystery_move', index: 2),
          ]),
        ],
        catalog: customCatalog(),
      );
      expect(insights.unknownActions, hasLength(1));
      expect(insights.unknownActions.single.actionType, 'mystery_move');
      expect(insights.customActions, hasLength(1));
    });

    test('neverUsedActions 按词表顺序排除已出现动作', () {
      final catalog = CapabilityActionCatalog.builtIn;
      final insights = aggregate(
        <ChainInsightChain>[
          chain('c1', steps: <ChainInsightStep>[
            step('case_split', index: 0),
            step('symmetry', index: 1),
          ]),
        ],
        catalog: catalog,
      );
      final expected = <String>[
        for (final action in catalog.actions)
          if (action.key != 'case_split' && action.key != 'symmetry')
            action.key,
      ];
      expect(
        insights.neverUsedActions.map((action) => action.key).toList(),
        expected,
      );
    });

    test('全部内置动作都出现时 neverUsedActions 为空', () {
      const all = CapabilityAction.catalog;
      final insights = aggregate(<ChainInsightChain>[
        chain('c1', steps: <ChainInsightStep>[
          for (var i = 0; i < all.length; i++) step(all[i].key, index: i),
        ]),
      ]);
      expect(insights.actions, hasLength(all.length));
      expect(insights.neverUsedActions, isEmpty);
    });

    test('空输入时 neverUsedActions 为空而不是全表', () {
      final insights = aggregate(
        const <ChainInsightChain>[],
        catalog: customCatalog(),
      );
      expect(insights.neverUsedActions, isEmpty);
    });

    test('自定义动作未出现时进入 neverUsedActions', () {
      final insights = aggregate(
        <ChainInsightChain>[
          chain('c1', steps: <ChainInsightStep>[step('case_split', index: 0)]),
        ],
        catalog: customCatalog(),
      );
      expect(
        insights.neverUsedActions.map((action) => action.key),
        contains('formula_rewrite'),
      );
      expect(
        insights.neverUsedActions.map((action) => action.key),
        isNot(contains('case_split')),
      );
    });
  });

  group('异常输入口径', () {
    test('空 chainId 的链被丢弃并计数', () {
      final insights = aggregate(<ChainInsightChain>[
        chain('', steps: <ChainInsightStep>[step('case_split', index: 0)]),
        chain('  ', steps: <ChainInsightStep>[step('case_split', index: 0)]),
        chain('c1', steps: <ChainInsightStep>[step('symmetry', index: 0)]),
      ]);
      expect(insights.ignoredChainCount, 2);
      expect(insights.chainCount, 1);
      expect(insights.stepCount, 1);
    });

    test('chainId 首尾空白被规整并可去重', () {
      final insights = aggregate(<ChainInsightChain>[
        chain(' c1 ', steps: <ChainInsightStep>[step('case_split', index: 0)]),
        chain('c1', steps: <ChainInsightStep>[step('symmetry', index: 0)]),
      ]);
      expect(insights.chainCount, 1);
      expect(insights.duplicateChainCount, 1);
      expect(insights.actions, hasLength(1));
    });

    test('重复 chainId 只取第一条链', () {
      final insights = aggregate(<ChainInsightChain>[
        chain('c1', steps: <ChainInsightStep>[step('case_split', index: 0)]),
        chain('c1', steps: <ChainInsightStep>[step('reduction', index: 0)]),
      ]);
      expect(insights.duplicateChainCount, 1);
      expect(insights.stepCount, 1);
      expect(insights.actions.map((item) => item.actionType), <String>[
        'case_split',
      ]);
    });

    test('空 actionType 的步被丢弃并计数', () {
      final insights = aggregate(<ChainInsightChain>[
        chain('c1', steps: <ChainInsightStep>[
          step('', index: 0),
          step('   ', index: 1),
          step('case_split', index: 2),
        ]),
      ]);
      expect(insights.ignoredStepCount, 2);
      expect(insights.stepCount, 1);
    });

    test('同链重复 index 只取第一条', () {
      final insights = aggregate(<ChainInsightChain>[
        chain('c1', steps: <ChainInsightStep>[
          step('case_split', index: 0, stuckRisk: 0.9),
          step('symmetry', index: 0, stuckRisk: 0.2),
        ]),
      ]);
      expect(insights.duplicateStepCount, 1);
      expect(insights.stepCount, 1);
      expect(insights.actions, hasLength(1));
      expect(insights.highRiskStepCount, 1);
    });

    test('index 为 null 的步不参与重复检测', () {
      final insights = aggregate(<ChainInsightChain>[
        chain('c1', steps: <ChainInsightStep>[
          step('case_split'),
          step('case_split'),
        ]),
      ]);
      expect(insights.duplicateStepCount, 0);
      expect(insights.stepCount, 2);
    });

    test('不同链的同名 index 不互相去重', () {
      final insights = aggregate(<ChainInsightChain>[
        chain('c1', steps: <ChainInsightStep>[step('case_split', index: 0)]),
        chain('c2', steps: <ChainInsightStep>[step('case_split', index: 0)]),
      ]);
      expect(insights.duplicateStepCount, 0);
      expect(insights.stepCount, 2);
    });

    test('knownAction 标记只影响占比，不改变词表知识判定', () {
      final insights = aggregate(<ChainInsightChain>[
        chain('c1', steps: <ChainInsightStep>[
          step('case_split', index: 0, knownAction: false),
        ]),
      ]);
      final insight = actionOf(insights, 'case_split');
      expect(insight.known, isTrue);
      expect(insight.knownActionRatio, 0.0);
      expect(insights.unknownActions, isEmpty);
    });

    test('已知标记为 true 的未知动作仍算词表不认识', () {
      final insights = aggregate(<ChainInsightChain>[
        chain('c1', steps: <ChainInsightStep>[
          step('mystery_move', index: 0, knownAction: true),
        ]),
      ]);
      final insight = actionOf(insights, 'mystery_move');
      expect(insight.knownActionRatio, 1.0);
      expect(insight.known, isFalse);
      expect(insights.unknownActions, hasLength(1));
    });

    test('questionId 首尾空白参与去重', () {
      final insights = aggregate(<ChainInsightChain>[
        chain('c1', questionId: ' q1 ', steps: <ChainInsightStep>[
          step('case_split', index: 0),
        ]),
        chain('c2', steps: <ChainInsightStep>[step('case_split', index: 0)]),
      ]);
      expect(insights.questionCount, 1);
      expect(actionOf(insights, 'case_split').questionCount, 1);
    });
  });

  group('排序、冻结与序列化', () {
    test('动作按步数降序，同分按 actionType 升序', () {
      final insights = aggregate(<ChainInsightChain>[
        chain('c1', steps: <ChainInsightStep>[
          step('case_split', index: 0),
          step('symmetry', index: 1),
        ]),
        chain('c2', questionId: 'q2', steps: <ChainInsightStep>[
          step('case_split', index: 0),
        ]),
        chain('c3', questionId: 'q3', steps: <ChainInsightStep>[
          step('reduction', index: 0),
        ]),
      ]);
      expect(
        insights.actions.map((insight) => insight.actionType).toList(),
        <String>['case_split', 'reduction', 'symmetry'],
      );
    });

    test('平均风险参与排序，null 排最后', () {
      final insights = aggregate(<ChainInsightChain>[
        chain('c1', steps: <ChainInsightStep>[
          step('symmetry', index: 1),
          step('reduction', index: 0, stuckRisk: 0.5),
        ]),
      ]);
      expect(
        insights.actions.map((insight) => insight.actionType).toList(),
        <String>['reduction', 'symmetry'],
      );
      final ordered = aggregate(<ChainInsightChain>[
        chain('c1', steps: <ChainInsightStep>[
          step('symmetry', index: 1, stuckRisk: 0.3),
          step('reduction', index: 0, stuckRisk: 0.9),
        ]),
      ]);
      expect(
        ordered.actions.map((insight) => insight.actionType).toList(),
        <String>['reduction', 'symmetry'],
      );
    });

    test('重复聚合结果一致（确定性）', () {
      final chains = <ChainInsightChain>[
        chain('c1', steps: <ChainInsightStep>[
          step('case_split', index: 0, stuckRisk: 0.7, hints: <String>['函数']),
          step('mystery_move', index: 1),
        ]),
        chain('c2', questionId: 'q2', steps: <ChainInsightStep>[
          step('symmetry', index: 0, stuckRisk: 0.9),
        ]),
      ];
      final first = aggregate(chains, catalog: customCatalog());
      final second = aggregate(chains, catalog: customCatalog());
      expect(jsonEncode(first.toJson()), jsonEncode(second.toJson()));
    });

    test('输出列表不可变', () {
      final insights = aggregate(<ChainInsightChain>[
        chain('c1', steps: <ChainInsightStep>[
          step('case_split', index: 0, stuckRisk: 0.9),
          step('mystery_move', index: 1),
        ]),
      ]);
      expect(
        () => insights.actions.add(insights.actions.first),
        throwsA(isA<UnsupportedError>()),
      );
      expect(
        () => insights.highRiskByQuestion.add(
          const ChainHighRiskGroup(
            key: 'x',
            highRiskStepCount: 0,
            questionCount: 0,
            chainCount: 0,
          ),
        ),
        throwsA(isA<UnsupportedError>()),
      );
      expect(
        () => insights.neverUsedActions.add(CapabilityAction.catalog.first),
        throwsA(isA<UnsupportedError>()),
      );
    });

    test('toJson 含诊断计数且可 JSON 编码', () {
      final t = DateTime.utc(2026, 10, 18, 22, 11);
      final insights = aggregate(<ChainInsightChain>[
        chain('c1', occurredAt: t, steps: <ChainInsightStep>[
          step('case_split', index: 0, stuckRisk: 0.9),
          step('', index: 1),
        ]),
        chain('', steps: <ChainInsightStep>[step('symmetry', index: 0)]),
      ]);
      final json = insights.toJson();
      expect(json['chain_count'], 1);
      expect(json['step_count'], 1);
      expect(json['ignored_chain_count'], 1);
      expect(json['ignored_step_count'], 1);
      expect(json['high_risk_threshold'], 0.6);
      final decoded = jsonDecode(jsonEncode(json)) as Map<String, Object?>;
      expect(decoded['actions'], isA<List<Object?>>());
      final actionJson =
          (decoded['actions']! as List<Object?>).single as Map<String, Object?>;
      expect(actionJson['action_type'], 'case_split');
      expect(actionJson['last_seen_at'], t.toIso8601String());
    });
  });

  group('从解析结果投影', () {
    ParsedChain parsedChain({
      String actionType = 'case_split',
      Map<String, Object?>? stepOverride,
    }) {
      return ParsedChain.fromJson(<String, Object?>{
        'summary': '先分类再验证',
        'steps': <Object?>[
          <String, Object?>{
            'index': 1,
            'goal': '把问题拆成两类',
            'actionType': actionType,
            if (stepOverride != null) ...stepOverride,
          },
        ],
      });
    }

    test('fromParsedStep 复制字段', () {
      final t = DateTime.utc(2026, 10, 18);
      final parsed = ParsedChain.fromJson(<String, Object?>{
        'summary': 's',
        'steps': <Object?>[
          <String, Object?>{
            'index': 2,
            'goal': 'g',
            'actionType': 'case_split',
            'justification': 'j',
            'checkMethod': 'c',
            'stuckRisk': 0.7,
            'knowledgeHints': <String>['函数'],
          },
        ],
      });
      final projected = ChainInsightStep.fromParsedStep(
        parsed.steps.single,
        occurredAt: t,
      );
      expect(projected.actionType, 'case_split');
      expect(projected.index, 2);
      expect(projected.stuckRisk, 0.7);
      expect(projected.knownAction, isTrue);
      expect(projected.knowledgeHints, <String>['函数']);
      expect(projected.occurredAt, t);
    });

    test('fromParsedChain 复制标识与步骤', () {
      final t = DateTime.utc(2026, 10, 18);
      final projected = ChainInsightChain.fromParsedChain(
        parsedChain(),
        chainId: ' c1 ',
        questionId: 'q1',
        occurredAt: t,
      );
      expect(projected.chainId, ' c1 ');
      expect(projected.questionId, 'q1');
      expect(projected.stepCount, 1);
      expect(projected.steps.single.actionType, 'case_split');
      expect(projected.occurredAt, t);
    });

    test('链时间作为步时间的兜底进入聚合', () {
      final t = DateTime.utc(2026, 10, 18, 9);
      final projected = ChainInsightChain.fromParsedChain(
        parsedChain(),
        chainId: 'c1',
        questionId: 'q1',
        occurredAt: t,
      );
      final insights = aggregate(<ChainInsightChain>[projected]);
      expect(actionOf(insights, 'case_split').lastSeenAt, t);
    });

    test('缺 stuckRisk 时继承解析器默认 0.5', () {
      final projected = ChainInsightChain.fromParsedChain(
        parsedChain(),
        chainId: 'c1',
        questionId: 'q1',
      );
      expect(projected.steps.single.stuckRisk, defaultStuckRisk);
      final insights = aggregate(<ChainInsightChain>[projected]);
      expect(actionOf(insights, 'case_split').maxStuckRisk, 0.5);
      expect(insights.highRiskStepCount, 0);
    });

    test('注入 lookup 的自定义动作在聚合中仍算自定义', () {
      final catalog = customCatalog();
      final projected = ChainInsightChain.fromParsedChain(
        ParsedChain.fromJson(
          <String, Object?>{
            'summary': 's',
            'steps': <Object?>[
              <String, Object?>{
                'index': 1,
                'goal': 'g',
                'actionType': 'formula_rewrite',
              },
            ],
          },
          lookup: catalog.byKey,
        ),
        chainId: 'c1',
        questionId: 'q1',
      );
      expect(projected.steps.single.knownAction, isTrue);
      final insights = aggregate(
        <ChainInsightChain>[projected],
        catalog: catalog,
      );
      final insight = actionOf(insights, 'formula_rewrite');
      expect(insight.known, isTrue);
      expect(insight.custom, isTrue);
    });
  });
}
