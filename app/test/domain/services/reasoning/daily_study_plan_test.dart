import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/domain/services/reasoning/chain_insights.dart';
import 'package:furnace/domain/services/reasoning/daily_study_plan.dart';
import 'package:furnace/domain/services/reasoning/learning_advice.dart';
import 'package:furnace/domain/services/reasoning/practice_recommendation.dart';

const _caseSplit = 'case_split';
const _mysteryMove = 'mystery_move';
const _weirdShift = 'weird_shift';

ChainInsights _emptyInsights() =>
    ChainInsights.aggregate(chains: const <ChainInsightChain>[]);

ChainInsights _highRiskInsights({int chains = 3}) {
  return ChainInsights.aggregate(
    chains: <ChainInsightChain>[
      for (var i = 0; i < chains; i++)
        ChainInsightChain(
          chainId: 'chain-$i',
          questionId: 'question-$i',
          steps: const <ChainInsightStep>[
            ChainInsightStep(
              actionType: _caseSplit,
              index: 0,
              stuckRisk: 0.9,
              knownAction: true,
              knowledgeHints: <String>['kp1'],
            ),
          ],
        ),
    ],
  );
}

ChainInsights _unknownInsights({
  List<String> actionTypes = const <String>[_mysteryMove, _weirdShift],
}) {
  return ChainInsights.aggregate(
    chains: <ChainInsightChain>[
      ChainInsightChain(
        chainId: 'unknown-chain',
        questionId: 'unknown-question',
        steps: <ChainInsightStep>[
          for (var i = 0; i < actionTypes.length; i++)
            ChainInsightStep(
              actionType: actionTypes[i],
              index: i,
              stuckRisk: 0.2,
              knownAction: false,
            ),
        ],
      ),
    ],
  );
}

ChainInsights _mixedInsights() {
  return ChainInsights.aggregate(
    chains: <ChainInsightChain>[
      for (var i = 0; i < 3; i++)
        ChainInsightChain(
          chainId: 'high-$i',
          questionId: 'high-question-$i',
          steps: const <ChainInsightStep>[
            ChainInsightStep(
              actionType: _caseSplit,
              index: 0,
              stuckRisk: 0.9,
              knownAction: true,
              knowledgeHints: <String>['kp1'],
            ),
          ],
        ),
      const ChainInsightChain(
        chainId: 'unknown-chain',
        questionId: 'unknown-question',
        steps: <ChainInsightStep>[
          ChainInsightStep(
            actionType: _mysteryMove,
            index: 0,
            stuckRisk: 0.2,
            knownAction: false,
          ),
        ],
      ),
    ],
  );
}

LearningAdvicePlan _practiceAdvices() => LearningAdvicePlan.build(
      insights: _highRiskInsights(),
    );

LearningAdvicePlan _collectAdvices() => LearningAdvicePlan.build(
      insights: _emptyInsights(),
      corpusQuestionCount: 3,
    );

PracticeRecommendationPlan _recommendations(
  List<PracticeQuestionCandidate> candidates, {
  Set<String>? actionTypes,
  Set<String>? knowledgePointIds,
}) {
  return PracticeRecommendationPlan.build(
    insights: _emptyInsights(),
    advicePlan: LearningAdvicePlan.empty(),
    candidates: candidates,
    preferredActionTypes: actionTypes,
    preferredKnowledgePointIds: knowledgePointIds,
  );
}

PracticeRecommendationPlan _defaultRecommendations({int count = 2}) {
  return _recommendations(<PracticeQuestionCandidate>[
    for (var i = 1; i <= count; i++)
      PracticeQuestionCandidate(
        questionId: 'q$i',
        knowledgePointIds: const <String>['kp1'],
        actionTypes: const <String>[_caseSplit],
      ),
  ]);
}

DailyStudyPlan _build({
  ChainInsights? insights,
  LearningAdvicePlan? advices,
  PracticeRecommendationPlan? recommendations,
  int? dueCardCount,
  int dailyMinutes = DailyStudyPlan.defaultDailyMinutes,
  int maxSteps = DailyStudyPlan.defaultMaxSteps,
}) {
  return DailyStudyPlan.build(
    insights: insights ?? _emptyInsights(),
    advices: advices ?? LearningAdvicePlan.empty(),
    recommendations: recommendations,
    dueCardCount: dueCardCount,
    dailyMinutes: dailyMinutes,
    maxSteps: maxSteps,
  );
}

