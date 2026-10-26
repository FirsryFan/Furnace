/// 通用能力 A1–A10 的练习统计（纯逻辑，不碰数据库）。
///
/// 输入是调用方从题库 / 练习记录读出的 [CapabilityAttempt] 列表（一题可挂多个能力），
/// 输出是不可变报告：每个能力点正确率、每个题型正确率、题型×能力（T×A）交叉表，
/// 以及「最弱能力点」排序。字段口径来自
/// `E:/FirsryOS/THREADRIPPER/handoff/2026-10-26-furnace-pipeline/FURNACE-PIPELINE-SPEC-v1.md`
/// 第 5.6 节（A1–A10 能力层）与第 5.9 节（result = 对 / 错 / 部分对，capability 可多值）。
///
/// 统计口径（测试锁定）：
/// * 一题挂多个能力 A 时，每个能力各记一次；正确率分母是「能力点出现次数」，不是题数；
/// * 「正确率」严格按 result == 对 计算，部分对不算对；另给部分对按半分的加权正确率；
/// * 没有合法能力 code 的记录不计入能力点，但仍计入整体 / 题型统计，并在
///   [CapabilityStatsReport.unattributedAttemptCount] 计数（匿名不可怕，隐藏数据才可怕）；
/// * 样本少于 [CapabilityStatsReport.minSamplesForConclusion] 的能力点照样给数字，
///   但 hasEnoughSamples = false 标明「别硬下结论」；
/// * 不自动判第 5.6 节的「通用缺陷 / 程序缺陷 / 噪音」：阈值属于判断，
///   本层只提供 T×A 交叉表作为数据底座；
/// * 不读时钟、不随机、不依赖输入顺序：同一个输入集合永远得到同一个报告。
library;

import 'question_capability.dart';

/// 下结论默认需要的最小样本数（能力点出现次数）。
const int kCapabilityMinSamplesForConclusion = 3;

/// [CapabilityStatsReport.weakest] 默认返回的能力点个数。
const int kCapabilityWeakestLimit = 3;

/// 练习结果（规格第 5.9 节的 result 三值：对 / 错 / 部分对）。
enum QuestionResult {
  /// 对。
  correct('对'),

  /// 错。
  incorrect('错'),

  /// 部分对。
  partial('部分对');

  const QuestionResult(this.labelZh);

  /// 中文标签。
  final String labelZh;

  /// 从字符串解析结果：correct / right / 对 / 正确、incorrect / wrong / 错 / 错误、
  /// partial / 部分对 / 部分正确（去首尾空白、不分大小写）；未知或 null 返回 null。
  static QuestionResult? fromCode(String? raw) {
    final trimmed = raw?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    switch (trimmed.toLowerCase()) {
      case 'correct':
      case 'right':
      case '对':
      case '正确':
        return QuestionResult.correct;
      case 'incorrect':
      case 'wrong':
      case '错':
      case '错误':
        return QuestionResult.incorrect;
      case 'partial':
      case '部分对':
      case '部分正确':
        return QuestionResult.partial;
    }
    return null;
  }
}

/// 一条练习记录（不可变 value object）。
///
/// 只带统计需要的字段，不依赖 drift / entity / DB；调用方自己把数据库行映射进来。
/// 构造时归一化：questionType 去首尾空白；capabilities 走
/// [capabilityCodesFromJson]（未知 code 丢弃、去重、按 A 序）；timeSpentSeconds 为负按 0 计。
class CapabilityAttempt {
  CapabilityAttempt({
    required this.questionId,
    required String questionType,
    List<String> capabilities = const <String>[],
    required this.result,
    int timeSpentSeconds = 0,
  })  : questionType = questionType.trim(),
        capabilities = capabilityCodesFromJson(capabilities),
        timeSpentSeconds = timeSpentSeconds < 0 ? 0 : timeSpentSeconds;

  /// 题目 id；空字符串允许（统计时不计入 distinctQuestionCount）。
  final String questionId;

  /// 题型 key，已去首尾空白；未知题型照样统计，展示时由 [questionTypeLabelZh] 原样返回。
  final String questionType;

  /// 归一化后的能力编号列表（不可变、去重、按 A 序）。
  final List<String> capabilities;

  /// 结果。
  final QuestionResult result;

