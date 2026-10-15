/// 找相似题（Q12）：给定一道题，在**已有题库**里找它的"同型邻居"。
///
/// 用户口径：AI **不出题**，只解题 / 拆题 / **找相似题**。所以这一层不生成任何题干，
/// 只在已有候选里排序——它是 `docs/PAPER_COMPOSER_DESIGN.md` §4 那句"缺口只报不补"
/// 的另一半：缺口可以补，但补的必须是库里已有的题。
///
/// 四个信号（都是"越多越像"的归一化分量）：
///
/// * **共用知识点**（权重最高）：两个题挂到同一个知识点，说明练的是同一件事；
/// * **思维链动作序列**（LCS 重合度）：`actionType` 是跨学科的桥——数学的"分类讨论"
///   和语文的"分层作答"是同一个能力动作，所以哪怕学科不同、知识点不同，动作同型也
///   值得推荐（跨学科迁移训练）；
/// * **学科**：同科加分（但不是必需）；
/// * **难度**：接近加分，缺读数时取中性，不惩罚"不知道"。
///
/// 两条纪律：
///
/// * **自己不推荐自己**；
/// * 分数低于 [kMinSimilarityScore] 的不算"相似"——"同学科、同难度"这种弱信号单独出现时
///   不该进榜（否则推荐会退化成"随机再给一道题"）。
library;

import '../reasoning/capability_action.dart';
import 'paper_composer.dart' show kSourceLevelPriority;

/// 低于这个分数不算相似：同学科 + 同难度（0.10 + 0.10）还不够，必须真有一条
/// "共用知识点"或"同型步骤"。
const double kMinSimilarityScore = 0.25;

/// 相似度权重（显式、**未标定**：相对大小有理由，具体数值等真实使用回填）。
class SimilarityWeights {
  const SimilarityWeights({
    this.knowledgePoint = 0.50,
    this.actionType = 0.30,
    this.subject = 0.10,
    this.difficulty = 0.10,
  });

  /// 共用知识点（占最高权重：练的是同一件事）。
  final double knowledgePoint;

  /// 思维链动作序列重合（跨学科迁移靠它）。
  final double actionType;

  /// 同学科。
  final double subject;

  /// 难度接近。
  final double difficulty;

  double get sum => knowledgePoint + actionType + subject + difficulty;

  /// 归一化到和为 1；和 ≤ 0 时原样返回（宁可退化，也不悄悄改权重）。
  SimilarityWeights normalized() {
    final total = sum;
    if (total <= 0) return this;
    return SimilarityWeights(
      knowledgePoint: knowledgePoint / total,
      actionType: actionType / total,
      subject: subject / total,
      difficulty: difficulty / total,
    );
  }

  Map<String, double> toMap() => {
        'knowledge_point': knowledgePoint,
        'action_type': actionType,
        'subject': subject,
        'difficulty': difficulty,
      };
}

/// 要找邻居的那道题。
class SimilarityFocus {
  const SimilarityFocus({
    required this.questionId,
    this.knowledgePointIds = const [],
    this.subjectKey = '',
    this.questionType = '',
    this.difficulty,
    this.actionTypes = const [],
  });

  final String questionId;

  /// 这道题覆盖的知识点（`TaskKnowledgePointResolver` + `kQuestionObjectType`）。
  final List<String> knowledgePointIds;

  final String subjectKey;
  final String questionType;

  /// 1..10；未知就留 `null`（分量取中性，不当成"最简单"）。
  final double? difficulty;

  /// 它的思维链动作序列（按步骤顺序的 `actionType`）；没有链就是空表。
  final List<String> actionTypes;
}

/// 题库里的一道候选题。
class SimilarityCandidate {
  const SimilarityCandidate({
    required this.questionId,
    this.knowledgePointIds = const [],
    this.subjectKey = '',
    this.questionType = '',
    this.sourceLevel = 'unknown',
    this.difficulty,
    this.actionTypes = const [],
  });

  final String questionId;
  final List<String> knowledgePointIds;
  final String subjectKey;
  final String questionType;