void main() {
  group('空输入与 noData', () {
    test('空输入返回单条 noData 步骤，不虚构计划', () {
      final plan = _build();
      expect(plan.steps, hasLength(1));
      final step = plan.steps.single;
      expect(step.kind, DailyPlanStepKind.noData);
      expect(step.priority, 600);
      expect(step.estimatedMinutes, 0);
      expect(step.titleZh, '今天没有可依据的数据');
      expect(plan.totalMinutes, 0);
      expect(plan.skippedStepCount, 0);
      expect(plan.isEmpty, isFalse);
      expect(plan.isNotEmpty, isTrue);
      expect(plan.focusKnowledgePointIds, isEmpty);
    });

    test('noData 文案如实说明没有数据且不虚构', () {
      final step = _build().steps.single;
      expect(step.detailZh, contains('今天没有到期卡片'));
      expect(step.detailZh, contains('不虚构计划'));
      expect(step.kind, DailyPlanStepKind.noData);
      expect(step.actionType, isNull);
      expect(step.cardCount, isNull);
      expect(step.questionIds, isEmpty);
      expect(step.knowledgePointIds, isEmpty);
    });

    test('空输入两次构建结果完全一致', () {
      final a = _build();
      final b = _build();
      expect(jsonEncode(a.toJson()), jsonEncode(b.toJson()));
    });

    test('空列表输入不抛异常', () {
      final emptyRecommendations = _recommendations(
        const <PracticeQuestionCandidate>[],
      );
      final plan = _build(recommendations: emptyRecommendations);
      expect(plan.steps.single.kind, DailyPlanStepKind.noData);
    });

    test('只有洞察读数时给 keepGoing 兜底一步', () {
      final plan = _build(insights: _highRiskInsights());
      expect(plan.steps, hasLength(1));
      final step = plan.steps.single;
      expect(step.kind, DailyPlanStepKind.keepGoing);
      expect(step.priority, 500);
      expect(step.estimatedMinutes, 1);
      expect(plan.totalMinutes, 1);
      expect(plan.skippedStepCount, 0);
    });

    test('只有 noData 建议不算证据', () {
      final noDataAdvices = LearningAdvicePlan.build(
        insights: _emptyInsights(),
      );
      expect(noDataAdvices.isNotEmpty, isTrue);
      final plan = _build(advices: noDataAdvices);
      expect(plan.steps.single.kind, DailyPlanStepKind.noData);
    });

    test('只有未知动作时只给补词表步骤，不给练习步骤', () {
      final plan = _build(
        insights: _unknownInsights(),
        advices: LearningAdvicePlan.build(insights: _unknownInsights()),
      );
      expect(plan.steps, hasLength(1));
      final step = plan.steps.single;
      expect(step.kind, DailyPlanStepKind.reviewVocabulary);
      expect(
        plan.steps.any(
          (step) => step.kind == DailyPlanStepKind.practiceQuestions,
        ),
        isFalse,
      );
    });
  });

  group('到期卡片', () {
    test('只有到期卡片时排一步且按 ceil(卡数/2) 估算', () {
      final plan = _build(dueCardCount: 4);
      final step = plan.steps.single;
      expect(step.kind, DailyPlanStepKind.reviewDueCards);
      expect(step.priority, 100);
      expect(step.cardCount, 4);
      expect(step.estimatedMinutes, 2);
      expect(step.detailZh, contains('到期卡片 4 张'));
      expect(step.detailZh, contains('2 分钟'));
      expect(plan.totalMinutes, 2);
      expect(plan.skippedStepCount, 0);
    });

    test('一张到期卡片估算 1 分钟', () {
      final plan = _build(dueCardCount: 1);
      expect(plan.steps.single.estimatedMinutes, 1);
    });

    test('卡片很多时按预算截断', () {
      final plan = _build(dueCardCount: 100, dailyMinutes: 3);
      final step = plan.steps.single;
      expect(step.cardCount, 100);
      expect(step.estimatedMinutes, 3);
      expect(plan.totalMinutes, 3);
    });

    test('dueCardCount 为 0 视为没有到期卡片', () {
      final plan = _build(dueCardCount: 0);
      expect(plan.steps.single.kind, DailyPlanStepKind.noData);
    });

    test('dueCardCount 为负数视为没有到期卡片', () {
      final plan = _build(dueCardCount: -3);
      expect(plan.steps.single.kind, DailyPlanStepKind.noData);
      expect(plan.totalMinutes, 0);
    });

    test('卡片步按自然时长 min(剩余, ceil(卡数/2)) 截断', () {
      final plan = _build(dueCardCount: 5, dailyMinutes: 8);
      expect(plan.steps.single.estimatedMinutes, 3);
      expect(plan.totalMinutes, 3);
    });
  });

  group('练习配题', () {
    test('练习步骤带题单、动作与知识点', () {
      final plan = _build(
        insights: _highRiskInsights(),
        advices: _practiceAdvices(),
        recommendations: _defaultRecommendations(),
      );
      expect(plan.steps, hasLength(1));
      final step = plan.steps.single;
      expect(step.kind, DailyPlanStepKind.practiceQuestions);
      expect(step.priority, 200);
      expect(step.questionIds, <String>['q1', 'q2']);
      expect(step.estimatedMinutes, 4);
      expect(step.actionType, _caseSplit);
      expect(step.knowledgePointIds, <String>['kp1']);
      expect(step.detailZh, contains('前 2 道题'));
      expect(step.detailZh, contains('每道约 2 分钟'));
      expect(step.detailZh, contains('重点动作：case_split'));
      expect(plan.totalMinutes, 4);
    });

    test('有练习动作建议但配题推荐为空时不生成练习步骤', () {
      final emptyRecommendations = _recommendations(
        const <PracticeQuestionCandidate>[],
      );
      final plan = _build(
        insights: _highRiskInsights(),
        advices: _practiceAdvices(),
        recommendations: emptyRecommendations,
      );
      expect(plan.steps.single.kind, DailyPlanStepKind.keepGoing);
      expect(
        plan.steps.any(
          (step) => step.kind == DailyPlanStepKind.practiceQuestions,
        ),
        isFalse,
      );
    });

    test('没有练习动作建议时动作与知识点回退到推荐命中项', () {
      final recommendations = _recommendations(
        const <PracticeQuestionCandidate>[
          PracticeQuestionCandidate(
            questionId: 'q1',
            knowledgePointIds: <String>['kpa'],
            actionTypes: <String>[_caseSplit],
          ),
          PracticeQuestionCandidate(
            questionId: 'q2',
            knowledgePointIds: <String>['kpa', 'kpb'],
            actionTypes: <String>[_caseSplit],
          ),
        ],
        actionTypes: <String>{_caseSplit},
        knowledgePointIds: <String>{'kpa', 'kpb'},
      );
      final plan = _build(
        advices: LearningAdvicePlan.empty(),
        recommendations: recommendations,
      );
      final step = plan.steps.single;
      expect(step.kind, DailyPlanStepKind.practiceQuestions);
      expect(step.actionType, _caseSplit);
      expect(step.knowledgePointIds, <String>['kpa', 'kpb']);
    });

    test('预算 3 分钟只排 1 道题', () {
      final plan = _build(
        recommendations: _defaultRecommendations(count: 4),
        dailyMinutes: 3,
      );
      final step = plan.steps.single;
      expect(step.questionIds, <String>['q1']);
      expect(step.estimatedMinutes, 2);
      expect(plan.totalMinutes, 2);
    });

    test('预算 1 分钟排不下练习时计入 skipped 并给 keepGoing', () {
      final plan = _build(
        recommendations: _defaultRecommendations(),
        dailyMinutes: 1,
      );
      expect(plan.skippedStepCount, 1);
      expect(plan.steps.single.kind, DailyPlanStepKind.keepGoing);
      expect(plan.totalMinutes, 1);
    });

    test('卡片先占预算后练习按剩余预算缩减题数', () {
      final plan = _build(
        dueCardCount: 1,
        recommendations: _defaultRecommendations(count: 4),
        dailyMinutes: 4,
      );
      expect(plan.steps, hasLength(2));
      expect(plan.steps[0].kind, DailyPlanStepKind.reviewDueCards);
      expect(plan.steps[1].kind, DailyPlanStepKind.practiceQuestions);
      expect(plan.steps[1].questionIds, <String>['q1']);
      expect(plan.totalMinutes, 3);
      expect(plan.skippedStepCount, 0);
    });

    test('练习题单按推荐名次排序而不是候选传入顺序', () {
      final recommendations = _recommendations(
        const <PracticeQuestionCandidate>[
          PracticeQuestionCandidate(questionId: 'q3'),
          PracticeQuestionCandidate(questionId: 'q1'),
          PracticeQuestionCandidate(questionId: 'q2'),
        ],
      );
      final plan = _build(recommendations: recommendations);
      expect(plan.steps.single.questionIds, <String>['q1', 'q2', 'q3']);
    });
  });

  group('补齐思维链', () {
    test('只有补齐思维链建议时排一步 5 分钟', () {
      final plan = _build(advices: _collectAdvices());
      expect(plan.steps, hasLength(1));
      final step = plan.steps.single;
      expect(step.kind, DailyPlanStepKind.collectChains);
      expect(step.priority, 300);
      expect(step.estimatedMinutes, 5);
      expect(plan.totalMinutes, 5);
      expect(step.detailZh, isNotEmpty);
    });

    test('预算不够时补链步骤用剩余分钟', () {
      final plan = _build(
        advices: _collectAdvices(),
        dueCardCount: 1,
        dailyMinutes: 3,
      );
      expect(plan.steps, hasLength(2));
      expect(plan.steps[1].kind, DailyPlanStepKind.collectChains);
      expect(plan.steps[1].estimatedMinutes, 2);
      expect(plan.totalMinutes, 3);
    });

    test('剩余预算为 0 时补链计入 skipped', () {
      final plan = _build(
        advices: _collectAdvices(),
        dueCardCount: 6,
        dailyMinutes: 2,
      );
      expect(plan.skippedStepCount, 1);
      expect(plan.steps, hasLength(1));
      expect(plan.steps.single.kind, DailyPlanStepKind.reviewDueCards);
      expect(plan.totalMinutes, 2);
    });

    test('练习排在补链之前', () {
      final advices = LearningAdvicePlan.build(
        insights: _highRiskInsights(),
        corpusQuestionCount: 10,
      );
      final plan = _build(
        insights: _highRiskInsights(),
        advices: advices,
        recommendations: _defaultRecommendations(),
      );
      expect(plan.steps, hasLength(2));
      expect(plan.steps[0].kind, DailyPlanStepKind.practiceQuestions);
      expect(plan.steps[1].kind, DailyPlanStepKind.collectChains);
      expect(plan.totalMinutes, 9);
    });
  });

  group('补能力动作词表', () {
    test('未知动作排一步补词表 3 分钟', () {
      final plan = _build(insights: _unknownInsights());
      expect(plan.steps, hasLength(1));
      final step = plan.steps.single;
      expect(step.kind, DailyPlanStepKind.reviewVocabulary);
      expect(step.priority, 400);
      expect(step.estimatedMinutes, 3);
      expect(step.detailZh, contains('词表还不认识 2 个动作'));
      expect(step.detailZh, contains(_mysteryMove));
      expect(step.detailZh, contains(_weirdShift));
      expect(plan.totalMinutes, 3);
    });

    test('补词表排在补链之后', () {
      final insights = _unknownInsights();
      final plan = _build(
        insights: insights,
        advices: LearningAdvicePlan.build(
          insights: insights,
          corpusQuestionCount: 5,
        ),
      );
      expect(plan.steps, hasLength(2));
      expect(plan.steps[0].kind, DailyPlanStepKind.collectChains);
      expect(plan.steps[1].kind, DailyPlanStepKind.reviewVocabulary);
      expect(plan.totalMinutes, 8);
    });

    test('词表步骤最多列 5 个动作名', () {
      final actionTypes = <String>[
        for (var i = 0; i < 7; i++) 'unknown_$i',
      ];
      final insights = _unknownInsights(actionTypes: actionTypes);
      final plan = _build(insights: insights);
      final detail = plan.steps.single.detailZh;
      final names = <String>[
        for (final action in insights.unknownActions) action.actionType,
      ];
      expect(names, hasLength(7));
      expect(detail, contains('词表还不认识 7 个动作'));
      expect(detail, contains(names.take(5).join('、')));
      expect(detail, isNot(contains(names[5])));
    });

    test('未知动作不会单独生成练习步骤', () {
      final insights = _unknownInsights();
      final plan = _build(
        insights: insights,
        advices: LearningAdvicePlan.build(insights: insights),
      );
      expect(
        plan.steps.any(
          (step) => step.kind == DailyPlanStepKind.practiceQuestions,
        ),
        isFalse,
      );
      expect(plan.steps.single.kind, DailyPlanStepKind.reviewVocabulary);
      expect(plan.skippedStepCount, 0);
    });
  });

  group('优先级、预算与 maxSteps', () {
    DailyStudyPlan complexPlan({int dailyMinutes = 30, int maxSteps = 5}) {
      final insights = _mixedInsights();
      return _build(
        insights: insights,
        advices: LearningAdvicePlan.build(
          insights: insights,
          corpusQuestionCount: insights.questionCount + 2,
        ),
        recommendations: _defaultRecommendations(count: 1),
        dueCardCount: 2,
        dailyMinutes: dailyMinutes,
        maxSteps: maxSteps,
      );
    }

    test('四类步骤按固定优先级排列', () {
      final plan = complexPlan();
      expect(plan.steps, hasLength(4));
      expect(
        <int>[for (final step in plan.steps) step.priority],
        <int>[100, 200, 300, 400],
      );
      expect(plan.totalMinutes, 11);
      expect(plan.skippedStepCount, 0);
    });

    test('maxSteps 为 1 时只排第一步，其余计入 skipped', () {
      final plan = complexPlan(maxSteps: 1);
      expect(plan.steps, hasLength(1));
      expect(plan.steps.single.kind, DailyPlanStepKind.reviewDueCards);
      expect(plan.skippedStepCount, 3);
      expect(plan.totalMinutes, 1);
    });

    test('maxSteps 小于 1 时按 1 处理', () {
      final plan = complexPlan(maxSteps: 0);
      expect(plan.steps, hasLength(1));
      expect(plan.skippedStepCount, 3);
    });

    test('maxSteps 大于上限时按 8 处理且四步都能排下', () {
      final plan = complexPlan(maxSteps: 20);
      expect(plan.steps, hasLength(4));
      expect(plan.skippedStepCount, 0);
    });

    test('dailyMinutes 小于 1 时按 1 处理', () {
      final plan = _build(dueCardCount: 1, dailyMinutes: 0);
      expect(plan.totalMinutes, 1);
      expect(plan.steps.single.estimatedMinutes, 1);
    });

    test('dailyMinutes 为负数时按 1 处理', () {
      final plan = _build(dueCardCount: 3, dailyMinutes: -10);
      expect(plan.totalMinutes, 1);
    });

    test('总分钟数不超过每日预算', () {
      final cases = <int>[1, 2, 3, 5, 8, 30, 120];
      for (final budget in cases) {
        final plan = complexPlan(dailyMinutes: budget, maxSteps: 8);
        expect(
          plan.totalMinutes <= budget,
          isTrue,
          reason: '预算 $budget',
        );
      }
    });

    test('预算耗尽时后续候选计入 skipped', () {
      final plan = _build(
        advices: _collectAdvices(),
        recommendations: _defaultRecommendations(count: 4),
        dueCardCount: 9,
        dailyMinutes: 6,
      );
      expect(plan.steps, hasLength(2));
      expect(plan.steps, hasLength(2));
      expect(plan.steps[0].kind, DailyPlanStepKind.reviewDueCards);
      expect(plan.steps[1].kind, DailyPlanStepKind.collectChains);
      expect(plan.steps[1].estimatedMinutes, 1);
      expect(plan.skippedStepCount, 1);
      expect(plan.totalMinutes, 6);
    });
  });

  group('焦点知识点', () {
    test('焦点来自练习步骤并去重保序', () {
      final recommendations = _recommendations(
        const <PracticeQuestionCandidate>[
          PracticeQuestionCandidate(
            questionId: 'q1',
            knowledgePointIds: <String>['kpa', 'kpb'],
          ),
          PracticeQuestionCandidate(
            questionId: 'q2',
            knowledgePointIds: <String>['kpb', 'kpc'],
          ),
        ],
        knowledgePointIds: <String>{'kpa', 'kpb', 'kpc'},
      );
      final plan = _build(recommendations: recommendations);
      expect(plan.focusKnowledgePointIds, <String>['kpa', 'kpb', 'kpc']);
    });

    test('焦点知识点最多 5 个', () {
      final candidates = <PracticeQuestionCandidate>[
        const PracticeQuestionCandidate(
          questionId: 'q1',
          knowledgePointIds: <String>['k1', 'k2'],
        ),
        const PracticeQuestionCandidate(
          questionId: 'q2',
          knowledgePointIds: <String>['k3', 'k4'],
        ),
        const PracticeQuestionCandidate(
          questionId: 'q3',
          knowledgePointIds: <String>['k5', 'k6'],
        ),
      ];
      final recommendations = _recommendations(
        candidates,
        knowledgePointIds: <String>{'k1', 'k2', 'k3', 'k4', 'k5', 'k6'},
      );
      final plan = _build(recommendations: recommendations);
      expect(
          plan.focusKnowledgePointIds, <String>['k1', 'k2', 'k3', 'k4', 'k5']);
    });

    test('没有练习步骤时焦点仍可来自练习动作建议', () {
      final plan = _build(
        insights: _highRiskInsights(),
        advices: _practiceAdvices(),
      );
      expect(plan.steps.single.kind, DailyPlanStepKind.keepGoing);
      expect(plan.focusKnowledgePointIds, <String>['kp1']);
    });

    test('只有到期卡片时焦点为空', () {
      final plan = _build(dueCardCount: 3);
      expect(plan.focusKnowledgePointIds, isEmpty);
    });
  });

  group('JSON 与常量', () {
    test('步骤 toJson 键序固定', () {
      final step = _build(dueCardCount: 2).steps.single;
      expect(step.toJson().keys.toList(), <String>[
        'kind',
        'priority',
        'title_zh',
        'detail_zh',
        'estimated_minutes',
        'action_type',
        'knowledge_point_ids',
        'question_ids',
        'card_count',
      ]);
    });

    test('计划 toJson 键序固定且值正确', () {
      final plan = _build(
        dueCardCount: 1,
        recommendations: _defaultRecommendations(),
      );
      final json = plan.toJson();
      expect(json.keys.toList(), <String>[
        'steps',
        'total_minutes',
        'focus_knowledge_point_ids',
        'skipped_step_count',
        'is_empty',
      ]);
      expect(json['total_minutes'], 1 + 4);
      expect(json['is_empty'], isFalse);
      expect((json['steps']! as List<Object?>).length, 2);
    });

    test('noData 计划 toJson 如实', () {
      final json = _build().toJson();
      expect(json['total_minutes'], 0);
      expect(json['is_empty'], isFalse);
      final steps = json['steps']! as List<Object?>;
      final first = steps.single! as Map<String, Object?>;
      expect(first['kind'], 'noData');
      expect(first['estimated_minutes'], 0);
      expect(first['priority'], 600);
    });

    test('枚举中文名齐全', () {
      expect(DailyPlanStepKind.practiceQuestions.labelZh, '练习配题推荐');
      expect(DailyPlanStepKind.reviewDueCards.labelZh, '复习到期卡片');
      expect(DailyPlanStepKind.collectChains.labelZh, '补齐思维链');
      expect(DailyPlanStepKind.reviewVocabulary.labelZh, '补能力动作词表');
      expect(DailyPlanStepKind.keepGoing.labelZh, '继续保持');
      expect(DailyPlanStepKind.noData.labelZh, '今天没有可依据的数据');
    });

    test('公开常量值固定', () {
      expect(DailyStudyPlan.defaultDailyMinutes, 30);
      expect(DailyStudyPlan.defaultMaxSteps, 5);
      expect(DailyStudyPlan.minDailyMinutes, 1);
      expect(DailyStudyPlan.minStepLimit, 1);
      expect(DailyStudyPlan.maxStepLimit, 8);
      expect(DailyStudyPlan.maxFocusKnowledgePoints, 5);
    });

    test('步骤列表不可变', () {
      final plan = _build(dueCardCount: 2);
      expect(
        () => plan.steps.add(_build().steps.single),
        throwsUnsupportedError,
      );
      expect(
        () => plan.focusKnowledgePointIds.add('x'),
        throwsUnsupportedError,
      );
    });

    test('步骤内列表不可变', () {
      final plan = _build(
        recommendations: _defaultRecommendations(),
      );
      final step = plan.steps.single;
      expect(
        () => step.questionIds.add('x'),
        throwsUnsupportedError,
      );
      expect(
        () => step.knowledgePointIds.add('x'),
        throwsUnsupportedError,
      );
    });

    test('混合输入两次构建 JSON 完全一致', () {
      final insights = _mixedInsights();
      final planA = _build(
        insights: insights,
        advices: LearningAdvicePlan.build(
          insights: insights,
          corpusQuestionCount: 10,
        ),
        recommendations: _defaultRecommendations(),
        dueCardCount: 3,
      );
      final planB = _build(
        insights: insights,
        advices: LearningAdvicePlan.build(
          insights: insights,
          corpusQuestionCount: 10,
        ),
        recommendations: _defaultRecommendations(),
        dueCardCount: 3,
      );
      expect(jsonEncode(planA.toJson()), jsonEncode(planB.toJson()));
    });
  });
}
