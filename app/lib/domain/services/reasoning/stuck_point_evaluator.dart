/// 沿思维链找「学生最可能卡在哪一步」（slice Q5）。
///
/// 数据来源有两份，性质不同，所以不能只信一份：
///
///  * **模型的判断**：`ParsedStep.stuckRisk`。它是模型读完题之后的先验，
///    跟这个学生是谁无关，问的是「一般学生最容易卡哪一步」。
///  * **学生的状态读数**：MindNet/DSR 在相关知识点上的记忆状态。它跟题目无关，
///    问的是「这个学生在这些知识点上现在记得怎么样」。
///
/// 这个评估器把两者等权融合（[modelWeight]），并**明确标注**每一步有没有拿到
/// 状态证据（[StepStuckPoint.hasStateEvidence]）。只有模型判断的那一步照样给出
/// 结果，但调用方/UI 不能把它显示成「根据你的状态算出来的」。
///
/// 本文件是纯逻辑：没有数据库、没有时钟、没有 Flutter。`nowHours`（自 Unix 纪元
/// 起的小时数）和状态对象都由调用方传入，与 `dsr_memory.dart` 的约定一致。
library;

import 'dart:math' as math;

import '../srs/dsr_memory.dart';
import 'reasoning_prompt.dart';

/// 一步的卡点评估结果。
class StepStuckPoint {
  const StepStuckPoint({
    required this.index,
    required this.goal,
    required this.actionType,
    required this.actionLabelZh,
    required this.modelRisk,
    required this.stateRisk,
    required this.fusedRisk,
    required this.matchedKnowledgePoints,
    required this.unmatchedHints,
    required this.suggestion,
  });

  /// 模型给的步号（从 1 开始，不强制连续）。
  final int index;

  final String goal;

  /// 模型回复里的原始动作串（未知动作也保留）。
  final String actionType;

  /// 动作词表里的中文名；未知动作时回落到 [actionType]。
  final String actionLabelZh;

  /// 模型声明的卡点风险，0..1。
  final double modelRisk;

  /// 由学生状态读数算出的风险，0..1；没有状态证据时为 `null`。
  final double? stateRisk;

  /// 融合后的风险，0..1。没有任何状态证据时等于 [modelRisk]。
  final double fusedRisk;

  /// 这一步命中的知识点（[ParsedStep.knowledgeHints] 里能在状态表里查到的）。
  final List<String> matchedKnowledgePoints;

  /// 这一步提到、但状态表里查不到的知识点提示（原样保留，便于之后补数据）。
  final List<String> unmatchedHints;

  /// 给用户的下一步动作建议。确定性生成，可直接断言。
  final String suggestion;

  /// 是否有学生状态证据参与融合。
  bool get hasStateEvidence => stateRisk != null;

  /// 是否落在「高卡点」区间。
  bool get isHighRisk => fusedRisk >= StuckPointEvaluator.highRiskThreshold;

  Map<String, Object?> toJson() => <String, Object?>{
        'index': index,
        'goal': goal,
        'actionType': actionType,
        'actionLabelZh': actionLabelZh,
        'modelRisk': modelRisk,
        'stateRisk': stateRisk,
        'fusedRisk': fusedRisk,
        'hasStateEvidence': hasStateEvidence,
        'matchedKnowledgePoints': matchedKnowledgePoints,
        'unmatchedHints': unmatchedHints,
        'suggestion': suggestion,
      };

  @override
  String toString() =>
      'StepStuckPoint($index, fused=$fusedRisk, evidence=$hasStateEvidence)';
}

/// 整条链的卡点报告。
class StuckPointReport {
  const StuckPointReport({required this.steps, required this.unmatchedHints});

  /// 按步号升序排列（与链的顺序一致）。
  final List<StepStuckPoint> steps;

  /// 全链范围内、状态表里查不到的知识点提示，按出现顺序去重。
  final List<String> unmatchedHints;

  bool get isEmpty => steps.isEmpty;

  /// 风险最高的一步；平手时取步号小的（更靠前的步骤先卡）。
  StepStuckPoint? get mostLikely {
    StepStuckPoint? best;
    for (final step in steps) {
      if (best == null ||
          step.fusedRisk > best.fusedRisk ||
          (step.fusedRisk == best.fusedRisk && step.index < best.index)) {
        best = step;
      }
    }
    return best;
  }

  /// 按融合风险降序、同分按步号升序的副本，给 UI 排「先补哪一步」。
  List<StepStuckPoint> get byRisk {
    final sorted = List<StepStuckPoint>.of(steps)
      ..sort((a, b) {
        final byRisk = b.fusedRisk.compareTo(a.fusedRisk);
        return byRisk != 0 ? byRisk : a.index.compareTo(b.index);
      });
    return List<StepStuckPoint>.unmodifiable(sorted);
  }

  /// 全链最高风险；空链为 0。
  double get overallRisk =>
      steps.isEmpty ? 0 : steps.map((s) => s.fusedRisk).reduce(math.max);

  /// 有状态证据的步数占总步数的比例，给 UI 交代「这份诊断有多少依据」。
  double get evidenceCoverage => steps.isEmpty
      ? 0
      : steps.where((s) => s.hasStateEvidence).length / steps.length;

  Map<String, Object?> toJson() => <String, Object?>{
        'overallRisk': overallRisk,
        'evidenceCoverage': evidenceCoverage,
        'mostLikelyIndex': mostLikely?.index,
        'steps': <Object?>[for (final step in steps) step.toJson()],
        'unmatchedHints': unmatchedHints,
      };

  @override
  String toString() =>
      'StuckPointReport(${steps.length} steps, overall=$overallRisk, '
      'evidence=$evidenceCoverage)';
}