  /// `gaokao` / `provincial_diagnostic` / `elite_school` / `school` / `personal` / `unknown`。
  final String sourceLevel;
  final double? difficulty;
  final List<String> actionTypes;

  double get sourcePriority => kSourceLevelPriority[sourceLevel.trim()] ?? 0.0;
}

/// 一条推荐。
class SimilarQuestion {
  const SimilarQuestion({
    required this.questionId,
    required this.score,
    required this.components,
    this.sharedKnowledgePointIds = const [],
    this.sharedActionTypes = const [],
    this.crossSubjectTransfer = false,
    required this.reasonZh,
  });

  final String questionId;

  /// 归一化权重下的加权总分。
  final double score;

  /// 四个分量（归一化权重后），便于界面解释"为什么像"与后续调权。
  final Map<String, double> components;

  final List<String> sharedKnowledgePointIds;

  /// 按聚焦题的步骤顺序列出的"同型动作"（去重）。
  final List<String> sharedActionTypes;

  /// 学科不同、但有同型动作 → 跨学科迁移训练候选。
  final bool crossSubjectTransfer;

  /// 中文理由（领域层文案，界面直接显示；l10n 化留后轮，与组卷/threadflow 同规矩）。
  final String reasonZh;

  Map<String, Object?> toJson() => {
        'question_id': questionId,
        'score': score,
        'components': components,
        'shared_knowledge_point_ids': sharedKnowledgePointIds,
        'shared_action_types': sharedActionTypes,
        'cross_subject_transfer': crossSubjectTransfer,
        'reason_zh': reasonZh,
      };
}

/// 排序器。纯函数：同样的输入永远给同样的输出（含 tie-break）。
abstract final class SimilarQuestionFinder {
  /// 动作序列最长只比这么多个步骤（防止异常长的链把 DP 拖慢；链本来就只有几步）。
  static const int maxSequenceLength = 50;

  /// 聚焦题在 [candidates] 里的同型邻居，按像的程度降序。
  ///
  /// * 聚焦题自己（同 id）不会出现；
  /// * 低于 [minScore] 的不返回；
  /// * 取前 [limit] 条（`limit <= 0` 视为不限制）；
  /// * 输入顺序不影响输出（按分数 → 共用点数 → 来源分级 → 题目 id 兜底排序）。
  static List<SimilarQuestion> rank({
    required SimilarityFocus focus,
    required List<SimilarityCandidate> candidates,
    int limit = 10,
    double minScore = kMinSimilarityScore,
    SimilarityWeights weights = const SimilarityWeights(),
    Map<String, String> knowledgePointNames = const {},
  }) {
    final normalized = weights.normalized();
    final focusPoints = cleanIds(focus.knowledgePointIds);
    final focusActions = cleanActions(focus.actionTypes);
    final focusId = focus.questionId.trim();

    final scored = <_Scored>[];
    for (final candidate in candidates) {
      final candidateId = candidate.questionId.trim();
      if (candidateId.isEmpty || candidateId == focusId) continue;

      final candidatePoints = cleanIds(candidate.knowledgePointIds);
      final sharedPoints = <String>[
        for (final point in focusPoints)
          if (candidatePoints.contains(point)) point,
      ];
      final pointScore =
          focusPoints.isEmpty ? 0.0 : sharedPoints.length / focusPoints.length;

      final candidateActions = cleanActions(candidate.actionTypes);
      final actionScore = actionSequenceOverlap(
        focusActions,
        candidateActions,
      );
      final sharedActions = <String>[
        for (final action in focusActions)
          if (candidateActions.contains(action)) action,
      ];

      final subjectScore =
          _subjectComponent(focus.subjectKey, candidate.subjectKey);
      final difficultyScore =
          _difficultyComponent(focus.difficulty, candidate.difficulty);

      final score = normalized.knowledgePoint * pointScore +
          normalized.actionType * actionScore +
          normalized.subject * subjectScore +
          normalized.difficulty * difficultyScore;
      if (score.isNaN || score < minScore) continue;

      final crossSubject = sharedActions.isNotEmpty &&
          _subjectKeyOf(focus.subjectKey) !=
              _subjectKeyOf(candidate.subjectKey) &&
          _subjectKeyOf(candidate.subjectKey).isNotEmpty &&
          _subjectKeyOf(focus.subjectKey).isNotEmpty;

      scored.add(
        _Scored(
          candidate: candidate,
          score: score,
          components: {
            'knowledge_point': pointScore,
            'action_type': actionScore,
            'subject': subjectScore,
            'difficulty': difficultyScore,
          },
          sharedPoints: List<String>.unmodifiable(sharedPoints),
          sharedActions: List<String>.unmodifiable(sharedActions),
          crossSubjectTransfer: crossSubject,
        ),
      );
    }

    scored.sort(_byScoreThenProvenance);
    final kept =
        limit > 0 && scored.length > limit ? scored.sublist(0, limit) : scored;
    return <SimilarQuestion>[
      for (final entry in kept)
        SimilarQuestion(
          questionId: entry.candidate.questionId.trim(),
          score: entry.score,
          components: Map<String, double>.unmodifiable(entry.components),
          sharedKnowledgePointIds: entry.sharedPoints,
          sharedActionTypes: entry.sharedActions,
          crossSubjectTransfer: entry.crossSubjectTransfer,
          reasonZh: _reasonZh(
            entry: entry,
            focus: focus,
            knowledgePointNames: knowledgePointNames,
          ),
        ),
    ];
  }

