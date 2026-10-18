/// 卷面质量评价：给一份已经组好的 [PaperPlan] 出确定性体检报告。
///
/// 用户口径（历史记录）：组完卷要能回答「这卷子够不够、偏不偏、缺什么」，
/// 而不是只有题数。本文件是纯逻辑：不调模型、不重排卷、不读文件系统、不碰 DB。
///
/// 输入只有 [PaperPlan] 与可选的展示名表、逐题难度；输出
/// [PaperQualityReport]。所有判据都是事实陈述 + evidence，中文文案不写
/// 「可能/大概」；缺数据就记
/// [PaperQualityCodes.difficultyDataUnavailable]，不拿 0 冒充读数。
///
/// 注意：PaperPlan 不保留逐题难度（难度只在 PaperCandidate 上参与打分），
/// 所以难度分布与难度判据要求调用方把 difficultyByQuestionId 传进来；
/// 不传时这两类判据不评估（记一条 info），其余判据照常。
library;

import 'domain_quota.dart';
import 'paper_composer.dart';
import 'subject_quota.dart';

/// 判据使用的 schema（与 PaperPlan.toJson 的 schema 同风格，便于落盘/比对）。
const String kPaperQualitySchema = 'mindnet.paper_quality/1';

/// 单学科占比超过这个值视为「过于集中」。
///
/// **未标定**：0.6 是保守值——一份卷子如果 60% 以上都来自同一科，练习面就
/// 太窄；但组卷本来就可能有「今天只练数学」的合理场景，所以只报 warning，
/// 不阻断。
const double kPaperQualitySubjectShareThreshold = 0.6;

/// 判断「学科集中」至少要有几道题（1 道题的卷子报集中没有意义）。
const int kPaperQualityConcentrationMinQuestions = 2;

/// 难度极差小于这个值视为「没有区分度」。
///
/// **未标定**：1.0 意味着整卷难度都挤在同一档附近；只对至少 3 道已录难度
/// 的题生效（2 道题的极差没有统计意义）。
const double kPaperQualityFlatSpreadThreshold = 1.0;

/// 判断「难度过平」至少要有几道已录难度的题。
const int kPaperQualityFlatMinQuestions = 3;

/// 判断「来源单一」至少要有几道题。
const int kPaperQualitySourceNarrowMinQuestions = 3;

/// 判断「zone 失衡」至少要有几道题。
const int kPaperQualityZoneMinQuestions = 3;

/// evidence 里最多列几个 id / 键（超过截断并显式写总数）。
const int kPaperQualityEvidenceIdLimit = 10;

/// 题目没有学科键时的展示名。
const String kPaperQualityUnknownSubjectLabel = '未标注学科';

/// 来源分级的展示名；键与 paper_composer.dart 的 kSourceLevelPriority 同集。
///
/// 只用于展示，不参与任何判据；调用方可以用 sourceLevelNames 覆盖。
const Map<String, String> kPaperQualitySourceLevelLabels = <String, String>{
  'gaokao': '高考',
  'provincial_diagnostic': '省统测',
  'elite_school': '名校',
  'school': '校考',
  'personal': '个人',
  'unknown': '未知',
};

/// 一条判据的严重度（顺序即排序顺序：error → warning → info）。
enum PaperQualitySeverity {
  error('错误'),
  warning('警告'),
  info('提示');

  const PaperQualitySeverity(this.labelZh);

  /// 中文标签（界面文案最终由 UI 决定，这里只保证可读）。
  final String labelZh;
}

/// 判据 code 与中文说明。
///
/// code 是稳定契约（落盘、测试、工具输出都用它）；说明只用于文档与排错。
abstract final class PaperQualityCodes {
  /// 卷面是空的：一道题都没排进来。
  static const String emptyPlan = 'empty_plan';

  /// 题数不够：实际题数少于目标题数。
  static const String fillShort = 'fill_short';

  /// 单学科占比过高。
  static const String subjectConcentrated = 'subject_concentrated';

  /// 难度分布过平（没有区分度）。
  static const String difficultyFlat = 'difficulty_flat';

  /// 难度均值偏离目标难度。
  static const String difficultyFarFromTarget = 'difficulty_far_from_target';

  /// 没有逐题难度读数，难度相关判据未评估。
  static const String difficultyDataUnavailable = 'difficulty_data_unavailable';

  /// 只有部分题有难度读数。
  static const String difficultyDataPartial = 'difficulty_data_partial';

  /// 来源档位只有一种。
  static const String sourceNarrow = 'source_narrow';

  /// 一道题都没挂知识点。
  static const String noKnowledgePoints = 'no_knowledge_points';

  /// 有该练的知识点没排进来（如实报缺口）。
  static const String knowledgePointGap = 'knowledge_point_gap';

  /// 学科保底没达成（题库有候选，但受配额/数量限制没补够）。
  static const String subjectMinShortfall = 'subject_min_shortfall';

