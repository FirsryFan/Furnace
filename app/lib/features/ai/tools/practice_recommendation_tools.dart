/// 配题推荐接进 AI 工具层（只读）。
///
/// 用户口径（Q16 之后）：TA 要的是「下一步练哪几道题」，不是再来一段讲解。
/// 排序与理由全在 `domain/services/reasoning/practice_recommendation.dart`
/// （确定性纯逻辑）；这个工具只做拼装：读表投影 → 洞察 → 学习建议 → 推荐，
/// 不调模型、不写库、不出题。
///
/// 与其他只读工具同款：write 风险 + 可逆 + readOnly，审批引擎在两种模式下
/// 都不会逐条询问只读查询。
library;

import 'package:drift/drift.dart';

import '../../../data/database/database.dart';
import '../../../data/repositories/question_repository.dart';
import '../../../data/repositories/settings_repository.dart';
import '../../../domain/services/questions/question_number.dart';
import '../../../domain/services/reasoning/capability_action.dart';
import '../../../domain/services/reasoning/capability_profile.dart';
import '../../../domain/services/reasoning/chain_insights.dart';
import '../../../domain/services/reasoning/learning_advice.dart';
import '../../../domain/services/reasoning/practice_recommendation.dart';
import '../../questions/application/capability_vocabulary_store.dart';
import '../../questions/application/chain_insights_reader.dart';
import '../../questions/application/practice_recommendation_provider.dart';
import '../domain/ai_tool.dart';

/// 按全库读数给出「下一步练哪几道题」的确定性推荐（题号 + 理由 + 命中动作）。
///
/// 与学习洞察页的「下一步练什么」同一份纯逻辑，只是这里换成模型可读的 JSON 结果，
/// 让对话里能直接点名题号，而不是让模型自己编题。
class RecommendPracticeTool extends AiTool {
  RecommendPracticeTool({required AppDatabase db}) : _db = db;

  final AppDatabase _db;

  /// 默认最多推荐几道题（与领域层默认一致）。
  static const int defaultMaxQuestions =
      PracticeRecommendationPlan.defaultMaxQuestions;

  /// 一次最多推荐几道：再多用户也读不完。
  static const int maxQuestionsLimit = 20;

  /// 学习建议默认条数（只取前两条进摘要，完整建议不进 result）。
  static const int adviceCount = 5;

  /// 「几步高风险才算值得练」的学习建议阈值（与 GetLearningAdviceTool 默认一致）。
  static const int highRiskMinSteps = 3;

  /// 难度轴下界（题库的 difficulty 口径是 1..10，不是 0..1）。
  static const double minDifficulty = 1.0;

  /// 难度轴上界。
  static const double maxDifficulty = 10.0;

  /// 理由的中文说法（只用于工具结果的展示，不参与排序）。
  static const Map<PracticeRecommendationReason, String> reasonLabelsZh =
      <PracticeRecommendationReason, String>{
    PracticeRecommendationReason.matchedAdviceAction: '命中学习建议里的练习动作',
    PracticeRecommendationReason.matchedHighRiskKnowledgePoint: '命中卡点知识点',
    PracticeRecommendationReason.unknownActionScaffold: '词表外动作，先补基础',
    PracticeRecommendationReason.upToDate: '答案与解析齐全',
    PracticeRecommendationReason.missingSolution: '缺解析（已扣分）',
    PracticeRecommendationReason.missingAnswer: '缺答案（已扣分）',
    PracticeRecommendationReason.tooHard: '难度高于目标',
    PracticeRecommendationReason.tooEasy: '难度低于目标',
    PracticeRecommendationReason.unrelated: '没有命中偏好，只作为填充候选',
  };

  @override
  String get name => 'recommend_practice';

  @override
  String get description => '从**已有题库**里挑出下一步最该练的几道题，给题号、分数与理由：'
      '先看学习建议里的练习动作与卡点知识点，再看答案/解析是否齐全、难度是否贴近目标。'
      '用在你需要回答「接下来练哪几道题 / 有没有现成的题可以练」的时候。'
      '**只读**：不调模型、不写库、**不出题**——只排序库里已有的题；'
      '权重与阈值是先验值，不是评分。';

