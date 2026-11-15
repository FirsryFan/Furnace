/// 组卷 → ThreadFlow 任务树物化器（schema v47，2026-11-15）。
///
/// 为什么需要它：组卷器（`PaperComposer` / `PaperPlan`）是纯函数、只读，产物只在
/// 页面或 AI 工具的内存里；侧边栏「本周任务 / 本日任务」与调度器读的是 `tasks`
/// 表，所以没有物化器时一份组好的卷子永远不会出现在 Thread 里。本类只做一件事：
/// 把 [PaperPlan] 落成「父容器节点 + 每题一个子节点」的任务树，并且可重复执行。
///
/// 三条硬约束（`INTEGRATION-CONTRACT-2026-11-15.md` §3.2 / §3.4）：
///
///  1. **幂等靠 `tasks.source_key`**：容器键
///     `paper:week:<yyyy-Www>:<paperKey>` / `paper:day:<yyyy-MM-dd>:<paperKey>` /
///     `paper:<paperKey>`，子键再拼 `:<questionId>`；重复物化只复用，不新增。
///     插入仍走 [ThreadFlowWriter.ensureTask]（同一 `source_key` 只建一行、只写
///     一条 `created`），本类**不**直接 insert `tasks`。
///  2. **只写 `tasks` / `thread_events` / `content_refs` / `object_tags`**：不写
///     content 正文（题干/答案/解析/DAG 文本一律不进库），也不写
///     `completion_logs`。`content_refs` 只存「question id ↔ task」的引用
///     （`role=paper_item`）与「plan → QSET」的引用（`role=source_package`，
///     只有显式 `paperKey` 是内容 id 形态时才写）；`object_tags(object_type=
///     'task')` 只挂**库里已经存在**的标签（题目标签的学科根 + 知识点直挂
///     标签），缺失就跳过并计数，物化器**绝不建标签**（契约 §3.3 P0）。
///  3. **不建第二调度器**：不排序、不选槽位、不写时间块。`expectedAt` 只放调用方
///     给的窗口起点（软期望），`dueAt` 只放窗口终点（硬截止）；两者不互相冒充
///     （契约 §3.2 的字段映射规则）。
///
/// 未接线：本类没有被组卷页或 UI 调用（task-73 只要求 service + tests；AI 工具
/// `materialize_paper` 是唯一调用方）。组卷页若接上，应把
/// `paperPlanProvider` 的结果 + 选定的窗口交给这里，**不要**在页面里自己拼任务树。
library;

import '../../../data/database/database.dart';
import '../../../data/repositories/content_ref_repository.dart';
import '../../../data/repositories/tag_repository.dart';
import '../content/content_ref_vocab.dart';
import '../paper/paper_composer.dart';
import '../questions/question_title_suggestion.dart' show subjectLabelZhOf;
import '../scheduling/domain_balance.dart' show kTaskObjectType;
import '../scheduling/thread_balance_inputs.dart'
    show kKnowledgePointObjectType, kQuestionObjectType;
import 'thread_flow_writer.dart';
import 'thread_node_kind.dart';

/// 一次物化请求：一份卷子 + 计划类型与时间窗。
///
/// 时间字段全部可空；缺什么就是 null（不猜）：
///  * [windowStart] → 子节点的 `expectedAt`（软期望）与周/日容器的日期标签；
///  * [windowEnd] → `dueAt`（硬 deadline，只有它进红名单/overdue）；
///  * [remindAt] → `remindAt`（只是提醒时刻，不参与排序）；
///  * [energyRequired] → 子节点的精力 1–10（容器不写精力，契约 §3.2）。
class PaperMaterializeRequest {
  const PaperMaterializeRequest({
    required this.plan,
    required this.containerKind,
    this.paperKey,
    this.windowStart,
    this.windowEnd,
    this.remindAt,
    this.energyRequired,
    this.minutesPerItem,
    this.containerTitle,
    this.containerTagIds = const <String>[],
    this.at,
  });

  /// 组卷结果（只读；物化器不会改它）。
  final PaperPlan plan;

  /// 父容器种类：只接受 [ThreadNodeKind.week] / [ThreadNodeKind.day] /
  /// [ThreadNodeKind.paper]。子节点固定是 [ThreadNodeKind.task]（一个可坐下做完
  /// 的单元），不复制成 paper/review。
  final ThreadNodeKind containerKind;

