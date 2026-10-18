/// 思维链质量体检：给一条已落库的思维链做确定性的可信度检查。
///
/// 推理层把模型/学生的拆题结果落成「链 + 步骤」后，数据本身可能不可信：
/// 链是空的、步骤序号重复、动作 key 是词表不认识的、卡点读数是 NaN、
/// 高危步没写卡住的原因……这些坏数据如果直接进洞察 / 画像 / 学习建议，
/// 会让「下一步练什么」指向错误的方向。本文件只做一件事：把每条链的
/// 可疑点翻成一组有稳定 code 与中文说明的 findings，供详情页 / 洞察页
/// 展示，或供上层决定「这条链要不要重做」。
///
/// 三个不变量（都有测试守着）：
/// * 确定性：同输入同输出，不依赖输入顺序与 Map 迭代顺序；两次调用的
///   ChainQualityReport.toJson 逐字节相等。链按 (questionId, chainId)
///   排序后体检，findings 按 questionId → chainId → stepIndex（null 在最后）
///   → severity → code → messageZh → evidence 排序。
/// * 不抛异常：空串 / 负数 / NaN / ±inf 等坏输入都变成显式 finding，
///   不静默吞掉、也不让调用方崩。
/// * 不编造：判据只使用输入里真实存在的字段；没有卡点读数就说「没有
///   读数」，不猜「这一步大概率高危」。中文文案里不出现「可能 / 大概」。
///
/// 判据清单见 ChainQualityCodes；严重级见 ChainQualitySeverity。
/// 纯 Dart：不 import Flutter / 数据库 / 网络，无 IO，输出列表与 Map 全部
/// 不可变。
library;

import 'capability_action.dart';
import 'capability_action_overlay.dart';

/// 一条 finding 的严重级。
enum ChainQualitySeverity {
  /// 数据坏了或结构不成立：这条链的读数不能直接用。
  error('错误'),

  /// 数据缺失或口径可疑：读数能用，但要打折扣。
  warning('警告'),

  /// 提示性信息：不影响读数，只说明还能补哪些字段。
  info('提示');

  const ChainQualitySeverity(this.labelZh);

  /// 中文展示名（界面 / 导出用）。
  final String labelZh;
}

/// 体检判据的稳定 code 集合。
///
/// code 会写进快照、测试与未来的界面：新增判据只能追加新 code，
/// 已有 code 不改名、不复用。每条判据的严重级见其文档注释，最终以
/// audit 产出的 ChainQualityFinding.severity 为准。
abstract final class ChainQualityCodes {
  /// 链里没有任何步骤（error）。空链无法判断任何东西。
  static const String emptyChain = 'empty_chain';

  /// 步骤数少于最少步数（warning）：拆题信息不全。
  static const String tooFewSteps = 'too_few_steps';

  /// 链的 chainId 去空白后为空（error）：链没有稳定标识，快照无法引用。
  static const String emptyChainId = 'empty_chain_id';

  /// 链的 questionId 去空白后为空（warning）：体检结果无法归到具体题目。
  static const String emptyQuestionId = 'empty_question_id';

  /// 步骤的 actionType 去空白后为空（error）。
  static const String emptyActionType = 'empty_action_type';

  /// 未知动作（按当前词表判定）占全部步骤的比例过高（warning）。
  static const String unknownActionRatioHigh = 'unknown_action_ratio_high';

  /// 链里没有任何一步使用已知动作（warning）：无法归入能力画像。
  static const String noKnownAction = 'no_known_action';

  /// 高危步骤没有写卡住的原因 justification（warning）。
  static const String highRiskMissingJustification =
      'high_risk_missing_justification';

  /// 高危步骤没有写怎么验证 / 自查 checkMethod（warning）。
  static const String highRiskMissingCheckMethod =
      'high_risk_missing_check_method';

  /// 整条链没有任何有限的卡点读数 stuckRisk（warning）。
  ///
  /// 设计说明：任务建议里的「高危步骤无卡点读数」在逻辑上自相矛盾——没有
  /// 读数就无法判定「高危」。所以这里落成链级判据：一条链一步读数都
  /// 没有时，任何「哪一步高危」的结论都不可信。
  static const String noRiskReading = 'no_risk_reading';

  /// 同一链内步骤序号重复（error）：步骤顺序不可靠。
  static const String duplicateStepIndex = 'duplicate_step_index';

