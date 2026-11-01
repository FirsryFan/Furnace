/// 题目详情页「MindNet 认知评价」的只读读数层。
///
/// 数据链：题目 → 题目与知识点共享的标签 → 知识点 → 每个知识点取一行代表卡
/// → [ProblemEvaluator] 对这道题跑一次扩散诊断（判词/理由/区域）→ 再读
/// `cognitive_priors` 的测评先验。
///
/// 诚实性规则（与同目录认知层一致）：
///
/// * 没有知识点、或知识点没有任何记忆状态行 ⇒ empty（[QuestionCognitiveReading.isEmpty]），
///   不拿难度先验或默认值编一个认知评价；
/// * 诊断没跑 ⇒ [ReviewZone.unavailable]，**不**读作「健康」（跑了、没抱怨才是 healthy）；
/// * 先验不是观测：只作额外一行展示，判词仍由复习状态与诊断给出；
/// * 全部读数未标定：阈值与边权见 `docs/MINDNET_CONTRACT.md` §9.3。
///
/// 与 `features/ai/tools/cognitive_tools.dart` 的 `evaluateProblems` 同源（同一个
/// 评估器、同一个标签↔知识点桥、同一条代表行规则），差别只有：这里只为一道题跑，
/// 且不传 starts（详情页不猜「用户此刻在想什么」）。
///
/// 只读：不调用任何 insert/update/delete。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/state/data_revision.dart';
import '../../../data/database/app_database_provider.dart';
import '../../../data/database/database.dart';
import '../../../data/repositories/repository_providers.dart';
import '../../../data/repositories/settings_repository.dart';
import '../../../domain/services/cognitive/assessment_prior.dart';
import '../../../domain/services/cognitive/cognitive_graph.dart';
import '../../../domain/services/cognitive/cognitive_model.dart';
import '../../../domain/services/cognitive/fast_diagnosis.dart'
    show BottleneckType;
import '../../../domain/services/cognitive/knowledge_point_tag_bridge.dart';
import '../../../domain/services/cognitive/library_diagnosis.dart'
    show representativeCardRow;
import '../../../domain/services/cognitive/mechanism_catalog.dart';
import '../../../domain/services/cognitive/problem_evaluator.dart';
import '../../../domain/services/scheduling/thread_balance_inputs.dart';
import '../../anki/application/review_advisory.dart'
    show ReviewAdvisory, ReviewZone;

/// 详情页对一道题给出的建议（产品规则，不是模型读数）。
enum QuestionCognitiveSuggestion {
  /// 现在练：发展中区 / 值得做。
  practiceNow,

  /// 先补先验：危险区（以为会其实不会），先补证据/先复习再说。
  buildPrior,

  /// 暂缓：已经会了、偏难、超纲或重复。
  postpone,

  /// 按计划：没有判词时的中性兜底。
  keepPlan,
}

/// 一道题的认知读数（纯数据，可序列化）。
class QuestionCognitiveReading {
  const QuestionCognitiveReading({
    required this.questionId,
    required this.knowledgePointIds,
    required this.judgedKnowledgePointIds,
    required this.zone,
    required this.verdict,
    required this.reason,
    required this.suggestion,
    required this.priorR0,
    required this.priorConfidence,
    required this.priorSamples,
    required this.fastLayerRan,
  });

  /// 空读数：没有知识点、没有记忆状态行、或题目不存在。
  factory QuestionCognitiveReading.empty(
    String questionId, {
    List<String> knowledgePointIds = const <String>[],
  }) =>
      QuestionCognitiveReading(
        questionId: questionId,
        knowledgePointIds: List<String>.unmodifiable(knowledgePointIds),
        judgedKnowledgePointIds: const <String>[],
        zone: ReviewZone.unavailable,
        verdict: null,
        reason: '',
        suggestion: QuestionCognitiveSuggestion.keepPlan,
        priorR0: null,
        priorConfidence: null,
        priorSamples: 0,
        fastLayerRan: false,
      );

  final String questionId;

  /// 题目挂上的知识点（题目与知识点共享标签推出的）。
  final List<String> knowledgePointIds;

  /// 其中真的有记忆状态行的那部分。空 = 模型没有可判断的观测。
  final List<String> judgedKnowledgePointIds;

  /// 题目级认知区域。诊断没跑时是 [ReviewZone.unavailable]（不是「健康」）。
  final ReviewZone zone;

  /// 六种判词；null = 没有判词（空读数）。
  final ProblemVerdict? verdict;

  /// 判词的人话理由（[ProblemEvaluator] 给的原文，不改写）。
  final String reason;

  /// 纯函数推出来的建议。
  final QuestionCognitiveSuggestion suggestion;

  /// 测评先验的 R0（多个知识点按置信度加权平均）；null = 没有测评先验。
  final double? priorR0;

  /// 参与平均的先验置信度均值（0..1）。
  final double? priorConfidence;

  /// 参与平均的先验样本总数。
  final int priorSamples;