  /// 卷子标识（契约里的 `QSET id` 或 `spec+question ids` 的 hash）。
  ///
  /// 为空时由 [PaperTaskMaterializer.paperKeyOf] 从题序无关的题目 id 集合推导；
  /// 只要卷子内容不变，重复物化的键就不变。若调用方有稳定套卷 id（`QSET-…`），
  /// 传进来更稳：重新组卷（题目增减）时仍落在同一个周/日容器里。
  final String? paperKey;

  /// 计划窗口起点（本地时刻）；week/day 容器**必需**（用于 `source_key` 的
  /// `yyyy-Www` / `yyyy-MM-dd` 标签，也作为子节点的软期望）。
  final DateTime? windowStart;

  /// 计划窗口终点（本地时刻）：写 `dueAt`（硬截止）。
  final DateTime? windowEnd;

  /// 提醒时刻（可选）。
  final DateTime? remindAt;

  /// 子节点需要的精力 1–10（可选；容器不写精力）。
  final int? energyRequired;

  /// 每道子题的估时（分钟，可选）。组卷器的 [PaperPlan] / [PaperItem] 本身不带
  /// 逐题估时，所以缺省是 null；给了才写，父容器再按「子节点之和」算。
  final int? minutesPerItem;

  /// 容器标题覆盖（可选）；为空时按计划类型 + 日期标签生成确定性标题。
  final String? containerTitle;

  /// 父容器额外要挂的标签 id（契约 §3.3 P0：调用方显式给，物化器不建标签）。
  ///
  /// 只引用**已经存在**的 `tags` 行：存在的 id 原样挂到容器上，不存在的跳过并
  /// 记入 [PaperTaskTree.refs] 的 `missingContainerTagIds`。为空时父容器只挂
  /// "子任务学科标签的并集"（若有）；两者都没有就一条标签都不写。
  ///
  /// 为什么不是 `paper`/`week`/`day` 标签：真实标签树里没有这类标签约定
  /// （契约 §4.1 的标签维度只有学科/章节/知识点/能力/题库质量），自动按
  /// `paper`/`week`/`day` 找同名标签等于凭空造约定；调用方要挂就显式给 id。
  final List<String> containerTagIds;

  /// 物化时刻（可选，默认 `DateTime.now()`）；测试注入固定时刻用。
  final DateTime? at;
}

/// 一次物化写了哪些内容引用 / 任务标签，以及哪些"想挂但库里没有"被跳过。
///
/// 计数口径（每条都能被单独断言）：
///  * [paperItemRefsEnsured] 是**确保存在**的逐题引用数（`upsert` 幂等，重复
///    物化仍是同一个数）；它回答"每个子任务都有一条题目引用吗"。
///  * [taskTagLinksCreated] 是**本次新增**的 `object_tags(task)` 行数（容器 +
///    子节点）；重复物化必须是 0。
///  * [subjectTagMisses] / [knowledgePointTagMisses] 只统计"有挂载意图但没有
///    可用标签"的题目：题目声明了学科却没有同学科根标签、或题目有知识点 id
///    但该知识点一条标签都没有。本来就不该挂的（学科空、没知识点）不计缺失。
class PaperTaskRefsReport {
  const PaperTaskRefsReport({
    required this.paperItemRefsEnsured,
    required this.sourcePackageRefEnsured,
    required this.taskTagLinksCreated,
    required this.subjectTagMisses,
    required this.knowledgePointTagMisses,
    required this.missingContainerTagIds,
  });

  /// 子任务 → 题目（`role=paper_item`）的引用数（每个子节点一条）。
  final int paperItemRefsEnsured;

  /// 父容器 → 卷子内容（`role=source_package`）的引用是否写入。
  ///
  /// 只有调用方显式给出**内容 id 形态**的 `paperKey`（`QSET-…`）时才写：派生键
  /// （题集指纹 / `plan`）不是内容 id，写成 `content_id` 就是把本地标识冒充成
  /// 跨设备锚点（契约 §2.3）。
  final bool sourcePackageRefEnsured;

  /// 本次新增的 `object_tags(object_type='task')` 行数（容器 + 子节点）。
  final int taskTagLinksCreated;

  /// 有学科键、但找不到同学科顶层标签的题目数。
  final int subjectTagMisses;

