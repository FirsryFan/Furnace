/// 全库入库体检聚合报告（QuestionAuditSummary）：把 [QuestionIntakeAudit] 的逐题
/// 结论（[QuestionAuditReport]）聚合成「这批题整体哪里烂、先修哪几道」。
///
/// 只做纯内存聚合：不读 DB、不调模型、不改题；输出全部显式排序、可复现。
///
/// 输入口径：期望每个 report 对应一道题（逐题调用 auditRow 后收集）。若把一次
/// audit(rows) 的整批 report 传进来，questionCount / cleanQuestionCount 仍按
/// report 数计，而 codeCounts / topOffenders 会按 finding.questionId 展开——
/// 两种用法不要混。空输入返回 [QuestionAuditSummary.empty]（比值 0，不抛）。
///
/// 排序口径（不依赖 Map 迭代顺序）：
///  - codeCounts：severity 升序（error → warning → info）→ findingCount 降序 →
///    questionCount 降序 → code 升序；
///  - topOffenders：priorityScore 降序 → errorCount 降序 → warningCount 降序 →
///    questionId 升序；
///  - 每题的 codes 与判据的 sampleQuestionIds 都按字符串升序。
///
/// 优先级公式：priorityScore = errorCount * [kQuestionAuditErrorWeight] +
/// warningCount * [kQuestionAuditWarningWeight] + infoCount *
/// [kQuestionAuditInfoWeight]。三个权重是**未标定**的公开常量：只回答
/// 「先修哪道」的相对顺序，不是质量结论。
library;

import 'question_intake_audit.dart';

/// 一条 error 的优先级权重（未标定：10 只用于相对排序）。
const int kQuestionAuditErrorWeight = 10;

/// 一条 warning 的优先级权重（未标定）。
const int kQuestionAuditWarningWeight = 3;

/// 一条 info 的优先级权重（未标定）。
const int kQuestionAuditInfoWeight = 1;

/// 默认最多回报多少道「优先修」的题。
const int kQuestionAuditDefaultMaxOffenders = 10;

/// 默认每个判据最多保留多少个样例题号。
const int kQuestionAuditDefaultMaxSampleQuestionIds = 5;

/// 一个判据 code 在全库的聚合计数。
///
/// [findingCount] 是该 code 的结论条数，[questionCount] 是不同题数；同一道题在同一
/// code 上出现两次时前者 +2、后者 +1。
class QuestionAuditCodeCount {
  const QuestionAuditCodeCount({
    required this.code,
    required this.severity,
    required this.findingCount,
    required this.questionCount,
    required this.sampleQuestionIds,
  });

  /// 判据 code（见 [QuestionAuditCodes]）。
  final String code;

  /// 该 code 的最高严重度（同 code 出现互相矛盾的严重度时取最重的一档）。
  final QuestionAuditSeverity severity;

  /// 该 code 的结论总条数。
  final int findingCount;

  /// 命中该 code 的不同题目数。
  final int questionCount;

  /// 命中该 code 的样例题号，按字符串升序，最多 maxSampleQuestionIds 个。
  final List<String> sampleQuestionIds;

  /// 浅序列化（UI 日志/调试用；键统一 snake_case）。
  Map<String, Object?> toJson() => <String, Object?>{
        'code': code,
        'severity': severity.name,
        'finding_count': findingCount,
        'question_count': questionCount,
        'sample_question_ids': sampleQuestionIds,
      };

  @override
  String toString() =>
      'QuestionAuditCodeCount($code, $severity, $findingCount 条 / $questionCount 题)';
}

/// 一道「问题题」的聚合画像：按严重度拆开计数并给出优先级分数。
class QuestionAuditOffender {
  const QuestionAuditOffender({
    required this.questionId,
    required this.errorCount,
    required this.warningCount,
    required this.infoCount,
    required this.codes,
    required this.priorityScore,
  });

  /// 题目 id（questions.id）。
  final String questionId;

