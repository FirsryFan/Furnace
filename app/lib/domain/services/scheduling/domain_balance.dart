/// ThreadFlow 两段式的**段落 B**：在"已经可行的候选"里回答
/// "现在做什么最有效 + 怎么把工作量摊到各学科"。
///
/// 边界（详细说明见 `docs/THREADFLOW_TWO_SEGMENT.md`）：
///
/// * **段落 A（纯算法，不含 MindNet）**：哪些时间窗可用、时长够不够、截止时间
///   是否收紧、是否被忙碌块占用——由 `thread_ranker.dart` 的 [ThreadRanker]
///   与 `time_window_engine.dart` 决定。本文件**不修改**它们，只在
///   [DomainBalanceRanker.feasible] 里原样转调一次，并把它的 `ready` 当作
///   段落 B 的输入；红名单（`insufficient` / `overdue`）原样带出。
/// * **段落 B（MindNet 语义）**：在这些可行候选中排序，并给出每个任务
///   "为什么它排这里"的中文理由。本文件只消费认知**读数**（危险区 /
///   发展区 / 测评先验），不自己跑认知引擎。
///
/// 纯 Dart：不读时钟、不碰数据库、不依赖 Flutter / drift；进的是普通数据，
/// 出的也是普通数据。
library;

import '../config/furnace_defaults.dart';
import 'thread_ranker.dart';

/// 没有挂任何学科标签的任务归入的领域键。
const String kUnclassifiedDomain = '未分类';

/// `ObjectTags.objectType` 中代表"任务"的取值。
const String kTaskObjectType = 'task';

// ---------------------------------------------------------------------------
// 输入：Tags 树 / ObjectTags 的纯数据投影
// ---------------------------------------------------------------------------

/// `Tags` 表的一行（纯数据；`path` 可空，和数据库一致）。
class DomainTag {
  const DomainTag({required this.id, this.parentId, this.path, this.name});

  final String id;
  final String? parentId;

  /// 权威全路径，例如 `Culture/Subject/Chinese/Composition`。
  final String? path;
  final String? name;
}

/// `ObjectTags` 表的一行（纯数据）。只有 `objectType == 'task'` 的链接参与
/// 领域推断。
class TaskTagLink {
  const TaskTagLink({
    required this.taskId,
    required this.tagId,
    this.objectType = kTaskObjectType,
  });

  final String taskId;
  final String tagId;
  final String objectType;
}

/// 领域键 = 标签树里的**顶层祖先**（不是叶子标签）。
abstract final class DomainKeyResolver {
  /// 从一条完整路径取顶层段；空路径/纯空白 → [kUnclassifiedDomain]。
  static String domainOfPath(String path) {
    final segments = TagPath.segments(path.trim());
    if (segments.isEmpty) {
      return kUnclassifiedDomain;
    }
    final top = segments.first.trim();
    return top.isEmpty ? kUnclassifiedDomain : top;
  }

  /// 一组路径 → 主领域键。
  ///
  /// 一个任务可能同时挂多个标签；规则写死为"路径最短的标签优先，同长度取
  /// 字典序最小的顶层段"——纯确定性，且偏保守（越靠顶层越像学科）。
  static String domainOfPaths(List<String> tagPaths) {
    String? best;
    var bestDepth = 1 << 30;
    for (final path in tagPaths) {
      final segments = TagPath.segments(path.trim());
      if (segments.isEmpty) {
        continue;
      }
      final depth = segments.length;
      final top = segments.first.trim();
      if (top.isEmpty) {
        continue;
      }
      if (best == null ||
          depth < bestDepth ||
          (depth == bestDepth && top.compareTo(best) < 0)) {
        best = top;
        bestDepth = depth;
      }
    }
    return best ?? kUnclassifiedDomain;
  }