  /// 快层诊断这一跑有没有真的跑。
  final bool fastLayerRan;

  /// 读数是否未标定（恒为 true，保留字段让消费方不用靠注释记忆）。
  bool get uncalibrated => true;

  /// 没有可展示的认知读数：界面据此显示空态，不编数。
  bool get isEmpty => judgedKnowledgePointIds.isEmpty;

  bool get hasPrior => priorR0 != null;

  Map<String, Object?> toJson() => <String, Object?>{
        'question_id': questionId,
        'knowledge_point_ids': knowledgePointIds,
        'judged_knowledge_point_ids': judgedKnowledgePointIds,
        'zone': zone.name,
        'fast_layer_ran': fastLayerRan,
        'verdict': verdict == null ? null : problemVerdictId(verdict!),
        'reason': reason,
        'suggestion': suggestion.name,
        'prior_r0': priorR0,
        'prior_confidence': priorConfidence,
        'prior_samples': priorSamples,
        'uncalibrated': uncalibrated,
      };
}

/// 判词的稳定 wire id（与 AI 工具、契约措辞一致）。只用于序列化/日志。
String problemVerdictId(ProblemVerdict verdict) => switch (verdict) {
      ProblemVerdict.tooEasy => 'too_easy',
      ProblemVerdict.zpd => 'zpd',
      ProblemVerdict.tooHard => 'too_hard',
      ProblemVerdict.outOfScope => 'out_of_scope',
      ProblemVerdict.redundant => 'redundant',
      ProblemVerdict.highValue => 'high_value',
    };

/// 区域聚合的优先次序（产品规则）：危险区最该先看见，其次发展区，再其余。
const List<ReviewZone> kQuestionCognitiveZonePriority = <ReviewZone>[
  ReviewZone.danger,
  ReviewZone.proximal,
  ReviewZone.deadEnd,
  ReviewZone.empty,
  ReviewZone.overload,
  ReviewZone.slow,
  ReviewZone.offGoal,
];

/// 把一道题的多个知识点抱怨聚成一个题目级区域。
///
/// * 诊断没跑 ⇒ unavailable（不退化成「健康」）；
/// * 跑了但没有任何抱怨 ⇒ healthy（查过，没问题）；
/// * 有抱怨 ⇒ 按 [kQuestionCognitiveZonePriority] 取第一条。
ReviewZone aggregateCognitiveZone({
  required bool fastLayerRan,
  required Iterable<BottleneckType> complaints,
}) {
  if (!fastLayerRan) {
    return ReviewZone.unavailable;
  }
  final zones = <ReviewZone>{
    for (final complaint in complaints) ReviewAdvisory.zoneOf(complaint),
  };
  for (final candidate in kQuestionCognitiveZonePriority) {
    if (zones.contains(candidate)) {
      return candidate;
    }
  }
  return ReviewZone.healthy;
}

/// 判词 + 区域 ⇒ 建议（纯函数，单测覆盖每条分支）。
QuestionCognitiveSuggestion cognitiveSuggestionFor({
  required ProblemVerdict? verdict,
  required ReviewZone zone,
}) {
  if (verdict == null) {
    return QuestionCognitiveSuggestion.keepPlan;
  }
  // 危险区压过判词：判词说「这题难不难」，危险区说「你对自己判断不准」。
  if (zone == ReviewZone.danger) {
    return QuestionCognitiveSuggestion.buildPrior;
  }
  switch (verdict) {
    case ProblemVerdict.zpd:
    case ProblemVerdict.highValue:
      return QuestionCognitiveSuggestion.practiceNow;
    case ProblemVerdict.tooEasy:
    case ProblemVerdict.tooHard:
    case ProblemVerdict.outOfScope:
    case ProblemVerdict.redundant:
      return QuestionCognitiveSuggestion.postpone;
  }
}