  /// 该题的 error 结论条数。
  final int errorCount;

  /// 该题的 warning 结论条数。
  final int warningCount;

  /// 该题的 info 结论条数。
  final int infoCount;

  /// 该题命中的全部 code，去重后按字符串升序。
  final List<String> codes;

  /// 优先级分数（公式见 library doc；越大越应先修）。
  final int priorityScore;

  /// 浅序列化。
  Map<String, Object?> toJson() => <String, Object?>{
        'question_id': questionId,
        'error_count': errorCount,
        'warning_count': warningCount,
        'info_count': infoCount,
        'codes': codes,
        'priority_score': priorityScore,
      };

  @override
  String toString() =>
      'QuestionAuditOffender($questionId, priority=$priorityScore)';
}

/// 全库体检的聚合结果。构造后只读；排序保证见 library doc。
class QuestionAuditSummary {
  const QuestionAuditSummary({
    required this.questionCount,
    required this.cleanQuestionCount,
    required this.dirtyQuestionCount,
    required this.cleanRatio,
    required this.findingsBySeverity,
    required this.codeCounts,
    required this.topOffenders,
    required this.truncatedOffenderCount,
  });

  /// 空输入的结果：题数 0、比值 0、不抛。
  static const QuestionAuditSummary empty = QuestionAuditSummary(
    questionCount: 0,
    cleanQuestionCount: 0,
    dirtyQuestionCount: 0,
    cleanRatio: 0,
    findingsBySeverity: <QuestionAuditSeverity, int>{
      QuestionAuditSeverity.error: 0,
      QuestionAuditSeverity.warning: 0,
      QuestionAuditSeverity.info: 0,
    },
    codeCounts: <QuestionAuditCodeCount>[],
    topOffenders: <QuestionAuditOffender>[],
    truncatedOffenderCount: 0,
  );

  /// 体检的 report 数（期望等于题目数）。
  final int questionCount;

  /// 没有任何 finding 的题目数。
  final int cleanQuestionCount;

  /// 至少命中一条 finding 的题目数。
  final int dirtyQuestionCount;

  /// 干净题占比（clean / questionCount；题数 0 记 0，范围 0–1）。
  final double cleanRatio;

  /// 每种严重度的结论条数（三档键齐全）。
  final Map<QuestionAuditSeverity, int> findingsBySeverity;

  /// 按 library doc 口径排序的判据聚合。
  final List<QuestionAuditCodeCount> codeCounts;

  /// 优先级最高的前 maxOffenders 道题。
  final List<QuestionAuditOffender> topOffenders;

  /// 因 maxOffenders 截断而没进 topOffenders 的题数。
  final int truncatedOffenderCount;

  int get errorCount => findingsBySeverity[QuestionAuditSeverity.error] ?? 0;

  int get warningCount =>
      findingsBySeverity[QuestionAuditSeverity.warning] ?? 0;

  int get infoCount => findingsBySeverity[QuestionAuditSeverity.info] ?? 0;

  /// 全部结论条数（三档之和）。
  int get findingCount => errorCount + warningCount + infoCount;

  /// 没有任何输入 report。空库也是一种「干净」，但 [isEmpty] 用于区分「没体检」。
  bool get isEmpty => questionCount == 0;

  /// 全部题都干净（或空输入）。注意：干净不等于「已证明没问题」。
  bool get isClean => dirtyQuestionCount == 0;

  /// 浅序列化（键顺序固定，便于测试逐字节比较）。
  Map<String, Object?> toJson() => <String, Object?>{
        'question_count': questionCount,
        'clean_question_count': cleanQuestionCount,
        'dirty_question_count': dirtyQuestionCount,
        'clean_ratio': _round6(cleanRatio),
        'findings_by_severity': <String, int>{
          'error': errorCount,
          'warning': warningCount,
          'info': infoCount,
        },
        'code_counts': <Object?>[
          for (final count in codeCounts) count.toJson(),
        ],
        'top_offenders': <Object?>[
          for (final offender in topOffenders) offender.toJson(),
        ],
        'truncated_offender_count': truncatedOffenderCount,
        'is_empty': isEmpty,
        'is_clean': isClean,
      };