  /// 步骤序号为负数（error）。
  static const String invalidStepIndex = 'invalid_step_index';

  /// 步骤序号不连续（warning）：中间缺号，链可能被截断过。
  static const String nonContiguousStepIndex = 'non_contiguous_step_index';

  /// 所有步骤都是同一个动作（info）：拆题维度单一。
  static const String singleAction = 'single_action';

  /// 相邻两步动作相同（info）：相邻重复，该合并的步骤被拆成了两步。
  static const String consecutiveDuplicateAction =
      'consecutive_duplicate_action';

  /// 步骤没有知识点提示 knowledgeHints（info）：卡点无法定位到知识点。
  static const String missingKnowledgeHints = 'missing_knowledge_hints';

  /// 卡点读数不是有限数（NaN / ±inf）（error）：数据已损坏。
  static const String invalidRiskReading = 'invalid_risk_reading';

  /// 卡点读数有限但越界（不在 0..1）（warning）：夹到边界后参与判定。
  static const String riskOutOfRange = 'risk_out_of_range';

  /// 步骤的 knownAction 快照与当前词表的判断不一致（info）。
  static const String staleKnownActionFlag = 'stale_known_action_flag';

  /// 全部稳定 code，按本文件里的定义顺序排列（测试与文档共用）。
  static const List<String> all = <String>[
    emptyChain,
    tooFewSteps,
    emptyChainId,
    emptyQuestionId,
    emptyActionType,
    unknownActionRatioHigh,
    noKnownAction,
    highRiskMissingJustification,
    highRiskMissingCheckMethod,
    noRiskReading,
    duplicateStepIndex,
    invalidStepIndex,
    nonContiguousStepIndex,
    singleAction,
    consecutiveDuplicateAction,
    missingKnowledgeHints,
    invalidRiskReading,
    riskOutOfRange,
    staleKnownActionFlag,
  ];
}

/// 体检输入里的一步（轻量行模型，由调用方从 ReasoningSteps / ParsedStep
/// 投影）。
class ChainQualityStepInput {
  /// 构造一步；actionType 与 index 必填，其余字段可选。
  const ChainQualityStepInput({
    required this.actionType,
    required this.index,
    this.stuckRisk,
    this.knownAction,
    this.justification,
    this.checkMethod,
    this.knowledgeHints = const <String>[],
  });

  /// 能力动作 key（数据库里的原串；空串是坏数据）。
  final String actionType;

  /// 步骤序号（数据库口径；负数 / 重复 / 缺号都是坏数据）。
  final int index;

  /// 卡点风险读数；null 表示没有读数，NaN / ±inf 表示读数损坏。
  final double? stuckRisk;

  /// 入库时已知动作的快照；null 表示没有快照。
  ///
  /// 体检用当前词表重新判定 known，这个字段只用于发现快照过期
  /// （ChainQualityCodes.staleKnownActionFlag）。
  final bool? knownAction;

  /// 卡住的原因；高危步为空会触发 finding。
  final String? justification;

  /// 怎么验证 / 自查；高危步为空会触发 finding。
  final String? checkMethod;

  /// 知识点提示（可空列表）；全部为空会触发 finding。
  final List<String> knowledgeHints;
}

/// 体检输入里的一条链。
class ChainQualityChainInput {
  /// 构造一条链；steps 缺省为空（会触发空链 finding）。
  const ChainQualityChainInput({
    required this.chainId,
    required this.questionId,
    this.steps = const <ChainQualityStepInput>[],
  });

  /// 链的稳定标识。
  final String chainId;

  /// 所属题目 id。
  final String questionId;

  /// 链里的步骤，按落库顺序给出。
  final List<ChainQualityStepInput> steps;
}

/// 一条体检结论。
class ChainQualityFinding {
  /// 构造一条 finding；evidence 会复制成不可变 Map。
  ChainQualityFinding({
    required this.code,
    required this.severity,
    required this.messageZh,
    required this.questionId,
    required this.chainId,
    this.stepIndex,
    Map<String, String> evidence = const <String, String>{},
  }) : evidence = Map<String, String>.unmodifiable(evidence);

  /// 稳定判据 code，取值来自 ChainQualityCodes。
  final String code;

  /// 严重级。
  final ChainQualitySeverity severity;

  /// 中文说明（具体到数字 / 动作 key，不写模糊话）。
  final String messageZh;