/// 一道题的 MindNet 认知读数。
final questionCognitiveReadingProvider = FutureProvider.autoDispose
    .family<QuestionCognitiveReading, String>((ref, questionId) async {
  // 写库（复习、改标签、AI…）后自动重读，与详情页其它 provider 同一条链。
  ref.watchDatabaseRevision();

  final database = ref.watch(appDatabaseProvider);
  final questions = ref.watch(questionRepositoryProvider);
  final assessments = ref.watch(assessmentRepositoryProvider);
  final model = ref.watch(cognitiveModelProvider);

  final question = await questions.byId(questionId);
  if (question == null) {
    return QuestionCognitiveReading.empty(questionId);
  }

  final objectTagRows = await database.select(database.objectTags).get();
  final links = <ObjectTagLink>[
    for (final row in objectTagRows)
      ObjectTagLink(
        tagId: row.tagId,
        objectType: row.objectType,
        objectId: row.objectId,
      ),
  ];
  final knowledgePointIds = TaskKnowledgePointResolver.resolveFromTagLinks(
        links,
        sourceObjectType: kQuestionObjectType,
      )[questionId] ??
      const <String>[];
  if (knowledgePointIds.isEmpty) {
    return QuestionCognitiveReading.empty(questionId);
  }

  final rows = await _representativeCardRows(database);
  final judged = <String>[
    for (final id in knowledgePointIds)
      if (rows.containsKey(id)) id,
  ];
  if (judged.isEmpty) {
    // 有知识点、但一张卡都没有：模型没有可判断的观测。空态，不编。
    return QuestionCognitiveReading.empty(
      questionId,
      knowledgePointIds: knowledgePointIds,
    );
  }

  final tags = <CognitiveTag>[
    for (final row in await database.select(database.tags).get())
      CognitiveTag.fromTag(row),
  ];
  final settings = await SettingsRepository(database).getSettings();
  // 与 AI 工具同一条装配：用户拖过的目标机制强度只在一处折算。
  final moduleDefaults = MechanismCatalog.problemEvaluatorDefaults(
    goalBeta: settings?.goalBeta,
  );

  final report = ProblemEvaluator.evaluate(
    candidates: <ProblemCandidate>[
      ProblemCandidate(
        id: question.id,
        stem: question.stem,
        knowledgePointIds: knowledgePointIds,
      ),
    ],
    tags: tags,
    rowsByKnowledgePoint: rows,
    model: model,
    nowHours: modelHoursOf(DateTime.now()),
    tagIdsByKnowledgePoint:
        KnowledgePointTagBridge.tagIdsByKnowledgePoint(links),
    moduleDefaults: moduleDefaults,
  );

  final evaluation =
      report.evaluations.isEmpty ? null : report.evaluations.first;
  if (evaluation == null) {
    return QuestionCognitiveReading.empty(
      questionId,
      knowledgePointIds: knowledgePointIds,
    );
  }

  final priors = await assessments.priorEstimatesFor(judged);
  final prior = _mergedPrior(priors);
  final zone = aggregateCognitiveZone(
    fastLayerRan: report.fastLayerRan,
    complaints: evaluation.diagnosisByKnowledgePoint.values,
  );

  return QuestionCognitiveReading(
    questionId: questionId,
    knowledgePointIds: List<String>.unmodifiable(knowledgePointIds),
    judgedKnowledgePointIds: List<String>.unmodifiable(
      evaluation.judgedKnowledgePointIds,
    ),
    zone: zone,
    verdict: evaluation.verdict,
    reason: evaluation.reason,
    suggestion: cognitiveSuggestionFor(
      verdict: evaluation.verdict,
      zone: zone,
    ),
    priorR0: prior.r0,
    priorConfidence: prior.confidence,
    priorSamples: prior.samples,
    fastLayerRan: report.fastLayerRan,
  );
});

/// 每个知识点取一行代表卡（与读数页/AI 工具同一条规则）。
///
/// 模板卡的行 `knowledge_point_id` 可能为 NULL（由模板反查），沿用
/// `questionKnowledgeStatesProvider` 的回退口径，避免同一个「这张卡属于谁」
/// 在两处给出不同答案。
Future<Map<String, CardState>> _representativeCardRows(
  AppDatabase database,
) async {
  final states = await database.select(database.cardStates).get();
  final templates = await database.select(database.cardTemplates).get();
  final knowledgePointOfTemplate = <String, String>{
    for (final template in templates) template.id: template.knowledgePointId,
  };

  final grouped = <String, List<CardState>>{};
  for (final row in states) {
    final knowledgePointId =
        row.knowledgePointId ?? knowledgePointOfTemplate[row.cardTemplateId];
    if (knowledgePointId == null || knowledgePointId.trim().isEmpty) {
      continue;
    }
    (grouped[knowledgePointId] ??= <CardState>[]).add(row);
  }

  final rows = <String, CardState>{};
  for (final entry in grouped.entries) {
    final row = representativeCardRow(entry.value);
    if (row != null) {
      rows[entry.key] = row;
    }
  }
  return rows;
}

/// 先验合并：多个知识点按置信度加权平均；没有可用先验 ⇒ 全 null。
///
/// 置信度由样本数 n 唯一决定（`n / (n + 3)`，见 `AssessmentRepository._mergePriors`），
/// 所以 n = 0 的先验不参与平均。
({double? r0, double? confidence, int samples}) _mergedPrior(
  Map<String, AssessmentPriorEstimate> priors,
) {
  var weightSum = 0.0;
  var r0Sum = 0.0;
  var confidenceSum = 0.0;
  var samples = 0;
  var counted = 0;
  final ids = priors.keys.toList()..sort();
  for (final id in ids) {
    final prior = priors[id]!;
    final weight = prior.confidence;
    if (!weight.isFinite || weight <= 0) {
      continue;
    }
    weightSum += weight;
    r0Sum += prior.r0 * weight;
    confidenceSum += weight;
    samples += prior.n;
    counted += 1;
  }
  if (weightSum <= 0 || counted == 0) {
    return (r0: null, confidence: null, samples: 0);
  }
  return (
    r0: r0Sum / weightSum,
    confidence: confidenceSum / counted,
    samples: samples,
  );
}