  /// 领域保底没达成（题库有候选，但受配额/数量限制没补够）。
  static const String domainMinShortfall = 'domain_min_shortfall';

  /// 学科保底没有可用题（缺口在收题，不在配额）。
  static const String uncoveredSubject = 'uncovered_subject';

  /// 领域保底没有可用题（缺口在收题，不在配额）。
  static const String uncoveredDomain = 'uncovered_domain';

  /// 有候选被配额上限挡下（上限生效；可放宽上限或增大目标题数）。
  static const String quotaBlocked = 'quota_blocked';

  /// zone 分布失衡（整卷同一 zone，且是危险区/发展区）。
  static const String zoneImbalanced = 'zone_imbalanced';

  /// 手工指定/排除的名单有问题（找不到、装不下、与排除冲突）。
  static const String manualSelectionIssues = 'manual_selection_issues';

  /// 所有 code（按声明顺序，稳定）。
  static const List<String> all = <String>[
    emptyPlan,
    fillShort,
    subjectConcentrated,
    difficultyFlat,
    difficultyFarFromTarget,
    difficultyDataUnavailable,
    difficultyDataPartial,
    sourceNarrow,
    noKnowledgePoints,
    knowledgePointGap,
    subjectMinShortfall,
    domainMinShortfall,
    uncoveredSubject,
    uncoveredDomain,
    quotaBlocked,
    zoneImbalanced,
    manualSelectionIssues,
  ];

  /// 每个 code 的中文说明（键集与 [all] 一致，测试钉住）。
  static const Map<String, String> descriptions = <String, String>{
    emptyPlan: '卷面空：一道题都没排进来',
    fillShort: '题数不够：实际题数少于目标题数',
    subjectConcentrated: '学科过于集中：单学科占比超过阈值',
    difficultyFlat: '难度过平：整卷难度挤在同一档',
    difficultyFarFromTarget: '难度偏离目标：均值超出容差',
    difficultyDataUnavailable: '没有逐题难度读数，难度判据未评估',
    difficultyDataPartial: '只有部分题有难度读数',
    sourceNarrow: '来源单一：整卷只有一种来源档位',
    noKnowledgePoints: '没有知识点归属：无法核对覆盖',
    knowledgePointGap: '知识点缺口：该练的知识点没排进来',
    subjectMinShortfall: '学科保底没达成',
    domainMinShortfall: '领域保底没达成',
    uncoveredSubject: '学科保底没有可用题（缺口在收题）',
    uncoveredDomain: '领域保底没有可用题（缺口在收题）',
    quotaBlocked: '有候选被配额上限挡住',
    zoneImbalanced: 'zone 分布失衡：整卷同一 zone',
    manualSelectionIssues: '手工指定/排除名单有问题',
  };
}

/// 一个分布桶（分布表的一行）。
class PaperQualityBucket {
  const PaperQualityBucket({
    required this.key,
    required this.labelZh,
    required this.count,
    required this.ratio,
  });

  /// 稳定键（学科键 / 领域键 / 难度档 / 来源键 / zone 名）。
  final String key;

  /// 展示名（学科走调用方的名字表；缺失回退到键）。
  final String labelZh;

  /// 数量。
  final int count;

  /// 占卷面题数的比例（领域可能多算，见
  /// [PaperQualityReport.domainDistribution]）。
  final double ratio;

  Map<String, Object?> toJson() => <String, Object?>{
        'key': key,
        'label_zh': labelZh,
        'count': count,
        'ratio': _round6(ratio),
      };

  @override
  String toString() => 'PaperQualityBucket($key: $count)';
}

/// 一条判据命中。
class PaperQualityWarning {
  const PaperQualityWarning({
    required this.code,
    required this.severity,
    required this.messageZh,
    this.evidence = const <String, String>{},
  });

  /// [PaperQualityCodes] 里的稳定 code。
  final String code;

  final PaperQualitySeverity severity;

  /// 中文事实陈述（不写模糊词）。
  final String messageZh;

  /// 证据（全部字符串，便于 toJson / 落盘）。
  final Map<String, String> evidence;

  Map<String, Object?> toJson() => <String, Object?>{
        'code': code,
        'severity': severity.name,
        'message_zh': messageZh,
        'evidence': evidence,
      };

  @override
  String toString() => 'PaperQualityWarning($code, $messageZh)';
}

/// 一份卷子的质量评价报告。
class PaperQualityReport {
  const PaperQualityReport({
    required this.questionCount,
    required this.requestedCount,
    required this.fillRatio,
    required this.subjectDistribution,
    required this.domainDistribution,
    required this.difficultyDistribution,
    required this.sourceLevelDistribution,
    required this.zoneDistribution,
    required this.coveredKnowledgePointCount,
    required this.knowledgePointCoverage,
    required this.uncoveredKnowledgePointIds,
    required this.quotaSatisfied,
    required this.warnings,
    required this.truncatedWarningCount,
  });