  /// 所属题目 id（已去首尾空白；可能为空）。
  final String questionId;

  /// 所属链 id（已去首尾空白；可能为空）。
  final String chainId;

  /// 命中步骤的序号；链级 finding 为 null。
  final int? stepIndex;

  /// 可复算的证据键值对（值全部是字符串）。
  final Map<String, String> evidence;

  /// 序列化为 snake_case 的 JSON 对象；evidence 键按字典序输出。
  Map<String, Object?> toJson() => <String, Object?>{
        'code': code,
        'severity': severity.name,
        'severity_label_zh': severity.labelZh,
        'message_zh': messageZh,
        'question_id': questionId,
        'chain_id': chainId,
        'step_index': stepIndex,
        'evidence': _sortedStringMap(evidence),
      };

  static Map<String, String> _sortedStringMap(Map<String, String> input) {
    final keys = input.keys.toList()..sort();
    return <String, String>{for (final key in keys) key: input[key]!};
  }
}

/// 一次体检的完整结果。
///
/// 不可变、纯数据：findings 已按确定性顺序排序；countsByCode /
/// countsBySeverity 统计截断前的全部结论（用户需要知道真实数量），
/// findings 只保留每个 code 的前 maxFindingsPerCode 条，
/// 被丢掉的条数记在 truncatedCounts。
class ChainQualityReport {
  ChainQualityReport._({
    required this.chainCount,
    required this.stepCount,
    required List<ChainQualityFinding> findings,
    required Map<ChainQualitySeverity, int> countsBySeverity,
    required Map<String, int> countsByCode,
    required Map<String, int> truncatedCounts,
    required this.maxFindingsPerCode,
  })  : findings = List<ChainQualityFinding>.unmodifiable(findings),
        countsBySeverity =
            Map<ChainQualitySeverity, int>.unmodifiable(countsBySeverity),
        countsByCode = Map<String, int>.unmodifiable(countsByCode),
        truncatedCounts = Map<String, int>.unmodifiable(truncatedCounts);

  /// 没有输入时的空报告（链 0、步 0、没有任何 finding）。
  factory ChainQualityReport.empty() {
    return ChainQualityReport._(
      chainCount: 0,
      stepCount: 0,
      findings: const <ChainQualityFinding>[],
      countsBySeverity: <ChainQualitySeverity, int>{
        for (final severity in ChainQualitySeverity.values) severity: 0,
      },
      countsByCode: const <String, int>{},
      truncatedCounts: const <String, int>{},
      maxFindingsPerCode: ChainQualityAudit.defaultMaxFindingsPerCode,
    );
  }

  /// 体检的链数（含坏链）。
  final int chainCount;

  /// 体检的步骤总数（含坏步骤）。
  final int stepCount;

  /// 截断后保留的 findings，已按确定性顺序排序。
  final List<ChainQualityFinding> findings;

  /// 截断前各严重级的条数；三个键永远都在（没有就是 0）。
  final Map<ChainQualitySeverity, int> countsBySeverity;

  /// 截断前各 code 的条数。
  final Map<String, int> countsByCode;

  /// 因 maxFindingsPerCode 被丢掉的数量（code → 条数）；空表示没截断。
  final Map<String, int> truncatedCounts;

  /// 本次体检使用的每 code 上限。
  final int maxFindingsPerCode;

  /// 没有任何 finding（链本身干净）。
  bool get isClean => findings.isEmpty;

  /// 是否发生了截断。
  bool get isTruncated => truncatedCounts.isNotEmpty;

  /// 截断前的结论总数。
  int get totalFindingCount {
    var total = 0;
    for (final count in countsByCode.values) {
      total += count;
    }
    return total;
  }

  /// 取某个判据 code 的 findings（保持报告里的顺序），返回不可变列表。
  List<ChainQualityFinding> findingsFor(String code) {
    return List<ChainQualityFinding>.unmodifiable(
      <ChainQualityFinding>[
        for (final finding in findings)
          if (finding.code == code) finding,
      ],
    );
  }

