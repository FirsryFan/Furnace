// 未知能力动作发现层：只统计词表不认识的 actionType，按可复现的排序给出
// 候选动作，供 UI 提示「这个动作值得加进词表」。

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/domain/services/reasoning/capability_action.dart';
import 'package:furnace/domain/services/reasoning/capability_action_discovery.dart';
import 'package:furnace/domain/services/reasoning/capability_action_overlay.dart';

CapabilityStepSample sample(
  String actionType, {
  String questionId = 'q1',
  double? stuckRisk,
}) {
  return CapabilityStepSample(
    actionType: actionType,
    questionId: questionId,
    stuckRisk: stuckRisk,
  );
}

List<CapabilityActionCandidate> discover(
  List<CapabilityStepSample> samples, {
  CapabilityActionCatalog? catalog,
  double highRiskThreshold = CapabilityActionDiscovery.defaultHighRiskThreshold,
  int maxSampleQuestionIds =
      CapabilityActionDiscovery.defaultMaxSampleQuestionIds,
}) {
  return CapabilityActionDiscovery.discover(
    samples: samples,
    catalog: catalog,
    highRiskThreshold: highRiskThreshold,
    maxSampleQuestionIds: maxSampleQuestionIds,
  );
}

CapabilityActionCatalog catalogOf(List<String> customKeys) {
  return CapabilityActionOverlay(
    customActions: <CustomCapabilityAction>[
      for (final key in customKeys)
        CustomCapabilityAction(key: key, labelZh: '自定义-$key'),
    ],
  ).catalog;
}

List<String> actionTypesOf(List<CapabilityActionCandidate> candidates) {
  return <String>[for (final candidate in candidates) candidate.actionType];
}