  /// 给一份 [PaperPlan] 出报告（确定性：同一输入同一输出）。
  ///
  /// [subjectNames] / [knowledgePointNames] / [difficultyLabels] /
  /// [sourceLevelNames] 只影响展示名，缺失一律回退到键。
  ///
  /// [difficultyByQuestionId]：题目 id → 难度（1–10）。PaperPlan 不保留逐题
  /// 难度，不传这组读数时 difficultyDistribution 为空，并记一条
  /// [PaperQualityCodes.difficultyDataUnavailable] 的 info；传了就按已录
  /// 难度的题评估分布与目标偏差（不完整时另记
  /// [PaperQualityCodes.difficultyDataPartial]）。
  ///
  /// [targetDifficulty] 为空 = 不评估「偏离目标」；[difficultyTolerance] 是
  /// 允许的绝对偏差（均值与目标差严格大于它才报）。
  ///
  /// [maxWarningsPerCode]：同一 code 最多保留几条 warn；超过截断并在最后一条
  /// 消息与 evidence 里写显式计数（truncated / total_for_code /
  /// shown_for_code），报告本身再记 [truncatedWarningCount]。小于等于 0 表示
  /// 不截断。
  static PaperQualityReport build({
    required PaperPlan plan,
    Map<String, String> subjectNames = const <String, String>{},
    Map<String, String> knowledgePointNames = const <String, String>{},
    Map<String, String> difficultyLabels = const <String, String>{},
    Map<String, String> sourceLevelNames = const <String, String>{},
    Map<String, double> difficultyByQuestionId = const <String, double>{},
    double? targetDifficulty,
    double difficultyTolerance = 1.0,
    int maxWarningsPerCode = 20,
  }) {
    return _PaperQualityBuilder(
      plan: plan,
      subjectNames: subjectNames,
      knowledgePointNames: knowledgePointNames,
      difficultyLabels: difficultyLabels,
      sourceLevelNames: sourceLevelNames,
      difficultyByQuestionId: difficultyByQuestionId,
      targetDifficulty: targetDifficulty,
      difficultyTolerance: difficultyTolerance,
      maxWarningsPerCode: maxWarningsPerCode,
    ).build();
  }

  /// 实际排进卷子的题数。
  final int questionCount;

  /// 目标题数（plan.requestedCount；负数按 0 处理）。
  final int requestedCount;

  /// 填充率：questionCount / requestedCount；目标为 0 时记 0（不除零）。
  final double fillRatio;

  /// 学科分布（按学科键升序；空学科键记为
  /// [kPaperQualityUnknownSubjectLabel]）。
  final List<PaperQualityBucket> subjectDistribution;

  /// 领域分布（来自 plan.byDomain；未启用领域配额时为空）。
  ///
  /// 一道题可属于多个领域，所以各桶 count 之和可以大于题数、ratio 之和可以
  /// 大于 1；无领域的题不计入。
  final List<PaperQualityBucket> domainDistribution;

  /// 难度分布（只统计有难度读数的题；key 是保留 1 位小数的难度档）。
  final List<PaperQualityBucket> difficultyDistribution;

  /// 来源分级分布（按来源键升序；空来源记为 unknown）。
  final List<PaperQualityBucket> sourceLevelDistribution;

  /// zone 分布（按 PaperZone 声明顺序；只出现实际出现的 zone）。
  final List<PaperQualityBucket> zoneDistribution;

  /// 卷面覆盖到的知识点数量（去重）。
  final int coveredKnowledgePointCount;

  /// 知识点覆盖率：covered / (covered ∪ uncovered)；分母为 0 时记 0。
  final double knowledgePointCoverage;

  /// plan 里如实报出的未覆盖知识点（清洗后字典序）。
  final List<String> uncoveredKnowledgePointIds;

  /// 配额是否满足：学科与领域都没有保底缺口。
  ///
  /// 被上限挡下（quotaBlockedQuestions / quotaBlockedByDomain）不算不满足——
  /// 那是上限生效的证明，另有 [PaperQualityCodes.quotaBlocked] info。
  final bool quotaSatisfied;

  /// 命中的判据（先按严重度 error → warning → info，同严重度按 code 升序；
  /// 同 code 内保持生成顺序）。
  final List<PaperQualityWarning> warnings;

  /// 因 maxWarningsPerCode 被截掉的条数（0 = 没截断）。
  final int truncatedWarningCount;

  /// 各严重度的条数（三个键始终齐全）。
  Map<PaperQualitySeverity, int> get countsBySeverity {
    final counts = <PaperQualitySeverity, int>{
      for (final severity in PaperQualitySeverity.values) severity: 0,
    };
    for (final warning in warnings) {
      counts[warning.severity] = (counts[warning.severity] ?? 0) + 1;
    }
    return Map<PaperQualitySeverity, int>.unmodifiable(counts);
  }

  bool get hasWarnings => warnings.isNotEmpty;

  bool get isEmpty => questionCount == 0;

