/// 学习建议接进 AI 工具层（只读）。
///
/// 用户口径（Q16 之后）：TA 需要的不是"模型再讲一遍"，而是**下一步具体练什么**。
/// 建议层本身是确定性纯逻辑（domain/services/reasoning/learning_advice.dart）：
/// 输入是全库思维链洞察 + 能力动作画像 + 题库题数，输出是带优先级的建议清单。
/// 这个工具只做拼装与偷懒退化，不调模型、不写库。
///
/// 与其他只读工具同款：write 风险 + 可逆 + readOnly，审批引擎在两种模式下都不会
/// 逐条询问只读查询。
library;

import 'package:drift/drift.dart';

import '../../../data/database/database.dart';
import '../../../data/repositories/question_repository.dart';
import '../../../data/repositories/settings_repository.dart';
import '../../../domain/services/reasoning/capability_profile.dart';
import '../../../domain/services/reasoning/chain_insights.dart';
import '../../../domain/services/reasoning/learning_advice.dart';
import '../../questions/application/capability_vocabulary_store.dart';
import '../../questions/application/chain_insights_reader.dart';
import '../domain/ai_tool.dart';

/// 按全库读数给出「下一步练什么」的确定性建议（练习已识别动作 / 补解题链 /
/// 扩充词表 / 继续练 / 数据不足）。
class GetLearningAdviceTool extends AiTool {
  GetLearningAdviceTool({required AppDatabase db}) : _db = db;

  final AppDatabase _db;

  /// 默认最多给几条建议。
  static const int defaultMaxAdvices = 5;

  /// 一次最多给几条：再多用户也读不完。
  static const int maxAdvicesLimit = 10;

  /// 默认「几步高风险才算值得练」。
  static const int defaultHighRiskMinSteps = 3;

  /// high_risk_min_steps 的合理上限（再高等于永远不给练习建议）。
  static const int maxHighRiskMinSteps = 20;

  @override
  String get name => 'get_learning_advice';

  @override
  String get description => '读完整个题库的解题链与能力动作画像，给出**下一步该练什么**的确定性建议：'
      '哪些能力动作上高风险步最多、该练哪个动作、哪些题还没有解题链、词表里哪些动作从没出现过、'
      '以及是否应该先继续积累数据。用在你需要回答「我现在最该练什么 / 从哪下手 / 有没有数据」的时候。'
      '**只读**：不调模型、不写库、不改复习计划；建议是启发式先验，阈值未标定，'
      '只作为行动提示而不是评分。';

  @override
  Map<String, Object?> get parameters => {
        'type': 'object',
        'properties': {
          'max_advices': {
            'type': 'integer',
            'minimum': 1,
            'maximum': maxAdvicesLimit,
            'description':
                '最多给几条建议，默认 $defaultMaxAdvices（上限 $maxAdvicesLimit）。',
          },
          'high_risk_min_steps': {
            'type': 'integer',
            'minimum': 1,
            'maximum': maxHighRiskMinSteps,
            'description': '至少几个高风险步才给「练这个动作」的建议，默认 '
                '$defaultHighRiskMinSteps（小于 1 的输入会被拒绝）。',
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
    final args = ToolArgs(invocation.arguments);
    var maxAdvices = args.optInt('max_advices') ?? defaultMaxAdvices;
    if (maxAdvices < 1) {
      throw ToolArgError('max_advices 必须是正整数（当前 $maxAdvices）');
    }
    if (maxAdvices > maxAdvicesLimit) {
      maxAdvices = maxAdvicesLimit;
    }
    var minSteps =
        args.optInt('high_risk_min_steps') ?? defaultHighRiskMinSteps;
    if (minSteps < 1) {
      throw ToolArgError('high_risk_min_steps 必须是正整数（当前 $minSteps）');
    }
    if (minSteps > maxHighRiskMinSteps) {
      minSteps = maxHighRiskMinSteps;
    }

    // 与页面同源：当前词表 overlay（读不出来退回内置词表，不阻塞建议）。
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

    final corpusQuestionCount = await _countQuestions();
    final plan = LearningAdvicePlan.build(
      insights: insights,
      profile: profile,
      highRiskMinSteps: minSteps,
      maxAdvices: maxAdvices,
      corpusQuestionCount: corpusQuestionCount,
    );

    final String summary;
    if (plan.isEmpty) {
      summary = '暂时没有足够数据给建议：先去解一道题或收几道题，再回来看。';
    } else {
      final first = plan.advices.first;
      final detail = first.detailZh.trim();
      if (first.kind == LearningAdviceKind.noData) {
        summary = '${first.titleZh}'
            '${detail.isEmpty ? '' : '——$detail'}';
      } else {
        summary = '下一步建议：${first.titleZh}'
            '${detail.isEmpty ? '' : '——$detail'}'
            '（共 ${plan.length} 条，完整的在 result 里）。';
      }
    }

    return ToolResult(
      ok: true,
      summary: summary,
      modelResult: <String, Object?>{
        'corpus_question_count': corpusQuestionCount,
        'reasoning_step_count': steps.length,
        'insights': <String, Object?>{
          'chain_count': insights.chainCount,
          'step_count': insights.stepCount,
          'question_count': insights.questionCount,
          'high_risk_step_count': insights.highRiskStepCount,
          'high_risk_chain_count': insights.highRiskChainCount,
          'custom_action_count': insights.customActions.length,
          'unknown_action_count': insights.unknownActions.length,
          'never_used_action_count': insights.neverUsedActions.length,
          'ignored_chain_count': insights.ignoredChainCount,
          'duplicate_chain_count': insights.duplicateChainCount,
          'ignored_step_count': insights.ignoredStepCount,
          'invalid_risk_step_count': insights.invalidRiskStepCount,
        },
        'thresholds': <String, Object?>{
          'high_risk_threshold': insights.highRiskThreshold,
          'high_risk_min_steps': minSteps,
          'max_advices': maxAdvices,
        },
        'plan': plan.toJson(),
        'note': '确定性建议（不调模型）；阈值未标定，只作行动提示，不是评分。',
      },
    );
  }

  /// 题库总题数（一次 COUNT；不把整张表读进内存）。
  Future<int> _countQuestions() async {
    final count = _db.questions.id.count();
    final row =
        await (_db.selectOnly(_db.questions)..addColumns([count])).getSingle();
    return row.read(count) ?? 0;
  }
}