  /// 用 `Tags` 树 + `ObjectTags` 链接把 `taskId` 解析成顶层祖先名。
  ///
  /// 这是 `RankEvent.tagPaths` 为空（数据库里 `Tags.path` 可空）时的兜底。
  /// 解析不出（标签不在传入的表里、或整条链缺失）时返回
  /// [kUnclassifiedDomain]，绝不抛异常。
  static Map<String, String> resolveFromTagTree({
    required List<DomainTag> tags,
    required List<TaskTagLink> links,
  }) {
    final byId = <String, DomainTag>{};
    for (final tag in tags) {
      if (tag.id.isEmpty) {
        continue;
      }
      byId[tag.id] = tag;
    }
    final bestDepth = <String, int>{};
    final result = <String, String>{};
    for (final link in links) {
      if (link.objectType != kTaskObjectType || link.taskId.isEmpty) {
        continue;
      }
      final resolved = _rootOf(link.tagId, byId);
      final currentDomain = result[link.taskId];
      final currentDepth = bestDepth[link.taskId];
      if (currentDomain == null ||
          resolved.depth < currentDepth! ||
          (resolved.depth == currentDepth &&
              resolved.domain.compareTo(currentDomain) < 0)) {
        result[link.taskId] = resolved.domain;
        bestDepth[link.taskId] = resolved.depth;
      }
    }
    return result;
  }

  /// 沿 `parentId` 上溯到根（带防环上限），返回根标签的领域键与树深。
  static ({String domain, int depth}) _rootOf(
    String tagId,
    Map<String, DomainTag> byId,
  ) {
    DomainTag? current = byId[tagId];
    if (current == null) {
      return (domain: kUnclassifiedDomain, depth: 1 << 30);
    }
    var depth = 0;
    var guard = byId.length + 1; // 防环
    while (guard-- > 0) {
      final parentId = current!.parentId;
      if (parentId == null || parentId.isEmpty) {
        break;
      }
      final parent = byId[parentId];
      if (parent == null) {
        break;
      }
      current = parent;
      depth += 1;
    }
    final top = current!;
    final path = top.path;
    if (path != null) {
      final segments = TagPath.segments(path.trim());
      if (segments.isNotEmpty && segments.first.trim().isNotEmpty) {
        return (domain: segments.first.trim(), depth: depth);
      }
    }
    final name = top.name?.trim();
    if (name != null && name.isNotEmpty) {
      return (domain: name, depth: depth);
    }
    return (
      domain: top.id.isEmpty ? kUnclassifiedDomain : top.id,
      depth: depth,
    );
  }
}

// ---------------------------------------------------------------------------
// 输入：认知读数（纯数据）
// ---------------------------------------------------------------------------

/// 一个知识点上"现在做它有多大效果"的认知读数。
///
/// 三个来源与调用方的映射（现成适配器：[CognitiveReadingsAdapter.readingsFor]
/// 在 `cognitive_readings.dart`）：
///
/// * [inDangerZone] ← `LibraryDiagnosis.byKnowledgePoint` 里的
///   `BottleneckType.danger`（自信高、实际提取不出来）；
/// * [inDevelopmentZone] ← 同一张表里的 `BottleneckType.weak`（差点想起来，
///   合意难度）；
/// * [priorR0] / [priorConfidence] ← `AssessmentPriorEstimate.r0` /
///   `.confidence`。
///
/// 没有读数就不产出这个对象——"没有信号"和"读数为 0"是两件事。
class KnowledgePointReading {
  const KnowledgePointReading({
    required this.knowledgePointId,
    this.inDangerZone = false,
    this.inDevelopmentZone = false,
    this.priorR0,
    this.priorConfidence = 0,
  });

  final String knowledgePointId;
  final bool inDangerZone;
  final bool inDevelopmentZone;

  /// 测评先验的编码强度上限 R0（0..1，越小越弱）；null = 没有先验。
  final double? priorR0;

  /// 先验置信度（0..1）。0 表示"只是先验，不参与加权"。
  final double priorConfidence;
}

/// 有效性分量的整定值。**全部未标定**（和仓库其它认知层一致）：数值是显式
/// 选定的粗映射，集中放在这里，标定之后只改一处。
class EffectivenessTuning {
  const EffectivenessTuning({
    this.neutral = 0.5,
    this.dangerBoost = 0.35,
    this.developmentBoost = 0.20,
    this.priorWeight = 0.30,
  });