  int severityCount(PaperQualitySeverity severity) =>
      countsBySeverity[severity] ?? 0;

  Map<String, Object?> toJson() => <String, Object?>{
        'schema': kPaperQualitySchema,
        'question_count': questionCount,
        'requested_count': requestedCount,
        'fill_ratio': _round6(fillRatio),
        'subject_distribution': [
          for (final bucket in subjectDistribution) bucket.toJson(),
        ],
        'domain_distribution': [
          for (final bucket in domainDistribution) bucket.toJson(),
        ],
        'difficulty_distribution': [
          for (final bucket in difficultyDistribution) bucket.toJson(),
        ],
        'source_level_distribution': [
          for (final bucket in sourceLevelDistribution) bucket.toJson(),
        ],
        'zone_distribution': [
          for (final bucket in zoneDistribution) bucket.toJson(),
        ],
        'covered_knowledge_point_count': coveredKnowledgePointCount,
        'knowledge_point_coverage': _round6(knowledgePointCoverage),
        'uncovered_knowledge_point_ids': uncoveredKnowledgePointIds,
        'quota_satisfied': quotaSatisfied,
        'counts_by_severity': <String, int>{
          for (final entry in countsBySeverity.entries)
            entry.key.name: entry.value,
        },
        'truncated_warning_count': truncatedWarningCount,
        'warnings': [
          for (final warning in warnings) warning.toJson(),
        ],
      };

  @override
  String toString() =>
      'PaperQualityReport(questions: $questionCount, warnings: $warnings)';
}

class _PaperQualityBuilder {
  _PaperQualityBuilder({
    required this.plan,
    required this.subjectNames,
    required this.knowledgePointNames,
    required this.difficultyLabels,
    required this.sourceLevelNames,
    required this.difficultyByQuestionId,
    required this.targetDifficulty,
    required this.difficultyTolerance,
    required this.maxWarningsPerCode,
  });

  final PaperPlan plan;
  final Map<String, String> subjectNames;
  final Map<String, String> knowledgePointNames;
  final Map<String, String> difficultyLabels;
  final Map<String, String> sourceLevelNames;
  final Map<String, double> difficultyByQuestionId;
  final double? targetDifficulty;
  final double difficultyTolerance;
  final int maxWarningsPerCode;

  final List<PaperQualityWarning> _raw = <PaperQualityWarning>[];

  PaperQualityReport build() {
    final items = plan.items;
    final requested = plan.requestedCount < 0 ? 0 : plan.requestedCount;
    final questionCount = items.length;

    final subjectCounts = <String, int>{};
    final sourceCounts = <String, int>{};
    final zoneCounts = <PaperZone, int>{};
    final coveredPoints = <String>{};
    final difficultySamples = <double>[];

    for (final item in items) {
      final subjectKey = item.subjectKey.trim();
      _increment(subjectCounts, subjectKey);
      final rawSource = item.sourceLevel.trim();
      final sourceKey = rawSource.isEmpty ? 'unknown' : rawSource;
      _increment(sourceCounts, sourceKey);
      zoneCounts[item.zone] = (zoneCounts[item.zone] ?? 0) + 1;
      final primaryPoint = item.knowledgePointId?.trim();
      if (primaryPoint != null && primaryPoint.isNotEmpty) {
        coveredPoints.add(primaryPoint);
      }
      for (final id in item.matchedKnowledgePointIds) {
        final trimmed = id.trim();
        if (trimmed.isNotEmpty) coveredPoints.add(trimmed);
      }
      final difficulty = difficultyByQuestionId[item.questionId];
      if (difficulty != null && difficulty.isFinite) {
        difficultySamples.add(difficulty);
      }
    }

    final fillRatio = requested > 0 ? questionCount / requested : 0.0;
    final subjectDistribution = _bucketsFromCounts(
      subjectCounts,
      questionCount,
      _subjectLabel,
    );
    final domainDistribution = _domainBuckets(questionCount);
    final difficultyDistribution =
        _difficultyBuckets(difficultySamples, questionCount);
    final sourceLevelDistribution = _bucketsFromCounts(
      sourceCounts,
      questionCount,
      _sourceLabel,
    );
    final zoneDistribution = _zoneBuckets(zoneCounts, questionCount);

    final uncoveredPoints = <String>{
      for (final id in plan.uncoveredKnowledgePointIds)
        if (id.trim().isNotEmpty) id.trim(),
    }.toList()
      ..sort();
    final coverageDenominator =
        <String>{...coveredPoints, ...uncoveredPoints}.length;
    final knowledgePointCoverage = coverageDenominator == 0
        ? 0.0
        : coveredPoints.length / coverageDenominator;

    final quotaSatisfied =
        plan.subjectShortfalls.isEmpty && plan.domainShortfalls.isEmpty;

    if (questionCount == 0) {
      _add(
        PaperQualityCodes.emptyPlan,
        PaperQualitySeverity.error,
        '卷面是空的：没有排进任何题（目标 $requested 道）。',
        <String, String>{
          'requested_count': requested.toString(),
          'candidate_count': plan.candidateCount.toString(),
        },
      );
    } else {
      _addFillFindings(requested, questionCount, fillRatio);
      _addSubjectFindings(subjectCounts, questionCount);
      _addSourceFindings(sourceCounts, questionCount);
      _addKnowledgePointFindings(
        coveredPoints,
        uncoveredPoints,
        knowledgePointCoverage,
        questionCount,
      );
      _addZoneFindings(zoneCounts, questionCount);
      _addDifficultyDataFindings(difficultySamples, questionCount);
    }

    _addQuotaShortfallFindings();
    _addQuotaBlockedFinding();
    _addManualFinding();

    final (warnings, truncated) = _finalizeWarnings();

    return PaperQualityReport(
      questionCount: questionCount,
      requestedCount: requested,
      fillRatio: fillRatio,
      subjectDistribution: subjectDistribution,
      domainDistribution: domainDistribution,
      difficultyDistribution: difficultyDistribution,
      sourceLevelDistribution: sourceLevelDistribution,
      zoneDistribution: zoneDistribution,
      coveredKnowledgePointCount: coveredPoints.length,
      knowledgePointCoverage: knowledgePointCoverage,
      uncoveredKnowledgePointIds: List<String>.unmodifiable(uncoveredPoints),
      quotaSatisfied: quotaSatisfied,
      warnings: warnings,
      truncatedWarningCount: truncated,
    );
  }