  @override
  Map<String, Object?> get parameters => <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'max_questions': <String, Object?>{
            'type': 'integer',
            'minimum': 1,
            'maximum': maxQuestionsLimit,
            'description':
                '最多推荐几道，默认 $defaultMaxQuestions（上限 $maxQuestionsLimit）。',
          },
          'subject_key': <String, Object?>{
            'type': 'string',
            'description': '只在这个学科里挑（如 math）；不传 = 全库挑。',
          },
          'target_difficulty': <String, Object?>{
            'type': 'number',
            'minimum': minDifficulty,
            'maximum': maxDifficulty,
            'description': '目标难度（题库口径 1..10）；不传 = 不按难度贴目标。',
          },
        },
        'required': <String>[],
      };

  @override
  ToolRisk riskFor(String action) => ToolRisk.write; // unused: no actions

  @override
  bool reversibleFor(String action) => true;

  @override
  bool get readOnly => true;

  @override
  bool get availableOnCurrentPlatform => true;

  @override
  Future<ToolResult> run(ToolInvocation invocation) async {
    try {
      return await _run(invocation.arguments);
    } on ToolArgError catch (error) {
      return ToolResult.failure(error.message);
    }
  }

  Future<ToolResult> _run(Map<String, Object?> rawArguments) async {
    final args = ToolArgs(rawArguments);
    final maxQuestions = _intArg(args, 'max_questions') ?? defaultMaxQuestions;
    if (maxQuestions < 1) {
      throw ToolArgError('max_questions 必须是正整数（当前 $maxQuestions）');
    }
    final limit =
        maxQuestions > maxQuestionsLimit ? maxQuestionsLimit : maxQuestions;
    final subjectKey = args.optString('subject_key');
    final targetDifficulty = _doubleArg(args, 'target_difficulty');
    if (targetDifficulty != null) {
      if (!targetDifficulty.isFinite ||
          targetDifficulty < minDifficulty ||
          targetDifficulty > maxDifficulty) {
        throw ToolArgError(
          'target_difficulty 必须是 $minDifficulty..$maxDifficulty 的有限数（当前 $targetDifficulty）',
        );
      }
    }

    // 词表 / 洞察 / 建议与页面同源：读不出来退回内置词表，不阻塞推荐。
    final overlay =
        await CapabilityVocabularyStore(SettingsRepository(_db)).load();
    final corpus = await readChainInsightCorpus(_db);
    final insights = ChainInsights.aggregate(
      chains: corpus.chains,
      catalog: overlay.catalog,
    );
    final repository = QuestionRepository(_db);
    final steps = await repository.allReasoningSteps();
    final profile = CapabilityProfile.of(<CapabilityStepSample>[
      for (final step in steps)
        CapabilityStepSample(
          actionType: step.actionType,
          stuckRisk: step.stuckRisk,
        ),
    ]);
    final advicePlan = LearningAdvicePlan.build(
      insights: insights,
      profile: profile,
      highRiskMinSteps: highRiskMinSteps,
      maxAdvices: adviceCount,
      corpusQuestionCount: await _countQuestions(),
    );

    final allCandidates = await readPracticeQuestionCandidates(_db);
    final candidates = <PracticeQuestionCandidate>[
      for (final candidate in allCandidates)
        if (subjectKey == null ||
            (candidate.subjectKey ?? '').trim() == subjectKey)
          candidate,
    ];
    final plan = PracticeRecommendationPlan.build(
      insights: insights,
      advicePlan: advicePlan,
      candidates: candidates,
      maxQuestions: limit,
      targetDifficulty: targetDifficulty,
    );

    final subjectByQuestionId = <String, String?>{
      for (final candidate in candidates)
        candidate.questionId.trim(): candidate.subjectKey,
    };

    final String summary;
    if (plan.isEmpty) {
      final subjectName = _subjectOf(subjectKey);
      summary = subjectName == null
          ? '题库里还没有能推荐的题：先收几道题、解一道题，再来看下一步练什么。'
          : '题库里没有学科「$subjectName」的候选题目：先收几道这一科的题，再看推荐。';
    } else {
      final first = plan.recommendations.first;
      final serialLabel = _serialLabelOf(first.serialNo);
      final subjectName =
          _subjectOf(subjectByQuestionId[first.questionId]) ?? '学科未标注';
      final reasonText = first.reasons.isEmpty
          ? '排序靠前'
          : <String>[
              for (final reason in first.reasons.take(2))
                reasonLabelsZh[reason] ?? reason.name,
            ].join('、');
      summary = '建议先练 $serialLabel（$subjectName）：$reasonText。'
          '共 ${plan.recommendations.length} 道，完整清单在 result 里。';
    }

    return ToolResult(
      ok: true,
      summary: summary,
      modelResult: <String, Object?>{
        'filters': <String, Object?>{
          'subject_key': subjectKey,
          'subject': _subjectOf(subjectKey),
          'target_difficulty': targetDifficulty,
          'max_questions': plan.maxQuestions,
        },
        'candidate_count': candidates.length,
        'request_count': plan.requestCount,
        'skipped_count': plan.skippedCount,
        'skipped_question_ids': plan.skippedQuestionIds,
        'recommendations': <Object?>[
          for (final recommendation in plan.recommendations)
            <String, Object?>{
              'rank': recommendation.rank,
              'question_id': recommendation.questionId,
              'serial_no': recommendation.serialNo,
              'serial_label': _serialLabelOf(recommendation.serialNo),
              'subject_key': subjectByQuestionId[recommendation.questionId],
              'subject':
                  _subjectOf(subjectByQuestionId[recommendation.questionId]),
              'score': recommendation.score,
              'reasons': <Object?>[
                for (final reason in recommendation.reasons)
                  <String, Object?>{
                    'key': reason.name,
                    'label_zh': reasonLabelsZh[reason] ?? reason.name,
                  },
              ],
              'matched_action_types': recommendation.matchedActionTypes,
              'matched_action_labels_zh': <String>[
                for (final actionType in recommendation.matchedActionTypes)
                  CapabilityAction.byKey(actionType)?.labelZh ?? actionType,
              ],
              'matched_knowledge_point_ids':
                  recommendation.matchedKnowledgePointIds,
            },
        ],
        'advices': <Object?>[
          for (final advice in advicePlan.advices.take(2))
            <String, Object?>{
              'kind': advice.kind.name,
              'priority': advice.priority,
              'title_zh': advice.titleZh,
              'detail_zh': advice.detailZh,
            },
        ],
        'thresholds': <String, Object?>{
          'high_risk_threshold': insights.highRiskThreshold,
          'high_risk_min_steps': highRiskMinSteps,
        },
        'note': '确定性推荐（不调模型、不出题）；阈值未标定，只作练习顺序提示，不是评分。',
      },
    );
  }

  /// 可选的整数参数：传了但不是整数时报错，而不是悄悄退回默认值。
  int? _intArg(ToolArgs args, String key) {
    if (!args.raw.containsKey(key) || args.raw[key] == null) {
      return null;
    }
    final value = args.optInt(key);
    if (value == null) {
      throw ToolArgError('$key 必须是整数（当前 ${args.raw[key]}）');
    }
    return value;
  }

  /// 可选的数值参数：传了但不是数时报错。
  double? _doubleArg(ToolArgs args, String key) {
    if (!args.raw.containsKey(key) || args.raw[key] == null) {
      return null;
    }
    final value = args.optDouble(key);
    if (value == null) {
      throw ToolArgError('$key 必须是数字（当前 ${args.raw[key]}）');
    }
    return value;
  }

  /// 题号展示：没有题号时如实说未编号，不编一个号。
  String _serialLabelOf(int? serialNo) {
    if (serialNo == null || serialNo < 1) {
      return kUnnumberedQuestionLabel;
    }
    return formatQuestionSerial(serialNo);
  }

  /// 学科中文名：词表缺失时回退原键。
  String? _subjectOf(String? subjectKey) {
    final key = subjectKey?.trim() ?? '';
    if (key.isEmpty) {
      return null;
    }
    return CapabilityAction.subjectLabelsZh[key] ?? key;
  }

  /// 题库总题数（一次 COUNT；不把整张表读进内存）。
  Future<int> _countQuestions() async {
    final count = _db.questions.id.count();
    final row =
        await (_db.selectOnly(_db.questions)..addColumns([count])).getSingle();
    return row.read(count) ?? 0;
  }
}