  /// 没有任何读数时的中性有效性。缺数据不等于低价值——沿用
  /// `thread_ranker.dart` 里 `_fitOf` 的同一条纪律。
  final double neutral;

  /// 危险区加成：MindNet 认为"自信高、实际 R 低"是最该立刻练的
  /// （`fast_diagnosis.dart` 的 danger 处方：间隔提取）。
  final double dangerBoost;

  /// 发展区（`weak`：差点想起来）加成：合意难度，收益高但低于危险区。
  final double developmentBoost;

  /// 先验项权重，乘 `(1 - R0) * confidence`：编码越弱越该现在补。
  final double priorWeight;
}

/// 段落 B 的权重表。和 `RankWeights` 一样显式暴露，方便 UI 展示/编辑。
class DomainBalanceWeights {
  const DomainBalanceWeights({
    this.effectiveness = 0.50,
    this.urgency = 0.25,
    this.goal = 0.10,
    this.balance = 0.15,
    this.overQuotaPenalty = 1.0,
  });

  /// **认知有效性（MindNet 项）的显式权重**：默认最大的一项，因为
  /// "做什么最有效"是这一段的主题。
  final double effectiveness;

  /// 紧迫度：复用段落 A 已经算好的 `RankScore.urgency`（0..1）。
  final double urgency;

  /// 目标匹配：复用段落 A 的 `RankScore.goalMatch`（0..1）。
  final double goal;

  /// 领域分散项权重（配额内奖励，0..1 的加成）。
  final double balance;

  /// 超出学科配额后**每个超出者**的扣分。故意取 1.0：大于任何归一化基础分差
  /// （基础分 ≤ 1），于是"配额内的任务"一定排在"配额外的任务"之前，等价于
  /// "先给每一科保底"的硬保证。它不走归一化，是显式参数，可以调。
  final double overQuotaPenalty;

  /// 四项权重之和（不含 [overQuotaPenalty]）。
  double get sum => effectiveness + urgency + goal + balance;

  /// 归一化到和为 1；和 ≤ 0 时原样返回（调用方自己保证非负）。
  DomainBalanceWeights normalized() {
    final total = sum;
    if (total <= 0) {
      return this;
    }
    return DomainBalanceWeights(
      effectiveness: effectiveness / total,
      urgency: urgency / total,
      goal: goal / total,
      balance: balance / total,
      overQuotaPenalty: overQuotaPenalty,
    );
  }

  Map<String, double> toMap() => {
        'effectiveness': effectiveness,
        'urgency': urgency,
        'goal': goal,
        'balance': balance,
        'overQuotaPenalty': overQuotaPenalty,
      };
}

// ---------------------------------------------------------------------------
// 输出：可解释的排序结果
// ---------------------------------------------------------------------------

/// 一个任务的领域平衡排序结果。
class BalancedTask {
  const BalancedTask({
    required this.taskId,
    required this.score,
    required this.baseScore,
    required this.effectiveness,
    required this.urgency,
    required this.goal,
    required this.balanceBonus,
    required this.overQuotaPenaltyApplied,
    required this.reasonZh,
    required this.domainKey,
    required this.balanceNote,
    required this.domainQuota,
    required this.domainOrderInWindow,
    required this.source,
    this.matchedKnowledgePointId,
    this.inDangerZone = false,
    this.inDevelopmentZone = false,
  });

  final String taskId;

  /// 贪心选择当时的排序分 = `baseScore + balance奖励 - overQuotaPenaltyApplied`。
  /// **可能是负数**：负分表示"被配额压到后面"，不是负价值。
  final double score;

  /// 不受配额影响的质量分，[0,1]。
  final double baseScore;

  /// 认知有效性分量（0..1，见 [EffectivenessTuning]）。
  final double effectiveness;

  /// 段落 A 的 urgency / goalMatch 分量（原样复用，0..1）。
  final double urgency;
  final double goal;

  /// 配额内奖励（0..1）；超出配额后为 0。
  final double balanceBonus;