  /// 共用知识点占聚焦题知识点的比例（0..1）。
  static double knowledgePointOverlap({
    required List<String> focus,
    required List<String> candidate,
  }) {
    final focusPoints = cleanIds(focus);
    if (focusPoints.isEmpty) return 0;
    final candidatePoints = cleanIds(candidate).toSet();
    var shared = 0;
    for (final point in focusPoints) {
      if (candidatePoints.contains(point)) shared++;
    }
    return shared / focusPoints.length;
  }

  /// 动作序列的最长公共子序列长度 / 聚焦题序列长度（0..1）。
  ///
  /// 用子序列而不是集合：`[归纳, 检验]` 和 `[归纳, 检验]` 比"集合一样但顺序相反"
  /// 更像——步骤顺序是解题结构的一部分。
  static double actionSequenceOverlap(
    List<String> focus,
    List<String> candidate,
  ) {
    final a = _truncate(cleanActions(focus));
    final b = _truncate(cleanActions(candidate));
    if (a.isEmpty || b.isEmpty) return 0;
    var previous = List<int>.filled(b.length + 1, 0);
    var current = List<int>.filled(b.length + 1, 0);
    for (var i = 1; i <= a.length; i++) {
      for (var j = 1; j <= b.length; j++) {
        current[j] = a[i - 1] == b[j - 1]
            ? previous[j - 1] + 1
            : (previous[j] >= current[j - 1] ? previous[j] : current[j - 1]);
      }
      final swap = previous;
      previous = current;
      current = swap;
      for (var j = 0; j < current.length; j++) {
        current[j] = 0;
      }
    }
    return previous[b.length] / a.length;
  }

  /// 去掉空白与空串、去重、排序（输入顺序不影响结果）。
  static List<String> cleanIds(Iterable<String> values) {
    final cleaned = <String>{};
    for (final value in values) {
      final trimmed = value.trim();
      if (trimmed.isNotEmpty) cleaned.add(trimmed);
    }
    return cleaned.toList()..sort();
  }

  /// 动作键：去空白与空串，**保留顺序与重复**（子序列要看顺序）。
  static List<String> cleanActions(Iterable<String> values) => <String>[
        for (final value in values)
          if (value.trim().isNotEmpty) value.trim(),
      ];

  static List<String> _truncate(List<String> values) =>
      values.length <= maxSequenceLength
          ? values
          : values.sublist(0, maxSequenceLength);

  /// 学科分量：两边都写了才判断；有一边没写就是中性 0.5（"不知道"不惩罚）。
  static double _subjectComponent(String focus, String candidate) {
    final a = _subjectKeyOf(focus);
    final b = _subjectKeyOf(candidate);
    if (a.isEmpty || b.isEmpty) return 0.5;
    return a == b ? 1.0 : 0.0;
  }

  static String _subjectKeyOf(String value) => value.trim();