  void _addFillFindings(int requested, int questionCount, double fillRatio) {
    if (questionCount >= requested) return;
    final missing = requested - questionCount;
    final fillRatioText = _format2(fillRatio);
    _add(
      PaperQualityCodes.fillShort,
      PaperQualitySeverity.warning,
      '题数不够：目标 $requested 道，实际 $questionCount 道，差 $missing 道'
      '（填充率 $fillRatioText）。',
      <String, String>{
        'requested_count': requested.toString(),
        'question_count': questionCount.toString(),
        'missing_count': missing.toString(),
        'fill_ratio': fillRatioText,
      },
    );
  }

  void _addSubjectFindings(Map<String, int> subjectCounts, int questionCount) {
    if (questionCount < kPaperQualityConcentrationMinQuestions) return;
    final top = _topEntry(subjectCounts);
    if (top == null) return;
    final ratio = top.value / questionCount;
    if (ratio <= kPaperQualitySubjectShareThreshold) return;
    final label = _subjectLabel(top.key);
    final count = top.value;
    final ratioText = _format2(ratio);
    final thresholdText = _format2(kPaperQualitySubjectShareThreshold);
    _add(
      PaperQualityCodes.subjectConcentrated,
      PaperQualitySeverity.warning,
      '学科过于集中：$label $count 道占 $ratioText（阈值 $thresholdText）。',
      <String, String>{
        'subject_key': top.key,
        'count': count.toString(),
        'ratio': ratioText,
        'threshold': thresholdText,
      },
    );
  }

  void _addSourceFindings(Map<String, int> sourceCounts, int questionCount) {
    if (questionCount < kPaperQualitySourceNarrowMinQuestions) return;
    if (sourceCounts.length != 1) return;
    final key = sourceCounts.keys.single;
    final label = _sourceLabel(key);
    _add(
      PaperQualityCodes.sourceNarrow,
      PaperQualitySeverity.warning,
      '来源单一：全部 $questionCount 道题都来自 $label。',
      <String, String>{
        'source_level': key,
        'count': questionCount.toString(),
      },
    );
  }

  void _addKnowledgePointFindings(
    Set<String> coveredPoints,
    List<String> uncoveredPoints,
    double coverage,
    int questionCount,
  ) {
    final coveredCount = coveredPoints.length;
    if (coveredCount == 0) {
      _add(
        PaperQualityCodes.noKnowledgePoints,
        PaperQualitySeverity.warning,
        '没有知识点归属：$questionCount 道题都没挂知识点，无法核对覆盖。',
        <String, String>{'question_count': questionCount.toString()},
      );
    }
    if (uncoveredPoints.isEmpty) return;
    final uncoveredCount = uncoveredPoints.length;
    final coverageText = _format2(coverage);
    _add(
      PaperQualityCodes.knowledgePointGap,
      PaperQualitySeverity.warning,
      '知识点缺口：$uncoveredCount 个该练的知识点一道都没排进来'
      '（覆盖率 $coverageText）。',
      <String, String>{
        'uncovered_count': uncoveredCount.toString(),
        'covered_count': coveredCount.toString(),
        'coverage': coverageText,
        'knowledge_point_ids': _joinKnowledgePointIds(uncoveredPoints),
        'knowledge_point_labels': _joinKnowledgePointLabels(uncoveredPoints),
      },
    );
  }