  /// 有知识点 id、但知识点没有任何现存标签的题目数。
  final int knowledgePointTagMisses;

  /// 调用方显式给了、但 `tags` 表里不存在的容器标签 id（已跳过，未建标签）。
  final List<String> missingContainerTagIds;

  /// 是否发生过"想挂但跳过"。为 true 不一定是错误，但说明这批任务带着缺口。
  bool get hasMisses =>
      subjectTagMisses > 0 ||
      knowledgePointTagMisses > 0 ||
      missingContainerTagIds.isNotEmpty;

  Map<String, Object?> toJson() => <String, Object?>{
        'paper_item_refs_ensured': paperItemRefsEnsured,
        'source_package_ref_ensured': sourcePackageRefEnsured,
        'task_tag_links_created': taskTagLinksCreated,
        'subject_tag_misses': subjectTagMisses,
        'knowledge_point_tag_misses': knowledgePointTagMisses,
        'missing_container_tag_ids': missingContainerTagIds,
      };
}

/// 一次物化的结果。
class PaperTaskTree {
  const PaperTaskTree({
    required this.container,
    required this.items,
    required this.createdContainer,
    required this.createdQuestionIds,
    required this.refs,
  });

  /// 父容器节点（week/day/paper）。
  final Task container;

  /// 子节点，按 [PaperPlan.items] 的顺序（重排不会改已有节点的标题）。
  final List<Task> items;

  /// 本次调用**新建**了容器（false = 复用已有节点）。
  final bool createdContainer;

  /// 本次调用**新建**的子节点题目 id（false 已存在的不在表里）。
  final List<String> createdQuestionIds;

  /// 本次写入的内容引用 / 任务标签报告（缺失标签的跳过计数在这里）。
  final PaperTaskRefsReport refs;

  /// 容器当前的估时（子节点之和；任一子节点没有估时 → null）。
  int? get estimateMinutes => container.estimateMinutes;
}

/// 组卷 → ThreadFlow 任务树物化器。
class PaperTaskMaterializer {
  PaperTaskMaterializer(
    AppDatabase db, {
    ThreadFlowWriter? writer,
    ContentRefRepository? contentRefs,
    TagRepository? tags,
  })  : _db = db,
        _writer = writer ?? ThreadFlowWriter(db),
        _contentRefs = contentRefs ?? ContentRefRepository(db),
        _tags = tags ?? TagRepository(db);

  final AppDatabase _db;
  final ThreadFlowWriter _writer;
  final ContentRefRepository _contentRefs;
  final TagRepository _tags;