  /// 难度分量：都写了就按 1 - |Δ|/9；缺一边取中性 0.5。
  static double _difficultyComponent(double? focus, double? candidate) {
    if (focus == null || candidate == null) return 0.5;
    if (focus.isNaN || candidate.isNaN) return 0.5;
    final gap = (focus - candidate).abs() / 9.0;
    final value = 1.0 - gap;
    return value.clamp(0.0, 1.0);
  }

  static int _byScoreThenProvenance(_Scored a, _Scored b) {
    final byScore = b.score.compareTo(a.score);
    if (byScore != 0) return byScore;
    final byPoints = b.sharedPoints.length.compareTo(a.sharedPoints.length);
    if (byPoints != 0) return byPoints;
    final byActions = b.sharedActions.length.compareTo(a.sharedActions.length);
    if (byActions != 0) return byActions;
    final bySource =
        b.candidate.sourcePriority.compareTo(a.candidate.sourcePriority);
    if (bySource != 0) return bySource;
    return a.candidate.questionId
        .trim()
        .compareTo(b.candidate.questionId.trim());
  }

  static String _reasonZh({
    required _Scored entry,
    required SimilarityFocus focus,
    required Map<String, String> knowledgePointNames,
  }) {
    final parts = <String>[];

    if (entry.sharedPoints.isNotEmpty) {
      parts.add('共用知识点${_labels(entry.sharedPoints, knowledgePointNames)}');
    }
    if (entry.sharedActions.isNotEmpty) {
      parts.add(
        '同型步骤${entry.sharedActions.map(_actionLabel).join(' → ')}'
        '（动作序列重合 ${_two(entry.components['action_type'] ?? 0)}）',
      );
    }
    if (entry.crossSubjectTransfer) {
      parts.add('跨学科迁移：学科不同，但解题动作同型');
    }
    if (entry.sharedPoints.isEmpty && entry.sharedActions.isEmpty) {
      // 走到这里只可能是同学科 + 难度接近（弱信号，但仍过阈值）。
      parts.add('同学科、难度接近，但还没有可对照的知识点或思维链');
    }
    final focusDifficulty = focus.difficulty;
    final candidateDifficulty = entry.candidate.difficulty;
    if (focusDifficulty != null && candidateDifficulty != null) {
      parts.add('难度 ${_two(focusDifficulty)} vs ${_two(candidateDifficulty)}');
    }
    final source = entry.candidate.sourceLevel.trim();
    if (source.isNotEmpty && source != 'unknown') {
      parts.add('来源：${_sourceLabel(source)}');
    }
    if (parts.isEmpty) return '库里和它挂载关系最接近的一道题。';
    return '${parts.join('；')}。';
  }

  /// 知识点名（有名字用名字，没有就回落到 id）；最多列两个，其余说"等 N 个"。
  static String _labels(List<String> ids, Map<String, String> names) {
    final labels = <String>[
      for (final id in ids)
        _quoted((names[id] ?? '').trim().isEmpty ? id : names[id]!.trim()),
    ];
    if (labels.length <= 2) return labels.join('、');
    return '${labels.take(2).join('、')} 等 ${labels.length} 个';
  }

  /// 动作中文标签；词表里查不到就原样显示 key（不隐藏未知动作）。
  static String _actionLabel(String key) {
    final action = CapabilityAction.byKey(key);
    return action == null ? key : action.labelZh;
  }

  static String _sourceLabel(String key) => switch (key) {
        'gaokao' => '高考真题',
        'provincial_diagnostic' => '省市诊断',
        'elite_school' => '名校测试',
        'school' => '校内题',
        'personal' => '自建题',
        _ => key,
      };

  static String _quoted(String value) => '「$value」';

  static String _two(double value) => value.toStringAsFixed(2);
}

class _Scored {
  const _Scored({
    required this.candidate,
    required this.score,
    required this.components,
    required this.sharedPoints,
    required this.sharedActions,
    required this.crossSubjectTransfer,
  });

  final SimilarityCandidate candidate;
  final double score;
  final Map<String, double> components;
  final List<String> sharedPoints;
  final List<String> sharedActions;
  final bool crossSubjectTransfer;
}