  /// 聚合全库体检报告。
  ///
  /// [maxOffenders] 与 [maxSampleQuestionIds] 小于 0 时按 0 处理（不抛）。
  static QuestionAuditSummary summarize(
    Iterable<QuestionAuditReport> reports, {
    int maxOffenders = kQuestionAuditDefaultMaxOffenders,
    int maxSampleQuestionIds = kQuestionAuditDefaultMaxSampleQuestionIds,
  }) =>
      _QuestionAuditSummarizer(
        maxOffenders: maxOffenders,
        maxSampleQuestionIds: maxSampleQuestionIds,
      ).summarize(reports);

  @override
  String toString() => 'QuestionAuditSummary('
      'questions=$questionCount, clean=$cleanQuestionCount, '
      'findings=$findingCount)';
}

/// 聚合实现：对 findings 做一次稳定的内存扫描。
class _QuestionAuditSummarizer {
  _QuestionAuditSummarizer({
    required this.maxOffenders,
    required this.maxSampleQuestionIds,
  });

  final int maxOffenders;
  final int maxSampleQuestionIds;

  final Map<String, int> _codeFindingCounts = <String, int>{};
  final Map<String, QuestionAuditSeverity> _codeSeverities =
      <String, QuestionAuditSeverity>{};
  final Map<String, Set<String>> _codeQuestionIds = <String, Set<String>>{};
  final Map<String, int> _errorCounts = <String, int>{};
  final Map<String, int> _warningCounts = <String, int>{};
  final Map<String, int> _infoCounts = <String, int>{};
  final Map<String, Set<String>> _offenderCodes = <String, Set<String>>{};
  final Map<QuestionAuditSeverity, int> _severityTotals =
      <QuestionAuditSeverity, int>{
    for (final severity in QuestionAuditSeverity.values) severity: 0,
  };

  QuestionAuditSummary summarize(Iterable<QuestionAuditReport> reports) {
    final List<QuestionAuditReport> reportList =
        reports.toList(growable: false);
    if (reportList.isEmpty) return QuestionAuditSummary.empty;
    var cleanCount = 0;
    for (final report in reportList) {
      if (report.findings.isEmpty) {
        cleanCount++;
        continue;
      }
      for (final finding in report.findings) {
        _accumulateCode(finding);
        _accumulateQuestion(finding);
      }
    }
    final int questionCount = reportList.length;
    final int dirtyCount = questionCount - cleanCount;
    final double ratio = cleanCount / questionCount;
    final List<QuestionAuditCodeCount> codeCounts = _buildCodeCounts();
    final List<QuestionAuditOffender> offenders = _buildOffenders();
    final int effectiveMaxOffenders = maxOffenders <= 0 ? 0 : maxOffenders;
    final int kept = offenders.length <= effectiveMaxOffenders
        ? offenders.length
        : effectiveMaxOffenders;
    return QuestionAuditSummary(
      questionCount: questionCount,
      cleanQuestionCount: cleanCount,
      dirtyQuestionCount: dirtyCount,
      cleanRatio: ratio.clamp(0.0, 1.0).toDouble(),
      findingsBySeverity: Map<QuestionAuditSeverity, int>.unmodifiable(
        _severityTotals,
      ),
      codeCounts: List<QuestionAuditCodeCount>.unmodifiable(codeCounts),
      topOffenders: List<QuestionAuditOffender>.unmodifiable(
        offenders.take(kept),
      ),
      truncatedOffenderCount: offenders.length - kept,
    );
  }

  void _accumulateCode(QuestionAuditFinding finding) {
    final String code = finding.code;
    _codeFindingCounts[code] = (_codeFindingCounts[code] ?? 0) + 1;
    final QuestionAuditSeverity? current = _codeSeverities[code];
    if (current == null || finding.severity.index < current.index) {
      _codeSeverities[code] = finding.severity;
    }
    _codeQuestionIds
        .putIfAbsent(code, () => <String>{})
        .add(finding.questionId);
  }