  void _addZoneFindings(Map<PaperZone, int> zoneCounts, int questionCount) {
    if (questionCount < kPaperQualityZoneMinQuestions) return;
    if (zoneCounts.length != 1) return;
    final zone = zoneCounts.keys.single;
    if (zone != PaperZone.danger && zone != PaperZone.development) return;
    final zoneLabel = zone.labelZh;
    _add(
      PaperQualityCodes.zoneImbalanced,
      PaperQualitySeverity.warning,
      'zone 分布失衡：$questionCount 道题全部落在 $zoneLabel。',
      <String, String>{
        'zone': zone.name,
        'count': questionCount.toString(),
      },
    );
  }

  void _addDifficultyDataFindings(
    List<double> samples,
    int questionCount,
  ) {
    if (samples.isEmpty) {
      _add(
        PaperQualityCodes.difficultyDataUnavailable,
        PaperQualitySeverity.info,
        '没有难度读数：本卷没有逐题难度，难度分布与难度判据未评估。',
        <String, String>{'question_count': questionCount.toString()},
      );
      return;
    }
    if (samples.length < questionCount) {
      final known = samples.length;
      final missing = questionCount - known;
      _add(
        PaperQualityCodes.difficultyDataPartial,
        PaperQualitySeverity.info,
        '只有部分题有难度读数：$questionCount 道里 $known 道，'
        '难度判据只按这些题算。',
        <String, String>{
          'known_count': known.toString(),
          'missing_count': missing.toString(),
        },
      );
    }
    var min = samples.first;
    var max = samples.first;
    var sum = 0.0;
    for (final value in samples) {
      if (value < min) min = value;
      if (value > max) max = value;
      sum += value;
    }
    final mean = sum / samples.length;
    final spread = max - min;
    if (samples.length >= kPaperQualityFlatMinQuestions &&
        spread < kPaperQualityFlatSpreadThreshold) {
      final known = samples.length;
      final spreadText = _format2(spread);
      final thresholdText = _format2(kPaperQualityFlatSpreadThreshold);
      _add(
        PaperQualityCodes.difficultyFlat,
        PaperQualitySeverity.warning,
        '难度过平：$known 道已录难度的题极差 $spreadText，低于阈值'
        ' $thresholdText。',
        <String, String>{
          'item_count': known.toString(),
          'spread': spreadText,
          'threshold': thresholdText,
        },
      );
    }
    final target = targetDifficulty;
    if (target == null || !target.isFinite) return;
    final deviation = (mean - target).abs();
    if (deviation <= difficultyTolerance) return;
    final known = samples.length;
    final meanText = _format2(mean);
    final targetText = _format2(target);
    final deviationText = _format2(deviation);
    final toleranceText = _format2(difficultyTolerance);
    _add(
      PaperQualityCodes.difficultyFarFromTarget,
      PaperQualitySeverity.warning,
      '难度偏离目标：均值 $meanText，目标 $targetText，偏差 '
      '$deviationText 超出容差 $toleranceText。',
      <String, String>{
        'item_count': known.toString(),
        'mean': meanText,
        'target': targetText,
        'deviation': deviationText,
        'tolerance': toleranceText,
      },
    );
  }

  void _addQuotaShortfallFindings() {
    final subjectShortfalls = <SubjectQuotaShortfall>[
      ...plan.subjectShortfalls,
    ]..sort((a, b) => a.subjectKey.compareTo(b.subjectKey));
    for (final shortfall in subjectShortfalls) {
      final subjectKey = shortfall.subjectKey;
      final label = _subjectLabel(subjectKey);
      final minimum = shortfall.minimumCount;
      final selected = shortfall.selectedCount;
      final available = shortfall.availableCount;
      final evidence = <String, String>{
        'subject_key': subjectKey,
        'minimum_count': minimum.toString(),
        'selected_count': selected.toString(),
        'available_count': available.toString(),
      };
      if (shortfall.isUncovered) {
        _add(
          PaperQualityCodes.uncoveredSubject,
          PaperQualitySeverity.warning,
          '学科保底没有可用题：$label 保底 $minimum 道，题库里 0 道候选。',
          evidence,
        );
        continue;
      }
      final diff = minimum - selected;
      _add(
        PaperQualityCodes.subjectMinShortfall,
        PaperQualitySeverity.warning,
        '学科保底没达成：$label 差 $diff 道（保底 $minimum 道，'
        '已排 $selected 道；可用候选 $available 道）。',
        evidence,
      );
    }

    final domainShortfalls = <DomainQuotaShortfall>[
      ...plan.domainShortfalls,
    ]..sort((a, b) => a.domain.compareTo(b.domain));
    for (final shortfall in domainShortfalls) {
      final domain = shortfall.domain;
      final minimum = shortfall.minimumCount;
      final selected = shortfall.selectedCount;
      final available = shortfall.availableCount;
      final evidence = <String, String>{
        'domain': domain,
        'minimum_count': minimum.toString(),
        'selected_count': selected.toString(),
        'available_count': available.toString(),
      };
      if (shortfall.isUncovered) {
        _add(
          PaperQualityCodes.uncoveredDomain,
          PaperQualitySeverity.warning,
          '领域保底没有可用题：$domain 保底 $minimum 道，题库里 0 道候选。',
          evidence,
        );
        continue;
      }
      final diff = minimum - selected;
      _add(
        PaperQualityCodes.domainMinShortfall,
        PaperQualitySeverity.warning,
        '领域保底没达成：$domain 差 $diff 道（保底 $minimum 道，'
        '已排 $selected 道；可用候选 $available 道）。',
        evidence,
      );
    }
  }