  /// 物化一份 [PaperPlan]：容器 + 每题一个子节点。
  ///
  /// 返回 [PaperTaskTree]。重复调用（同一请求）是 no-op：所有节点按
  /// `source_key` 复用，不新增行、不追加事件。
  Future<PaperTaskTree> materialize(PaperMaterializeRequest request) async {
    _validate(request);

    final plan = request.plan;
    final kind = request.containerKind;
    final start = request.windowStart;
    final paperKey = _resolvePaperKey(request);
    final prefix = _sourcePrefix(kind, start);
    final containerKey = '$prefix:$paperKey';
    final now = request.at ?? DateTime.now();
    final expectedAt = start?.millisecondsSinceEpoch;
    final dueAt = request.windowEnd?.millisecondsSinceEpoch;
    final remindAt = request.remindAt?.millisecondsSinceEpoch;

    // 一个事务包住整棵树：任何一步失败（例如同 source_key 换了 kind）都不留
    // 半棵树；error 直接抛出，不静默吞。
    return _db.transaction(() async {
      // 题目 id 在 PaperPlan 里本应唯一（组卷器用 pickedIds 去重）；这里再防一次，
      // 不因脏输入建出两条同键子节点。
      final planned = <_PlannedItem>[];
      final seen = <String>{};
      for (var index = 0; index < plan.items.length; index++) {
        final item = plan.items[index];
        final questionId = item.questionId.trim();
        if (questionId.isEmpty) {
          throw ArgumentError('PaperPlan.items[$index] has an empty questionId');
        }
        if (!seen.add(questionId)) {
          continue;
        }
        planned.add(_PlannedItem(item: item, index: index, questionId: questionId));
      }

      final existingKeys = await _sourceKeysInUse(<String>[
        containerKey,
        for (final entry in planned) '$containerKey:${entry.questionId}',
      ]);

      final container = await _writer.ensureTask(
        title: _containerTitle(kind, start, paperKey, plan, request.containerTitle),
        kind: kind,
        sourceKey: containerKey,
        description: _containerDescription(plan, paperKey),
        dueAt: dueAt,
        expectedAt: expectedAt,
        remindAt: remindAt,
        at: now,
      );

      final children = <Task>[];
      final createdQuestionIds = <String>[];
      for (final entry in planned) {
        final itemKey = '$containerKey:${entry.questionId}';
        final child = await _writer.ensureTask(
          title: '第 ${entry.index + 1} 题 · ${entry.questionId}',
          kind: ThreadNodeKind.task,
          sourceKey: itemKey,
          parentId: container.id,
          description: _itemDescription(entry.item),
          estimateMinutes: request.minutesPerItem,
          dueAt: dueAt,
          remindAt: remindAt,
          expectedAt: expectedAt,
          energyRequired: request.energyRequired,
          at: now,
        );
        children.add(child);
        if (!existingKeys.contains(itemKey)) {
          createdQuestionIds.add(entry.questionId);
        }
      }

      // 父容器 estimate = 子节点之和：按**库里实际的子节点**重算（覆盖本轮新增与
      // 上次遗留两种情况）。任一子节点没有估时 → 父容器也不写（未知不冒充 0）。
      // 走 writer.plan 而不是直写列：估时是排期事实，应留下 `planned` 事件。
      final childRows = await (_db.select(_db.tasks)
            ..where((t) => t.parentId.equals(container.id)))
          .get();
      final sum = _sumEstimates(childRows);
      var treeContainer = container;
      if (sum != null && sum != container.estimateMinutes) {
        final plannedResult = await _writer.plan(
          container.id,
          estimateMinutes: sum,
          sourceKey: '$containerKey:planned:$sum',
          at: now,
        );
        treeContainer = plannedResult.task;
      }

      // 内容引用 + 任务标签：与任务树同一个事务（任何一步失败整棵树回滚），
      // 且都是幂等的（content_refs 四元组唯一键、object_tags 三元组唯一键）。
      final refs = await _writeRefsAndTags(
        request: request,
        container: treeContainer,
        planned: planned,
        children: children,
      );

      return PaperTaskTree(
        container: treeContainer,
        items: children,
        createdContainer: !existingKeys.contains(containerKey),
        createdQuestionIds: createdQuestionIds,
        refs: refs,
      );
    });
  }

  /// 容器 `source_key`（容器键 = `<prefix>:<paperKey>`）。
  ///
  /// 供测试/调用方复算幂等键；[windowStart] 对 week/day 必需。
  static String containerSourceKey({
    required ThreadNodeKind containerKind,
    required String paperKey,
    DateTime? windowStart,
  }) {
    if (paperKey.trim().isEmpty) {
      throw ArgumentError('paperKey must not be empty');
    }
    return '${_sourcePrefix(containerKind, windowStart)}:${paperKey.trim()}';
  }

  /// 子节点 `source_key`（容器键 + `:<questionId>`）。
  static String itemSourceKey({
    required ThreadNodeKind containerKind,
    required String paperKey,
    required String questionId,
    DateTime? windowStart,
  }) {
    final id = questionId.trim();
    if (id.isEmpty) {
      throw ArgumentError('questionId must not be empty');
    }
    return '${containerSourceKey(containerKind: containerKind, paperKey: paperKey, windowStart: windowStart)}:$id';
  }

  /// ISO 周标签 `yyyy-Www`（本地日历日；周一为一周第一天）。
  ///
  /// 纯日期运算走 UTC 日历，避免夏令时把 `difference` 算歪；结果只取决于
  /// 年月日，与运行时时区无关。
  static String isoWeekLabel(DateTime day) {
    final date = DateTime.utc(day.year, day.month, day.day);
    // ISO：这一周的「定义日」是周四；周四落在哪一年，这一周就属于哪一年。
    final thursday = date.add(Duration(days: 4 - date.weekday));
    final year = thursday.year;
    final jan4 = DateTime.utc(year, 1, 4);
    final firstThursday = jan4.add(Duration(days: 4 - jan4.weekday));
    final week = 1 + thursday.difference(firstThursday).inDays ~/ 7;
    return '${year.toString().padLeft(4, '0')}-W${week.toString().padLeft(2, '0')}';
  }

