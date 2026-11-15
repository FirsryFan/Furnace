/// `object_tags.object_type` 的固定词表（`INTEGRATION-CONTRACT-2026-11-15.md` §4.2）。
///
/// 这一列一直是自由 TEXT，代码里散落着字面量；新增的读取方（标签知识入口
/// `TagKnowledgeIndex`）从这里取常量，不再各写一份字符串。**值一旦落库就不能
/// 改名**：改值等于让历史行失联，所以只加值、不改值。
///
/// 注意它和 `content_refs.object_type`（`ContentObjectType`）不是同一张表：
/// 两边在 `task` / `question` / `knowledge_point` / `card_template` 上取值相同，
/// 但词表边界不同（内容引用没有 `time_block` / `task_template` / `mind_map`），
/// 所以不要互相 import 冒充同一个枚举。
library;

/// `object_tags.object_type` 的词表（契约 §4.2）。
abstract final class ObjectTypes {
  /// Thread 节点（`tasks.id`）。
  static const String task = 'task';

  /// 产品知识点（`knowledge_points.id`）。
  static const String knowledgePoint = 'knowledge_point';

  /// 题库题目（`questions.id`）。
  static const String question = 'question';

  /// 时间块（`time_blocks.id`）。
  static const String timeBlock = 'time_block';

  /// 卡模板（`card_templates.id`）。
  static const String cardTemplate = 'card_template';

  /// 任务模板（`task_templates.id`）。
  static const String taskTemplate = 'task_template';

  /// 思维导图（`mind_maps.id`）。
  static const String mindMap = 'mind_map';

  /// 标签自身（标签之间的关联，历史用法）。
  static const String tag = 'tag';

  static const Set<String> values = {
    task,
    knowledgePoint,
    question,
    timeBlock,
    cardTemplate,
    taskTemplate,
    mindMap,
    tag,
  };
}