  /// 实际扣掉的分数（= [DomainBalanceWeights.overQuotaPenalty] × 超出个数）。
  final double overQuotaPenaltyApplied;

  /// 一句话中文理由：「为什么它排这里」。
  final String reasonZh;

  /// 顶层标签祖先；没有标签时为 [kUnclassifiedDomain]。
  final String domainKey;

  /// 领域/配额维度的一句话说明（[[balanceNote]] 是中文，见字段名）。
  final String balanceNote;

  /// 该领域的本窗口配额。
  final int domainQuota;

  /// 在所属领域的本窗口排位（1 = 该领域第一个）。
  final int domainOrderInWindow;

  /// 触发有效性判断的知识点 id；没有读数时为 null。
  final String? matchedKnowledgePointId;

  final bool inDangerZone;
  final bool inDevelopmentZone;

  /// 原始段落 A 结果（带完整分数分解），方便 UI 取用。
  final RankedEvent source;

  /// 是否被配额罚过。
  bool get overQuota => overQuotaPenaltyApplied > 0;

  /// 是否没有学科标签。
  bool get isUnclassified => domainKey == kUnclassifiedDomain;
}

/// 段落 B 的完整输出。
class DomainBalanceOutput {
  const DomainBalanceOutput({
    required this.ranked,
    required this.insufficient,
    required this.overdue,
    required this.domainQuota,
  });

  /// 推荐顺序（贪心选择顺序，**不是** score 降序——奖励会随后变化）。
  final List<BalancedTask> ranked;

  /// 段落 A 的红名单，原样带出。
  final List<RankedEvent> insufficient;
  final List<RankedEvent> overdue;

  /// 每个领域的配额。
  final Map<String, int> domainQuota;

  bool get isEmpty => ranked.isEmpty;

  List<String> get taskIds => [for (final task in ranked) task.taskId];
}

// ---------------------------------------------------------------------------
// 排序器
// ---------------------------------------------------------------------------

abstract final class DomainBalanceRanker {
  /// 段落 A 的显式入口：只做可行域过滤（截止时间硬约束 + 忙碌占用 + 时长），
  /// 不排序、不含领域/认知逻辑。
  ///
  /// 行为与 `ThreadRanker.rank` 完全一致（这里只是转调，不复制、不覆盖），
  /// 目的是让"MindNet 只看到可行候选"这件事在类型上可见。
  static RankOutput feasible({
    required List<RankEvent> events,
    required RankContext context,
  }) =>
      ThreadRanker.rank(events: events, context: context);

  /// 每个领域的配额：`max(1, ceil(windowSlots / domainCount))`。
  ///
  /// 只有一个学科时配额 = 全部槽位（单科不会因为配额被砍）；学科越多，
  /// 每科保底越少，但永远不会是 0。
  static int quotaFor(int windowSlots, int domainCount) {
    if (domainCount <= 0) {
      return windowSlots <= 0 ? 1 : windowSlots;
    }
    if (windowSlots <= 0) {
      return 1;
    }
    return (windowSlots + domainCount - 1) ~/ domainCount;
  }