  /// 从 [PaperPlan] 推导卷子标识（题序无关的题目 id 集合的 64 位 FNV-1a）。
  ///
  /// 契约 §R8 允许「无内容包时 `paper:{sha256(spec+question ids)}`」；这里刻意用
  /// 无依赖的 FNV-1a 而不是 sha256（仓库没有 crypto 直接依赖），它只要求**稳定**
  /// 与低碰撞，不用于安全。调用方有真实 `QSET-…` id 时应直接传 `paperKey`，不要
  /// 依赖这个兜底。
  static String paperKeyOf(PaperPlan plan) {
    final ids = <String>[
      for (final item in plan.items) item.questionId.trim(),
    ]..sort();
    return _fingerprint('paper-plan/1\u0001${ids.join('\u0001')}');
  }

  /// 显式 `paperKey` 只有在**内容 id 形态**（`QSET-…`）时才当内容引用。
  ///
  /// [paperKeyOf] 的题集指纹和 AI 工具默认的 `plan` 都是本地幂等键，不是 C 层
  /// 的内容 id；把它们写进 `content_refs.content_id` 会让一条本地标识冒充
  /// 跨设备锚点（契约 §2.3 第 3 条）。所以只有 `QSET-` 前缀的显式 key 才写。
  static String? contentIdOfPaperKey(String? paperKey) {
    final trimmed = paperKey?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    if (!_contentIdPattern.hasMatch(trimmed)) {
      return null;
    }
    return trimmed;
  }

  /// C 层内容 id 的形态：`QSET-<日期/编号>`（契约 §2.2）。
  static final RegExp _contentIdPattern =
      RegExp(r'^QSET-[A-Za-z0-9][A-Za-z0-9._-]*$');

