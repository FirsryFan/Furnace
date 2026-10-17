/// 能力动作画像：把已入库的解题链按「跨学科动作」聚合，回答一个问题 ——
/// **我卡住的时候，卡住的是哪一个动作？**
///
/// 为什么值得单独一层（而不是散在题目详情页里）：一条链上的一步只说明"这道题这一步
/// 有风险"，同一类动作在多道题上反复高风险，才说明"这块肌肉没练出来"。而能力动作
/// 本来就是跨学科的公共词汇（见 `capability_action.dart` 的三条设计约束），所以按
/// 动作聚合出来的画像可以直接指导下一份卷子该练什么。
///
/// 诚实性规则（与推理层其它读数同一条口径）：
/// 1. **只聚合真有的读数**：`stuckRisk` 为 null 的步骤只算条数，**不进平均**——
///    把"模型没给判断"当成 0 会把风险摊薄。
/// 2. **未知动作不吞**：词表里没有的 `actionType` 照原样显示（`known == false`），
///    不硬塞进某个已知动作里；词表是会长的，静默归类会掩盖契约漂移。
/// 3. **没有样本就说没有**：空输入返回空列表，不编一行"暂无异常"。
library;

import 'capability_action.dart';

/// 聚合输入：一条步骤的最小信息。
class CapabilityStepSample {
  const CapabilityStepSample({required this.actionType, this.stuckRisk});

  /// 步骤写的能力动作 key（原串；可能不在词表里）。
  final String actionType;

  /// AI 判定的卡点风险（0–1）；null = 没给判断。
  final double? stuckRisk;
}

/// 一个能力动作的聚合读数。
class CapabilityReading {
  const CapabilityReading({
    required this.actionType,
    required this.label,
    required this.known,
    required this.stepCount,
    required this.riskyStepCount,
    required this.avgStuckRisk,
  });

  /// 原串 key（未知动作时就是它本身）。
  final String actionType;

  /// 展示名：词表里有的用它，没有的用原串。
  final String label;

  /// 这个词表认不认识这个 key。
  final bool known;

  /// 这个动作出现的步骤数（含没有风险读数的那些）。
  final int stepCount;

  /// 其中被判为"高风险"的步骤数（`stuckRisk >= [CapabilityProfile.riskyThreshold]`）。
  final int riskyStepCount;

  /// 有读数的步骤的平均卡点风险；一条读数都没有时是 null。
  final double? avgStuckRisk;

  Map<String, Object?> toJson() => <String, Object?>{
        'action_type': actionType,
        'label': label,
        'known': known,
        'step_count': stepCount,
        'risky_step_count': riskyStepCount,
        'avg_stuck_risk': avgStuckRisk,
      };
}

/// 纯聚合逻辑：样本 → 按"最该练"排序的读数列表。
abstract final class CapabilityProfile {
  /// 判"高风险"的门槛。与详情页把 `stuckRisk` 画成红条的口径一致。
  static const double riskyThreshold = 0.6;

  /// 至少几步才进画像？1 步也进 —— 画像里会显示条数，读者自己看得见样本多小；
  /// 藏起来反而让人以为"没有这一步的风险"，那是不对的。
  static List<CapabilityReading> of(Iterable<CapabilityStepSample> steps) {
    final buckets = <String, _Bucket>{};
    for (final step in steps) {
      final key = step.actionType.trim();
      if (key.isEmpty) {
        continue;
      }
      final bucket = buckets.putIfAbsent(key, _Bucket.new);
      bucket.add(step.stuckRisk);
    }
    final readings = <CapabilityReading>[
      for (final entry in buckets.entries)
        CapabilityReading(
          actionType: entry.key,
          known: CapabilityAction.isKnownKey(entry.key),
          label: CapabilityAction.byKey(entry.key)?.labelZh ?? entry.key,
          stepCount: entry.value.stepCount,
          riskyStepCount: entry.value.riskyStepCount,
          avgStuckRisk: entry.value.avg,
        ),
    ];
    readings.sort(_compare);
    return readings;
  }

  static int _compare(CapabilityReading a, CapabilityReading b) {
    // 有读数的排前面：平均风险高的更该练。
    if (a.avgStuckRisk != null && b.avgStuckRisk == null) {
      return -1;
    }
    if (a.avgStuckRisk == null && b.avgStuckRisk != null) {
      return 1;
    }
    final byAvg = (b.avgStuckRisk ?? 0).compareTo(a.avgStuckRisk ?? 0);
    if (byAvg != 0) {
      return byAvg;
    }
    final byRisky = b.riskyStepCount.compareTo(a.riskyStepCount);
    if (byRisky != 0) {
      return byRisky;
    }
    final bySteps = b.stepCount.compareTo(a.stepCount);
    if (bySteps != 0) {
      return bySteps;
    }
    return a.label.compareTo(b.label);
  }
}

class _Bucket {
  int stepCount = 0;
  int riskyStepCount = 0;
  int _riskCount = 0;
  double _riskSum = 0;

  void add(double? risk) {
    stepCount++;
    if (risk == null) {
      return;
    }
    _riskCount++;
    _riskSum += risk;
    if (risk >= CapabilityProfile.riskyThreshold) {
      riskyStepCount++;
    }
  }

  double? get avg => _riskCount == 0 ? null : _riskSum / _riskCount;
}