  /// 段落 B：可行候选 → 领域平衡 + 认知有效性的可解释排序。
  ///
  /// 流程：`ThreadRanker.rank`（段落 A）→ 只取 `ready` → 每个任务算
  /// 基础分（认知有效性 × [DomainBalanceWeights.effectiveness] + 紧迫度 ×
  /// urgency + 目标匹配 × goal）→ 带配额奖励/惩罚做贪心选择 → 输出推荐顺序、
  /// 中文理由与领域说明。
  ///
  /// 空输入/退化输入返回空结果或中性结果，绝不抛异常。
  static DomainBalanceOutput rank({
    required List<RankEvent> events,
    required RankContext context,

    /// taskId → 知识点 id 列表（任务的挂载关系，调用方从数据库读好后传进来）。
    Map<String, List<String>> taskKnowledgePoints = const {},

    /// 认知读数（危险区 / 发展区 / 测评先验），按知识点 id 对齐。
    List<KnowledgePointReading> readings = const [],

    /// `Tags` 树（`RankEvent.tagPaths` 为空时的兜底）。
    List<DomainTag> tags = const [],

    /// `ObjectTags` 链接（`objectType == 'task'` 的才生效）。
    List<TaskTagLink> taskTagLinks = const [],

    /// 知识点 id → 显示名（`KnowledgePoints.title`）。
    ///
    /// [taskKnowledgePoints] 里装的是知识点 **id**，而理由行要念出**名字**；
    /// 知识点 id（`kp-…`）与标签 id（`tag-…`）不是同一个命名空间，所以名字
    /// 只能单独传进来。缺名字时理由行回落到 id（可追溯优先于好看）。
    Map<String, String> knowledgePointNames = const {},

    /// 段落 B 权重表。
    DomainBalanceWeights weights = const DomainBalanceWeights(),

    /// 有效性整定值。
    EffectivenessTuning tuning = const EffectivenessTuning(),

    /// 本窗口实际能装下几个任务；null/≤0 时按候选个数算配额。
    int? windowSlots,

    /// 按领域显式指定配额（正数才生效），覆盖 [quotaFor]。
    Map<String, int> explicitQuotas = const {},
  }) {
    final segmentA = feasible(events: events, context: context);
    final ready = segmentA.ready;
    if (ready.isEmpty) {
      return DomainBalanceOutput(
        ranked: const <BalancedTask>[],
        insufficient: segmentA.insufficient,
        overdue: segmentA.overdue,
        domainQuota: const <String, int>{},
      );
    }

    final normalized = weights.normalized();
    final readingIndex = <String, KnowledgePointReading>{};
    for (final reading in readings) {
      if (reading.knowledgePointId.trim().isEmpty) {
        continue;
      }
      readingIndex.putIfAbsent(reading.knowledgePointId, () => reading);
    }
    final treeDomains = DomainKeyResolver.resolveFromTagTree(
      tags: tags,
      links: taskTagLinks,
    );
    // 理由行会念出知识点名字，所以这里把 id → name 先建好：排序用 id，说话用名字。
    // 名字缺失（标签行被删）时回落到 id——可追溯优先于好看。
    //
    // 两张表合并：标签树给标签 id→名字（领域桶的显示名），
    // [knowledgePointNames] 给知识点 id→名字（理由行里的「知识点「…」」）。
    // 两个命名空间不重叠（`tag-…` / `kp-…`），合并不会互相覆盖。
    final nameById = <String, String>{
      for (final tag in tags)
        if (tag.id.trim().isNotEmpty && (tag.name ?? '').trim().isNotEmpty)
          tag.id: tag.name!.trim(),
      for (final entry in knowledgePointNames.entries)
        if (entry.key.trim().isNotEmpty && entry.value.trim().isNotEmpty)
          entry.key.trim(): entry.value.trim(),
    };

    final candidates = <_Candidate>[];
    for (var index = 0; index < ready.length; index++) {
      final ranked = ready[index];
      var domain = DomainKeyResolver.domainOfPaths(ranked.event.tagPaths);
      if (domain == kUnclassifiedDomain) {
        final fromTree = treeDomains[ranked.event.id];
        if (fromTree != null && fromTree.isNotEmpty) {
          domain = fromTree;
        }
      }
      final effect = _effectivenessOf(
        ranked.event.id,
        taskKnowledgePoints,
        readingIndex,
        tuning,
      );
      candidates.add(
        _Candidate(
          index: index,
          ranked: ranked,
          domain: domain,
          effect: effect,
          base: effect.effectiveness * normalized.effectiveness +
              ranked.score.urgency * normalized.urgency +
              ranked.score.goalMatch * normalized.goal,
        ),
      );
    }

    // 领域出现顺序按候选顺序固定，保证配额表本身也是确定的。
    final domains = <String>[];
    final seenDomains = <String>{};
    for (final candidate in candidates) {
      if (seenDomains.add(candidate.domain)) {
        domains.add(candidate.domain);
      }
    }
    final slots = (windowSlots != null && windowSlots > 0)
        ? windowSlots
        : candidates.length;
    final quotas = <String, int>{
      for (final domain in domains)
        domain: _positive(explicitQuotas[domain]) ??
            quotaFor(slots, domains.length),
    };

    final remaining = List<_Candidate>.of(candidates);
    final counts = <String, int>{};
    final result = <BalancedTask>[];

    while (remaining.isNotEmpty) {
      _Candidate? best;
      for (final candidate in remaining) {
        final used = counts[candidate.domain] ?? 0;
        final quota = quotas[candidate.domain] ?? 1;
        final bonus = used < quota ? 1.0 - used / quota : 0.0;
        final over = used < quota ? 0.0 : (used - quota + 1).toDouble();
        candidate.balanceBonus = bonus;
        candidate.overQuota = over;
        candidate.penaltyPoints = weights.overQuotaPenalty * over;
        candidate.score = candidate.base +
            normalized.balance * bonus -
            candidate.penaltyPoints;
        if (best == null || _isBetter(candidate, best)) {
          best = candidate;
        }
      }
      final chosen = best!;
      remaining.remove(chosen);
      final used = counts[chosen.domain] ?? 0;
      counts[chosen.domain] = used + 1;
      result.add(
        _toOutput(
          chosen,
          used: used,
          quota: quotas[chosen.domain] ?? 1,
          nameById: nameById,
        ),
      );
    }

    return DomainBalanceOutput(
      ranked: result,
      insufficient: segmentA.insufficient,
      overdue: segmentA.overdue,
      domainQuota: quotas,
    );
  }

