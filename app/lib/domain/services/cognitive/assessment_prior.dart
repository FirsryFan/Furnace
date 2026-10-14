/// 测评层的**先验估计器**（[ASSESSMENT_DESIGN.md] §7 的 M1a）。
///
/// 这一层只做一件事：把"自评 + 抽检"这两类测评信号，换算成认知模型能吃的
/// **先验**——`R0`（编码强度上限）、`D`（难度）与 `fluency`（主观流畅度），
/// 外加一个全局的**校准偏置**（自评系统性高估/低估了多少）。
///
/// 三条纪律，写死在代码里：
///
/// * **先验不是观测**。结果不写进 `card_states`（那里只放复习行为长出来的
///   状态）；调用方按"有观测用观测、无观测用先验"合并。混写会让复习校正
///   失去意义。
/// * **没有信号就不产出**。一个知识点既没自评也没抽检时，这里返回的是
///   "没有先验"，不是一个编出来的默认值（`card_states.encoding_strength`
///   的 NULL 语义同此）。
/// * **全部未标定**。下面每个常数都是显式选定的粗映射，不是实测标定值；
///   [`AssessmentPriorEstimate.confidence`] 与样本数 `n` 一起暴露出去，
///   让上层能说"这是个先验"而不是"这是事实"。
///
/// 纯 Dart：不读时钟、不碰数据库、不依赖 Flutter，和同目录其它认知层模块
/// 一样可被向量化单测覆盖。
library;

import '../srs/dsr_memory.dart';

/// 一个知识点在一轮测评里留下的证据。
///
/// [objectiveResults] 为空表示"这一轮没有对这个点做客观抽检"——这与"抽检了
/// 且全错"是两件事，估计器对二者的处理不同。
class AssessmentEvidence {
  const AssessmentEvidence({
    required this.knowledgePointId,
    this.selfRating,
    this.objectiveResults = const <bool>[],
    this.elapsedMs,
  });

  /// 知识点（`knowledge_points.id`）。
  final String knowledgePointId;

  /// 自评：0–5（JOL，"你觉得自己会多少"）。NULL 表示没问。
  final int? selfRating;

  /// 客观抽检的逐题对错。空表示没抽检。
  final List<bool> objectiveResults;

  /// 自评或抽检耗时（毫秒）。先只记录，不参与建模（设计文档 §2 第 9 行）。
  final int? elapsedMs;
}

/// 一个知识点的先验估计。
class AssessmentPriorEstimate {
  const AssessmentPriorEstimate({
    required this.knowledgePointId,
    required this.r0,
    required this.difficulty,
    required this.fluency,
    required this.n,
    required this.confidence,
    required this.basis,
  });

  final String knowledgePointId;

  /// 编码强度上限先验（MindNet `R0`）。有抽检时由正确率给，只有自评时由
  /// 修正后的流畅度给。
  final double r0;

  /// 难度先验（MindNet `D`，FSRS 量纲 1–10）。只有客观抽检能给，否则 NULL。
  final double? difficulty;

  /// 主观流畅度先验（元认知信念的输入 `f`），0–1。没自评时为 NULL。
  final double? fluency;

  /// 样本数：抽检题数 + （有自评则 1）。
  final int n;

  /// 置信度 `n / (n + 3)`，0–1。纯先验、没有观测校正，所以永远小于 1。
  final double confidence;

  /// 人可读的依据，例如 `self:4` / `objective:1/3`。写进 JSON 供 UI 展示。
  final List<String> basis;

  Map<String, Object?> toJson() => <String, Object?>{
        'knowledge_point_id': knowledgePointId,
        'r0': r0,
        'difficulty': difficulty,
        'fluency': fluency,
        'n': n,
        'confidence': confidence,
        'basis': basis,
      };
}

/// 一轮测评的先验读数。
class AssessmentPriorReading {
  const AssessmentPriorReading({
    required this.estimates,
    required this.calibrationBias,
    required this.judgedCount,
    required this.ignoredCount,
  });

  /// 输出 JSON 的 schema 串，和同目录其它读数保持一致的做法。
  static const String schema = 'mindnet.assessment_prior/1';

  static const AssessmentPriorReading empty = AssessmentPriorReading(
    estimates: <AssessmentPriorEstimate>[],
    calibrationBias: 0,
    judgedCount: 0,
    ignoredCount: 0,
  );

  final List<AssessmentPriorEstimate> estimates;

  /// 自评与客观正确率的平均差（`fluency_self − correctRate`，只在两者都有的
  /// 点上算）。正数＝高估（危险区的来源），负数＝低估（焦虑区的来源）。
  final double calibrationBias;

  /// 参与校准的点数（既有自评又有抽检）。
  final int judgedCount;

  /// 两个信号都没有、因此没有产出先验的点数。
  final int ignoredCount;

  bool get isEmpty => estimates.isEmpty;