  /// 序列化为 snake_case 的 JSON 对象。
  Map<String, Object?> toJson() => <String, Object?>{
        'chain_count': chainCount,
        'step_count': stepCount,
        'finding_count': findings.length,
        'total_finding_count': totalFindingCount,
        'is_clean': isClean,
        'is_truncated': isTruncated,
        'max_findings_per_code': maxFindingsPerCode,
        'counts_by_severity': <String, Object?>{
          for (final severity in ChainQualitySeverity.values)
            severity.name: countsBySeverity[severity] ?? 0,
        },
        'counts_by_code': _sortedCounts(countsByCode),
        'truncated_counts': _sortedCounts(truncatedCounts),
        'findings': <Object?>[
          for (final finding in findings) finding.toJson(),
        ],
      };

  static Map<String, Object?> _sortedCounts(Map<String, int> input) {
    final keys = input.keys.toList()..sort();
    return <String, Object?>{for (final key in keys) key: input[key]};
  }
}

/// 推理链质量体检的入口。
///
/// 纯静态、无状态：audit 是唯一的公开入口，可重复调用。
abstract final class ChainQualityAudit {
  /// 默认最少步数。
  static const int defaultMinSteps = 3;

  /// 默认高危阈值（与洞察层一致）。
  static const double defaultHighRiskThreshold = 0.6;

  /// 默认每个 code 最多保留多少条 findings。
  static const int defaultMaxFindingsPerCode = 50;

  /// 未知动作占比判据的阈值：严格大于它才命中（0.5 表示「超过一半」）。
  static const double unknownActionRatioThreshold = 0.5;

  /// 体检一批链，返回确定性报告。
  ///
  /// catalog：当前词表（内置 + 用户 overlay）。null 时退回内置词表
  /// 判定已知动作；调用方应尽量传当前词表，否则自定义动作会被判成未知。
  /// minSteps：少于该步数的非空链给 tooFewSteps；小于 1 按 1 处理。
  /// highRiskThreshold：stuckRisk 大于等于该阈值视为高危；非有限值退回
  /// defaultHighRiskThreshold，否则夹到 0..1。越界的有限读数先夹到 0..1
  /// 再参与高危判定。
  /// maxFindingsPerCode：每个 code 最多保留几条 findings（按排序后的
  /// 前 N 条），小于 1 按 1 处理；被丢掉的条数记进报告。
  static ChainQualityReport audit(
    List<ChainQualityChainInput> chains, {
    CapabilityActionCatalog? catalog,
    int minSteps = defaultMinSteps,
    double highRiskThreshold = defaultHighRiskThreshold,
    int maxFindingsPerCode = defaultMaxFindingsPerCode,
  }) {
    final safeMinSteps = minSteps < 1 ? 1 : minSteps;
    final safeThreshold = _sanitizeThreshold(highRiskThreshold);
    final safeMaxPerCode = maxFindingsPerCode < 1 ? 1 : maxFindingsPerCode;

    final entries = <_ChainEntry>[
      for (var i = 0; i < chains.length; i++)
        _ChainEntry(
          chain: chains[i],
          questionId: chains[i].questionId.trim(),
          chainId: chains[i].chainId.trim(),
          order: i,
        ),
    ]..sort(_compareChains);

    final findings = <ChainQualityFinding>[];
    var stepCount = 0;
    for (final entry in entries) {
      stepCount += entry.chain.steps.length;
      if (entry.questionId.isEmpty) {
        findings.add(
          ChainQualityFinding(
            code: ChainQualityCodes.emptyQuestionId,
            severity: ChainQualitySeverity.warning,
            messageZh: '这条链没有题目标识（questionId），体检结果无法归到具体题目。',
            questionId: entry.questionId,
            chainId: entry.chainId,
          ),
        );
      }
      if (entry.chainId.isEmpty) {
        findings.add(
          ChainQualityFinding(
            code: ChainQualityCodes.emptyChainId,
            severity: ChainQualitySeverity.error,
            messageZh: '这条链没有链标识（chainId），快照无法引用它。',
            questionId: entry.questionId,
            chainId: entry.chainId,
          ),
        );
      }
      _auditChain(
        chain: entry.chain,
        questionId: entry.questionId,
        chainId: entry.chainId,
        catalog: catalog,
        minSteps: safeMinSteps,
        highRiskThreshold: safeThreshold,
        add: findings.add,
      );
    }

    findings.sort(_compareFindings);

    final countsByCode = <String, int>{};
    final countsBySeverity = <ChainQualitySeverity, int>{
      for (final severity in ChainQualitySeverity.values) severity: 0,
    };
    for (final finding in findings) {
      countsByCode[finding.code] = (countsByCode[finding.code] ?? 0) + 1;
      countsBySeverity[finding.severity] =
          (countsBySeverity[finding.severity] ?? 0) + 1;
    }

    final kept = <ChainQualityFinding>[];
    final truncatedCounts = <String, int>{};
    final keptPerCode = <String, int>{};
    for (final finding in findings) {
      final keptCount = keptPerCode[finding.code] ?? 0;
      if (keptCount >= safeMaxPerCode) {
        truncatedCounts[finding.code] =
            (truncatedCounts[finding.code] ?? 0) + 1;
        continue;
      }
      keptPerCode[finding.code] = keptCount + 1;
      kept.add(finding);
    }

    return ChainQualityReport._(
      chainCount: chains.length,
      stepCount: stepCount,
      findings: kept,
      countsBySeverity: countsBySeverity,
      countsByCode: countsByCode,
      truncatedCounts: truncatedCounts,
      maxFindingsPerCode: safeMaxPerCode,
    );
  }