  /// 写 `content_refs` 与 `object_tags(object_type='task')`（在物化事务内）。
  ///
  /// 三条硬规则：
  ///  1. **只放引用，不复制正文**：content_refs 只有 id / role / subject /
  ///     version+hash（未知就不给，成对为空）/ metadata 摘要；object_tags 只有
  ///     (tag, 'task', taskId) 三元组；
  ///  2. **只引用已存在的标签**：题目直挂标签的顶层学科根、知识点的直挂标签、
  ///     调用方显式给的容器标签，全部按 `tags` 表过滤；缺失的跳过并计数，
  ///     绝不 `createTag`；
  ///  3. **幂等**：content_refs 按唯一键 upsert（内容不变就不更新），
  ///     object_tags 走 `addTagToObjects`（已存在的链接跳过，返回新增数）。
  Future<PaperTaskRefsReport> _writeRefsAndTags({
    required PaperMaterializeRequest request,
    required Task container,
    required List<_PlannedItem> planned,
    required List<Task> children,
  }) async {
    // --- 1) content_refs：逐题 paper_item（不写正文） ---
    for (var index = 0; index < planned.length; index++) {
      final item = planned[index].item;
      final subject = item.subjectKey.trim();
      final knowledgePointId = item.knowledgePointId?.trim();
      await _contentRefs.upsert(
        contentId: planned[index].questionId,
        objectType: ContentObjectType.task,
        objectId: children[index].id,
        role: ContentRefRole.paperItem,
        subject: subject.isEmpty ? null : subject,
        // content_version/content_hash 成对为空：PaperPlan 里没有内容版本，
        // "不知道"就不给（契约 §2.3：只给一个是脏数据）。
        metadata: <String, Object?>{
          if (knowledgePointId != null && knowledgePointId.isNotEmpty)
            'knowledge_point_id': knowledgePointId,
          if (item.questionType.trim().isNotEmpty)
            'question_type': item.questionType.trim(),
          if (item.sourceLevel.trim().isNotEmpty)
            'source_level': item.sourceLevel.trim(),
        },
      );
    }
    final paperContentId = contentIdOfPaperKey(request.paperKey);
    if (paperContentId != null) {
      await _contentRefs.upsert(
        contentId: paperContentId,
        objectType: ContentObjectType.task,
        objectId: container.id,
        role: ContentRefRole.sourcePackage,
        metadata: <String, Object?>{
          'container_kind': request.containerKind.id,
          'question_count': planned.length,
        },
      );
    }

    // --- 2) 标签候选：全部从库里**读**，不建 ---
    final allTags = await _tags.getAllTags();
    final tagById = <String, Tag>{for (final tag in allTags) tag.id: tag};
    final rootIdByName = <String, String>{};
    for (final tag in allTags) {
      if (tag.parentId != null) {
        continue; // 学科 = 顶层标签（契约 §4.1），只看根。
      }
      final name = tag.name.trim();
      if (name.isEmpty || rootIdByName.containsKey(name)) {
        continue;
      }
      rootIdByName[name] = tag.id;
    }

    final questionTags = await _tags.tagIdsByObjectIds(
      objectType: kQuestionObjectType,
      objectIds: <String>[for (final entry in planned) entry.questionId],
    );
    final pointIds = <String>{};
    for (final entry in planned) {
      final primary = entry.item.knowledgePointId?.trim();
      if (primary != null && primary.isNotEmpty) {
        pointIds.add(primary);
      }
      for (final pointId in entry.item.matchedKnowledgePointIds) {
        final trimmed = pointId.trim();
        if (trimmed.isNotEmpty) {
          pointIds.add(trimmed);
        }
      }
    }
    final pointTags = pointIds.isEmpty
        ? const <String, List<String>>{}
        : await _tags.tagIdsByObjectIds(
            objectType: kKnowledgePointObjectType,
            objectIds: pointIds,
          );

    // --- 3) 每个子任务要挂哪些标签 ---
    final tagIdsByTaskId = <String, Set<String>>{};
    final subjectTagIdsByItem = <Set<String>>[];
    var subjectTagMisses = 0;
    var knowledgePointTagMisses = 0;
    for (var index = 0; index < planned.length; index++) {
      final item = planned[index].item;
      final taskId = children[index].id;
      final subject = item.subjectKey.trim();
      final subjectLabel = subjectLabelZhOf(subject);

      // 3a. 题目现成标签的**顶层根**就是学科（契约 §4.1）。只收名字等于本题
      // 学科名的根：`能力/*`、`题库质量/*` 这些非学科根不该挂到练习节点上。
      final subjectTagIds = <String>{};
      if (subjectLabel != null) {
        final label = subjectLabel.trim();
        for (final tagId in questionTags[planned[index].questionId] ??
            const <String>[]) {
          final rootId = _rootTagIdOf(tagId, tagById);
          if (rootId == null) {
            continue;
          }
          final rootName = tagById[rootId]?.name.trim();
          if (rootName == label) {
            subjectTagIds.add(rootId);
          }
        }
        // 3b. 题目没有标签（或根对不上）时，按学科名找现成的顶层标签。
        if (subjectTagIds.isEmpty) {
          final rootId = rootIdByName[label];
          if (rootId != null) {
            subjectTagIds.add(rootId);
          }
        }
      }
      if (subjectTagIds.isEmpty && subject.isNotEmpty) {
        subjectTagMisses++;
      }

      // 3c. 知识点直挂标签：任务与知识点共标签，段落 B 才能反推知识点
      // （`TaskKnowledgePointResolver.resolveFromTagLinks`，契约 §3.3）。
      final pointTagIds = <String>{};
      final pointIdsForItem = <String>{
        if (item.knowledgePointId?.trim().isNotEmpty ?? false)
          item.knowledgePointId!.trim(),
        for (final pointId in item.matchedKnowledgePointIds)
          if (pointId.trim().isNotEmpty) pointId.trim(),
      };
      for (final pointId in pointIdsForItem) {
        pointTagIds.addAll(pointTags[pointId] ?? const <String>[]);
      }
      if (pointTagIds.isEmpty && pointIdsForItem.isNotEmpty) {
        knowledgePointTagMisses++;
      }

      final taskTagIds = <String>{...subjectTagIds, ...pointTagIds};
      if (taskTagIds.isNotEmpty) {
        tagIdsByTaskId[taskId] = taskTagIds;
      }
      subjectTagIdsByItem.add(subjectTagIds);
    }

    // --- 4) 父容器：子题学科标签并集 + 调用方显式给的现存标签 ---
    final containerTagIds = <String>{
      for (final ids in subjectTagIdsByItem) ...ids,
    };
    final missingContainerTagIds = <String>[];
    for (final raw in request.containerTagIds) {
      final tagId = raw.trim();
      if (tagId.isEmpty) {
        continue;
      }
      if (tagById.containsKey(tagId)) {
        containerTagIds.add(tagId);
      } else {
        missingContainerTagIds.add(tagId);
      }
    }
    if (containerTagIds.isNotEmpty) {
      tagIdsByTaskId[container.id] = containerTagIds;
    }

    // --- 5) 批量写 object_tags(task)：同一标签一次挂多个对象 ---
    final taskIdsByTagId = <String, Set<String>>{};
    tagIdsByTaskId.forEach((taskId, tagIds) {
      for (final tagId in tagIds) {
        (taskIdsByTagId[tagId] ??= <String>{}).add(taskId);
      }
    });
    var linksCreated = 0;
    final tagIds = taskIdsByTagId.keys.toList()..sort();
    for (final tagId in tagIds) {
      final objectIds = taskIdsByTagId[tagId]!.toList()..sort();
      linksCreated += await _tags.addTagToObjects(
        tagId: tagId,
        objectIds: objectIds,
        objectType: kTaskObjectType,
      );
    }

    return PaperTaskRefsReport(
      paperItemRefsEnsured: planned.length,
      sourcePackageRefEnsured: paperContentId != null,
      taskTagLinksCreated: linksCreated,
      subjectTagMisses: subjectTagMisses,
      knowledgePointTagMisses: knowledgePointTagMisses,
      missingContainerTagIds:
          List<String>.unmodifiable(missingContainerTagIds..sort()),
    );
  }