  Map<String, Object?> toJson() => <String, Object?>{
        'schema': schema,
        'calibration_bias': calibrationBias,
        'judged_count': judgedCount,
        'ignored_count': ignoredCount,
        'estimates': <Object?>[for (final e in estimates) e.toJson()],
      };
}

/// 先验换算表。**全部未标定**：数值是显式选定的粗映射，随真实数据标定
/// （`docs/CALIBRATION.md` 的口径）后再改这里，不许散落在 UI 里。
abstract final class AssessmentPrior {
  /// 有抽检时：`R0 = base + span × 正确率`。全错 0.35、全对 0.90。
  static const double r0ObjectiveBase = 0.35;
  static const double r0ObjectiveSpan = 0.55;

  /// 只有自评时：`R0 = base + span × 修正后流畅度`。0.45–0.85。
  static const double r0SelfBase = 0.45;
  static const double r0SelfSpan = 0.40;

  /// 先验 R0 的钳制区间：0.3 太差（卡片该重学）、0.95 以上不当成先验下写。
  static const double r0Min = 0.30;
  static const double r0Max = 0.95;

  /// 难度：`D = base + span × 错误率`，钳到 FSRS 的 1–10。
  static const double difficultyBase = 3.0;
  static const double difficultySpan = 6.0;
  static const double difficultyMin = 1.0;
  static const double difficultyMax = 10.0;

  /// 置信度的伪计数：`n / (n + k)`。k=3 表示"三题之后才敢说一半把握"。
  static const double confidencePseudoCount = 3.0;

  /// 读数。没有信号的点不产出估计，只计入 [AssessmentPriorReading.ignoredCount]。
  static AssessmentPriorReading read({
    required List<AssessmentEvidence> evidence,
  }) {
    for (final e in evidence) {
      if (e.knowledgePointId.trim().isEmpty) {
        throw ArgumentError('知识点 id 不能为空');
      }
      final rating = e.selfRating;
      if (rating != null && (rating < 0 || rating > 5)) {
        throw ArgumentError(
          '自评必须在 0–5 之间，实际 ${e.knowledgePointId} 的 $rating',
        );
      }
    }

    final selfFluency = <String, double>{};
    final correctRate = <String, double>{};
    for (final e in evidence) {
      if (e.selfRating != null) {
        selfFluency[e.knowledgePointId] = e.selfRating! / 5.0;
      }
      if (e.objectiveResults.isNotEmpty) {
        final hits = e.objectiveResults.where((ok) => ok).length;
        correctRate[e.knowledgePointId] = hits / e.objectiveResults.length;
      }
    }

    final paired = <double>[];
    for (final id in selfFluency.keys) {
      final rate = correctRate[id];
      if (rate != null) {
        paired.add(selfFluency[id]! - rate);
      }
    }
    final bias =
        paired.isEmpty ? 0.0 : paired.reduce((a, b) => a + b) / paired.length;

    final estimates = <AssessmentPriorEstimate>[];
    var ignored = 0;
    for (final e in evidence) {
      final id = e.knowledgePointId;
      final self = selfFluency[id];
      final rate = correctRate[id];
      if (self == null && rate == null) {
        ignored++;
        continue;
      }

      // 修正后的主观流畅度：自评减掉全局偏置（例如系统性高估 0.2 就减 0.2）。
      final correctedFluency =
          self == null ? null : _clamp(self - bias, 0.0, 1.0);

      final r0Raw = rate != null
          ? r0ObjectiveBase + r0ObjectiveSpan * rate
          : r0SelfBase + r0SelfSpan * correctedFluency!;

      final basis = <String>[
        if (self != null) 'self:${e.selfRating}',
        if (rate != null)
          'objective:${e.objectiveResults.where((ok) => ok).length}'
              '/${e.objectiveResults.length}',
      ];

      final n = e.objectiveResults.length + (self != null ? 1 : 0);
      estimates.add(
        AssessmentPriorEstimate(
          knowledgePointId: id,
          r0: DsrMemory.round6(_clamp(r0Raw, r0Min, r0Max)),
          difficulty: rate == null
              ? null
              : DsrMemory.round6(
                  _clamp(
                    difficultyBase + difficultySpan * (1 - rate),
                    difficultyMin,
                    difficultyMax,
                  ),
                ),
          fluency: correctedFluency == null
              ? null
              : DsrMemory.round6(correctedFluency),
          n: n,
          confidence: DsrMemory.round6(
            n / (n + confidencePseudoCount),
          ),
          basis: basis,
        ),
      );
    }

    return AssessmentPriorReading(
      estimates: estimates,
      calibrationBias: DsrMemory.round6(bias),
      judgedCount: paired.length,
      ignoredCount: ignored,
    );
  }

  static double _clamp(double x, double lo, double hi) =>
      x < lo ? lo : (x > hi ? hi : x);
}
