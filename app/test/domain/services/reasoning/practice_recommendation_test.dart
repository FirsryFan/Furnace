import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/domain/services/reasoning/chain_insights.dart';
import 'package:furnace/domain/services/reasoning/learning_advice.dart';
import 'package:furnace/domain/services/reasoning/practice_recommendation.dart';

void main() {
  group('练习建议与卡点偏好的来源', () {
    test('测试前提：三条高危同动作步会生成练习建议', () {
      final plan = _practicePlan();
      expect(
        plan.advices.any(
          (advice) =>
              advice.kind == LearningAdviceKind.practiceAction &&
              advice.actionType == 'case_split',
        ),
        isTrue,
        reason: '测试样本必须能产出 practiceAction 建议，否则后续断言没有意义',
      );
      expect(
        plan.advices
            .where((advice) => advice.kind == LearningAdviceKind.practiceAction)
            .expand((advice) => advice.knowledgePointIds)
            .toList(),
        contains('kp1'),
      );
    });

    test('命中练习建议动作加 adviceActionScore 分', () {
      final plan = _buildPlan(
        insights: _practiceInsights(),
        advicePlan: _practicePlan(),
        candidates: <PracticeQuestionCandidate>[
          _candidate('q1', actionTypes: <String>['case_split']),
        ],
      );
      final recommendation = plan.recommendations.single;
      expect(
          recommendation.score, PracticeRecommendationPlan.adviceActionScore);
      expect(recommendation.reasons, <PracticeRecommendationReason>[
        PracticeRecommendationReason.matchedAdviceAction,
      ]);
      expect(recommendation.matchedActionTypes, <String>['case_split']);
      expect(recommendation.matchedKnowledgePointIds, isEmpty);
    });

    test('命中练习建议里的知识点加 highRiskKnowledgePointScore 分', () {
      final plan = _buildPlan(
        insights: _practiceInsights(),
        advicePlan: _practicePlan(),
        candidates: <PracticeQuestionCandidate>[
          _candidate('q1', knowledgePointIds: <String>['kp1']),
        ],
      );
      final recommendation = plan.recommendations.single;
      expect(
        recommendation.score,
        PracticeRecommendationPlan.highRiskKnowledgePointScore,
      );
      expect(recommendation.reasons, <PracticeRecommendationReason>[
        PracticeRecommendationReason.matchedHighRiskKnowledgePoint,
      ]);
      expect(recommendation.matchedKnowledgePointIds, <String>['kp1']);
    });

    test('动作与知识点同时命中时分数相加、理由按枚举序', () {
      final plan = _buildPlan(
        insights: _practiceInsights(),
        advicePlan: _practicePlan(),
        candidates: <PracticeQuestionCandidate>[
          _candidate(
            'q1',
            actionTypes: <String>['case_split'],
            knowledgePointIds: <String>['kp1'],
          ),
        ],
      );
      final recommendation = plan.recommendations.single;
      expect(recommendation.score, closeTo(5.0, 1e-9));
      expect(recommendation.reasons, <PracticeRecommendationReason>[
        PracticeRecommendationReason.matchedAdviceAction,
        PracticeRecommendationReason.matchedHighRiskKnowledgePoint,
      ]);
    });

    test('没有练习建议时知识点偏好退回洞察里的卡点知识点', () {
      final plan = _buildPlan(
        insights: _singleRiskInsights(),
        advicePlan: LearningAdvicePlan.empty(),
        candidates: <PracticeQuestionCandidate>[
          _candidate('q1', knowledgePointIds: <String>['kp9']),
        ],
      );
      final recommendation = plan.recommendations.single;
      expect(
        recommendation.score,
        PracticeRecommendationPlan.highRiskKnowledgePointScore,
      );
      expect(recommendation.reasons, <PracticeRecommendationReason>[
        PracticeRecommendationReason.matchedHighRiskKnowledgePoint,
      ]);
    });
  });

  group('未知动作补习', () {
    test('命中未知动作加 unknownActionScaffoldScore 分并标记理由', () {
      final plan = _buildPlan(
        insights: _mixedInsights(),
        candidates: <PracticeQuestionCandidate>[
          _candidate('q1', actionTypes: <String>['mystery_move']),
        ],
      );
      final recommendation = plan.recommendations.single;
      expect(
        recommendation.score,
        PracticeRecommendationPlan.unknownActionScaffoldScore,
      );
      expect(recommendation.reasons, <PracticeRecommendationReason>[
        PracticeRecommendationReason.unknownActionScaffold,
      ]);
    });

    test('关闭未知动作补习后不加分、不产生补习理由', () {
      final plan = _buildPlan(
        insights: _mixedInsights(),
        candidates: <PracticeQuestionCandidate>[
          _candidate('q1', actionTypes: <String>['mystery_move']),
        ],
        includeUnknownActionScaffold: false,
      );
      final recommendation = plan.recommendations.single;
      expect(recommendation.score, 0.0);
      expect(recommendation.reasons, <PracticeRecommendationReason>[
        PracticeRecommendationReason.unrelated,
      ]);
    });

    test('未知动作补习关闭不影响按建议动作命中', () {
      final plan = _buildPlan(
        insights: _mixedInsights(),
        advicePlan: _practicePlanOf(_mixedInsights()),
        candidates: <PracticeQuestionCandidate>[
          _candidate('q1', actionTypes: <String>['case_split']),
        ],
        includeUnknownActionScaffold: false,
      );
      final recommendation = plan.recommendations.single;
      expect(
          recommendation.score, PracticeRecommendationPlan.adviceActionScore);
      expect(recommendation.reasons, <PracticeRecommendationReason>[
        PracticeRecommendationReason.matchedAdviceAction,
      ]);
    });
  });

  group('难度贴近与资料完整度', () {
    test('难度与目标一致时拿满难度分', () {
      final plan = _buildPlan(
        candidates: <PracticeQuestionCandidate>[
          _candidate('q1', difficulty: 3.0),
        ],
        targetDifficulty: 3.0,
      );
      final recommendation = plan.recommendations.single;
      expect(
        recommendation.score,
        closeTo(PracticeRecommendationPlan.difficultyMatchScore, 1e-9),
      );
      expect(recommendation.reasons, <PracticeRecommendationReason>[
        PracticeRecommendationReason.unrelated,
      ]);
    });

    test('难度差值在容差内不提示偏难偏易', () {
      final plan = _buildPlan(
        candidates: <PracticeQuestionCandidate>[
          _candidate('q1', difficulty: 3.4),
        ],
        targetDifficulty: 3.0,
      );
      final recommendation = plan.recommendations.single;
      expect(recommendation.score, closeTo(1.6, 1e-9));
      expect(recommendation.reasons,
          isNot(contains(PracticeRecommendationReason.tooHard)));
      expect(recommendation.reasons,
          isNot(contains(PracticeRecommendationReason.tooEasy)));
    });

    test('难度偏高按距离扣难度分并标记 tooHard', () {
      final plan = _buildPlan(
        candidates: <PracticeQuestionCandidate>[
          _candidate('q1', difficulty: 4.5),
        ],
        targetDifficulty: 3.0,
      );
      final recommendation = plan.recommendations.single;
      expect(recommendation.score, closeTo(0.5, 1e-9));
      expect(
        recommendation.reasons,
        contains(PracticeRecommendationReason.tooHard),
      );
      expect(
        recommendation.reasons,
        isNot(contains(PracticeRecommendationReason.tooEasy)),
      );
    });

    test('难度偏低按距离扣难度分并标记 tooEasy', () {
      final plan = _buildPlan(
        candidates: <PracticeQuestionCandidate>[
          _candidate('q1', difficulty: 0.5),
        ],
        targetDifficulty: 3.0,
      );
      final recommendation = plan.recommendations.single;
      expect(recommendation.score, 0.0);
      expect(
        recommendation.reasons,
        contains(PracticeRecommendationReason.tooEasy),
      );
      expect(
        recommendation.reasons,
        isNot(contains(PracticeRecommendationReason.tooHard)),
      );
    });

    test('NaN 难度当作无读数：不计分也不提示难度', () {
      final plan = _buildPlan(
        candidates: <PracticeQuestionCandidate>[
          _candidate('q1', difficulty: double.nan),
        ],
        targetDifficulty: 3.0,
      );
      final recommendation = plan.recommendations.single;
      expect(recommendation.score, 0.0);
      expect(recommendation.reasons, <PracticeRecommendationReason>[
        PracticeRecommendationReason.unrelated,
      ]);
    });

    test('无穷大目标难度当作无目标：不计分也不提示难度', () {
      final plan = _buildPlan(
        candidates: <PracticeQuestionCandidate>[
          _candidate('q1', difficulty: 3.0),
        ],
        targetDifficulty: double.infinity,
      );
      final recommendation = plan.recommendations.single;
      expect(recommendation.score, 0.0);
      expect(recommendation.reasons, <PracticeRecommendationReason>[
        PracticeRecommendationReason.unrelated,
      ]);
    });

    test('缺解析扣 missingSolutionPenalty 分并标记理由', () {
      final plan = _buildPlan(
        candidates: <PracticeQuestionCandidate>[
          _candidate('q1', hasSolution: false),
        ],
      );
      final recommendation = plan.recommendations.single;
      expect(
        recommendation.score,
        -PracticeRecommendationPlan.missingSolutionPenalty,
      );
      expect(recommendation.reasons, <PracticeRecommendationReason>[
        PracticeRecommendationReason.missingSolution,
        PracticeRecommendationReason.unrelated,
      ]);
    });

    test('缺答案扣 missingAnswerPenalty 分并标记理由', () {
      final plan = _buildPlan(
        candidates: <PracticeQuestionCandidate>[
          _candidate('q1', hasAnswer: false),
        ],
      );
      final recommendation = plan.recommendations.single;
      expect(
        recommendation.score,
        -PracticeRecommendationPlan.missingAnswerPenalty,
      );
      expect(recommendation.reasons,
          contains(PracticeRecommendationReason.missingAnswer));
    });

    test('答案与解析都缺时两项扣分叠加、理由都在', () {
      final plan = _buildPlan(
        candidates: <PracticeQuestionCandidate>[
          _candidate('q1', hasAnswer: false, hasSolution: false),
        ],
      );
      final recommendation = plan.recommendations.single;
      expect(recommendation.score, closeTo(-2.5, 1e-9));
      expect(recommendation.reasons, <PracticeRecommendationReason>[
        PracticeRecommendationReason.missingSolution,
        PracticeRecommendationReason.missingAnswer,
        PracticeRecommendationReason.unrelated,
      ]);
    });

    test('答案与解析齐全时标记 upToDate 但不加减分', () {
      final plan = _buildPlan(
        candidates: <PracticeQuestionCandidate>[
          _candidate('q1', hasAnswer: true, hasSolution: true),
        ],
      );
      final recommendation = plan.recommendations.single;
      expect(recommendation.score, 0.0);
      expect(recommendation.reasons, <PracticeRecommendationReason>[
        PracticeRecommendationReason.upToDate,
        PracticeRecommendationReason.unrelated,
      ]);
    });

    test('答案/解析未知（null）时不扣分也不提示', () {
      final plan = _buildPlan(
        candidates: <PracticeQuestionCandidate>[_candidate('q1')],
      );
      final recommendation = plan.recommendations.single;
      expect(recommendation.score, 0.0);
      expect(recommendation.reasons, <PracticeRecommendationReason>[
        PracticeRecommendationReason.unrelated,
      ]);
    });

    test('命中动作时缺解析仍扣分，理由包含动作与缺失', () {
      final plan = _buildPlan(
        insights: _practiceInsights(),
        advicePlan: _practicePlan(),
        candidates: <PracticeQuestionCandidate>[
          _candidate(
            'q1',
            actionTypes: <String>['case_split'],
            hasSolution: false,
          ),
        ],
      );
      final recommendation = plan.recommendations.single;
      expect(recommendation.score, closeTo(1.5, 1e-9));
      expect(recommendation.reasons, <PracticeRecommendationReason>[
        PracticeRecommendationReason.matchedAdviceAction,
        PracticeRecommendationReason.missingSolution,
      ]);
    });

    test('理由按枚举声明顺序输出（动作→缺失→难度）', () {
      final plan = _buildPlan(
        insights: _practiceInsights(),
        advicePlan: _practicePlan(),
        candidates: <PracticeQuestionCandidate>[
          _candidate(
            'q1',
            actionTypes: <String>['case_split'],
            hasSolution: false,
            difficulty: 4.5,
          ),
        ],
        preferredActionTypes: const <String>{'case_split'},
        preferredKnowledgePointIds: const <String>{},
        targetDifficulty: 3.0,
      );
      final recommendation = plan.recommendations.single;
      expect(recommendation.score, closeTo(2.0, 1e-9));
      expect(recommendation.reasons, <PracticeRecommendationReason>[
        PracticeRecommendationReason.matchedAdviceAction,
        PracticeRecommendationReason.missingSolution,
        PracticeRecommendationReason.tooHard,
      ]);
    });
  });

  group('显式偏好覆盖默认偏好', () {
    test('preferredActionTypes 覆盖学习建议里的动作', () {
      final plan = _buildPlan(
        insights: _practiceInsights(),
        advicePlan: _practicePlan(),
        candidates: <PracticeQuestionCandidate>[
          _candidate('q1', actionTypes: <String>['case_split']),
        ],
        preferredActionTypes: const <String>{'analogy_transfer'},
      );
      final recommendation = plan.recommendations.single;
      expect(recommendation.score, 0.0);
      expect(recommendation.reasons, <PracticeRecommendationReason>[
        PracticeRecommendationReason.unrelated,
      ]);
    });

    test('preferredActionTypes 传空集表示明确没有动作偏好', () {
      final plan = _buildPlan(
        insights: _practiceInsights(),
        advicePlan: _practicePlan(),
        candidates: <PracticeQuestionCandidate>[
          _candidate('q1', actionTypes: <String>['case_split']),
        ],
        preferredActionTypes: const <String>{},
      );
      final recommendation = plan.recommendations.single;
      expect(recommendation.score, 0.0);
      expect(recommendation.reasons, <PracticeRecommendationReason>[
        PracticeRecommendationReason.unrelated,
      ]);
    });

    test('preferredKnowledgePointIds 覆盖建议与卡点知识点', () {
      final plan = _buildPlan(
        insights: _practiceInsights(),
        advicePlan: _practicePlan(),
        candidates: <PracticeQuestionCandidate>[
          _candidate('q1', knowledgePointIds: <String>['kp1']),
          _candidate('q2', knowledgePointIds: <String>['kpz']),
        ],
        preferredKnowledgePointIds: const <String>{'kpz'},
      );
      final byId = <String, PracticeRecommendation>{
        for (final recommendation in plan.recommendations)
          recommendation.questionId: recommendation,
      };
      expect(byId['q1']!.score, 0.0);
      expect(byId['q2']!.score,
          PracticeRecommendationPlan.highRiskKnowledgePointScore);
      expect(plan.recommendations.first.questionId, 'q2');
    });

    test('preferredKnowledgePointIds 传空集表示明确没有知识点偏好', () {
      final plan = _buildPlan(
        insights: _singleRiskInsights(),
        candidates: <PracticeQuestionCandidate>[
          _candidate('q1', knowledgePointIds: <String>['kp9']),
        ],
        preferredKnowledgePointIds: const <String>{},
      );
      final recommendation = plan.recommendations.single;
      expect(recommendation.score, 0.0);
      expect(recommendation.reasons, <PracticeRecommendationReason>[
        PracticeRecommendationReason.unrelated,
      ]);
    });

    test('偏好与候选 key 会 trim 并去重后精确匹配', () {
      final plan = _buildPlan(
        insights: _practiceInsights(),
        advicePlan: _practicePlan(),
        candidates: <PracticeQuestionCandidate>[
          _candidate(
            'q1',
            actionTypes: <String>[' case_split ', '', '  '],
            knowledgePointIds: <String>[' kp1 ', 'kp1', '  '],
          ),
        ],
        preferredActionTypes: const <String>{' case_split '},
        preferredKnowledgePointIds: const <String>{' kp1 '},
      );
      final recommendation = plan.recommendations.single;
      expect(recommendation.score, closeTo(5.0, 1e-9));
      expect(recommendation.matchedActionTypes, <String>['case_split']);
      expect(recommendation.matchedKnowledgePointIds, <String>['kp1']);
    });

    test('匹配大小写敏感（词表 key 约定小写蛇形）', () {
      final plan = _buildPlan(
        insights: _practiceInsights(),
        advicePlan: _practicePlan(),
        candidates: <PracticeQuestionCandidate>[
          _candidate('q1', actionTypes: <String>['case_split']),
        ],
        preferredActionTypes: const <String>{'CASE_SPLIT'},
      );
      final recommendation = plan.recommendations.single;
      expect(recommendation.score, 0.0);
      expect(recommendation.matchedActionTypes, isEmpty);
    });
  });

  group('排序与截断', () {
    test('按分数降序排列并给 rank', () {
      final plan = _buildPlan(
        insights: _practiceInsights(),
        advicePlan: _practicePlan(),
        candidates: <PracticeQuestionCandidate>[
          _candidate('q_action', actionTypes: <String>['case_split']),
          _candidate(
            'q_both',
            actionTypes: <String>['case_split'],
            knowledgePointIds: <String>['kp1'],
          ),
          _candidate('q_kp', knowledgePointIds: <String>['kp1']),
        ],
      );
      expect(
        plan.recommendations.map((item) => item.questionId).toList(),
        <String>['q_both', 'q_action', 'q_kp'],
      );
      expect(
        plan.recommendations.map((item) => item.rank).toList(),
        <int>[1, 2, 3],
      );
    });

    test('同分时命中动作数多的在前', () {
      final plan = _buildPlan(
        candidates: <PracticeQuestionCandidate>[
          _candidate(
            'q_kps',
            knowledgePointIds: <String>['k1', 'k2', 'k3'],
          ),
          _candidate('q_actions', actionTypes: <String>['a1', 'a2']),
        ],
        preferredActionTypes: const <String>{'a1', 'a2'},
        preferredKnowledgePointIds: const <String>{'k1', 'k2', 'k3'},
      );
      expect(
        plan.recommendations.map((item) => item.questionId).toList(),
        <String>['q_actions', 'q_kps'],
      );
      expect(
        plan.recommendations.map((item) => item.score).toList(),
        <double>[6.0, 6.0],
      );
    });

    test('同分同命中数时按题号升序，null 题号排最后', () {
      final plan = _buildPlan(
        candidates: <PracticeQuestionCandidate>[
          _candidate('q_c', serialNo: null),
          _candidate('q_a', serialNo: 5),
          _candidate('q_b', serialNo: 2),
        ],
      );
      expect(
        plan.recommendations.map((item) => item.questionId).toList(),
        <String>['q_b', 'q_a', 'q_c'],
      );
    });

    test('同分、同命中数、同题号时按 questionId 升序', () {
      final plan = _buildPlan(
        candidates: <PracticeQuestionCandidate>[
          _candidate('q_beta'),
          _candidate('q_alpha'),
        ],
      );
      expect(
        plan.recommendations.map((item) => item.questionId).toList(),
        <String>['q_alpha', 'q_beta'],
      );
    });

    test('截断到 maxQuestions，剩余题目进 skippedQuestionIds', () {
      final plan = _buildPlan(
        insights: _practiceInsights(),
        advicePlan: _practicePlan(),
        candidates: <PracticeQuestionCandidate>[
          _candidate('q_none'),
          _candidate('q_kp', knowledgePointIds: <String>['kp1']),
          _candidate('q_action', actionTypes: <String>['case_split']),
          _candidate(
            'q_both',
            actionTypes: <String>['case_split'],
            knowledgePointIds: <String>['kp1'],
          ),
        ],
        maxQuestions: 2,
      );
      expect(
        plan.recommendations.map((item) => item.questionId).toList(),
        <String>['q_both', 'q_action'],
      );
      expect(plan.skippedQuestionIds, <String>['q_kp', 'q_none']);
      expect(plan.requestCount, 4);
      expect(plan.skippedCount, 2);
      expect(plan.maxQuestions, 2);
    });

    test('maxQuestions 为 0 时推荐为空、全部跳过、isEmpty 为 true', () {
      final plan = _buildPlan(
        candidates: <PracticeQuestionCandidate>[
          _candidate('q1'),
          _candidate('q2'),
        ],
        maxQuestions: 0,
      );
      expect(plan.isEmpty, isTrue);
      expect(plan.isNotEmpty, isFalse);
      expect(plan.recommendations, isEmpty);
      expect(plan.skippedQuestionIds, <String>['q1', 'q2']);
      expect(plan.requestCount, 2);
    });

    test('负数 maxQuestions 夹成 0', () {
      final plan = _buildPlan(
        candidates: <PracticeQuestionCandidate>[_candidate('q1')],
        maxQuestions: -3,
      );
      expect(plan.isEmpty, isTrue);
      expect(plan.maxQuestions, 0);
      expect(plan.skippedQuestionIds, <String>['q1']);
    });

    test('maxQuestions 大于候选数时没有跳过项', () {
      final plan = _buildPlan(
        candidates: <PracticeQuestionCandidate>[
          _candidate('q1'),
          _candidate('q2'),
        ],
        maxQuestions: 10,
      );
      expect(plan.recommendations.length, 2);
      expect(plan.skippedQuestionIds, isEmpty);
      expect(plan.isEmpty, isFalse);
    });

    test('空候选返回空计划且不抛异常', () {
      final plan = _buildPlan(candidates: const <PracticeQuestionCandidate>[]);
      expect(plan.isEmpty, isTrue);
      expect(plan.recommendations, isEmpty);
      expect(plan.skippedQuestionIds, isEmpty);
      expect(plan.requestCount, 0);
    });
  });

  group('候选去重与非法输入', () {
    test('同 questionId 保留分数更高的候选', () {
      final plan = _buildPlan(
        insights: _practiceInsights(),
        advicePlan: _practicePlan(),
        candidates: <PracticeQuestionCandidate>[
          _candidate('q1', actionTypes: <String>['case_split']),
          _candidate('q1', knowledgePointIds: <String>['kp1']),
        ],
      );
      expect(plan.requestCount, 1);
      expect(plan.recommendations.length, 1);
      expect(plan.recommendations.single.score, closeTo(3.0, 1e-9));
      expect(
          plan.recommendations.single.reasons, <PracticeRecommendationReason>[
        PracticeRecommendationReason.matchedAdviceAction,
      ]);
    });

    test('同 questionId 且同分时保留先出现的候选', () {
      final plan = _buildPlan(
        candidates: <PracticeQuestionCandidate>[
          _candidate('q1', serialNo: 9),
          _candidate('q1', serialNo: 1),
        ],
      );
      expect(plan.requestCount, 1);
      expect(plan.recommendations.single.serialNo, 9);
    });

    test('空白 questionId 的候选被丢弃，不参与计数也不进 skipped', () {
      final plan = _buildPlan(
        candidates: <PracticeQuestionCandidate>[
          _candidate(''),
          _candidate('   '),
          _candidate('q1'),
        ],
        maxQuestions: 0,
      );
      expect(plan.requestCount, 1);
      expect(plan.recommendations, isEmpty);
      expect(plan.skippedQuestionIds, <String>['q1']);
    });

    test('候选里空白的动作/知识点 key 被忽略', () {
      final plan = _buildPlan(
        insights: _practiceInsights(),
        advicePlan: _practicePlan(),
        candidates: <PracticeQuestionCandidate>[
          _candidate(
            'q1',
            actionTypes: <String>[' case_split ', '', '  '],
            knowledgePointIds: <String>['', ' kp1 ', ' '],
          ),
        ],
      );
      expect(plan.recommendations.single.matchedActionTypes,
          <String>['case_split']);
      expect(
        plan.recommendations.single.matchedKnowledgePointIds,
        <String>['kp1'],
      );
    });

    test('NaN / 无穷难度下分数仍为有限 double', () {
      final plan = _buildPlan(
        insights: _practiceInsights(),
        advicePlan: _practicePlan(),
        candidates: <PracticeQuestionCandidate>[
          _candidate(
            'q1',
            actionTypes: <String>['case_split'],
            difficulty: double.nan,
            hasAnswer: false,
          ),
          _candidate('q2', difficulty: double.negativeInfinity),
          _candidate('q3', difficulty: double.infinity),
        ],
        targetDifficulty: double.nan,
      );
      for (final recommendation in plan.recommendations) {
        expect(recommendation.score.isFinite, isTrue);
        expect(recommendation.score.isNaN, isFalse);
      }
      expect(plan.requestCount, 3);
    });

    test('空读数与空候选组合不抛异常', () {
      final plan = _buildPlan(
        insights: ChainInsights.aggregate(chains: const <ChainInsightChain>[]),
        advicePlan: LearningAdvicePlan.empty(),
      );
      expect(plan.isEmpty, isTrue);
      expect(plan.toJson()['request_count'], 0);
    });
  });

  group('toJson 固定键序', () {
    test('计划 JSON 键序、类型与截断信息完整', () {
      final plan = _buildPlan(
        insights: _practiceInsights(),
        advicePlan: _practicePlan(),
        candidates: <PracticeQuestionCandidate>[
          _candidate(
            'q_both',
            serialNo: 7,
            actionTypes: <String>['case_split'],
            knowledgePointIds: <String>['kp1'],
            hasAnswer: true,
            hasSolution: true,
            difficulty: 3.0,
          ),
          _candidate('q_none'),
        ],
        maxQuestions: 1,
        targetDifficulty: 3.0,
      );
      final json = plan.toJson();
      expect(json.keys.toList(), <String>[
        'recommendation_count',
        'skipped_count',
        'request_count',
        'is_empty',
        'max_questions',
        'recommendations',
        'skipped_question_ids',
      ]);
      expect(json['recommendation_count'], 1);
      expect(json['skipped_count'], 1);
      expect(json['request_count'], 2);
      expect(json['is_empty'], isFalse);
      expect(json['max_questions'], 1);

      final recommendationJson = (json['recommendations']! as List<Object?>)
          .single as Map<String, Object?>;
      expect(recommendationJson.keys.toList(), <String>[
        'question_id',
        'serial_no',
        'score',
        'rank',
        'reasons',
        'matched_action_types',
        'matched_knowledge_point_ids',
      ]);
      expect(recommendationJson['question_id'], 'q_both');
      expect(recommendationJson['serial_no'], 7);
      expect(
        recommendationJson['score'],
        closeTo(7.0, 1e-9),
      );
      expect(recommendationJson['rank'], 1);
      expect(recommendationJson['reasons'], <String>[
        'matchedAdviceAction',
        'matchedHighRiskKnowledgePoint',
        'upToDate',
      ]);
      expect(
          recommendationJson['matched_action_types'], <String>['case_split']);
      expect(
          recommendationJson['matched_knowledge_point_ids'], <String>['kp1']);
      expect(json['skipped_question_ids'], <String>['q_none']);
    });

    test('空计划 JSON 的 is_empty 为 true 且列表为空', () {
      final json = _buildPlan().toJson();
      expect(json['is_empty'], isTrue);
      expect(json['recommendation_count'], 0);
      expect(json['skipped_count'], 0);
      expect(json['request_count'], 0);
      expect(json['max_questions'],
          PracticeRecommendationPlan.defaultMaxQuestions);
      expect(json['recommendations'], isEmpty);
      expect(json['skipped_question_ids'], isEmpty);
    });

    test('推荐结果不暴露可变内部列表', () {
      final plan = _buildPlan(
        candidates: <PracticeQuestionCandidate>[_candidate('q1')],
      );
      expect(
        () => plan.recommendations.add(plan.recommendations.first),
        throwsUnsupportedError,
      );
      final recommendation = plan.recommendations.single;
      expect(
        () =>
            recommendation.reasons.add(PracticeRecommendationReason.unrelated),
        throwsUnsupportedError,
      );
      expect(
        () => recommendation.matchedActionTypes.add('x'),
        throwsUnsupportedError,
      );
    });
  });
}

