/// 标签知识入口的统一只读索引（`INTEGRATION-CONTRACT-2026-11-15.md` §4.3 / §8-14）。
///
/// 契约要求：**查询永远走同一个 `TagKnowledgeIndex`**，页面/工具不得各自拼
/// SQL，否则同一个标签在两个页面会数出不同的数量。这里就是那唯一的读法：
///
///  * 查题：`object_tags(object_type='question')`；
///  * 查知识点：`object_tags(object_type='knowledge_point')`；
///  * 查卡：知识点 → `card_templates.knowledge_point_id`（卡组 = 标签子树，
///    `review_group_plans.tag_id`）；另外把历史上直接挂在卡模板上的
///    `object_tags(object_type='card_template')` 也算进来——那是真实存在的行，
///    不读它就等于「有卡却显示没有」；
///  * 查 Thread 任务：`object_tags(object_type='task')`。
///
/// 三条纪律：
///  1. **只读**：不写任何表，不建标签，不改对象；
///  2. **不猜关系**：只认 `object_tags` / `knowledge_points` / `card_templates`
///     里真实存在的行；没有关系的对象不出现在结果里。`content_refs` 没有
///     tag 列，因此**不参与**按标签查询（见 `TAG-KNOWLEDGE-ENTRY-2026-11-15.md`）；
///  3. **不伪造数量**：列表长度就是真实存在的对象数；多态链接指向已删除对象
///     时只记进 [TagKnowledgeSnapshot.missingTargets]，不补假行。
///
/// 范围：默认只看标签**自己**的直挂对象；`includeDescendants` 打开后按
/// `parent_id` 子树统计（与 `TagRepository.objectCountByTagId(includeDescendants)`
/// 同一口径），不依赖 `path` 派生列。
library;

import '../../../data/database/database.dart';
import '../../../data/repositories/anki_repository.dart';
import '../../../data/repositories/question_repository.dart';
import '../../../data/repositories/review_plan_repository.dart';
import '../../../data/repositories/tag_repository.dart';
import '../../../data/repositories/task_repository.dart';
import '../../../domain/services/tags/object_types.dart';
import '../../../domain/services/thread/thread_status.dart';

/// 一次「标签 → 题/卡/任务」查询的结果快照。
///
/// 四个列表都只含**真实存在的行**，长度就是页面上的数量。
class TagKnowledgeSnapshot {
  const TagKnowledgeSnapshot({
    required this.tagId,
    required this.tag,
    required this.questions,
    required this.cards,
    required this.tasks,
    required this.knowledgePointCount,
    this.reviewGroup,
    this.missingTargets = 0,
  });

  /// 查的标签 id（即使标签已被删也保留请求值）。
  final String tagId;

  /// 标签行；null = 这个标签已经不在了（页面如实说「已不存在」，不显示三块）。
  final Tag? tag;

  final List<Question> questions;
  final List<TagKnowledgeCard> cards;
  final List<Task> tasks;

  /// 标签子树命中的知识点数量（只用于文案/诊断；卡片块自己按 KP 取模版）。
  final int knowledgePointCount;

  /// 卡片归属的卡组（最近一个配置过 `review_group_plans` 的祖先/自身标签）。
  /// null = 没有任何上级标签是卡组，此时没有可用的「去复习」入口。
  final TagKnowledgeReviewGroup? reviewGroup;

  /// 悬空链接数：`object_tags` 指向了已删除的题/任务/知识点/卡模板。
  ///
  /// 这不是一个页面数字，而是「有链接但读不到对象」的诚实计数：大于 0 表示库
  /// 里有残渣，不代表这里藏了内容。
  final int missingTargets;

  bool get isMissingTag => tag == null;

  bool get isEmpty =>
      questions.isEmpty && cards.isEmpty && tasks.isEmpty;
}

/// 卡片块的一行：卡模板 + 它的知识点标题（模板只存知识点 id）。
class TagKnowledgeCard {
  const TagKnowledgeCard({
    required this.template,
    this.knowledgePointTitle,
  });

  final CardTemplate template;

  /// 所属知识点标题；知识点已删或模板是历史直挂行时为 null。
  final String? knowledgePointTitle;

  String get id => template.id;
}