  /// 标签沿 `parentId` 走到顶层；链断或成环返回 null（不猜、不造）。
  static String? _rootTagIdOf(String tagId, Map<String, Tag> tagById) {
    var current = tagById[tagId];
    final visited = <String>{};
    while (current != null && current.parentId != null) {
      if (!visited.add(current.id)) {
        return null;
      }
      current = tagById[current.parentId!];
    }
    return current?.id;
  }

  // ---------------------------------------------------------------------------
  // internals
  // ---------------------------------------------------------------------------

  static void _validate(PaperMaterializeRequest request) {
    final kind = request.containerKind;
    if (kind != ThreadNodeKind.week &&
        kind != ThreadNodeKind.day &&
        kind != ThreadNodeKind.paper) {
      throw ArgumentError(
        'containerKind must be week/day/paper, got "${kind.id}"',
      );
    }
    if (kind != ThreadNodeKind.paper && request.windowStart == null) {
      throw ArgumentError(
        'windowStart is required for "${kind.id}" containers '
        '(source_key needs the date label)',
      );
    }
    final minutes = request.minutesPerItem;
    if (minutes != null && minutes <= 0) {
      throw ArgumentError('minutesPerItem must be > 0, got $minutes');
    }
    final energy = request.energyRequired;
    if (energy != null && (energy < 1 || energy > 10)) {
      throw ArgumentError('energyRequired must be in 1..10, got $energy');
    }
    final start = request.windowStart;
    final end = request.windowEnd;
    if (start != null && end != null && end.isBefore(start)) {
      throw ArgumentError(
        'windowEnd ${end.toIso8601String()} is before '
        'windowStart ${start.toIso8601String()}',
      );
    }
  }

  static String _resolvePaperKey(PaperMaterializeRequest request) {
    final explicit = request.paperKey?.trim();
    if (explicit != null && explicit.isNotEmpty) {
      return explicit;
    }
    return paperKeyOf(request.plan);
  }

  static String _sourcePrefix(ThreadNodeKind kind, DateTime? windowStart) {
    switch (kind) {
      case ThreadNodeKind.week:
        if (windowStart == null) {
          throw ArgumentError('windowStart is required for week containers');
        }
        return 'paper:week:${isoWeekLabel(windowStart)}';
      case ThreadNodeKind.day:
        if (windowStart == null) {
          throw ArgumentError('windowStart is required for day containers');
        }
        return 'paper:day:${_dateLabel(windowStart)}';
      case ThreadNodeKind.paper:
        return 'paper';
      case ThreadNodeKind.task:
      case ThreadNodeKind.review:
        throw ArgumentError(
          'containerKind must be week/day/paper, got "${kind.id}"',
        );
    }
  }

  static String _dateLabel(DateTime day) {
    final year = day.year.toString().padLeft(4, '0');
    final month = day.month.toString().padLeft(2, '0');
    final date = day.day.toString().padLeft(2, '0');
    return '$year-$month-$date';
  }