  /// 确定性比较：排序分 → 基础分 → taskId 升序 → 原始下标。
  ///
  /// 前两层决定排序，后两层保证"输入顺序不同也排得一样"。
  static bool _isBetter(_Candidate a, _Candidate b) {
    if (a.score != b.score) {
      return a.score > b.score;
    }
    if (a.base != b.base) {
      return a.base > b.base;
    }
    final byId = a.ranked.event.id.compareTo(b.ranked.event.id);
    if (byId != 0) {
      return byId < 0;
    }
    return a.index < b.index;
  }

  static int? _positive(int? value) =>
      (value != null && value > 0) ? value : null;

  static BalancedTask _toOutput(
    _Candidate candidate, {
    required int used,
    required int quota,
    required Map<String, String> nameById,
  }) {
    return BalancedTask(
      taskId: candidate.ranked.event.id,
      score: candidate.score,
      baseScore: candidate.base,
      effectiveness: candidate.effect.effectiveness,
      urgency: candidate.ranked.score.urgency,
      goal: candidate.ranked.score.goalMatch,
      balanceBonus: candidate.balanceBonus,
      overQuotaPenaltyApplied: candidate.penaltyPoints,
      reasonZh: _reasonZh(candidate, nameById: nameById),
      domainKey: candidate.domain,
      balanceNote: _balanceNote(candidate, used: used, quota: quota),
      domainQuota: quota,
      domainOrderInWindow: used + 1,
      source: candidate.ranked,
      matchedKnowledgePointId: candidate.effect.matchedKnowledgePointId,
      inDangerZone: candidate.effect.inDangerZone,
      inDevelopmentZone: candidate.effect.inDevelopmentZone,
    );
  }

  /// 一个任务挂多个知识点时取**最有效**的那个（max）；一个也没有读数时
  /// 返回中性值，并把 matchedKnowledgePointId 留空。
  static _Effect _effectivenessOf(
    String taskId,
    Map<String, List<String>> taskKnowledgePoints,
    Map<String, KnowledgePointReading> readingIndex,
    EffectivenessTuning tuning,
  ) {
    final ids = taskKnowledgePoints[taskId];
    if (ids == null || ids.isEmpty) {
      return _Effect(effectiveness: tuning.neutral);
    }
    _Effect? best;
    for (final id in ids) {
      if (id.trim().isEmpty) {
        continue;
      }
      final reading = readingIndex[id];
      if (reading == null) {
        continue;
      }
      var value = tuning.neutral;
      if (reading.inDangerZone) {
        value += tuning.dangerBoost;
      }
      if (reading.inDevelopmentZone) {
        value += tuning.developmentBoost;
      }
      final r0 = reading.priorR0;
      if (r0 != null && reading.priorConfidence > 0) {
        final weakness = 1.0 - r0.clamp(0.0, 1.0);
        value += tuning.priorWeight *
            weakness *
            reading.priorConfidence.clamp(0.0, 1.0);
      }
      final effect = _Effect(
        effectiveness: value.clamp(0.0, 1.0),
        matchedKnowledgePointId: id,
        inDangerZone: reading.inDangerZone,
        inDevelopmentZone: reading.inDevelopmentZone,
        reading: reading,
      );
      if (best == null || effect.effectiveness > best.effectiveness) {
        best = effect;
      }
    }
    return best ?? _Effect(effectiveness: tuning.neutral);
  }