  /// 用时秒数；负数已夹成 0。
  final int timeSpentSeconds;
}

/// 一组练习结果的计数与正确率（不可变）。
class ResultCounts {
  const ResultCounts({
    this.attempts = 0,
    this.correct = 0,
    this.incorrect = 0,
    this.partial = 0,
  });

  /// 全零计数。
  static const ResultCounts empty = ResultCounts();

  /// 次数（能力点统计里 = 能力点出现次数）。
  final int attempts;

  /// 对。
  final int correct;

  /// 错。
  final int incorrect;

  /// 部分对。
  final int partial;

  /// 严格正确率 = 对 / 次数；部分对不算对。无样本返回 null。
  double? get accuracy01 => attempts == 0 ? null : correct / attempts;

  /// 加权正确率 = (对 + 0.5 × 部分对) / 次数。无样本返回 null。
  double? get weightedAccuracy01 =>
      attempts == 0 ? null : (correct + partial / 2) / attempts;

  /// 没有任何样本。
  bool get isEmpty => attempts == 0;

  /// 至少有一样本。
  bool get isNotEmpty => attempts > 0;
}

/// 单个题型（T）的统计。
class QuestionTypeStats {
  QuestionTypeStats({
    required this.questionType,
    required this.counts,
    required Map<String, ResultCounts> byCapability,
  })  : labelZh = questionTypeLabelZh(questionType),
        byCapability = Map<String, ResultCounts>.unmodifiable(byCapability);

  /// 题型 key（已去首尾空白）。
  final String questionType;

  /// 题型中文标签；未知 key 原样返回（见 [questionTypeLabelZh]）。
  final String labelZh;

  /// 该题型的总体计数。
  final ResultCounts counts;

  /// T×A 的「A 维」：能力编号 → 计数，按 A 序号升序，只含出现过的能力。
  final Map<String, ResultCounts> byCapability;

  /// 题型严格正确率；无样本返回 null。
  double? get accuracy01 => counts.accuracy01;
}

/// 单个能力点（A）的统计。
class CapabilityPointStats {
  CapabilityPointStats({
    required this.capability,
    required this.counts,
    required Map<String, ResultCounts> byQuestionType,
    required this.sampleMinimum,
  }) : byQuestionType = Map<String, ResultCounts>.unmodifiable(byQuestionType);

  /// 能力。
  final QuestionCapability capability;

  /// 该能力的计数（分母是能力点出现次数）。
  final ResultCounts counts;

  /// 该能力在各题型上的计数（按题型 key 字典序），只含出现过的题型。
  final Map<String, ResultCounts> byQuestionType;

  /// 下结论所需的最小样本数（由报告统一给出）。
  final int sampleMinimum;

  /// 能力编号。
  String get code => capability.code;

  /// 能力中文名。
  String get labelZh => capability.labelZh;

  /// 一句话判定口径。
  String get definitionZh => capability.definitionZh;

  /// 严格正确率；无样本返回 null。
  double? get accuracy01 => counts.accuracy01;

  /// 加权正确率；无样本返回 null。
  double? get weightedAccuracy01 => counts.weightedAccuracy01;

  /// 样本是否够下结论。
  bool get hasEnoughSamples => counts.attempts >= sampleMinimum;
}

/// 能力统计报告（不可变）。
///
/// 由 [CapabilityStatsReport.of] 构造；手写构造也接受任意顺序，构造器会把
/// 列表与交叉表冻结成不可变视图（交叉表外壳按题型 key 升序、内层按 A 序）。
class CapabilityStatsReport {
  CapabilityStatsReport({
    required this.attemptCount,
    required this.distinctQuestionCount,
    required this.totalTimeSpentSeconds,
    required this.overall,
    required List<CapabilityPointStats> capabilities,
    required List<QuestionTypeStats> questionTypes,
    required this.unattributedAttemptCount,
    required this.minSamplesForConclusion,
    required Map<String, Map<String, ResultCounts>> crossTable,
  })  : capabilities = List<CapabilityPointStats>.unmodifiable(capabilities),
        questionTypes = List<QuestionTypeStats>.unmodifiable(questionTypes),
        crossTable = _frozenCrossTable(crossTable);

  /// 记录条数。
  final int attemptCount;