  static String _containerTitle(
    ThreadNodeKind kind,
    DateTime? windowStart,
    String paperKey,
    PaperPlan plan,
    String? override,
  ) {
    final explicit = override?.trim();
    if (explicit != null && explicit.isNotEmpty) {
      return explicit;
    }
    final count = plan.items.length;
    switch (kind) {
      case ThreadNodeKind.week:
        return '组卷 · ${isoWeekLabel(windowStart!)}（$count 题）';
      case ThreadNodeKind.day:
        return '组卷 · ${_dateLabel(windowStart!)}（$count 题）';
      case ThreadNodeKind.paper:
        // paper 容器没有日期标签；标题带上卷子标识的前 8 位，避免多份卷子同名。
        return '组卷 · $count 题（${paperKey.length <= 8 ? paperKey : paperKey.substring(0, 8)}）';
      case ThreadNodeKind.task:
      case ThreadNodeKind.review:
        throw ArgumentError(
          'containerKind must be week/day/paper, got "${kind.id}"',
        );
    }
  }

  static String _containerDescription(PaperPlan plan, String paperKey) {
    final parts = <String>[
      '组卷计划：${plan.items.length}/${plan.requestedCount} 题',
      'paper_key=$paperKey',
      if (plan.isShort) '题量未凑够（题库不足或过滤过严）',
      if (plan.uncoveredKnowledgePointIds.isNotEmpty)
        '无候选知识点 ${plan.uncoveredKnowledgePointIds.length} 个',
      if (plan.deferredKnowledgePointIds.isNotEmpty)
        '本轮未排知识点 ${plan.deferredKnowledgePointIds.length} 个',
    ];
    return parts.join('；');
  }

  static String _itemDescription(PaperItem item) {
    final lines = <String>[
      if (item.reasonZh.isNotEmpty) '为什么排它：${item.reasonZh}',
      if (item.improvementNote.isNotEmpty) '提升点：${item.improvementNote}',
      if (item.backgroundZh.isNotEmpty) '知识背景：${item.backgroundZh}',
      '分区：${item.zone.labelZh}',
      if (item.subjectKey.isNotEmpty) '学科：${item.subjectKey}',
      if (item.questionType.isNotEmpty) '题型：${item.questionType}',
      if (item.knowledgePointId != null) '主知识点：${item.knowledgePointId}',
    ];
    return lines.join('\n');
  }

  /// 父容器估时 = 子节点之和；没有子节点、或任一子节点没有估时 → null。
  static int? _sumEstimates(List<Task> children) {
    if (children.isEmpty) {
      return null;
    }
    var sum = 0;
    for (final child in children) {
      final estimate = child.estimateMinutes;
      if (estimate == null) {
        return null;
      }
      sum += estimate;
    }
    return sum;
  }

  Future<Set<String>> _sourceKeysInUse(List<String> keys) async {
    final inUse = <String>{};
    if (keys.isEmpty) {
      return inUse;
    }
    final rows = await (_db.select(_db.tasks)
          ..where((t) => t.sourceKey.isIn(keys)))
        .get();
    for (final row in rows) {
      final key = row.sourceKey;
      if (key != null) {
        inUse.add(key);
      }
    }
    return inUse;
  }

  // 64 位 FNV-1a 的参数。offset basis 超过 2^63-1，所以用 BigInt.parse 而不是
  // 十六进制字面量（后者在 VM 上会回绕成负数）。
  static final BigInt _fnvOffset = BigInt.parse('14695981039346656037');
  static final BigInt _fnvPrime = BigInt.parse('1099511628211');
  static final BigInt _u64Mask = (BigInt.one << 64) - BigInt.one;

  /// 64 位 FNV-1a（十六进制、小写、16 个字符）。
  static String _fingerprint(String input) {
    var hash = _fnvOffset;
    for (final unit in input.codeUnits) {
      hash = ((hash ^ BigInt.from(unit)) * _fnvPrime) & _u64Mask;
    }
    return hash.toRadixString(16).padLeft(16, '0');
  }
}

class _PlannedItem {
  const _PlannedItem({
    required this.item,
    required this.index,
    required this.questionId,
  });

  final PaperItem item;
  final int index;
  final String questionId;
}