  void _accumulateQuestion(QuestionAuditFinding finding) {
    final String id = finding.questionId;
    switch (finding.severity) {
      case QuestionAuditSeverity.error:
        _errorCounts[id] = (_errorCounts[id] ?? 0) + 1;
      case QuestionAuditSeverity.warning:
        _warningCounts[id] = (_warningCounts[id] ?? 0) + 1;
      case QuestionAuditSeverity.info:
        _infoCounts[id] = (_infoCounts[id] ?? 0) + 1;
    }
    _severityTotals[finding.severity] =
        (_severityTotals[finding.severity] ?? 0) + 1;
    _offenderCodes.putIfAbsent(id, () => <String>{}).add(finding.code);
  }

  List<QuestionAuditCodeCount> _buildCodeCounts() {
    final List<String> codes = _codeFindingCounts.keys.toList()..sort();
    final List<QuestionAuditCodeCount> counts = <QuestionAuditCodeCount>[
      for (final code in codes)
        QuestionAuditCodeCount(
          code: code,
          severity: _codeSeverities[code]!,
          findingCount: _codeFindingCounts[code]!,
          questionCount: _codeQuestionIds[code]!.length,
          sampleQuestionIds: _sampleIds(_codeQuestionIds[code]!),
        ),
    ];
    counts.sort(_compareCodeCounts);
    return counts;
  }

  List<QuestionAuditOffender> _buildOffenders() {
    final List<String> ids = _offenderCodes.keys.toList()..sort();
    final List<QuestionAuditOffender> offenders = <QuestionAuditOffender>[
      for (final id in ids)
        QuestionAuditOffender(
          questionId: id,
          errorCount: _errorCounts[id] ?? 0,
          warningCount: _warningCounts[id] ?? 0,
          infoCount: _infoCounts[id] ?? 0,
          codes:
              List<String>.unmodifiable(_offenderCodes[id]!.toList()..sort()),
          priorityScore: (_errorCounts[id] ?? 0) * kQuestionAuditErrorWeight +
              (_warningCounts[id] ?? 0) * kQuestionAuditWarningWeight +
              (_infoCounts[id] ?? 0) * kQuestionAuditInfoWeight,
        ),
    ];
    offenders.sort(_compareOffenders);
    return offenders;
  }

  List<String> _sampleIds(Set<String> ids) {
    final List<String> sorted = ids.toList()..sort();
    final int effective = maxSampleQuestionIds <= 0 ? 0 : maxSampleQuestionIds;
    return List<String>.unmodifiable(sorted.take(effective));
  }

  static int _compareCodeCounts(
    QuestionAuditCodeCount a,
    QuestionAuditCodeCount b,
  ) {
    final int bySeverity = a.severity.index.compareTo(b.severity.index);
    if (bySeverity != 0) return bySeverity;
    final int byFinding = b.findingCount.compareTo(a.findingCount);
    if (byFinding != 0) return byFinding;
    final int byQuestion = b.questionCount.compareTo(a.questionCount);
    if (byQuestion != 0) return byQuestion;
    return a.code.compareTo(b.code);
  }

  static int _compareOffenders(
    QuestionAuditOffender a,
    QuestionAuditOffender b,
  ) {
    final int byPriority = b.priorityScore.compareTo(a.priorityScore);
    if (byPriority != 0) return byPriority;
    final int byError = b.errorCount.compareTo(a.errorCount);
    if (byError != 0) return byError;
    final int byWarning = b.warningCount.compareTo(a.warningCount);
    if (byWarning != 0) return byWarning;
    return a.questionId.compareTo(b.questionId);
  }
}

double _round6(double value) {
  if (!value.isFinite) return 0;
  return (value * 1000000).roundToDouble() / 1000000;
}