  /// 去重后的题目数（trim 后非空的 questionId 去重）。
  final int distinctQuestionCount;

  /// 用时合计（每条负时间已在 [CapabilityAttempt] 夹成 0）。
  final int totalTimeSpentSeconds;

  /// 全部记录的总体计数。
  final ResultCounts overall;

  /// 出现过的能力点，按 A 序号升序；空输入为空列表。
  final List<CapabilityPointStats> capabilities;

  /// 出现过的题型，按题型 key 字典序；空输入为空列表。
  final List<QuestionTypeStats> questionTypes;

  /// 没有合法能力 code 的记录数。
  final int unattributedAttemptCount;

  /// 下结论所需的最小样本数（< 1 的入参会被夹成 1）。
  final int minSamplesForConclusion;

  /// 题型 → 能力 → 计数（T×A 交叉表，只含有数据的格子）。
  final Map<String, Map<String, ResultCounts>> crossTable;

  /// 没有任何记录。
  bool get isEmpty => attemptCount == 0;

  /// 至少有一条记录。
  bool get isNotEmpty => attemptCount > 0;

  /// 总体严格正确率；无样本返回 null。
  double? get accuracy01 => overall.accuracy01;

  /// 取某能力点的统计；未知编号返回 null。
  CapabilityPointStats? pointFor(String capabilityCode) {
    final capability = QuestionCapability.fromCode(capabilityCode);
    if (capability == null) return null;
    for (final point in capabilities) {
      if (point.capability == capability) return point;
    }
    return null;
  }

  /// 「最弱能力点」排序，默认取 3 个（[kCapabilityWeakestLimit]）。
  ///
  /// 排序规则（确定性，测试锁定）：
  /// 1. 样本足够（attempts >= minSamplesForConclusion）的在前，样本不足的在后
  ///    ——样本不足不是「最强」，只是「还不能下结论」，仍列出并带 attempts / hasEnoughSamples；
  /// 2. 组内按严格正确率升序（越低越弱）；
  /// 3. 正确率相同按次数降序（样本多的更可信）；
  /// 4. 再相同按 A 序号升序（A1 先），保证同分不随机；
  /// 5. limit <= 0 返回空列表；limit 超过可用能力点返回全部。
  List<CapabilityPointStats> weakest({int limit = kCapabilityWeakestLimit}) {
    if (limit <= 0 || capabilities.isEmpty) {
      return const <CapabilityPointStats>[];
    }
    final ranked = List<CapabilityPointStats>.of(capabilities)
      ..sort(_compareWeakness);
    final take = limit < ranked.length ? limit : ranked.length;
    return List<CapabilityPointStats>.unmodifiable(ranked.take(take));
  }