void main() {
  group('识别未知动作', () {
    test('内置词表全部认识：没有候选', () {
      final samples = <CapabilityStepSample>[
        for (final key in CapabilityAction.keys)
          sample(key, questionId: 'q_$key'),
      ];
      expect(discover(samples), isEmpty);
      expect(CapabilityAction.keys, isNotEmpty);
    });

    test('未知动作：步数 / 题目数 / 样本正确', () {
      final candidates = discover(<CapabilityStepSample>[
        sample('balance_equation', questionId: 'q1'),
        sample('draw_forces', questionId: 'q2'),
        sample('balance_equation', questionId: 'q2'),
      ]);
      expect(candidates.length, 2);
      final balance = candidates.first;
      expect(balance.actionType, 'balance_equation');
      expect(balance.stepCount, 2);
      expect(balance.questionCount, 2);
      expect(balance.highRiskStepCount, 0);
      expect(balance.averageStuckRisk, isNull);
      expect(balance.sampleQuestionIds, <String>['q1', 'q2']);
      final draw = candidates.last;
      expect(draw.actionType, 'draw_forces');
      expect(draw.stepCount, 1);
      expect(draw.questionCount, 1);
      expect(draw.sampleQuestionIds, <String>['q2']);
    });

    test('空白 actionType 丢弃', () {
      final candidates = discover(<CapabilityStepSample>[
        sample(''),
        sample('   ', questionId: ''),
        sample('\t'),
      ]);
      expect(candidates, isEmpty);
    });

    test('首尾空白归整，大小写敏感', () {
      final candidates = discover(<CapabilityStepSample>[
        sample(' first_principles '),
        sample('First_Principles'),
        sample('first_principles'),
      ]);
      expect(candidates.length, 1);
      expect(candidates.single.actionType, 'First_Principles');
      expect(candidates.single.stepCount, 1);
    });
  });

  group('排序', () {
    test('步数降序', () {
      final candidates = discover(<CapabilityStepSample>[
        sample('aaa', questionId: 'q1'),
        sample('aaa', questionId: 'q2'),
        sample('aaa', questionId: 'q3'),
        sample('bbb', questionId: 'q1'),
        sample('bbb', questionId: 'q2'),
        sample('ccc', questionId: 'q1'),
      ]);
      expect(actionTypesOf(candidates), <String>['aaa', 'bbb', 'ccc']);
      expect(candidates[0].stepCount, 3);
      expect(candidates[1].stepCount, 2);
      expect(candidates[2].stepCount, 1);
    });

    test('步数相同按题数降序', () {
      final candidates = discover(<CapabilityStepSample>[
        sample('alpha', questionId: 'q1'),
        sample('alpha', questionId: 'q1'),
        sample('beta', questionId: 'q1'),
        sample('beta', questionId: 'q2'),
      ]);
      expect(actionTypesOf(candidates), <String>['beta', 'alpha']);
      expect(candidates[0].stepCount, 2);
      expect(candidates[1].stepCount, 2);
      expect(candidates[0].questionCount, 2);
      expect(candidates[1].questionCount, 1);
    });

    test('步数题数都相同按 actionType 升序', () {
      final candidates = discover(<CapabilityStepSample>[
        sample('zeta'),
        sample('Alpha'),
        sample('beta'),
      ]);
      expect(actionTypesOf(candidates), <String>['Alpha', 'beta', 'zeta']);
    });
  });

  group('题目统计', () {
    test('同一题多步只算一题，样本按首次出现顺序', () {
      final candidate = discover(<CapabilityStepSample>[
        sample('balance_equation', questionId: 'q1'),
        sample('balance_equation', questionId: 'q2'),
        sample('balance_equation', questionId: 'q1'),
      ]).single;
      expect(candidate.questionCount, 2);
      expect(candidate.stepCount, 3);
      expect(candidate.sampleQuestionIds, <String>['q1', 'q2']);
    });

    test('空 questionId 不计数、不进样本', () {
      final candidate = discover(<CapabilityStepSample>[
        sample('balance_equation', questionId: ''),
        sample('balance_equation', questionId: '   '),
      ]).single;
      expect(candidate.stepCount, 2);
      expect(candidate.questionCount, 0);
      expect(candidate.sampleQuestionIds, isEmpty);
    });

    test('样本截断：默认 5 条', () {
      final samples = <CapabilityStepSample>[
        for (var index = 1; index <= 7; index++)
          sample('balance_equation', questionId: 'q$index'),
      ];
      final candidate = discover(samples).single;
      expect(candidate.questionCount, 7);
      expect(candidate.sampleQuestionIds, <String>[
        'q1',
        'q2',
        'q3',
        'q4',
        'q5',
      ]);
    });

    test('maxSampleQuestionIds 非正数：样本清空', () {
      final samples = <CapabilityStepSample>[
        sample('balance_equation', questionId: 'q1'),
      ];
      expect(
        discover(samples, maxSampleQuestionIds: 0).single.sampleQuestionIds,
        isEmpty,
      );
      expect(
        discover(samples, maxSampleQuestionIds: -3).single.sampleQuestionIds,
        isEmpty,
      );
    });
  });

  group('风险统计', () {
    test('缺失风险不插补：只对有测量的步骤求平均', () {
      final candidate = discover(<CapabilityStepSample>[
        sample('balance_equation', stuckRisk: null),
        sample('balance_equation', stuckRisk: 0.8),
        sample('balance_equation', stuckRisk: null),
      ]).single;
      expect(candidate.stepCount, 3);
      expect(candidate.averageStuckRisk, isNotNull);
      expect(candidate.averageStuckRisk, closeTo(0.8, 0.0001));
      expect(candidate.highRiskStepCount, 1);
    });

    test('完全没有可用测量：平均值为 null、高危 0', () {
      final candidate = discover(<CapabilityStepSample>[
        sample('balance_equation'),
        sample('balance_equation'),
      ]).single;
      expect(candidate.averageStuckRisk, isNull);
      expect(candidate.highRiskStepCount, 0);
    });

    test('默认阈值 0.6 含边界', () {
      final candidate = discover(<CapabilityStepSample>[
        sample('balance_equation', stuckRisk: 0.59),
        sample('balance_equation', stuckRisk: 0.6),
        sample('balance_equation', stuckRisk: 0.61),
      ]).single;
      expect(candidate.highRiskStepCount, 2);
      expect(candidate.averageStuckRisk, closeTo(0.6, 0.0001));
    });

    test('自定义阈值', () {
      final candidate = discover(
        <CapabilityStepSample>[
          sample('balance_equation', stuckRisk: 0.7),
          sample('balance_equation', stuckRisk: 0.8),
        ],
        highRiskThreshold: 0.8,
      ).single;
      expect(candidate.highRiskStepCount, 1);
      expect(candidate.averageStuckRisk, closeTo(0.75, 0.0001));
    });

    test('阈值超界：夹到 0..1', () {
      final high = discover(
        <CapabilityStepSample>[
          sample('aaa', stuckRisk: 0.99),
          sample('aaa', stuckRisk: 1),
        ],
        highRiskThreshold: 1.5,
      ).single;
      expect(high.highRiskStepCount, 1);
      final low = discover(
        <CapabilityStepSample>[
          sample('aaa', stuckRisk: 0),
          sample('aaa', stuckRisk: 0.3),
        ],
        highRiskThreshold: -1,
      ).single;
      expect(low.highRiskStepCount, 2);
    });

    test('风险值夹到 0..1 后再求平均', () {
      final high = discover(<CapabilityStepSample>[
        sample('aaa', stuckRisk: 1.5),
        sample('aaa', stuckRisk: 0.5),
      ]).single;
      expect(high.averageStuckRisk, closeTo(0.75, 0.0001));
      final low = discover(<CapabilityStepSample>[
        sample('aaa', stuckRisk: -0.5),
        sample('aaa', stuckRisk: 0.5),
      ]).single;
      expect(low.averageStuckRisk, closeTo(0.25, 0.0001));
    });

    test('NaN / infinity 不参与统计', () {
      final candidate = discover(<CapabilityStepSample>[
        sample('balance_equation', stuckRisk: double.nan),
        sample('balance_equation', stuckRisk: double.infinity),
        sample('balance_equation', stuckRisk: double.negativeInfinity),
        sample('balance_equation', stuckRisk: null),
      ]).single;
      expect(candidate.stepCount, 4);
      expect(candidate.averageStuckRisk, isNull);
      expect(candidate.highRiskStepCount, 0);
    });

    test('阈值 NaN 退回默认 0.6', () {
      final candidate = discover(
        <CapabilityStepSample>[
          sample('aaa', stuckRisk: 0.5),
          sample('aaa', stuckRisk: 0.7),
        ],
        highRiskThreshold: double.nan,
      ).single;
      expect(candidate.highRiskStepCount, 1);
    });
  });

  group('词表来源', () {
    test('默认只用内置词表：自定义动作也算未知', () {
      final candidate = discover(<CapabilityStepSample>[
        sample('force_diagram'),
      ]).single;
      expect(candidate.actionType, 'force_diagram');
    });

    test('传 overlay.catalog：已生效的自定义动作不再算未知', () {
      final candidates = discover(
        <CapabilityStepSample>[
          sample('force_diagram'),
          sample('balance_equation'),
        ],
        catalog: catalogOf(<String>['force_diagram']),
      );
      expect(actionTypesOf(candidates), <String>['balance_equation']);
    });

    test('传自定义 catalog 时内置动作仍然认识', () {
      final candidates = discover(
        <CapabilityStepSample>[
          sample('first_principles'),
          sample('force_diagram'),
        ],
        catalog: catalogOf(<String>['force_diagram']),
      );
      expect(candidates, isEmpty);
    });
  });

  group('输出', () {
    test('空样本返回空列表', () {
      expect(discover(<CapabilityStepSample>[]), isEmpty);
    });

    test('返回列表与样本题目列表都不可变', () {
      final candidates = discover(<CapabilityStepSample>[
        sample('balance_equation', questionId: 'q1'),
      ]);
      expect(
        () => candidates.add(
          const CapabilityActionCandidate(
            actionType: 'x',
            stepCount: 0,
            questionCount: 0,
            highRiskStepCount: 0,
            averageStuckRisk: null,
            sampleQuestionIds: <String>[],
          ),
        ),
        throwsUnsupportedError,
      );
      expect(
        () => candidates.single.sampleQuestionIds.add('q9'),
        throwsUnsupportedError,
      );
    });

    test('toJson 可往返 JSON', () {
      final candidate = discover(<CapabilityStepSample>[
        sample('balance_equation', questionId: 'q1', stuckRisk: 0.5),
        sample('balance_equation', questionId: 'q2', stuckRisk: 0.7),
      ]).single;
      final decoded = jsonDecode(jsonEncode(candidate.toJson()));
      expect(decoded, isA<Map<String, Object?>>());
      final map = decoded as Map<String, Object?>;
      expect(map['actionType'], 'balance_equation');
      expect(map['stepCount'], 2);
      expect(map['questionCount'], 2);
      expect(map['highRiskStepCount'], 1);
      expect(
        (map['averageStuckRisk']! as num).toDouble(),
        closeTo(0.6, 0.0001),
      );
      expect(map['sampleQuestionIds'], <String>['q1', 'q2']);
    });
  });
}
