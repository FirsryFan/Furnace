import 'dart:convert';

import 'question_capability.dart';

/// 一次自测作答的「能力—对错」观察。
class AbilityAttempt {
  const AbilityAttempt({required this.capabilityJson, required this.isCorrect});

  final String? capabilityJson;
  final bool isCorrect;
}

/// 按能力编号聚合自测正确率。
class AbilityStat {
  const AbilityStat({
    required this.code,
    required this.labelZh,
    required this.total,
    required this.correct,
  });

  final String code;
  final String labelZh;
  final int total;
  final int correct;

  double get accuracy => total == 0 ? 0 : correct / total;
}

/// 从自测记录聚合能力读数。
///
/// 只返回样本 ≥ [minSamples] 的能力；样本不足不猜。未知能力编号丢弃。
List<AbilityStat> aggregateAbilityStats(
  Iterable<AbilityAttempt> attempts, {
  int minSamples = 3,
}) {
  final totals = <String, int>{};
  final corrects = <String, int>{};
  for (final attempt in attempts) {
    final raw = attempt.capabilityJson;
    if (raw == null || raw.trim().isEmpty) continue;
    List<String> codes;
    try {
      codes = capabilityCodesFromJson(jsonDecode(raw));
    } on FormatException {
      continue;
    }
    for (final code in codes) {
      totals[code] = (totals[code] ?? 0) + 1;
      if (attempt.isCorrect) {
        corrects[code] = (corrects[code] ?? 0) + 1;
      }
    }
  }
  final result = <AbilityStat>[
    for (final entry in totals.entries)
      if (entry.value >= minSamples)
        AbilityStat(
          code: entry.key,
          labelZh: QuestionCapability.fromCode(entry.key)?.labelZh ?? entry.key,
          total: entry.value,
          correct: corrects[entry.key] ?? 0,
        ),
  ];
  result.sort((a, b) => a.accuracy.compareTo(b.accuracy));
  return result;
}