/// 把模型先验与学生状态读数融合成「这一步学生会不会卡」。
abstract final class StuckPointEvaluator {
  /// 融合风险 >= 这个值就算高卡点：建议先停下补这一步。
  static const double highRiskThreshold = 0.6;

  /// 融合风险 >= 这个值算中等：建议做完后用自检确认。
  static const double mediumRiskThreshold = 0.35;

  /// 模型先验在融合里的权重；学生状态同权（1 - [modelWeight]）。
  ///
  /// 0.5 是刻意的：两份证据的性质不同、谁更准都还没有标定数据
  /// （`docs/CALIBRATION.md` 的协议还没跑过），偏向任何一边都是没有依据的调参。
  /// 标定跑完之前，这个常量是唯一正确的选择——包括它「看起来不够聪明」这一点。
  static const double modelWeight = 0.5;

  /// 状态风险里「已经忘了」占的权重，其余给「这个知识点本身难」。
  static const double retrievalWeight = 0.6;

  /// 状态风险里难度项的权重。
  static const double difficultyWeight = 0.4;

  /// 评估一条链。
  ///
  /// * [steps] 解析出来的步骤（[parseChain] 的产物）。
  /// * [statesByKnowledgePoint] 知识点 id → 记忆状态。**只认精确 key**（两侧
  ///   trim 后比较），查不到的知识点会进 [StuckPointReport.unmatchedHints]，
  ///   而不是被当成「记得很好」——把缺数据读成正面证据是最容易犯的错。
  /// * [nowHours] 自 Unix 纪元起的小时数，用于算当前可提取度。
  static StuckPointReport evaluate({
    required List<ParsedStep> steps,
    required Map<String, DsrState> statesByKnowledgePoint,
    required double nowHours,
    DsrParams params = const DsrParams(),
  }) {
    final lookup = <String, DsrState>{};
    for (final entry in statesByKnowledgePoint.entries) {
      final key = entry.key.trim();
      if (key.isNotEmpty) {
        lookup[key] = entry.value;
      }
    }

    final evaluated = <StepStuckPoint>[];
    final unmatched = <String>[];
    final unmatchedSeen = <String>{};

    for (final step in steps) {
      final matched = <String>[];
      final missing = <String>[];
      final risks = <double>[];

      for (final rawHint in step.knowledgeHints) {
        final hint = rawHint.trim();
        if (hint.isEmpty) {
          continue;
        }
        final state = lookup[hint];
        if (state == null) {
          missing.add(hint);
          if (unmatchedSeen.add(hint)) {
            unmatched.add(hint);
          }
          continue;
        }
        matched.add(hint);
        risks.add(stateRiskOf(state, nowHours: nowHours, params: params));
      }

      final double? stateRisk =
          risks.isEmpty ? null : risks.reduce((a, b) => a + b) / risks.length;
      final modelRisk = _clamp01(step.stuckRisk);
      final fusedRisk = stateRisk == null
          ? modelRisk
          : _clamp01(modelWeight * modelRisk + (1 - modelWeight) * stateRisk);

      final actionLabel = step.action?.labelZh ?? step.actionType;
      evaluated.add(StepStuckPoint(
        index: step.index,
        goal: step.goal,
        actionType: step.actionType,
        actionLabelZh: actionLabel,
        modelRisk: modelRisk,
        stateRisk: stateRisk,
        fusedRisk: fusedRisk,
        matchedKnowledgePoints: List<String>.unmodifiable(matched),
        unmatchedHints: List<String>.unmodifiable(missing),
        suggestion: suggestFor(
          risk: fusedRisk,
          actionLabelZh: actionLabel,
          hasStateEvidence: stateRisk != null,
        ),
      ));
    }

    evaluated.sort((a, b) => a.index.compareTo(b.index));
    return StuckPointReport(
      steps: List<StepStuckPoint>.unmodifiable(evaluated),
      unmatchedHints: List<String>.unmodifiable(unmatched),
    );
  }

  /// 单个知识点状态的风险读数，0..1。
  ///
  /// `1 - R` 是「现在想不起来的程度」，`D`（1..10）是知识点自身的难度；两样都在，
  /// 是因为「难」和「忘了」在干预手段上完全不同：难要多花时间讲，忘要及时复习。
  static double stateRiskOf(
    DsrState state, {
    required double nowHours,
    DsrParams params = const DsrParams(),
  }) {
    final r = _clamp01(DsrMemory.retrievability(state, nowHours, params).r);
    final difficulty01 = _clamp01((state.d - 1) / 9);
    return _clamp01(
      retrievalWeight * (1 - r) + difficultyWeight * difficulty01,
    );
  }

  /// 生成下一步建议。
  ///
  /// 措辞里**明说**依据来自状态读数还是仅来自模型判断——两者对用户的含义不同，
  /// 不该混成一句话。所以「没有状态数据」这个提醒会附加在**每一档**建议后面，
  /// 而不只是高风险那一档：低风险同样可能是「只是这个学生没数据」。
  static String suggestFor({
    required double risk,
    required String actionLabelZh,
    required bool hasStateEvidence,
  }) {
    final String base;
    if (risk >= highRiskThreshold) {
      base = hasStateEvidence
          ? '先停下补这一步：$actionLabelZh（你的状态读数显示这里已经明显遗忘）'
          : '先停下补这一步：$actionLabelZh（模型判断的高风险）';
    } else if (risk >= mediumRiskThreshold) {
      base = '做完这一步用自检确认：$actionLabelZh';
    } else {
      base = '这一步可以快过：$actionLabelZh';
    }
    return hasStateEvidence ? base : '$base（暂无你的状态数据）';
  }

  static double _clamp01(double value) {
    if (value.isNaN) {
      return 0;
    }
    return value < 0 ? 0 : (value > 1 ? 1 : value);
  }
}