ChainInsights _practiceInsights({
  String actionType = 'case_split',
  String knowledgePointId = 'kp1',
}) {
  return ChainInsights.aggregate(
    chains: <ChainInsightChain>[
      ChainInsightChain(
        chainId: 'c1',
        questionId: 'q1',
        steps: <ChainInsightStep>[
          ChainInsightStep(
            actionType: actionType,
            index: 0,
            stuckRisk: 0.9,
            knowledgeHints: <String>[knowledgePointId],
          ),
          ChainInsightStep(
            actionType: actionType,
            index: 1,
            stuckRisk: 0.8,
            knowledgeHints: <String>[knowledgePointId],
          ),
          ChainInsightStep(
            actionType: actionType,
            index: 2,
            stuckRisk: 0.95,
            knowledgeHints: <String>[knowledgePointId],
          ),
        ],
      ),
    ],
  );
}

ChainInsights _mixedInsights() {
  return ChainInsights.aggregate(
    chains: <ChainInsightChain>[
      const ChainInsightChain(
        chainId: 'c1',
        questionId: 'q1',
        steps: <ChainInsightStep>[
          ChainInsightStep(
            actionType: 'case_split',
            index: 0,
            stuckRisk: 0.9,
            knowledgeHints: <String>['kp1'],
          ),
          ChainInsightStep(
            actionType: 'case_split',
            index: 1,
            stuckRisk: 0.8,
            knowledgeHints: <String>['kp1'],
          ),
          ChainInsightStep(
            actionType: 'case_split',
            index: 2,
            stuckRisk: 0.95,
            knowledgeHints: <String>['kp1'],
          ),
          ChainInsightStep(
            actionType: 'mystery_move',
            index: 3,
            stuckRisk: 0.1,
          ),
        ],
      ),
    ],
  );
}