  static void _auditChain({
    required ChainQualityChainInput chain,
    required String questionId,
    required String chainId,
    required CapabilityActionCatalog? catalog,
    required int minSteps,
    required double highRiskThreshold,
    required void Function(ChainQualityFinding) add,
  }) {
    final steps = chain.steps;
    if (steps.isEmpty) {
      add(
        ChainQualityFinding(
          code: ChainQualityCodes.emptyChain,
          severity: ChainQualitySeverity.error,
          messageZh: '这条链没有任何步骤，无法判断可信度。',
          questionId: questionId,
          chainId: chainId,
        ),
      );
      return;
    }

    void addFinding(
      String code,
      ChainQualitySeverity severity,
      String messageZh, {
      int? stepIndex,
      Map<String, String> evidence = const <String, String>{},
    }) {
      add(
        ChainQualityFinding(
          code: code,
          severity: severity,
          messageZh: messageZh,
          questionId: questionId,
          chainId: chainId,
          stepIndex: stepIndex,
          evidence: evidence,
        ),
      );
    }

    if (steps.length < minSteps) {
      final stepCountText = steps.length.toString();
      final minStepsText = minSteps.toString();
      addFinding(
        ChainQualityCodes.tooFewSteps,
        ChainQualitySeverity.warning,
        '这条链只有 $stepCountText 步，少于最少 $minStepsText 步，拆题信息不全。',
        evidence: <String, String>{
          'step_count': stepCountText,
          'min_steps': minStepsText,
        },
      );
    }

    var knownCount = 0;
    var unknownCount = 0;
    var finiteReadingCount = 0;
    var allSameAction = true;
    String? firstAction;
    String previousAction = '';
    int? previousIndex;
    final seenIndexes = <int, int>{};
    final validIndexes = <int>[];

    for (var position = 0; position < steps.length; position++) {
      final step = steps[position];
      final stepIndex = step.index;
      final actionType = step.actionType.trim();
      final known = _isKnownAction(actionType, catalog);
      if (known) {
        knownCount++;
      } else {
        unknownCount++;
      }

      if (actionType.isEmpty) {
        addFinding(
          ChainQualityCodes.emptyActionType,
          ChainQualitySeverity.error,
          '第 $stepIndex 步的动作 key 为空，无法归入任何能力动作。',
          stepIndex: stepIndex,
        );
      }

      final snapshot = step.knownAction;
      if (actionType.isNotEmpty && snapshot != null && snapshot != known) {
        addFinding(
          ChainQualityCodes.staleKnownActionFlag,
          ChainQualitySeverity.info,
          '第 $stepIndex 步的 knownAction 快照是 $snapshot，当前词表判断是 $known，快照已过期。',
          stepIndex: stepIndex,
          evidence: <String, String>{
            'action_type': actionType,
            'snapshot_known': snapshot.toString(),
            'current_known': known.toString(),
          },
        );
      }

      final reading = step.stuckRisk;
      double? finiteRisk;
      if (reading != null) {
        if (reading.isNaN || reading.isInfinite) {
          addFinding(
            ChainQualityCodes.invalidRiskReading,
            ChainQualitySeverity.error,
            '第 $stepIndex 步的卡点读数不是有限数（NaN / ±inf），数据已损坏。',
            stepIndex: stepIndex,
            evidence: <String, String>{'stuck_risk': reading.toString()},
          );
        } else {
          finiteReadingCount++;
          if (reading < 0 || reading > 1) {
            addFinding(
              ChainQualityCodes.riskOutOfRange,
              ChainQualitySeverity.warning,
              '第 $stepIndex 步的卡点读数是 $reading，超出 0..1，按边界夹取后使用。',
              stepIndex: stepIndex,
              evidence: <String, String>{'stuck_risk': reading.toString()},
            );
          }
          var clamped = reading;
          if (clamped < 0) {
            clamped = 0;
          }
          if (clamped > 1) {
            clamped = 1;
          }
          finiteRisk = clamped;
        }
      }

      final isHighRisk = finiteRisk != null && finiteRisk >= highRiskThreshold;
      if (isHighRisk) {
        final riskText = finiteRisk.toString();
        if ((step.justification ?? '').trim().isEmpty) {
          addFinding(
            ChainQualityCodes.highRiskMissingJustification,
            ChainQualitySeverity.warning,
            '第 $stepIndex 步卡点风险 $riskText，但没有写卡住的原因（justification）。',
            stepIndex: stepIndex,
            evidence: <String, String>{
              'action_type': actionType,
              'stuck_risk': riskText,
            },
          );
        }
        if ((step.checkMethod ?? '').trim().isEmpty) {
          addFinding(
            ChainQualityCodes.highRiskMissingCheckMethod,
            ChainQualitySeverity.warning,
            '第 $stepIndex 步卡点风险 $riskText，但没有写怎么验证（checkMethod）。',
            stepIndex: stepIndex,
            evidence: <String, String>{
              'action_type': actionType,
              'stuck_risk': riskText,
            },
          );
        }
      }

      final hasHint = step.knowledgeHints.any((hint) => hint.trim().isNotEmpty);
      if (!hasHint) {
        addFinding(
          ChainQualityCodes.missingKnowledgeHints,
          ChainQualitySeverity.info,
          '第 $stepIndex 步没有知识点提示（knowledgeHints），卡点无法定位到知识点。',
          stepIndex: stepIndex,
        );
      }

      if (stepIndex < 0) {
        addFinding(
          ChainQualityCodes.invalidStepIndex,
          ChainQualitySeverity.error,
          '第 $position 个步骤的序号是 $stepIndex（负数），步骤顺序不可靠。',
          stepIndex: stepIndex,
        );
      } else {
        validIndexes.add(stepIndex);
      }

      final occurrence = seenIndexes[stepIndex];
      if (occurrence == null) {
        seenIndexes[stepIndex] = 1;
      } else {
        final next = occurrence + 1;
        seenIndexes[stepIndex] = next;
        addFinding(
          ChainQualityCodes.duplicateStepIndex,
          ChainQualitySeverity.error,
          '第 $position 个步骤的序号 $stepIndex 与前面的步骤重复（第 $next 次出现），步骤顺序不可靠。',
          stepIndex: stepIndex,
          evidence: <String, String>{
            'occurrence': next.toString(),
            'position': position.toString(),
          },
        );
      }

      if (actionType.isEmpty) {
        allSameAction = false;
      } else {
        firstAction ??= actionType;
        if (actionType != firstAction) {
          allSameAction = false;
        }
      }

      if (position > 0 &&
          actionType.isNotEmpty &&
          actionType == previousAction) {
        final previousIndexText = previousIndex?.toString() ?? '';
        addFinding(
          ChainQualityCodes.consecutiveDuplicateAction,
          ChainQualitySeverity.info,
          '第 $stepIndex 步与上一步动作相同（$actionType），相邻重复。',
          stepIndex: stepIndex,
          evidence: <String, String>{
            'action_type': actionType,
            'previous_index': previousIndexText,
          },
        );
      }
      previousAction = actionType;
      previousIndex = stepIndex;
    }

    if (steps.length >= 2 && allSameAction && firstAction != null) {
      final stepCountText = steps.length.toString();
      addFinding(
        ChainQualityCodes.singleAction,
        ChainQualitySeverity.info,
        '全部 $stepCountText 步都是同一个动作（$firstAction），拆题维度单一。',
        evidence: <String, String>{
          'action_type': firstAction,
          'step_count': stepCountText,
        },
      );
    }

    if (knownCount == 0) {
      addFinding(
        ChainQualityCodes.noKnownAction,
        ChainQualitySeverity.warning,
        '这条链没有一步使用已知动作，无法归入能力画像。',
        evidence: <String, String>{
          'step_count': steps.length.toString(),
        },
      );
    }

    if (unknownCount > 0 &&
        unknownCount / steps.length > unknownActionRatioThreshold) {
      final ratioText = (unknownCount / steps.length).toStringAsFixed(2);
      addFinding(
        ChainQualityCodes.unknownActionRatioHigh,
        ChainQualitySeverity.warning,
        '未知动作占 $unknownCount / $steps.length 步（比例 $ratioText），词表不认识它们，画像不可信。',
        evidence: <String, String>{
          'unknown_step_count': unknownCount.toString(),
          'step_count': steps.length.toString(),
          'ratio': ratioText,
        },
      );
    }

    if (finiteReadingCount == 0) {
      addFinding(
        ChainQualityCodes.noRiskReading,
        ChainQualitySeverity.warning,
        '这条链没有任何有限的卡点读数（stuckRisk），无法判断哪一步高危。',
        evidence: <String, String>{
          'step_count': steps.length.toString(),
        },
      );
    }

    final uniqueIndexes = validIndexes.toSet().toList()..sort();
    for (var i = 1; i < uniqueIndexes.length; i++) {
      final expected = uniqueIndexes[i - 1] + 1;
      final currentIndex = uniqueIndexes[i];
      if (currentIndex != expected) {
        addFinding(
          ChainQualityCodes.nonContiguousStepIndex,
          ChainQualitySeverity.warning,
          '步骤序号不连续：$expected 缺失，下一步是 $currentIndex。',
          evidence: <String, String>{
            'previous_index': uniqueIndexes[i - 1].toString(),
            'current_index': currentIndex.toString(),
            'missing_index': expected.toString(),
          },
        );
        break;
      }
    }
  }