/// 卡片归属的卡组：`review_group_plans.tag_id` + 它的标签路径。
///
/// 卡组 = 标签子树，所以从选中标签往上找第一个配置过计划的标签；复习页
/// （`ReviewPage(scopeTagId: …)`）只接受计划里存在的卡组 id。
class TagKnowledgeReviewGroup {
  const TagKnowledgeReviewGroup({
    required this.tagId,
    required this.tagPath,
  });

  final String tagId;
  final String tagPath;
}

/// 标签知识入口的统一只读索引。
class TagKnowledgeIndex {
  TagKnowledgeIndex({
    required TagRepository tags,
    required QuestionRepository questions,
    required AnkiRepository anki,
    required TaskRepository tasks,
    required ReviewPlanRepository reviewPlans,
  })  : _tags = tags,
        _questions = questions,
        _anki = anki,
        _tasks = tasks,
        _reviewPlans = reviewPlans;

  final TagRepository _tags;
  final QuestionRepository _questions;
  final AnkiRepository _anki;
  final TaskRepository _tasks;
  final ReviewPlanRepository _reviewPlans;

  /// 读取一个标签（可选整棵子树）挂着的题/卡/任务。
  ///
  /// [includeDescendants] = true 时把子标签上的链接也算进来（卡组也按子树划分，
  /// 与复习计划同一口径）。标签不存在时返回 [TagKnowledgeSnapshot.isMissingTag]
  /// 为 true 的快照，而不是抛错——删标签与页面打开可能同时发生。
  Future<TagKnowledgeSnapshot> snapshot(
    String tagId, {
    bool includeDescendants = false,
  }) async {
    final cleanTagId = tagId.trim();
    final tag = cleanTagId.isEmpty ? null : await _tags.getTagById(cleanTagId);
    if (tag == null) {
      return TagKnowledgeSnapshot(
        tagId: cleanTagId,
        tag: null,
        questions: const <Question>[],
        cards: const <TagKnowledgeCard>[],
        tasks: const <Task>[],
        knowledgePointCount: 0,
      );
    }

    final scopeTagIds = includeDescendants
        ? await _tags.subtreeTagIds(tag.id)
        : <String>[tag.id];
    final links = await _tags.objectLinksForTags(scopeTagIds);

    final questionIds = _linkedIds(links, ObjectTypes.question);
    final knowledgePointIds = _linkedIds(links, ObjectTypes.knowledgePoint);
    final taskIds = _linkedIds(links, ObjectTypes.task);
    final directTemplateIds = _linkedIds(links, ObjectTypes.cardTemplate);

    final questionRows = await _questions.byIds(questionIds);
    final knowledgePoints = await _anki.knowledgePointsByIds(knowledgePointIds);
    final templates = <CardTemplate>[
      ...await _anki.templatesForKnowledgePoints(knowledgePointIds),
      ...await _anki.templatesByIds(directTemplateIds),
    ];
    final taskRows = await _tasks.byIds(taskIds);

    final knowledgePointTitleById = <String, String>{
      for (final point in knowledgePoints) point.id: point.title,
    };

    // 卡模板按 id 去重：同一条模板可能既经知识点出现、又有一条历史直挂链接。
    final seenTemplateIds = <String>{};
    final cards = <TagKnowledgeCard>[
      for (final template in templates)
        if (seenTemplateIds.add(template.id))
          TagKnowledgeCard(
            template: template,
            knowledgePointTitle: knowledgePointTitleById[
                template.knowledgePointId],
          ),
    ]..sort(_byCardOrder);

    // 仓储返回的是 drift 的只读列表：排序前先拷一份，别就地改。
    final orderedQuestions = <Question>[...questionRows]
      ..sort(_byQuestionOrder);
    final orderedTasks = <Task>[...taskRows]..sort(_byTaskOrder);

    final missingTargets =
        (questionIds.length - questionRows.length) +
            (knowledgePointIds.length - knowledgePoints.length) +
            (taskIds.length - taskRows.length) +
            directTemplateIds
                .where((id) => !seenTemplateIds.contains(id))
                .length;

    return TagKnowledgeSnapshot(
      tagId: tag.id,
      tag: tag,
      questions: orderedQuestions,
      cards: cards,
      tasks: orderedTasks,
      knowledgePointCount: knowledgePoints.length,
      reviewGroup: await _reviewGroupFor(tag),
      missingTargets: missingTargets < 0 ? 0 : missingTargets,
    );
  }