ChainInsights _singleRiskInsights() {
  return ChainInsights.aggregate(
    chains: <ChainInsightChain>[
      const ChainInsightChain(
        chainId: 'c1',
        questionId: 'q1',
        steps: <ChainInsightStep>[
          ChainInsightStep(
            actionType: 'case_split',
            index: 0,
            stuckRisk: 0.9,
            knowledgeHints: <String>['kp9'],
          ),
        ],
      ),
    ],
  );
}

LearningAdvicePlan _practicePlan() => _practicePlanOf(_practiceInsights());

LearningAdvicePlan _practicePlanOf(ChainInsights insights) {
  return LearningAdvicePlan.build(insights: insights);
}

PracticeQuestionCandidate _candidate(
  String questionId, {
  int? serialNo,
  List<String> actionTypes = const <String>[],
  List<String> knowledgePointIds = const <String>[],
  double? difficulty,
  bool? hasAnswer,
  bool? hasSolution,
  String? subjectKey,
  String? sourceLevel,
  double? aiQuality,
}) {
  return PracticeQuestionCandidate(
    questionId: questionId,
    serialNo: serialNo,
    actionTypes: actionTypes,
    knowledgePointIds: knowledgePointIds,
    difficulty: difficulty,
    hasAnswer: hasAnswer,
    hasSolution: hasSolution,
    subjectKey: subjectKey,
    sourceLevel: sourceLevel,
    aiQuality: aiQuality,
  );
}

PracticeRecommendationPlan _buildPlan({
  ChainInsights? insights,
  LearningAdvicePlan? advicePlan,
  List<PracticeQuestionCandidate> candidates =
      const <PracticeQuestionCandidate>[],
  int maxQuestions = PracticeRecommendationPlan.defaultMaxQuestions,
  Set<String>? preferredActionTypes,
  Set<String>? preferredKnowledgePointIds,
  double? targetDifficulty,
  bool includeUnknownActionScaffold = true,
}) {
  return PracticeRecommendationPlan.build(
    insights: insights ??
        ChainInsights.aggregate(chains: const <ChainInsightChain>[]),
    advicePlan: advicePlan ?? LearningAdvicePlan.empty(),
    candidates: candidates,
    maxQuestions: maxQuestions,
    preferredActionTypes: preferredActionTypes,
    preferredKnowledgePointIds: preferredKnowledgePointIds,
    targetDifficulty: targetDifficulty,
    includeUnknownActionScaffold: includeUnknownActionScaffold,
  );
}