  static bool _isKnownAction(
    String actionType,
    CapabilityActionCatalog? catalog,
  ) {
    final trimmed = actionType.trim();
    if (trimmed.isEmpty) {
      return false;
    }
    if (catalog != null) {
      return catalog.isKnownKey(trimmed);
    }
    return CapabilityAction.isKnownKey(trimmed);
  }

  static double _sanitizeThreshold(double value) {
    if (value.isNaN || value.isInfinite) {
      return defaultHighRiskThreshold;
    }
    if (value < 0) {
      return 0;
    }
    if (value > 1) {
      return 1;
    }
    return value;
  }

  static int _compareChains(_ChainEntry a, _ChainEntry b) {
    var result = a.questionId.compareTo(b.questionId);
    if (result != 0) {
      return result;
    }
    result = a.chainId.compareTo(b.chainId);
    if (result != 0) {
      return result;
    }
    return a.order.compareTo(b.order);
  }

  static int _compareFindings(
    ChainQualityFinding a,
    ChainQualityFinding b,
  ) {
    var result = a.questionId.compareTo(b.questionId);
    if (result != 0) {
      return result;
    }
    result = a.chainId.compareTo(b.chainId);
    if (result != 0) {
      return result;
    }
    final aIndex = a.stepIndex;
    final bIndex = b.stepIndex;
    if (aIndex == null && bIndex != null) {
      return 1;
    }
    if (aIndex != null && bIndex == null) {
      return -1;
    }
    if (aIndex != null && bIndex != null) {
      result = aIndex.compareTo(bIndex);
      if (result != 0) {
        return result;
      }
    }
    result = a.severity.index.compareTo(b.severity.index);
    if (result != 0) {
      return result;
    }
    result = a.code.compareTo(b.code);
    if (result != 0) {
      return result;
    }
    result = a.messageZh.compareTo(b.messageZh);
    if (result != 0) {
      return result;
    }
    return _evidenceKey(a.evidence).compareTo(_evidenceKey(b.evidence));
  }

  static String _evidenceKey(Map<String, String> evidence) {
    final keys = evidence.keys.toList()..sort();
    final parts = <String>[];
    for (final key in keys) {
      final value = evidence[key];
      parts.add('$key=$value');
    }
    return parts.join('|');
  }
}

class _ChainEntry {
  const _ChainEntry({
    required this.chain,
    required this.questionId,
    required this.chainId,
    required this.order,
  });

  final ChainQualityChainInput chain;
  final String questionId;
  final String chainId;
  final int order;
}
