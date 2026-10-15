/// 把认知层的输出投影成段落 B 的 [KnowledgePointReading]。
///
/// 这是**唯一**同时认识 `fast_diagnosis.dart` / `assessment_prior.dart` 与
/// `domain_balance.dart` 的地方：段落 B 因此保持"纯排序"，对认知层零依赖，
/// 换诊断算法时只改这一个文件。
///
/// 设计纪律（与 `KnowledgePointReading` 的文档一致）：
///
/// * **没有信号 ≠ 读数为 0**：一个知识点既不在危险区/发展区、也没有先验时，
///   这里**不产出**读数，段落 B 会用中性有效性代替；
/// * **诊断层没跑 ≠ 库是健康的**：`diagnosisByKnowledgePoint == null` 表示
///   "这轮没跑诊断"（`LibraryDiagnosis.notRun`），此时只用先验；传进来一个
///   空 map 才表示"跑了，没发现瓶颈"；
/// * 先验的 `confidence == 0` 视为"不参与加权"，等价于没有先验。
library;

import '../cognitive/assessment_prior.dart';
import '../cognitive/fast_diagnosis.dart';
import 'domain_balance.dart';

abstract final class CognitiveReadingsAdapter {
  /// 把诊断结论 + 测评先验对齐到 [knowledgePointIds] 上。
  ///
  /// 输入顺序不影响输出顺序（按知识点 id 排序），重复 id 只保留第一次出现的
  /// 位置判断结果。
  static List<KnowledgePointReading> readingsFor({
    required Iterable<String> knowledgePointIds,

    /// `LibraryDiagnosis.byKnowledgePoint`；null = 诊断层没跑。
    Map<String, BottleneckType>? diagnosisByKnowledgePoint,

    /// `knowledgePointId -> AssessmentPriorEstimate`。
    Map<String, AssessmentPriorEstimate> priors =
        const <String, AssessmentPriorEstimate>{},
  }) {
    final readings = <KnowledgePointReading>[];
    final seen = <String>{};
    for (final raw in knowledgePointIds) {
      final id = raw.trim();
      if (id.isEmpty || !seen.add(id)) {
        continue;
      }
      final verdict = diagnosisByKnowledgePoint?[id];
      final prior = priors[id];
      final inDanger = verdict == BottleneckType.danger;
      final inDevelopment = verdict == BottleneckType.weak;
      final priorCounts = prior != null && prior.confidence > 0;
      if (!inDanger && !inDevelopment && !priorCounts) {
        continue; // 没有信号：不产出读数
      }
      readings.add(
        KnowledgePointReading(
          knowledgePointId: id,
          inDangerZone: inDanger,
          inDevelopmentZone: inDevelopment,
          priorR0: priorCounts ? _unit(prior.r0) : null,
          priorConfidence: priorCounts ? _unit(prior.confidence) : 0,
        ),
      );
    }
    readings.sort(
      (a, b) => a.knowledgePointId.compareTo(b.knowledgePointId),
    );
    return readings;
  }

  /// 便捷入口：直接把 [TaskKnowledgePointResolver] 的结果喂进来。
  static List<KnowledgePointReading> forTaskKnowledgePoints({
    Map<String, List<String>> taskKnowledgePoints =
        const <String, List<String>>{},
    Map<String, BottleneckType>? diagnosisByKnowledgePoint,
    Map<String, AssessmentPriorEstimate> priors =
        const <String, AssessmentPriorEstimate>{},
  }) {
    final ids = <String>{};
    for (final list in taskKnowledgePoints.values) {
      ids.addAll(list);
    }
    return readingsFor(
      knowledgePointIds: ids,
      diagnosisByKnowledgePoint: diagnosisByKnowledgePoint,
      priors: priors,
    );
  }

  static double _unit(double value) {
    if (value.isNaN) {
      return 0;
    }
    return value.clamp(0.0, 1.0).toDouble();
  }
}
