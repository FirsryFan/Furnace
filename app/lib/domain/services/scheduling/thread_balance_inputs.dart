/// ThreadFlow 段落 B 的**纯数据输入**。
///
/// 段落 B（`domain_balance.dart`）只吃纯数据；这个文件负责把数据库里的
/// `Tags` / `ObjectTags` 投影成它要的形状，并回答一个领域问题：
/// **"这个任务在练哪些知识点"**——答案不是存在某张表里的，而是靠
/// "任务和知识点挂在同一个标签上"推出来的。
///
/// 这一层不读数据库、不认识 drift、不依赖 Flutter；具体的数据读取在
/// `app/lib/features/thread/application/thread_balance_provider.dart`。
library;

import 'domain_balance.dart';

/// `ObjectTags` 表的一行（纯数据）。
///
/// 这里**不限定** `objectType`：推"任务 → 知识点"要同时看两类链接
/// （`objectType == 'task'` 与 `'knowledge_point'`），所以两种都要装进来。
class ObjectTagLink {
  const ObjectTagLink({
    required this.tagId,
    required this.objectType,
    required this.objectId,
  });

  final String tagId;

  /// `'task'` / `'knowledge_point'` / 其它（其它只被忽略，不报错）。
  final String objectType;
  final String objectId;
}

/// `ObjectTags.objectType` 里知识点的取值。和 `question_repository.dart`、
/// 认知页的读取逻辑用同一个字符串（本项目没有外键，字符串就是契约）。
const String kKnowledgePointObjectType = 'knowledge_point';

/// 任务 → 知识点：靠**共享标签**推出。
///
/// 规则（纯确定性、可测试）：
///
/// * 一个任务挂了标签 T，一个知识点也挂了标签 T ⇒ 这个任务练这个知识点；
/// * 一个任务挂多个标签时取它们的**并集**（不是交集）；
/// * 推不出任何知识点的任务**不出现在结果里**——"没有挂载"和"挂载了 0 个"
///   是两件事，段落 B 对两者的处理不同（前者不参与认知有效性），所以这里
///   直接省略，让调用方看得见；
/// * 重复链接自动去重，结果里的任务 id 与知识点 id 都排序，保证同一份输入
///   永远给出同一份输出。
abstract final class TaskKnowledgePointResolver {
  static Map<String, List<String>> resolveFromTagLinks(
    List<ObjectTagLink> links,
  ) {
    final knowledgePointsByTag = <String, Set<String>>{};
    final tasksByTag = <String, Set<String>>{};
    for (final link in links) {
      final tagId = link.tagId.trim();
      final objectId = link.objectId.trim();
      if (tagId.isEmpty || objectId.isEmpty) {
        continue;
      }
      if (link.objectType == kKnowledgePointObjectType) {
        (knowledgePointsByTag[tagId] ??= <String>{}).add(objectId);
      } else if (link.objectType == kTaskObjectType) {
        (tasksByTag[tagId] ??= <String>{}).add(objectId);
      }
    }

    final knowledgePointsByTask = <String, Set<String>>{};
    final tagIds = tasksByTag.keys.toList()..sort();
    for (final tagId in tagIds) {
      final knowledgePoints = knowledgePointsByTag[tagId];
      if (knowledgePoints == null || knowledgePoints.isEmpty) {
        continue;
      }
      for (final taskId in tasksByTag[tagId]!) {
        (knowledgePointsByTask[taskId] ??= <String>{}).addAll(knowledgePoints);
      }
    }

    final taskIds = knowledgePointsByTask.keys.toList()..sort();
    return <String, List<String>>{
      for (final taskId in taskIds)
        taskId: knowledgePointsByTask[taskId]!.toList()..sort(),
    };
  }
}

/// 一次段落 B 排序需要的全部外部输入。
///
/// 默认值就是"什么都不知道"：空挂载、空读数、空标签树。此时段落 B 仍然工作
/// （领域全是 [kUnclassifiedDomain]，有效性取中性值），只是没有个性化信息。
class ThreadBalanceInputs {
  const ThreadBalanceInputs({
    this.taskKnowledgePoints = const <String, List<String>>{},
    this.readings = const <KnowledgePointReading>[],
    this.tags = const <DomainTag>[],
    this.taskTagLinks = const <TaskTagLink>[],
    this.knowledgePointNames = const <String, String>{},
    this.weights = const DomainBalanceWeights(),
    this.tuning = const EffectivenessTuning(),
    this.windowSlots,
  });

  /// 任务 → 知识点 id 列表（见 [TaskKnowledgePointResolver]）。
  final Map<String, List<String>> taskKnowledgePoints;

  /// 认知读数，按知识点 id 对齐。
  final List<KnowledgePointReading> readings;

  /// `Tags` 树：`RankEvent.tagPaths` 为空时用它兜底推领域。
  final List<DomainTag> tags;

  /// `ObjectTags` 里 `objectType == 'task'` 的链接，用于推任务的顶层领域。
  final List<TaskTagLink> taskTagLinks;

  /// 知识点 id → 显示名（`KnowledgePoints.title`），只给理由行说话用。
  ///
  /// 知识点 id（`kp-…`）和标签 id（`tag-…`）是两个命名空间，
  /// [`Tags`] 的名字表因此替代不了这张表：少了它，理由行只能念 id。
  final Map<String, String> knowledgePointNames;

  /// 段落 B 权重。
  final DomainBalanceWeights weights;

  /// 有效性整定值。
  final EffectivenessTuning tuning;

  /// 本窗口能装下几个任务；null = 按候选个数算配额。
  final int? windowSlots;

  /// "什么都不知道"的输入。
  static const ThreadBalanceInputs empty = ThreadBalanceInputs();

  /// 是否带了任何个性化信息（用于 UI 决定要不要说"暂无状态数据"）。
  bool get hasData =>
      taskKnowledgePoints.isNotEmpty ||
      readings.isNotEmpty ||
      tags.isNotEmpty ||
      taskTagLinks.isNotEmpty;

  bool get isEmpty => !hasData;

  ThreadBalanceInputs copyWith({
    Map<String, List<String>>? taskKnowledgePoints,
    List<KnowledgePointReading>? readings,
    List<DomainTag>? tags,
    List<TaskTagLink>? taskTagLinks,
    Map<String, String>? knowledgePointNames,
    DomainBalanceWeights? weights,
    EffectivenessTuning? tuning,
    int? windowSlots,
  }) =>
      ThreadBalanceInputs(
        taskKnowledgePoints: taskKnowledgePoints ?? this.taskKnowledgePoints,
        readings: readings ?? this.readings,
        tags: tags ?? this.tags,
        taskTagLinks: taskTagLinks ?? this.taskTagLinks,
        knowledgePointNames: knowledgePointNames ?? this.knowledgePointNames,
        weights: weights ?? this.weights,
        tuning: tuning ?? this.tuning,
        windowSlots: windowSlots ?? this.windowSlots,
      );

  /// 调试/日志用的紧凑描述（不含权重细节）。
  String describe() =>
      'tasks=${taskKnowledgePoints.length} readings=${readings.length} '
      'tags=${tags.length} links=${taskTagLinks.length} '
      'windowSlots=${windowSlots ?? 'null'}';
}