  void _addQuotaBlockedFinding() {
    final subjectBlocked = plan.quotaBlockedQuestions.length;
    final domainBlocked = plan.quotaBlockedByDomain.length;
    if (subjectBlocked == 0 && domainBlocked == 0) return;
    _add(
      PaperQualityCodes.quotaBlocked,
      PaperQualitySeverity.info,
      '有题被配额上限挡下：学科上限 $subjectBlocked 道、领域上限 '
      '$domainBlocked 道（放宽对应上限或增大目标题数才能看到它们）。',
      <String, String>{
        'subject_blocked_count': subjectBlocked.toString(),
        'domain_blocked_count': domainBlocked.toString(),
        'subject_counts': _quotaSubjectCounts(),
        'domain_counts': _quotaDomainCounts(),
      },
    );
  }

  void _addManualFinding() {
    if (!plan.manualSelectionEnabled) return;
    final missing = plan.manualMissingQuestionIds.length;
    final skipped = plan.manualSkippedQuestionIds.length;
    final conflicts = plan.manualConflictQuestionIds.length;
    if (missing == 0 && skipped == 0 && conflicts == 0) return;
    _add(
      PaperQualityCodes.manualSelectionIssues,
      PaperQualitySeverity.info,
      '手工名单有问题：题库里找不到 $missing 道、目标题数装不下 $skipped 道、'
      '与排除冲突 $conflicts 道。',
      <String, String>{
        'missing_ids': missing.toString(),
        'skipped_ids': skipped.toString(),
        'conflict_ids': conflicts.toString(),
        'missing_preview': _joinIds(plan.manualMissingQuestionIds),
        'skipped_preview': _joinIds(plan.manualSkippedQuestionIds),
        'conflict_preview': _joinIds(plan.manualConflictQuestionIds),
      },
    );
  }

  (List<PaperQualityWarning>, int) _finalizeWarnings() {
    final groups = <String, List<PaperQualityWarning>>{};
    for (final warning in _raw) {
      groups
          .putIfAbsent(warning.code, () => <PaperQualityWarning>[])
          .add(warning);
    }
    final kept = <PaperQualityWarning>[];
    var truncated = 0;
    for (final group in groups.values) {
      final limit = maxWarningsPerCode <= 0 ? group.length : maxWarningsPerCode;
      if (group.length <= limit) {
        kept.addAll(group);
        continue;
      }
      truncated += group.length - limit;
      kept.addAll(group.take(limit));
      final last = kept.removeLast();
      final total = group.length;
      final baseMessage = last.messageZh;
      kept.add(
        PaperQualityWarning(
          code: last.code,
          severity: last.severity,
          messageZh: '$baseMessage（同类共 $total 条，已显示前 $limit 条）',
          evidence: <String, String>{
            ...last.evidence,
            'truncated': 'true',
            'total_for_code': total.toString(),
            'shown_for_code': limit.toString(),
          },
        ),
      );
    }
    final ordered = <({int index, PaperQualityWarning warning})>[
      for (var i = 0; i < kept.length; i++) (index: i, warning: kept[i]),
    ]..sort((a, b) {
        final severity =
            a.warning.severity.index.compareTo(b.warning.severity.index);
        if (severity != 0) return severity;
        final code = a.warning.code.compareTo(b.warning.code);
        if (code != 0) return code;
        return a.index.compareTo(b.index);
      });
    return (
      List<PaperQualityWarning>.unmodifiable(
        <PaperQualityWarning>[for (final entry in ordered) entry.warning],
      ),
      truncated,
    );
  }

  List<PaperQualityBucket> _bucketsFromCounts(
    Map<String, int> counts,
    int total,
    String Function(String key) labelOf,
  ) {
    final keys = counts.keys.toList()..sort();
    return List<PaperQualityBucket>.unmodifiable(<PaperQualityBucket>[
      for (final key in keys)
        PaperQualityBucket(
          key: key,
          labelZh: labelOf(key),
          count: counts[key]!,
          ratio: total > 0 ? counts[key]! / total : 0.0,
        ),
    ]);
  }

  List<PaperQualityBucket> _domainBuckets(int total) {
    final counts = <String, int>{};
    for (final entry in plan.byDomain.entries) {
      final key = entry.key.trim();
      if (key.isEmpty || entry.value <= 0) continue;
      counts[key] = (counts[key] ?? 0) + entry.value;
    }
    return _bucketsFromCounts(counts, total, (key) => key);
  }