  /// 从练习记录聚合报告；空输入返回空报告（不抛异常）。
  ///
  /// [minSamplesForConclusion] 小于 1 时按 1 计。
  static CapabilityStatsReport of(
    Iterable<CapabilityAttempt> attempts, {
    int minSamplesForConclusion = kCapabilityMinSamplesForConclusion,
  }) {
    final minimum = minSamplesForConclusion < 1 ? 1 : minSamplesForConclusion;
    final overall = _MutableCounts();
    var attemptCount = 0;
    var totalSeconds = 0;
    var unattributed = 0;
    final questionIds = <String>{};
    final capabilityCounts = <QuestionCapability, _MutableCounts>{};
    final capabilityTypes = <QuestionCapability, Map<String, _MutableCounts>>{};
    final typeCounts = <String, _MutableCounts>{};
    final typeCapabilities = <String, Map<String, _MutableCounts>>{};

    for (final attempt in attempts) {
      attemptCount += 1;
      totalSeconds += attempt.timeSpentSeconds;
      final questionId = attempt.questionId.trim();
      if (questionId.isNotEmpty) questionIds.add(questionId);
      final type = attempt.questionType;
      overall.add(attempt.result);
      typeCounts.putIfAbsent(type, _MutableCounts.new).add(attempt.result);
      final capabilities = attempt.capabilities;
      if (capabilities.isEmpty) {
        unattributed += 1;
      }
      for (final code in capabilities) {
        final capability = QuestionCapability.fromCode(code);
        if (capability == null) continue;
        capabilityCounts
            .putIfAbsent(capability, _MutableCounts.new)
            .add(attempt.result);
        capabilityTypes
            .putIfAbsent(capability, () => <String, _MutableCounts>{})
            .putIfAbsent(type, _MutableCounts.new)
            .add(attempt.result);
        typeCapabilities
            .putIfAbsent(type, () => <String, _MutableCounts>{})
            .putIfAbsent(code, _MutableCounts.new)
            .add(attempt.result);
      }
    }

    final points = <CapabilityPointStats>[];
    for (final capability in QuestionCapability.values) {
      final accumulator = capabilityCounts[capability];
      if (accumulator == null) continue;
      final byType =
          capabilityTypes[capability] ?? const <String, _MutableCounts>{};
      final sortedTypes = byType.keys.toList()..sort();
      points.add(
        CapabilityPointStats(
          capability: capability,
          counts: accumulator.toCounts(),
          byQuestionType: <String, ResultCounts>{
            for (final type in sortedTypes) type: byType[type]!.toCounts(),
          },
          sampleMinimum: minimum,
        ),
      );
    }

    final sortedTypeKeys = typeCounts.keys.toList()..sort();
    final typeStats = <QuestionTypeStats>[];
    for (final type in sortedTypeKeys) {
      final accumulator = typeCounts[type]!;
      final byCapability =
          typeCapabilities[type] ?? const <String, _MutableCounts>{};
      final sortedCodes = byCapability.keys.toList()
        ..sort(_compareCapabilityCode);
      typeStats.add(
        QuestionTypeStats(
          questionType: type,
          counts: accumulator.toCounts(),
          byCapability: <String, ResultCounts>{
            for (final code in sortedCodes)
              code: byCapability[code]!.toCounts(),
          },
        ),
      );
    }

    return CapabilityStatsReport(
      attemptCount: attemptCount,
      distinctQuestionCount: questionIds.length,
      totalTimeSpentSeconds: totalSeconds,
      overall: overall.toCounts(),
      capabilities: points,
      questionTypes: typeStats,
      unattributedAttemptCount: unattributed,
      minSamplesForConclusion: minimum,
      crossTable: <String, Map<String, ResultCounts>>{
        for (final stats in typeStats) stats.questionType: stats.byCapability,
      },
    );
  }
}

class _MutableCounts {
  int attempts = 0;
  int correct = 0;
  int incorrect = 0;
  int partial = 0;

  void add(QuestionResult result) {
    attempts += 1;
    if (result == QuestionResult.correct) {
      correct += 1;
    } else if (result == QuestionResult.incorrect) {
      incorrect += 1;
    } else {
      partial += 1;
    }
  }

  ResultCounts toCounts() => ResultCounts(
        attempts: attempts,
        correct: correct,
        incorrect: incorrect,
        partial: partial,
      );
}

int _compareWeakness(CapabilityPointStats a, CapabilityPointStats b) {
  if (a.hasEnoughSamples != b.hasEnoughSamples) {
    return a.hasEnoughSamples ? -1 : 1;
  }
  final byAccuracy = a.accuracy01!.compareTo(b.accuracy01!);
  if (byAccuracy != 0) return byAccuracy;
  final byAttempts = b.counts.attempts.compareTo(a.counts.attempts);
  if (byAttempts != 0) return byAttempts;
  return a.capability.index.compareTo(b.capability.index);
}

int _compareCapabilityCode(String a, String b) =>
    _capabilityIndex(a).compareTo(_capabilityIndex(b));

int _capabilityIndex(String code) {
  final capability = QuestionCapability.fromCode(code);
  return capability == null
      ? QuestionCapability.values.length
      : capability.index;
}

Map<String, Map<String, ResultCounts>> _frozenCrossTable(
  Map<String, Map<String, ResultCounts>> source,
) {
  final sortedTypes = source.keys.toList()..sort();
  final frozen = <String, Map<String, ResultCounts>>{};
  for (final type in sortedTypes) {
    final inner = source[type]!;
    final sortedCodes = inner.keys.toList()..sort(_compareCapabilityCode);
    frozen[type] = Map<String, ResultCounts>.unmodifiable(
      <String, ResultCounts>{
        for (final code in sortedCodes) code: inner[code]!,
      },
    );
  }
  return Map<String, Map<String, ResultCounts>>.unmodifiable(frozen);
}