  /// 一句话中文理由：只讲**主导**的那条依据，避免堆砌。
  ///
  /// 知识点用 [nameById] 里的名字说话（排序仍按 id）。名字查不到时回落到 id：
  /// 这句话是要给人看的，但"哪个知识点"不能因此消失。
  static String _reasonZh(
    _Candidate candidate, {
    required Map<String, String> nameById,
  }) {
    final effect = candidate.effect;
    final kp = effect.matchedKnowledgePointId;
    final kpName = kp == null ? null : (nameById[kp] ?? kp);
    final subject = kpName == null ? '这个任务' : '知识点「$kpName」';
    if (effect.inDangerZone) {
      return '$subject 在危险区（自信高、实际提取不出来），现在练它收益最大，所以排在这里。';
    }
    if (effect.inDevelopmentZone) {
      return '$subject 处在发展区（差点就能想起来），趁热补一下性价比最高，所以排在这里。';
    }
    final r0 = effect.reading?.priorR0;
    if (r0 != null) {
      return '测评先验显示 $subject 的编码强度只有 R0=${r0.toStringAsFixed(2)}'
          '（越弱越该现在补），所以排在这里。';
    }
    if (candidate.ranked.event.dueAt != null &&
        candidate.ranked.score.urgency >= 0.5) {
      return '没有危险区/发展区读数，但这项紧迫度高'
          '（urgency=${candidate.ranked.score.urgency.toStringAsFixed(2)}），'
          '按紧迫度与学科均衡排在这里。';
    }
    return '没有危险区/发展区读数，按紧迫度、目标匹配和学科均衡的中性分数排在这里。';
  }

  static String _balanceNote(
    _Candidate candidate, {
    required int used,
    required int quota,
  }) {
    final head = candidate.domain == kUnclassifiedDomain
        ? '无学科标签（归为「$kUnclassifiedDomain」一组）'
        : '学科 ${candidate.domain}';
    if (candidate.overQuota > 0) {
      return '$head 配额 $quota 个已排满，这是第 ${candidate.overQuota.toInt()} 个'
          '超出者，罚 ${candidate.penaltyPoints.toStringAsFixed(2)} 分，'
          '排到配额内的任务之后。';
    }
    return '$head 本窗口第 ${used + 1} 个（配额 $quota 个内），'
        '领域分散奖励 +${candidate.balanceBonus.toStringAsFixed(2)}。';
  }
}

/// 一个任务的有效性判定（内部中间量）。
class _Effect {
  const _Effect({
    required this.effectiveness,
    this.matchedKnowledgePointId,
    this.inDangerZone = false,
    this.inDevelopmentZone = false,
    this.reading,
  });

  final double effectiveness;
  final String? matchedKnowledgePointId;
  final bool inDangerZone;
  final bool inDevelopmentZone;
  final KnowledgePointReading? reading;
}

/// 贪心选择用的可变候选（内部中间量）。
class _Candidate {
  _Candidate({
    required this.index,
    required this.ranked,
    required this.domain,
    required this.effect,
    required this.base,
  });

  final int index;
  final RankedEvent ranked;
  final String domain;
  final _Effect effect;
  final double base;

  double score = 0;
  double balanceBonus = 0;
  double overQuota = 0;
  double penaltyPoints = 0;
}