  List<PaperQualityBucket> _difficultyBuckets(
    List<double> samples,
    int total,
  ) {
    final counts = <String, int>{};
    for (final value in samples) {
      final key = value.toStringAsFixed(1);
      counts[key] = (counts[key] ?? 0) + 1;
    }
    final keys = counts.keys.toList()
      ..sort((a, b) => double.parse(a).compareTo(double.parse(b)));
    return List<PaperQualityBucket>.unmodifiable(<PaperQualityBucket>[
      for (final key in keys)
        PaperQualityBucket(
          key: key,
          labelZh: difficultyLabels[key] ?? '难度 $key',
          count: counts[key]!,
          ratio: total > 0 ? counts[key]! / total : 0.0,
        ),
    ]);
  }

  List<PaperQualityBucket> _zoneBuckets(
    Map<PaperZone, int> counts,
    int total,
  ) {
    return List<PaperQualityBucket>.unmodifiable(<PaperQualityBucket>[
      for (final zone in PaperZone.values)
        if (counts.containsKey(zone))
          PaperQualityBucket(
            key: zone.name,
            labelZh: zone.labelZh,
            count: counts[zone]!,
            ratio: total > 0 ? counts[zone]! / total : 0.0,
          ),
    ]);
  }

  MapEntry<String, int>? _topEntry(Map<String, int> counts) {
    if (counts.isEmpty) return null;
    final keys = counts.keys.toList()..sort();
    var best = keys.first;
    for (final key in keys) {
      if (counts[key]! > counts[best]!) best = key;
    }
    return MapEntry<String, int>(best, counts[best]!);
  }

  String _subjectLabel(String key) {
    if (key.isEmpty) return kPaperQualityUnknownSubjectLabel;
    return subjectNames[key] ?? key;
  }

  String _sourceLabel(String key) =>
      sourceLevelNames[key] ?? kPaperQualitySourceLevelLabels[key] ?? key;

  String _joinKnowledgePointIds(List<String> ids) {
    final total = ids.length;
    final shown = ids.take(kPaperQualityEvidenceIdLimit).join(', ');
    if (total <= kPaperQualityEvidenceIdLimit) return shown;
    return '$shown…（共 $total 个）';
  }

  String _joinKnowledgePointLabels(List<String> ids) {
    final total = ids.length;
    final shown = ids
        .take(kPaperQualityEvidenceIdLimit)
        .map((id) => knowledgePointNames[id] ?? id)
        .join(', ');
    if (total <= kPaperQualityEvidenceIdLimit) return shown;
    return '$shown…（共 $total 个）';
  }

  String _joinIds(List<String> ids) {
    final cleaned = <String>[
      for (final id in ids)
        if (id.trim().isNotEmpty) id.trim(),
    ];
    final total = cleaned.length;
    if (total == 0) return '';
    final shown = cleaned.take(kPaperQualityEvidenceIdLimit).join(', ');
    if (total <= kPaperQualityEvidenceIdLimit) return shown;
    return '$shown…（共 $total 个）';
  }

  String _quotaSubjectCounts() {
    final counts = <String, int>{};
    for (final blocked in plan.quotaBlockedQuestions) {
      final key = blocked.subjectKey.trim();
      if (key.isEmpty) continue;
      counts[key] = (counts[key] ?? 0) + 1;
    }
    return _countsText(counts);
  }

  String _quotaDomainCounts() {
    final counts = <String, int>{};
    for (final blocked in plan.quotaBlockedByDomain) {
      final key = blocked.domain.trim();
      if (key.isEmpty) continue;
      counts[key] = (counts[key] ?? 0) + 1;
    }
    return _countsText(counts);
  }

  String _countsText(Map<String, int> counts) {
    if (counts.isEmpty) return '';
    final keys = counts.keys.toList()..sort();
    final shown = keys.take(kPaperQualityEvidenceIdLimit).toList();
    final parts = <String>[];
    for (final key in shown) {
      final count = counts[key]!;
      parts.add('$key $count 道');
    }
    final totalKeys = keys.length;
    final suffix =
        totalKeys <= kPaperQualityEvidenceIdLimit ? '' : '…（共 $totalKeys 个）';
    return parts.join('、') + suffix;
  }

  void _add(
    String code,
    PaperQualitySeverity severity,
    String messageZh,
    Map<String, String> evidence,
  ) {
    _raw.add(
      PaperQualityWarning(
        code: code,
        severity: severity,
        messageZh: messageZh,
        evidence: evidence,
      ),
    );
  }
}

void _increment(Map<String, int> counts, String key) {
  counts[key] = (counts[key] ?? 0) + 1;
}

double _round6(double value) => (value * 1000000).roundToDouble() / 1000000;

String _format2(double value) => value.toStringAsFixed(2);