  /// 一次查询里某个对象类型被链接到的 id（保持首次出现顺序、去重、trim 空值）。
  static List<String> _linkedIds(
    Iterable<ObjectTag> links,
    String objectType,
  ) {
    final ids = <String>[];
    final seen = <String>{};
    for (final link in links) {
      if (link.objectType != objectType) {
        continue;
      }
      final id = link.objectId.trim();
      if (id.isEmpty || !seen.add(id)) {
        continue;
      }
      ids.add(id);
    }
    return ids;
  }

  /// 题目顺序：题号升序（没编号的排最后），同号按 id 稳定。
  ///
  /// 题号是跨学科一条序列（`docs/QUESTION_BANK_DESIGN.md` §11.1），列表按它排
  /// 最接近「题库里翻到哪一页」的直觉；同号多题（跨库合并允许）用 id 兜底，
  /// 同一份库每次读到的顺序一致，翻页不抖。
  static int _byQuestionOrder(Question a, Question b) {
    final aSerial = a.serialNo;
    final bSerial = b.serialNo;
    if (aSerial == null && bSerial != null) {
      return 1;
    }
    if (aSerial != null && bSerial == null) {
      return -1;
    }
    if (aSerial != null && bSerial != null && aSerial != bSerial) {
      return aSerial.compareTo(bSerial);
    }
    return a.id.compareTo(b.id);
  }

  /// 卡片顺序：按知识点标题（没有标题的排最后）→ 模板 sortOrder → id。
  static int _byCardOrder(TagKnowledgeCard a, TagKnowledgeCard b) {
    final aTitle = a.knowledgePointTitle;
    final bTitle = b.knowledgePointTitle;
    if (aTitle == null && bTitle != null) {
      return 1;
    }
    if (aTitle != null && bTitle == null) {
      return -1;
    }
    if (aTitle != null && bTitle != null && aTitle != bTitle) {
      return aTitle.compareTo(bTitle);
    }
    final bySort = a.template.sortOrder.compareTo(b.template.sortOrder);
    if (bySort != 0) {
      return bySort;
    }
    return a.id.compareTo(b.id);
  }

  /// 任务顺序：待办/进行中在前，terminated 在后；同状态按创建时间倒序 → id。
  static int _byTaskOrder(Task a, Task b) {
    final byStatus = _taskStatusRank(a).compareTo(_taskStatusRank(b));
    if (byStatus != 0) {
      return byStatus;
    }
    final byTime = b.createdAt.compareTo(a.createdAt);
    if (byTime != 0) {
      return byTime;
    }
    return a.id.compareTo(b.id);
  }

  static int _taskStatusRank(Task task) =>
      switch (ThreadStatus.fromStorage(task.status)) {
        ThreadStatus.todo => 0,
        ThreadStatus.doing => 1,
        ThreadStatus.blocked => 2,
        ThreadStatus.skipped => 3,
        ThreadStatus.done => 4,
      };

  /// 卡片归属的卡组：从选中标签沿 `parent_id` 往上找第一个配置过计划的标签。
  ///
  /// 只读 `review_group_plans`；没有计划 = 没有卡组（返回 null，不猜一个不存在的
  /// 卡组）。卡组路径优先用标签行的 `path`，没有就退回名称——复习页标题只需要
  /// 一个认得出来的名字。
  Future<TagKnowledgeReviewGroup?> _reviewGroupFor(Tag tag) async {
    final plans = await _reviewPlans.groupPlans();
    if (plans.isEmpty) {
      return null;
    }
    final planTagIds = <String>{for (final plan in plans) plan.tagId};
    final allTags = await _tags.getAllTags();
    final tagById = <String, Tag>{for (final row in allTags) row.id: row};

    String? current = tag.id;
    final visited = <String>{};
    while (current != null && visited.add(current)) {
      if (planTagIds.contains(current)) {
        final groupTag = tagById[current];
        final path = groupTag?.path;
        return TagKnowledgeReviewGroup(
          tagId: current,
          tagPath: path == null || path.isEmpty
              ? (groupTag?.name ?? current)
              : path,
        );
      }
      current = tagById[current]?.parentId;
    }
    return null;
  }
}
